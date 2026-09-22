// M0 golden exporter (05 §1.5): runs the OLD Dart implementation's pure logic
// over the fixtures and writes expectation files to test/golden/ for the
// native Swift test suite to assert against.
//
// Run: flutter test test/golden/export_golden_test.dart \
//         --dart-define=m0-regen=true
// Without the define all tests are SKIPPED so plain `flutter test` never
// rewrites the goldens.
//
// NOTE: this file lives inside test/golden/, so regeneration wipes only the
// generated *.json artifacts (never source files).
//
// Determinism notes:
// - all inputs are fixed; where output depends on wall-clock (timeago relative
//   branches) the reference `now` is recorded inside the golden so the native
//   side can inject the same clock;
// - live-corpus-derived values change when the corpus is re-collected; rerun
//   this exporter after any corpus refresh.
// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';
import 'dart:ui' show Color;

import 'package:anycast/api/podcasts.dart';
import 'package:anycast/api/share.dart';
import 'package:anycast/api/user.dart' show User;
import 'package:anycast/models/playlist_episode.dart';
import 'package:anycast/models/subscription.dart';
import 'package:anycast/models/subtitle.dart';
import 'package:anycast/models/translation.dart';
import 'package:anycast/pages/feeds.dart';
import 'package:anycast/pages/player.dart' show buildExportText;
import 'package:anycast/pages/settings.dart';
import 'package:anycast/states/chat.dart' show buildChatHistory;
import 'package:anycast/utils/formatters.dart';
import 'package:anycast/utils/rss_fetcher.dart';
import 'package:flutter/painting.dart' show FileImage;
import 'package:flutter_chat_core/flutter_chat_core.dart' as chat;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:palette_generator/palette_generator.dart';
import 'package:sanitize_html/sanitize_html.dart' as sanitize;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:webfeed_plus/webfeed_plus.dart';

const goldenDir = 'test/golden';
const encoder = JsonEncoder.withIndent('  ');
const _regen = bool.fromEnvironment('m0-regen');

void writeGolden(String name, Object? data) {
  final f = File('$goldenDir/$name');
  f.parent.createSync(recursive: true);
  f.writeAsStringSync(encoder.convert(data));
}

String absPath(String p) =>
    p.startsWith('/') ? p : '${Directory.current.path}/$p';

Map<String, dynamic> rssManifest() =>
    jsonDecode(File('test/fixtures/rss/manifest.json').readAsStringSync())
        as Map<String, dynamic>;

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  setUpAll(() {
    if (!_regen) return; // never wipe goldens unless regenerating
    final dir = Directory(goldenDir);
    if (dir.existsSync()) {
      // wipe only generated artifacts; keep this source file
      for (final e in dir.listSync(recursive: true)) {
        if (e is File && e.path.endsWith('.json')) {
          e.deleteSync();
        }
      }
      final dump = Directory('$goldenDir/G15_db_dump');
      if (dump.existsSync()) dump.deleteSync(recursive: true);
    }
    Directory(goldenDir).createSync(recursive: true);
  });

  group('m0 golden export', () {
    test('G1: playlist position insertion algorithm', () async {
      final db = await databaseFactory.openDatabase(inMemoryDatabasePath,
          options: OpenDatabaseOptions(
              version: 1, onCreate: (db, v) => _createPlaylistOnly(db)));

      final results = <String, dynamic>{};
      results['head_inserts_200'] = await _runOps(db, _opsHead(200));
      results['mid_insert_saturation'] = await _runOps(db, _opsMidSaturation());
      results['mixed_seeded'] = await _runOps(db, _opsMixedSeeded(60));
      writeGolden('G1_playlist_position.json', {
        'source': 'PlaylistEpisodeModel.insertOrUpdateByIndex '
            '(models/playlist_episode.dart:90-135), insertion scenarios only '
            '(K26: move scenarios asserted separately against fixed semantics)',
        'position_semantics':
            'REAL midpoint of neighbors; head = right-0.0015; '
                'tail = left+0.0015; reorder to 0..n when mid gap < 0.0005',
        'scenarios': results,
      });
      await db.close();
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('G2: insertOrUpdateByIndex boundary indices', () async {
      final cases = <String, dynamic>{};
      cases['empty_index0'] = await _singleCase(null, 0);
      cases['append_at_length'] = await _singleCase(3, 3);
      cases['index_length_plus_1'] = await _singleCase(3, 4);
      cases['index_way_out_of_range'] = await _singleCase(3, 10);
      writeGolden('G2_insert_or_update_by_index.json', {
        'source': 'models/playlist_episode.dart:90-125 (insertion only, K26)',
        'cases': cases,
      });
    });

    test('G3: toLrc / formatLrcTime', () {
      final segs = [
        {'start': 0.0, 'end': 3.9, 'text': 'First line'},
        {'start': 61.234567, 'end': 125.999, 'text': 'fractional seconds 中文'},
        {'start': 3599.9999, 'end': 3600.5, 'text': 'near the hour mark'},
        {'start': 5.0, 'end': 9.5, 'text': 'emoji 🎧 & “quotes” عربى'},
        {'start': 600.001, 'end': 660.0, 'text': 'ten minutes in'},
      ];
      final sub = SubtitleModel.empty();
      sub.enclosureUrl = 'https://g3.example.com/ep.mp3';
      sub.status = 'succeeded';
      sub.language = 'en';
      sub.subtitle = jsonEncode(segs);
      final tr = TranslationModel.empty();
      tr.enclosureUrl = 'https://g3.example.com/ep.mp3';
      tr.status = 'succeeded';
      tr.language = 'zh';
      tr.translation = jsonEncode(
          segs.map((s) => {...s, 'text': '【译】${s['text']}'}).toList());

      final lrcTimes = <String, String>{
        '0.0': formatLrcTime(0.0),
        '4.999': formatLrcTime(4.999),
        '59.9999': formatLrcTime(59.9999),
        '61.234567': formatLrcTime(61.234567),
        '599.999': formatLrcTime(599.999),
        '3599.9999': formatLrcTime(3599.9999),
        '3600.5': formatLrcTime(3600.5),
      };

      writeGolden('G3_to_lrc.json', {
        'source':
            'SubtitleModel.toLrc / TranslationModel.toLrc / formatLrcTime '
                '(models/subtitle.dart:101-116, formatters.dart:180-185)',
        'subtitle_json': sub.subtitle,
        'subtitle_toLrc': sub.toLrc(),
        'translation_toLrc': tr.toLrc(),
        'formatLrcTime': lrcTimes,
        'note': 'byte-exact LRC text: [mm:ss.mmm] two lines per segment',
      });
    });

    test('G4: exported subtitle text assembly', () {
      final mainLrc =
          '[00:00.000]line one\n[00:03.900]\n[00:04.000]line two\n[00:08.500]\n';
      final trLrc = '[00:00.000]第一行\n[00:03.900]\n';
      writeGolden('G4_export_text.json', {
        'source': 'buildExportText (pages/player.dart:950-978)',
        'cases': {
          'full': buildExportText('Episode 42', 'Some Channel', mainLrc, trLrc),
          'no_translation':
              buildExportText('Episode 42', 'Some Channel', mainLrc, null),
          'empty_translation_string':
              buildExportText('Episode 42', 'Some Channel', mainLrc, ''),
          'null_title_defaults': buildExportText(null, null, mainLrc, null),
          'empty_channel_title_only':
              buildExportText('Solo', '', mainLrc, null),
          'title_with_slash':
              buildExportText('EP/1: crash test', 'Chan', mainLrc, null),
        },
        'note': 'title_with_slash documents K29: filename uses raw subject',
      });
    });

    test('G5: htmlToText / sanitize fallback', () {
      final inputs = [
        'plain text without markup',
        '<p>simple <b>bold</b> paragraph</p>',
        '<p>entity &amp; &lt;test&gt; &quot;quoted&quot;</p>',
        '<div><span>nested</span> <a href="https://x.com">link</a></div>',
        '<script>alert(1)</script><p>after script</p>',
        '<p></p>',
        '<p>   </p>',
        '<p>中文段落与 emoji 🎧</p>',
        '<p style="color:red">styled</p>',
        '   <p>leading whitespace html</p>   ',
        'text starting with lesser-than < symbol',
      ];
      final cases = <Map<String, dynamic>>[];
      for (final input in inputs) {
        final startsWithLt = input.trim().startsWith('<');
        String sanitized = '';
        String? sanitizeError;
        if (startsWithLt) {
          try {
            sanitized = sanitize.sanitizeHtml(input).trim();
          } catch (e) {
            sanitizeError = e.toString();
          }
        }
        final fallbackUsed = startsWithLt && sanitized.isEmpty;
        cases.add({
          'input': input,
          'startsWith_lt': startsWithLt,
          'sanitized': sanitized,
          'sanitize_error': sanitizeError,
          'sanitize_empty_fallback_to_htmlToText': fallbackUsed,
          'htmlToText': htmlToText(input),
          'renderHtml_uses': startsWithLt
              ? (fallbackUsed ? 'htmlToText' : 'sanitized')
              : 'raw text',
        });
      }
      final corpus = <String, String>{};
      final manifest = rssManifest();
      for (final b in ['standard', 'http_plain']) {
        for (final item in (manifest['live'][b] as List).take(3)) {
          final raw =
              File('test/fixtures/rss/$b/${item['file']}').readAsStringSync();
          final m = RegExp(r'<description>([\s\S]{0,2000}?)</description>')
              .firstMatch(raw);
          if (m != null) {
            corpus['${item['file']}'] = htmlToText(m.group(1)!);
          }
        }
      }
      writeGolden('G5_html_to_text.json', {
        'source':
            'htmlToText (rss_fetcher.dart:159-179) + renderHtml 判定 (formatters.dart:80-110)',
        'cases': cases,
        'corpus_channel_descriptions_htmlToText': corpus,
      });
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('G6: OPML parsing', () async {
      final files = [
        'app_export.opml',
        'overcast.opml',
        'xiaoyuzhou.opml',
        'giant_500.opml',
      ];
      final cases = <String, dynamic>{};
      for (final f in files) {
        final path = 'test/fixtures/opml/$f';
        if (!File(path).existsSync()) continue;
        final opml = await parseOPML(path);
        cases[f] = {
          'count': opml.length,
          'entries':
              opml.map((o) => {'title': o.title, 'xmlUrl': o.url}).toList(),
        };
      }
      writeGolden('G6_opml_parse.json', {
        'source': 'parseOPML (pages/feeds.dart:269-300): all nested outlines, '
            'xmlUrl required, title falls back to text',
        'cases': cases,
      });
    });

    test('G7: RSS field mapping', () async {
      final manifest = rssManifest();
      final fixtures = <Map<String, dynamic>>[];

      Future<void> mapFixture(String bucket, String file, String url,
          {bool summaryOnly = false, bool onlyFirst = false}) async {
        final bytes = File('test/fixtures/rss/$bucket/$file').readAsBytesSync();
        try {
          final data = parseFeedResponse(
              url,
              http.Response.bytes(bytes, 200,
                  headers: {'content-type': 'text/xml; charset=utf-8'}),
              onlyFistEpisode: onlyFirst);
          if (data == null) {
            fixtures.add(
                {'bucket': bucket, 'file': file, 'result': 'parse_error_null'});
            return;
          }
          final s = data.subscription!;
          final eps = data.feedEpisodes!;
          final full = eps.length <= 60 && !summaryOnly;
          fixtures.add({
            'bucket': bucket,
            'file': file,
            'onlyFirstEpisode': onlyFirst,
            'subscription': {
              'rssFeedUrl': s.rssFeedUrl,
              'title': s.title,
              'description': s.description?.substring(
                  0, s.description!.length > 300 ? 300 : s.description!.length),
              'imageUrl': s.imageUrl,
              'link': s.link,
              'categories': s.categories,
              'author': s.author,
              'email': s.email,
              'lastUpdated': s.lastUpdated,
            },
            'episode_count': eps.length,
            'episodes_full': full,
            'episodes': (full ? eps : eps.take(3))
                .map((e) => {
                      'title': e.title,
                      'duration': e.duration,
                      'pubDate': e.pubDate,
                      'enclosureUrl': e.enclosureUrl,
                      'imageUrl': e.imageUrl,
                    })
                .toList(),
            'pub_date_desc_sorted':
                _isSortedDesc(eps.map((e) => e.pubDate ?? 0).toList()),
          });
        } catch (e) {
          fixtures.add({
            'bucket': bucket,
            'file': file,
            'throws': e.toString().split('\n').first,
          });
        }
      }

      for (final b in ['standard', 'http_plain', 'user_subs']) {
        for (final item in (manifest['live'][b] as List? ?? [])) {
          await mapFixture(b, item['file'], item['url'],
              summaryOnly: (item['items'] ?? 0) > 200);
        }
      }
      final firstStd = (manifest['live']['standard'] as List).first;
      await mapFixture('standard', firstStd['file'], firstStd['url'],
          onlyFirst: true);

      for (final mf in [
        'no_duration',
        'no_image',
        'no_pubdate',
        'no_author',
        'mixed_duration_formats'
      ]) {
        await mapFixture('missing_fields', '$mf.xml', 'constructed:$mf');
      }
      await mapFixture(
          'weird_dates', 'weird_pubdates.xml', 'constructed:weird_pubdates');
      await mapFixture('giant', 'giant_1200_items.xml', 'constructed:giant',
          summaryOnly: true);
      for (final mf in ['truncated', 'html_error_page', 'bom_prefixed']) {
        await mapFixture('malformed', '$mf.xml', 'constructed:$mf');
      }

      // per-date parse probe (weird dates crash the whole-feed sort; probe singles)
      final weirdDates = ((jsonDecode(
          File('test/fixtures/rss/weird_dates/manifest.json')
              .readAsStringSync()) as List)[0]['dates']) as List;
      final dateProbe = <String, dynamic>{};
      for (final d in weirdDates) {
        final xml =
            '<?xml version="1.0"?><rss version="2.0"><channel><title>t</title>'
            '<item><title>i</title><pubDate>$d</pubDate>'
            '<enclosure url="https://x.example.com/a.mp3" type="audio/mpeg"/></item>'
            '</channel></rss>';
        try {
          final feed = RssFeed.parse(xml);
          final pd = feed.items?.firstOrNull?.pubDate;
          dateProbe['$d'] = pd?.toUtc().millisecondsSinceEpoch;
        } catch (e) {
          dateProbe['$d'] = {'throws': e.toString().split('\n').first};
        }
      }

      writeGolden('G7_rss_mapping.json', {
        'source': 'parseFeedResponse (utils/rss_fetcher.dart): duration '
            'HH:MM:SS|seconds -> ms, pubDate -> epoch ms, categories joined by '
            'comma, items sorted by pubDate desc, onlyFirstEpisode',
        'fixtures': fixtures,
        'weird_date_single_probe': dateProbe,
        'note':
            'pubDate null crashes the sort (K5 baseline); recorded as throws',
      });
    }, timeout: const Timeout(Duration(minutes: 5)));

    test('G8: saveNewEpisodes merge semantics', () async {
      final manifest = rssManifest();
      final item = (manifest['live']['standard'] as List)
          .firstWhere((i) => (i['items'] ?? 0) >= 50);
      final bytes =
          File('test/fixtures/rss/standard/${item['file']}').readAsBytesSync();
      final data = parseFeedResponse(
          item['url'], http.Response.bytes(bytes, 200),
          onlyFistEpisode: false)!;
      final fetched = data.feedEpisodes!;
      final newest = fetched.first.pubDate!;

      final s1 =
          SubscriptionModel.fromMap({..._subMap(data), 'lastUpdated': null});
      final s2 =
          SubscriptionModel.fromMap({..._subMap(data), 'lastUpdated': newest});
      final older = fetched[fetched.length ~/ 2].pubDate!;
      final s3 =
          SubscriptionModel.fromMap({..._subMap(data), 'lastUpdated': older});

      final r1 = computeNewEpisodes([data], [s1]);
      final r2 = computeNewEpisodes([data], [s2]);
      final r3 = computeNewEpisodes([data], [s3]);

      writeGolden('G8_save_new_episodes.json', {
        'source':
            'computeNewEpisodes (pages/feeds.dart:321-357 original logic)',
        'fetched_episode_count': fetched.length,
        'first_import': {
          'updated_subscription_urls':
              r1.subscriptions.map((s) => s.rssFeedUrl).toList(),
          'updated_episode_urls':
              r1.episodes.map((e) => e.enclosureUrl).toList(),
        },
        'local_wins': {
          'updated_subscription_urls':
              r2.subscriptions.map((s) => s.rssFeedUrl).toList(),
          'updated_episode_urls':
              r2.episodes.map((e) => e.enclosureUrl).toList(),
        },
        'local_older': {
          'local_lastUpdated': older,
          'updated_subscription_urls':
              r3.subscriptions.map((s) => s.rssFeedUrl).toList(),
          'updated_episode_urls':
              r3.episodes.map((e) => e.enclosureUrl).toList(),
          'updated_episode_pubDates':
              r3.episodes.map((e) => e.pubDate).toList(),
        },
      });
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('G9: settings codec', () {
      final csvCases = <Map<String, dynamic>>[];
      for (final c in [
        [0, 0, 0],
        [1, 2, 3],
        [23, 23, 6],
        [7, 19, 4],
      ]) {
        final csv = '${c[0]},${c[1]},${c[2]}';
        final parsed = csv.split(',').map(int.parse).toList();
        csvCases.add({
          'encode_input': c,
          'csv': csv,
          'decoded': parsed,
          'mins_value': [null, 10, 20, 30, 40, 50, 60][parsed[2]],
        });
      }

      final speedSteps = List.generate(7, (i) => 0.5 + i * 0.25);
      final countdownMins = List.generate(7, (i) => i * 10);

      final localeCases = <String, dynamic>{};
      for (final locale in [
        'en_US',
        'zh_Hans_CN',
        'zh_CN',
        'fr_FR',
        'zh-Hans-CN',
        'ja-JP',
        'de'
      ]) {
        final parts = locale.split('_');
        var language = 'en';
        var country = 'US';
        if (parts.length > 1) {
          language = parts[0];
          country = parts[parts.length - 1];
        }
        localeCases[locale] = {'language': language, 'country': country};
      }

      writeGolden('G9_settings_codec.json', {
        'source': 'models/settings.dart + states/player.dart:290-311 + '
            'pages/settings.dart lists + player.dart sliders',
        'autoSleepTimer_csv': csvCases,
        'speed_steps': speedSteps,
        'countdown_minutes': countdownMins,
        'countdown_labels': [
          'OFF',
          '10 min',
          '20 min',
          '30 min',
          '40 min',
          '50 min',
          '1 hour'
        ],
        'target_languages': targetLangList,
        'target_language_codes': targetLangList.map((l) => l['code']).toList(),
        'countries_raw': countryList,
        'countries_sorted_by_name': [...countryList]
          ..sort((a, b) => a['name']!.compareTo(b['name']!)),
        'locale_derivation': localeCases,
        'default_row': {
          'note': 'settings.dart:33-36 INSERT OR IGNORE defaults; '
              'autoRefreshInterval=300 (口径裁定, 01 §2)',
          'darkMode': 0,
          'speed': 1.0,
          'skipSilence': 0,
          'autoSleepTimer': '0,0,0',
          'maxCacheCount': 10,
          'autoRefreshInterval': 300,
          'maxFeedEpisodes': 100,
          'maxHistoryEpisodes': 100,
          'continuousPlaying': 1,
        },
        'autoRefresh_choices_seconds': [60, 180, 300, 600, 1800],
        'max_episodes_choices': [50, 100, 200, 300],
      });
    });

    test('G10: time / duration formatting', () {
      final now = DateTime.now();
      final nowMs = now.millisecondsSinceEpoch;
      final past2020 = DateTime.utc(2020, 5, 15, 12, 30).millisecondsSinceEpoch;
      final future2030 = DateTime.utc(2030, 1, 2, 3, 4).millisecondsSinceEpoch;
      final thisYearStart = DateTime.utc(now.year, 1, 5).millisecondsSinceEpoch;
      final lastYear = DateTime.utc(now.year - 1, 6, 15).millisecondsSinceEpoch;

      writeGolden('G10_time_formats.json', {
        'source':
            'utils/formatters.dart + getPlayedAndTotalTime (models/playlist_episode.dart:160-164)',
        'reference_now_ms': nowMs,
        'formatDatetime': {
          'past_2020': formatDatetime(past2020),
          'future_2030': formatDatetime(future2030),
          'this_year_jan': formatDatetime(thisYearStart),
          'last_year': formatDatetime(lastYear),
          'just_now_is_special_cased': 'now' == formatDatetime(nowMs) ||
              formatDatetime(nowMs) == 'just now',
        },
        'formatDate': {
          'past_2020': formatDate(past2020),
          'this_year': formatDate(thisYearStart),
        },
        'formatDuration': {
          'zero': formatDuration(0),
          '59s': formatDuration(59000),
          '1m': formatDuration(60000),
          '99m': formatDuration(99 * 60000),
          '100m': formatDuration(100 * 60000),
          '134m': formatDuration(134 * 60000),
        },
        'formatRemainingTime': {
          'zero_duration': formatRemainingTime(Duration.zero, Duration.zero),
          'unplayed_73m':
              formatRemainingTime(const Duration(minutes: 73), Duration.zero),
          'played_1h13m': formatRemainingTime(
              const Duration(minutes: 90), const Duration(minutes: 17)),
          'played_past_end': formatRemainingTime(
              const Duration(minutes: 30), const Duration(minutes: 35)),
        },
        'getPlayedAndTotalTime': {
          'normal':
              PlaylistEpisodeModel.getPlayedAndTotalTime(1292000, 1916000),
          'null_duration_convention':
              PlaylistEpisodeModel.getPlayedAndTotalTime(5000, 0),
          'hour_rollover':
              PlaylistEpisodeModel.getPlayedAndTotalTime(3661000, 7322000),
        },
        'formatCountdown': {
          'zero': formatCountdown(Duration.zero),
          'negative': formatCountdown(const Duration(seconds: -5)),
          '59s': formatCountdown(const Duration(seconds: 59)),
          '60m': formatCountdown(const Duration(minutes: 60)),
          '59m59s': formatCountdown(const Duration(minutes: 59, seconds: 59)),
        },
        'formatTime': {
          'zero': formatTime(Duration.zero),
          '1h2m3s':
              formatTime(const Duration(hours: 1, minutes: 2, seconds: 3)),
        },
        'urlToDomain': {
          'https': urlToDomain('https://www.ximalaya.com/album/41563226.xml'),
          'no_scheme': urlToDomain('example.com/path'),
        },
        'note':
            'timeago relative branches are computed against reference_now_ms; native side must inject the same instant',
      });
    });

    test('G11: User.fromJson', () {
      final cases = <String, dynamic>{};
      for (final e in [
        {'uid': 'u1', 'expired_at': null, 'remaining': 10, 'plus': 0},
        {
          'uid': 'u2',
          'expired_at': '2027-03-15T09:30:00+00:00',
          'remaining': 42,
          'plus': 1
        },
        {
          'uid': 'u3',
          'expired_at': '2024-07-29T15:35:52+00:00',
          'remaining': 0,
          'plus': 1
        },
        {
          'uid': 'u4',
          'expired_at': '2027-03-15T04:30:00-05:00',
          'remaining': 3,
          'plus': 1
        },
        {
          'uid': 'u5',
          'expired_at': '2027-03-15T09:30:00Z',
          'remaining': 1,
          'plus': 0
        },
      ]) {
        try {
          final user = User.fromJson(e.cast<String, dynamic>());
          cases['${e['expired_at']}'] = {
            'uid': user.uid,
            'remaining': user.remaining,
            'plus': user.plus,
            'expireAt_epoch_ms':
                user.expireAt?.dateTime.toUtc().millisecondsSinceEpoch,
            'expireAt_iso': user.expireAt?.dateTime.toUtc().toIso8601String(),
          };
        } catch (err) {
          cases['${e['expired_at']}'] = {
            'throws': err.toString().split('\n').first
          };
        }
      }
      writeGolden('G11_user_from_json.json', {
        'source':
            'User.fromJson (api/user.dart:17-31), Jiffy pattern yyyy-MM-ddTHH:mm:ssZ',
        'cases': cases,
      });
    });

    test('G12: shortlink request params', () {
      final urls = [
        'https://anycast.website/player?rssfeedurl=https%3A%2F%2Fexample.com%2Ffeed.xml&enclosureurl=https%3A%2F%2Fexample.com%2Fep1.mp3',
        'https://anycast.website/channel?rssfeedurl=https%3A%2F%2Fexample.com%2Ffeed.xml',
        'https://anycast.website/player?rssfeedurl=&enclosureurl=',
      ];
      final cases = <Map<String, dynamic>>[];
      for (final u in urls) {
        cases.add({
          'url': u,
          'md5': getMd5(u),
          'md5_len': getMd5(u).length,
          'body_json': jsonEncode({
            'cmd': 'add',
            'url': u,
            'password': password,
            'key': getMd5(u),
          }),
          'result_url_when_ok': Uri(
            scheme: 'https',
            host: 's.kindjeff.com',
            path: '/${getMd5(u)}',
          ).toString(),
        });
      }
      writeGolden('G12_shortlink_params.json', {
        'source': 'api/share.dart:12-57',
        'timeout_seconds': 3,
        'retry_max_attempts': 3,
        'retry_only': ['SocketException', 'TimeoutException'],
        'cases': cases,
      });
    });

    test('G13: chat history array construction', () async {
      final controller = chat.InMemoryChatController();
      final cases = <String, dynamic>{};

      Future<List<Map<String, String>>> scenario(
          List<(String, String)> msgs) async {
        for (var i = 0; i < msgs.length; i++) {
          await controller.insertMessage(chat.TextMessage(
            id: 'm$i',
            authorId: msgs[i].$1,
            createdAt: DateTime.utc(2026, 1, 1, 12, 0, i),
            text: msgs[i].$2,
          ));
        }
        final h = buildChatHistory(controller.messages);
        await controller.setMessages(const []);
        return h;
      }

      cases['two_messages'] =
          await scenario([('human', 'hello'), ('ai', 'hi')]);
      cases['ten_messages'] = await scenario(
          [for (var i = 0; i < 10; i++) (i.isEven ? 'human' : 'ai', 'msg $i')]);
      cases['twelve_messages_cutoff'] = await scenario(
          [for (var i = 0; i < 12; i++) (i.isEven ? 'human' : 'ai', 'msg $i')]);

      writeGolden('G13_chat_history.json', {
        'source': 'buildChatHistory (states/chat.dart, original sendMessage '
            'lines 26-35): first 10 in list order, single-key maps, reversed',
        'cases': cases,
        'contract_note': 'history末元素即当前 user_input(≤10条时); >10条时发送的是'
            '最旧10条(旧版实际行为,不得"修复")',
      });
    });

    test('G14: getTextSafeColor', () {
      // Vendored verbatim from 1.2.1+38 (formatters.dart:139-153): the
      // function was REMOVED upstream by the post-baseline visual-refresh
      // PRs. Goldens pin the released baseline behavior, which native must
      // still replicate for the lyrics view text color.
      Color baselineGetTextSafeColor(Color dynamicColor) {
        // 定义亮度阈值，低于这个值就认为颜色太暗
        const double brightnessThreshold = 0.2;

        // 计算颜色的亮度
        double brightness = dynamicColor.computeLuminance();

        if (brightness < brightnessThreshold) {
          // 如果颜色太暗，返回一个替代颜色
          return const Color(0xFF10B981);
        } else {
          // 如果颜色亮度足够，返回原始的动态颜色
          return dynamicColor;
        }
      }

      final inputs = [
        0xFF000000,
        0xFF0A0A0A,
        0xFF111111,
        0xFF1A1A1A,
        0xFF222222,
        0xFF2A2A2A,
        0xFF333333,
        0xFF555555,
        0xFF808080,
        0xFFAAAAAA,
        0xFFFFFFFF,
        0xFF10B981,
        0xFF113316,
      ];
      final cases = <String, dynamic>{};
      for (final v in inputs) {
        final c = Color(v);
        final result = baselineGetTextSafeColor(c);
        final resultHex = result.toARGB32().toRadixString(16).toUpperCase();
        cases['0x${v.toRadixString(16).toUpperCase().padLeft(8, '0')}'] = {
          'luminance': c.computeLuminance(),
          'threshold': 0.2,
          'returns_fallback': result.toARGB32() == 0xFF10B981,
          'result': '0x${resultHex.padLeft(8, '0')}',
        };
      }
      writeGolden('G14_text_safe_color.json', {
        'source': 'getTextSafeColor (utils/formatters.dart:139-153 @ '
            '1.2.1+38; function removed by post-baseline visual refresh on '
            'the Flutter line — native still implements this released '
            'behavior)',
        'fallback': '0xFF10B981',
        'cases': cases,
      });
    });

    test('G15: DB normalized dumps', () async {
      final buckets = [
        'db_light',
        'db_heavy',
        'db_user',
        'db_device',
        'db_dirty',
        'db_v3',
        'db_edge_subs',
        'db_crashed',
        'db_corrupt_truncated',
        'db_corrupt_notadb',
        'db_corrupt_partial',
      ];
      const tables = [
        'playlist',
        'player',
        'settings',
        'subscription',
        'feedEpisode',
        'playlistEpisode',
        'historyEpisode',
        'subtitle',
        'translation',
      ];
      for (final b in buckets) {
        final path = 'test/fixtures/db/$b/anycast.db';
        final dump = <String, dynamic>{'bucket': b};
        try {
          final db = await databaseFactory.openDatabase(absPath(path));
          dump['user_version'] =
              (await db.rawQuery('PRAGMA user_version')).first.values.first;
          for (final t in tables) {
            dump[t] = await db.rawQuery('SELECT * FROM $t ORDER BY id ASC');
          }
          dump['sqlite_sequence'] = await db
              .rawQuery('SELECT * FROM sqlite_sequence ORDER BY name ASC');
          await db.close();
        } catch (e) {
          dump['open_error'] = e.toString().split('\n').first;
        }
        for (final meta in ['anycast_episode', 'libCachedImageData']) {
          final mp = 'test/fixtures/db/$b/Library/Application Support/$meta.db';
          if (File(mp).existsSync()) {
            try {
              final db = await databaseFactory.openDatabase(absPath(mp));
              dump[meta] = {
                'user_version': (await db.rawQuery('PRAGMA user_version'))
                    .first
                    .values
                    .first,
                'cacheObject': await db
                    .rawQuery('SELECT * FROM cacheObject ORDER BY _id ASC'),
              };
              await db.close();
            } catch (e) {
              dump[meta] = {'open_error': e.toString().split('\n').first};
            }
          }
        }
        if (b == 'db_crashed') {
          dump['note'] =
              'dumped AFTER sqlite rolled back the hot journal; in-flight row must be absent';
        }
        writeGolden('G15_db_dump/$b.json', dump);
      }
    }, timeout: const Timeout(Duration(minutes: 5)));

    test('G16: search result trim', () {
      final raw = {
        'rss_url': 'https://example.com/feed.xml',
        'title': '  Padded Channel Title  ',
        'description': '\n description with newlines \t',
        'small_cover_url': 'https://img.example.com/x.jpg',
        'link': 'https://example.com/',
        'keywords': ['tech', 'news', ' culture '],
        'author': '  Author Name  ',
      };
      final trimmed = resMap2Channel(raw.cast<String, dynamic>());
      writeGolden('G16_search_trim.json', {
        'source': 'resMap2Channel (api/podcasts.dart:32-43)',
        'input': raw,
        'output': {
          'rssFeedUrl': trimmed.rssFeedUrl,
          'title': trimmed.title,
          'description': trimmed.description,
          'imageUrl': trimmed.imageUrl,
          'link': trimmed.link,
          'categories': trimmed.categories,
          'author': trimmed.author,
          'email': trimmed.email,
        },
      });
    });

    test('G-palette: dominant colors of cover images', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final cases = <Map<String, dynamic>>[];
      final dir = Directory('test/fixtures/images');
      if (dir.existsSync()) {
        final files = dir.listSync().whereType<File>().toList()
          ..sort((a, b) => a.path.compareTo(b.path));
        for (final f in files) {
          try {
            final provider = FileImage(f);
            final palette = await PaletteGenerator.fromImageProvider(provider);
          final dominant = palette.dominantColor?.color;
          final dominantInt = dominant?.toARGB32();
          cases.add({
            'file': f.uri.pathSegments.last,
            'dominantColor':
                '0x${dominantInt?.toRadixString(16).toUpperCase().padLeft(8, '0')}',
            'dominantColor_int': dominantInt,
          });
          } catch (e) {
            cases.add({'file': f.uri.pathSegments.last, 'error': e.toString()});
          }
        }
      }
      writeGolden('G_palette_dominant.json', {
        'source':
            'PaletteGenerator.fromImageProvider (utils/formatters.dart:167-177)',
        'fallback': '0xFF111316',
        'assertion_note':
            'native CoreImage comparison uses CIEDE2000 < 10, not exact equality (05 §3)',
        'cases': cases,
      });
    }, timeout: const Timeout(Duration(minutes: 5)));

    test('manifest', () {
      final files = Directory(goldenDir)
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.json'))
          .map((f) => f.path.substring(goldenDir.length + 1))
          .toList()
        ..sort();
      writeGolden('manifest.json', {
        'generated_at': DateTime.now().toUtc().toIso8601String(),
        'app_version': '1.2.1+38',
        'generator': 'test/golden/export_golden_test.dart',
        'files': [
          for (final f in files)
            {'file': f, 'bytes': File('$goldenDir/$f').lengthSync()}
        ],
      });
    });
  }, skip: _regen ? false : 'pass --dart-define=m0-regen=true to regenerate');
}

// ---------------------------------------------------------------------------
// G1/G2 helpers

Future<void> _createPlaylistOnly(Database db) async {
  await db.execute('''
    CREATE TABLE IF NOT EXISTS playlistEpisode (
      id INTEGER PRIMARY KEY,
      title TEXT,
      description TEXT,
      duration INTEGER,
      enclosureUrl TEXT UNIQUE,
      pubDate INTEGER,
      imageUrl TEXT,
      channelTitle TEXT,
      rssFeedUrl TEXT,
      playlistId INTEGER,
      position REAL,
      playedDuration INTEGER
    )
  ''');
}

PlaylistEpisodeModel _ep(int i) {
  return PlaylistEpisodeModel.fromMap({
    'title': 'Episode $i',
    'enclosureUrl': 'https://g1.example.com/ep-$i.mp3',
    'duration': 600000 + i,
    'pubDate': 1700000000000 + i * 604800000,
    'channelTitle': 'Channel',
    'rssFeedUrl': 'https://g1.example.com/feed.xml',
    'playlistId': 1,
  });
}

List<Map<String, dynamic>> _opsHead(int n) => [
      for (var i = 0; i < n; i++)
        {'index': 0, 'url': 'https://g1.example.com/ep-$i.mp3', 'n': i}
    ];

List<Map<String, dynamic>> _opsMidSaturation() {
  // prefill two, then insert repeatedly at index 1 -> midpoint halves until
  // gap < 0.0005 -> _reorder fires
  return [
    {'index': 0, 'url': 'https://g1.example.com/ep-1000.mp3', 'n': 1000},
    {'index': 0, 'url': 'https://g1.example.com/ep-1001.mp3', 'n': 1001},
    for (var i = 0; i < 8; i++)
      {
        'index': 1,
        'url': 'https://g1.example.com/ep-${2000 + i}.mp3',
        'n': 2000 + i
      },
  ];
}

List<Map<String, dynamic>> _opsMixedSeeded(int n) {
  // deterministic pseudo-random mix of head/mid/tail inserts
  final ops = <Map<String, dynamic>>[];
  var seed = 42;
  int rnd() => seed = (seed * 1103515245 + 12345) & 0x7fffffff;
  for (var i = 0; i < n; i++) {
    ops.add({
      'index': rnd() % (i + 1),
      'url': 'https://g1.example.com/ep-$i.mp3',
      'n': i
    });
  }
  return ops;
}

Future<Map<String, dynamic>> _runOps(
    dynamic db, List<Map<String, dynamic>> ops) async {
  final steps = <Map<String, dynamic>>[];
  for (var i = 0; i < ops.length; i++) {
    final ep = _ep(ops[i]['n'] as int);
    await PlaylistEpisodeModel.insertOrUpdateByIndex(
        db, 1, ops[i]['index'] as int, ep);
    final list = await PlaylistEpisodeModel.listByPlaylistId(db, 1);
    final positions = list.map((e) => e.position).toList();
    steps.add({
      'op': ops[i],
      'positions': positions,
      'urls': list.map((e) => e.enclosureUrl).toList(),
      'reordered': _looksReordered(positions),
    });
  }
  return {'ops': ops.length, 'steps': steps};
}

bool _looksReordered(List<double?> positions) {
  if (positions.length < 2) return false;
  for (var i = 0; i < positions.length; i++) {
    if (positions[i] != i.toDouble()) return false;
  }
  return true;
}

Future<Map<String, dynamic>> _singleCase(int? prefill, int index) async {
  final db = await databaseFactory.openDatabase(inMemoryDatabasePath,
      options: OpenDatabaseOptions(
          version: 1, onCreate: (db, v) => _createPlaylistOnly(db)));
  if (prefill != null) {
    for (var i = 0; i < prefill; i++) {
      await PlaylistEpisodeModel.insertOrUpdateByIndex(db, 1, 0, _ep(100 + i));
    }
  }
  try {
    await PlaylistEpisodeModel.insertOrUpdateByIndex(db, 1, index, _ep(999));
    final list = await PlaylistEpisodeModel.listByPlaylistId(db, 1);
    final result = {
      'prefill': prefill,
      'index': index,
      'positions': list.map((e) => e.position).toList(),
      'threw': false,
    };
    await db.close();
    return result;
  } catch (e) {
    await db.close();
    return {
      'prefill': prefill,
      'index': index,
      'threw': true,
      'error': e.toString().split('\n').first,
    };
  }
}

Map<String, dynamic> _subMap(PodcastImportData data) {
  final s = data.subscription!;
  return {
    'rssFeedUrl': s.rssFeedUrl,
    'title': s.title,
    'description': s.description,
    'imageUrl': s.imageUrl,
    'link': s.link,
    'categories': s.categories,
    'author': s.author,
    'email': s.email,
    'lastUpdated': s.lastUpdated,
  };
}

bool _isSortedDesc(List<int> values) {
  for (var i = 1; i < values.length; i++) {
    if (values[i - 1] < values[i]) return false;
  }
  return true;
}
