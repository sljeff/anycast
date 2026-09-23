// M0 DB fixtures generator (05 §1.1): builds every fixture bucket under
// test/fixtures/db/ using the app's REAL table creators, models and insertion
// algorithms, fed by the archived RSS corpus + channels index.
//
// Run: flutter test test/fixtures/generate_db_fixtures_test.dart \
//         --dart-define=m0-regen=true
// (offline; depends only on test/fixtures/rss + test/fixtures/channels_index.json)
// Without the define this test is SKIPPED so plain `flutter test` never
// rewrites the fixtures.
//
// Determinism: fixed epoch base; live-corpus content is whatever is in git.
// The settings default row is created by settingsTableCreator (which reads the
// host locale) and then normalized by explicit UPDATEs below.
// NOTE: lives OUTSIDE test/fixtures/db because generation wipes that directory.
// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';

import 'package:anycast/models/feed_episode.dart';
import 'package:anycast/models/helper.dart' show tableCreators;
import 'package:anycast/models/history_episode.dart';
import 'package:anycast/models/player.dart';
import 'package:anycast/models/playlist_episode.dart';
import 'package:anycast/models/subtitle.dart';
import 'package:anycast/models/subscription.dart';
import 'package:anycast/models/translation.dart';
import 'package:anycast/utils/rss_fetcher.dart';
import 'package:anycast/widgets/import_export.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

final baseEpoch = DateTime.utc(2026, 6, 1).millisecondsSinceEpoch;

const _regen = bool.fromEnvironment('m0-regen');

/// sqflite_common_ffi redirects RELATIVE db paths under flutter test to
/// .dart_tool/sqflite_common_ffi/databases/ — always pass absolute paths.
String absPath(String p) =>
    p.startsWith('/') ? p : '${Directory.current.path}/$p';

late Directory dbRoot;

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  setUpAll(() {
    dbRoot = Directory('test/fixtures/db');
  });

  test('generate all db fixture buckets', () async {
    // Wipe only generator-owned buckets; db_device is a pulled iOS container
    // (integration_test/m0_seed_test.dart), not regenerable here.
    const generated = [
      'db_light', 'db_heavy', 'db_user', 'db_dirty', 'db_v3',
      'db_edge_subs', 'db_crashed', 'db_corrupt_truncated',
      'db_corrupt_notadb', 'db_corrupt_partial', 'db_smoke',
    ];
    for (final b in generated) {
      final d = Directory('${dbRoot.path}/$b');
      if (d.existsSync()) d.deleteSync(recursive: true);
    }
    dbRoot.createSync(recursive: true);

    final sources = await FixtureSources.load();

    await buildLight(sources);
    await buildHeavy(sources);
    await buildUser(sources);
    await buildDirty(sources);
    await buildV3();
    await buildCrashed();
    await buildCorrupt();
    await buildEdgeSubs(sources);
    await buildSmoke(sources);
    await writeOpmlFixture(sources);

    print('all db fixture buckets written under ${dbRoot.path}');
  }, skip: _regen ? false : 'pass --dart-define=m0-regen=true to regenerate');
}

// ---------------------------------------------------------------------------
// sources

class FixtureSources {
  final List<Map<String, dynamic>> channelsIndex;
  // rssFeedUrl -> parsed import data (real mapping code over archived XML)
  final List<PodcastImportData> parsedFeeds;
  // the author's real subscription export (rss/user_subs bucket)
  final List<PodcastImportData> userFeeds;

  FixtureSources(this.channelsIndex, this.parsedFeeds, this.userFeeds);

  static Future<FixtureSources> load() async {
    final indexFile = File('test/fixtures/channels_index.json');
    final channelsIndex = (jsonDecode(indexFile.readAsStringSync()) as List)
        .cast<Map<String, dynamic>>();

    final parsed = <PodcastImportData>[];
    for (final bucket in ['standard', 'http_plain']) {
      final dir = Directory('test/fixtures/rss/$bucket');
      if (!dir.existsSync()) continue;
      for (final f in dir.listSync()) {
        if (!f.path.endsWith('.xml')) continue;
        final bytes = File(f.path).readAsBytesSync();
        final url = _urlForCorpusFile(f.path);
        final resp = http.Response.bytes(bytes, 200);
        final data = parseFeedResponse(url, resp, onlyFistEpisode: false);
        if (data != null && data.subscription?.title != null) {
          parsed.add(data);
        }
      }
    }

    final userFeeds = <PodcastImportData>[];
    final userManifestFile =
        File('test/fixtures/rss/user_subs/manifest.json');
    if (userManifestFile.existsSync()) {
      final userManifest =
          (jsonDecode(userManifestFile.readAsStringSync()) as List)
              .cast<Map<String, dynamic>>();
      final urlByFile = {
        for (final item in userManifest)
          item['file'] as String: item['url'] as String,
      };
      final dir = Directory('test/fixtures/rss/user_subs');
      for (final f in dir.listSync()) {
        if (!f.path.endsWith('.xml')) continue;
        final file = f.path.split(Platform.pathSeparator).last;
        final url = urlByFile[file];
        if (url == null) continue;
        final bytes = File(f.path).readAsBytesSync();
        final data = parseFeedResponse(
            url, http.Response.bytes(bytes, 200),
            onlyFistEpisode: false);
        if (data != null && data.subscription?.title != null) {
          userFeeds.add(data);
        }
      }
    }
    return FixtureSources(channelsIndex, parsed, userFeeds);
  }

  static String _urlForCorpusFile(String path) {
    final manifest =
        jsonDecode(File('test/fixtures/rss/manifest.json').readAsStringSync())
            as Map<String, dynamic>;
    final file = path.split(Platform.pathSeparator).last;
    for (final b in ['standard', 'http_plain']) {
      for (final item in (manifest['live'][b] as List)) {
        if (item['file'] == file) return item['url'] as String;
      }
    }
    return 'https://unknown.example.com/$file';
  }

  /// ≥[minCount] subscriptions with unique titles (title is UNIQUE).
  List<SubscriptionModel> subscriptions({required int minCount}) {
    final seen = <String>{};
    final result = <SubscriptionModel>[];
    for (final d in parsedFeeds) {
      final s = d.subscription!;
      if (s.title == null || seen.contains(s.title)) continue;
      seen.add(s.title!);
      result.add(s);
      if (result.length >= minCount) break;
    }
    var i = 0;
    while (result.length < minCount && i < channelsIndex.length) {
      final c = channelsIndex[i++];
      final title = (c['title'] as String?)?.trim();
      final url = c['url'] as String?;
      if (title == null ||
          title.isEmpty ||
          url == null ||
          seen.contains(title)) {
        continue;
      }
      seen.add(title);
      result.add(SubscriptionModel.fromMap({
        'rssFeedUrl': url,
        'title': title,
        'description': (c['description'] as String?) ?? '',
        'imageUrl': c['image'],
        'link': c['link'],
        'categories': null,
        'author': null,
        'email': null,
        // index-only feeds have no archived XML: deterministic lastUpdated
        'lastUpdated': baseEpoch + result.length * 86400000,
      }));
    }
    return result;
  }

  /// Real feed episodes across archived feeds, newest first.
  List<FeedEpisodeModel> feedEpisodes({int limit = 300}) {
    final all = <FeedEpisodeModel>[];
    for (final d in parsedFeeds) {
      all.addAll(d.feedEpisodes!);
    }
    all.sort((a, b) => (b.pubDate ?? 0).compareTo(a.pubDate ?? 0));
    // dedupe by enclosureUrl (UNIQUE constraint)
    final seen = <String>{};
    final out = <FeedEpisodeModel>[];
    for (final e in all) {
      if (e.enclosureUrl == null || seen.contains(e.enclosureUrl)) continue;
      seen.add(e.enclosureUrl!);
      out.add(e);
      if (out.length >= limit) break;
    }
    return out;
  }

  /// Feed episodes from the author's subscription set, newest first.
  List<FeedEpisodeModel> userFeedEpisodes({int limit = 500}) {
    final all = <FeedEpisodeModel>[];
    for (final d in userFeeds) {
      all.addAll(d.feedEpisodes!);
    }
    all.sort((a, b) => (b.pubDate ?? 0).compareTo(a.pubDate ?? 0));
    final seen = <String>{};
    final out = <FeedEpisodeModel>[];
    for (final e in all) {
      if (e.enclosureUrl == null || seen.contains(e.enclosureUrl)) continue;
      seen.add(e.enclosureUrl!);
      out.add(e);
      if (out.length >= limit) break;
    }
    return out;
  }
}

// ---------------------------------------------------------------------------
// bucket builders

Future<Database> createDb(String path) {
  return databaseFactory.openDatabase(absPath(path),
      options: OpenDatabaseOptions(
          version: 4,
          onCreate: (db, v) async {
            for (final creator in tableCreators) {
              await creator(db);
            }
          }));
}

Future<void> normalizeSettings(Database db,
    {String country = 'US',
    String language = 'en',
    double speed = 1.0,
    String autoSleepTimer = '0,0,0',
    int maxCacheCount = 10,
    int autoRefreshInterval = 300,
    int maxFeedEpisodes = 100,
    int maxHistoryEpisodes = 100,
    int continuousPlaying = 1,
    int skipSilence = 0,
    int darkMode = 0}) async {
  await db.rawUpdate('''
    UPDATE settings SET darkMode = ?, speed = ?, skipSilence = ?,
      autoSleepTimer = ?, maxCacheCount = ?, countryCode = ?, targetLanguage = ?,
      autoRefreshInterval = ?, maxFeedEpisodes = ?, maxHistoryEpisodes = ?,
      continuousPlaying = ?
    WHERE id = 1
  ''', [
    darkMode,
    speed,
    skipSilence,
    autoSleepTimer,
    maxCacheCount,
    country,
    language,
    autoRefreshInterval,
    maxFeedEpisodes,
    maxHistoryEpisodes,
    continuousPlaying,
  ]);
}

List<Map<String, dynamic>> subtitleSegments(int count, {bool special = false}) {
  return List.generate(count, (i) {
    final text = special
        ? (i % 5 == 0
            ? 'café — “quotes” 中文混排 عربى 🎧'
            : 'Segment $i with a moderately long sentence about podcasting. ' *
                3)
        : 'Transcript segment $i of the episode.';
    return {
      'start': (i * 4.2),
      'end': (i * 4.2 + 3.9),
      'text': text,
    };
  });
}

Future<void> writeCacheMetaDb(String dir, List<String> enclosureUrls,
    {bool farFutureValidTill = false}) async {
  final supportDir = Directory('$dir/Library/Application Support');
  supportDir.createSync(recursive: true);
  final cacheDir = Directory('$dir/Library/Caches/anycast_episode');
  cacheDir.createSync(recursive: true);
  final audioBytes =
      File('test/fixtures/audio/very_short_8s.mp3').readAsBytesSync();

  final db = await databaseFactory.openDatabase(
      absPath('${supportDir.path}/anycast_episode.db'),
      options: OpenDatabaseOptions(
          version: 3,
          onCreate: (db, v) async {
            await db.execute('''
      create table cacheObject (
        _id integer primary key,
        url text,
        key text,
        relativePath text,
        eTag text,
        validTill integer,
        touched integer,
        length integer
        );
      ''');
          }));

  final batch = db.batch();
  for (var i = 0; i < enclosureUrls.length && i < 3; i++) {
    final name = fakeUuidV1(baseEpoch + i * 1000);
    File('${cacheDir.path}/$name.mp3').writeAsBytesSync(audioBytes);
    final touched = baseEpoch + 86400000 * i;
    batch.insert('cacheObject', {
      'url': enclosureUrls[i],
      'key': enclosureUrls[i],
      'relativePath': '$name.mp3',
      'eTag': '"etag-$i"',
      // The smoke bucket must survive the native stale cleanup
      // (validTill < now ⇒ row + file deleted), so its rows carry a
      // deterministic far-future expiry instead of the corpus dates.
      'validTill': farFutureValidTill
          ? baseEpoch + 10 * 365 * 86400000
          : touched + 30 * 86400000,
      'touched': touched,
      'length': audioBytes.length,
    });
  }
  await batch.commit(noResult: true);
  await db.close();

  // image cache meta DB (files deliberately absent: tolerated-orphan case)
  final db2 = await databaseFactory.openDatabase(
      absPath('${supportDir.path}/libCachedImageData.db'),
      options: OpenDatabaseOptions(
          version: 3,
          onCreate: (db, v) async {
            await db.execute('''
      create table cacheObject (
        _id integer primary key,
        url text,
        key text,
        relativePath text,
        eTag text,
        validTill integer,
        touched integer,
        length integer
        );
      ''');
          }));
  final b2 = db2.batch();
  for (var i = 0; i < 3; i++) {
    b2.insert('cacheObject', {
      'url': 'https://img.example.com/cover$i.jpg',
      'key': 'https://img.example.com/cover$i.jpg',
      'relativePath': '${fakeUuidV1(baseEpoch + 7 * 86400000 + i)}.jpg',
      'eTag': null,
      'validTill': baseEpoch + 30 * 86400000,
      'touched': baseEpoch,
      'length': 120000 + i,
    });
  }
  await b2.commit(noResult: true);
  await db2.close();
}

String fakeUuidV1(int epochMs) {
  // deterministic uuid-v1-shaped name (layout is not semantically consumed:
  // files are located purely via the DB relativePath column)
  final ts = (epochMs & 0xFFFFFFFFFFFF).toRadixString(16).padLeft(12, '0');
  final rand =
      (epochMs * 2654435761 & 0xFFFFFFFF).toRadixString(16).padLeft(8, '0');
  final hex = '$ts${rand}1ae49c0ffee'.padRight(32, '0').substring(0, 32);
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-'
      '${hex.substring(16, 20)}-${hex.substring(20, 32)}';
}

Future<void> fillPlaylist(Database db, List<FeedEpisodeModel> eps) async {
  for (var i = 0; i < eps.length; i++) {
    final ep = PlaylistEpisodeModel.fromMap(eps[i].toMap());
    ep.playlistId = 1;
    // realistic usage: mostly "add to top", occasional mid insert
    final index = (i % 7 == 3) ? (i ~/ 2) : 0;
    await PlaylistEpisodeModel.insertOrUpdateByIndex(db, 1, index, ep);
  }
  // first (current) episodes partially played
  final list = await PlaylistEpisodeModel.listByPlaylistId(db, 1);
  for (var i = 0; i < list.length && i < 8; i++) {
    list[i].playedDuration = ((list[i].duration ?? 3600000) * 0.3).round();
    await db.update(
        'playlistEpisode', {'playedDuration': list[i].playedDuration},
        where: 'enclosureUrl = ?', whereArgs: [list[i].enclosureUrl]);
  }
}

Future<void> fillSubtitlesAndTranslations(
    Database db, List<String> enclosureUrls, int count) async {
  for (var i = 0; i < count; i++) {
    final url = enclosureUrls[i % enclosureUrls.length];
    final sub = SubtitleModel.empty();
    sub.enclosureUrl = url;
    sub.status = 'succeeded';
    sub.language = 'en';
    sub.subtitle = jsonEncode(subtitleSegments(40 + i, special: i.isOdd));
    await SubtitleModel.insert(db, sub);

    final tr = TranslationModel.empty();
    tr.enclosureUrl = url;
    tr.status = 'succeeded';
    tr.language = 'zh';
    tr.translation = jsonEncode(subtitleSegments(40 + i)
        .map((s) =>
            {'start': s['start'], 'end': s['end'], 'text': '【译】${s['text']}'})
        .toList());
    await TranslationModel.insert(db, tr);
  }
}

Future<void> buildLight(FixtureSources sources) async {
  final dir = '${dbRoot.path}/db_light';
  await Directory(dir).create(recursive: true);
  final db = await createDb('$dir/anycast.db');

  final subs = sources.subscriptions(minCount: 4);
  await SubscriptionModel.addMany(db, subs);

  final eps = sources.feedEpisodes(limit: 20);
  await FeedEpisodeModel.insertMany(db, eps);

  await fillPlaylist(db, eps.sublist(0, 3));
  await normalizeSettings(db);
  await db.close();

  await writeCacheMetaDb(dir, eps.take(2).map((e) => e.enclosureUrl!).toList());
}

/// db_smoke: the REPRODUCIBLE `-m2-smoke-play` container (2026-09-23
/// correction — the recorded M2 smoke numbers cannot be replayed from the
/// committed db_light: its player pointer is NULL, so restore returns early
/// and the smoke guard never fires, and its queue head is an uncached
/// podtrac URL). Unlike db_light: ① `player.currentPlaylistId` is set;
/// ② the queue head is a CACHED episode; ③ the head's playedDuration sits
/// INSIDE the 8s fixture audio (db_light's 30%-of-RSS-duration values seek
/// past the end of the file); ④ cache rows carry a far-future validTill so
/// the native stale cleanup keeps them.
Future<void> buildSmoke(FixtureSources sources) async {
  final dir = '${dbRoot.path}/db_smoke';
  await Directory(dir).create(recursive: true);
  final db = await createDb('$dir/anycast.db');

  final subs = sources.subscriptions(minCount: 4);
  await SubscriptionModel.addMany(db, subs);

  final eps = sources.feedEpisodes(limit: 20);
  await FeedEpisodeModel.insertMany(db, eps);

  // Deterministic queue (fillPlaylist scatters for realism): insert
  // bottom-up so eps[1] — a cached ximalaya episode — is the head, and the
  // uncached podtrac episode sits last for a manual miss-path run.
  for (final e in [eps[2], eps[0], eps[1]]) {
    final ep = PlaylistEpisodeModel.fromMap(e.toMap());
    ep.playlistId = 1;
    await PlaylistEpisodeModel.insertOrUpdateByIndex(db, 1, 0, ep);
  }
  await PlayerModel.update(
      db, PlayerModel.fromMap({'currentPlaylistId': 1}));
  await db.update(
      'playlistEpisode', {'playedDuration': 3000},
      where: 'enclosureUrl = ?', whereArgs: [eps[1].enclosureUrl]);
  await normalizeSettings(db);
  await db.close();

  await writeCacheMetaDb(dir,
      eps.take(2).map((e) => e.enclosureUrl!).toList(),
      farFutureValidTill: true);
}

Future<void> buildHeavy(FixtureSources sources) async {
  final dir = '${dbRoot.path}/db_heavy';
  await Directory(dir).create(recursive: true);
  final db = await createDb('$dir/anycast.db');

  final subs = sources.subscriptions(minCount: 40);
  await SubscriptionModel.addMany(db, subs);

  final eps = sources.feedEpisodes(limit: 300);
  await FeedEpisodeModel.insertMany(db, eps);

  // history: played oldest->newest so id DESC == most-recently-played first
  final oldestFirst = eps.reversed.toList();
  for (var i = 0; i < 300 && i < oldestFirst.length; i++) {
    await HistoryEpisodeModel.insert(
        db, HistoryEpisodeModel.fromMap(oldestFirst[i].toMap()));
  }

  await fillPlaylist(db, eps.sublist(0, 55));
  await fillSubtitlesAndTranslations(
      db, eps.take(55).map((e) => e.enclosureUrl!).toList(), 12);
  await normalizeSettings(db,
      country: 'CN',
      language: 'zh',
      speed: 1.5,
      autoSleepTimer: '1,2,3',
      maxFeedEpisodes: 300,
      maxHistoryEpisodes: 300,
      skipSilence: 1,
      continuousPlaying: 0);
  await db.close();

  await writeCacheMetaDb(dir, eps.take(3).map((e) => e.enclosureUrl!).toList());
}

/// db_user: the author's real subscription set (rss/user_subs corpus) written
/// through the app's real model insert paths. Stands in for a real-device
/// pull until container extraction is done (05 §1.1 fallback path c).
Future<void> buildUser(FixtureSources sources) async {
  final dir = '${dbRoot.path}/db_user';
  await Directory(dir).create(recursive: true);
  final db = await createDb('$dir/anycast.db');

  final subs = [for (final d in sources.userFeeds) d.subscription!];
  await SubscriptionModel.addMany(db, subs);

  final eps = sources.userFeedEpisodes(limit: 500);
  await FeedEpisodeModel.insertMany(db, eps);

  // history: played oldest->newest so id DESC == most-recently-played first
  final oldestFirst = eps.reversed.toList();
  for (var i = 0; i < 40 && i < oldestFirst.length; i++) {
    await HistoryEpisodeModel.insert(
        db, HistoryEpisodeModel.fromMap(oldestFirst[i].toMap()));
  }

  await fillPlaylist(db, eps.sublist(0, eps.length < 15 ? eps.length : 15));
  await fillSubtitlesAndTranslations(
      db, eps.take(15).map((e) => e.enclosureUrl!).toList(), 6);
  await normalizeSettings(db, country: 'CN', language: 'zh');
  await db.close();

  await writeCacheMetaDb(dir, eps.take(3).map((e) => e.enclosureUrl!).toList());
}

Future<void> buildDirty(FixtureSources sources) async {
  final dir = '${dbRoot.path}/db_dirty';
  await Directory(dir).create(recursive: true);
  final db = await createDb('$dir/anycast.db');

  final subs = sources.subscriptions(minCount: 5);
  await SubscriptionModel.addMany(db, subs);
  final eps = sources.feedEpisodes(limit: 30);
  await FeedEpisodeModel.insertMany(db, eps);
  await normalizeSettings(db);

  // dirty rows (05 §1.1): NULL duration / NULL pubDate / >100KB HTML
  // description / emoji-CJK-RTL titles / empty strings
  final big =
      '<p>${'lorem ipsum dolor sit amet <b>bold</b> &amp; entity '.padRight(2048, 'x')}</p>' *
          64;
  final dirty = [
    {
      'duration': null,
      'pubDate': baseEpoch,
      'description': 'null duration row'
    },
    {'duration': 3600000, 'pubDate': null, 'description': 'null pubDate row'},
    {'duration': 3600000, 'pubDate': baseEpoch + 1, 'description': big},
    {
      'duration': 3600000,
      'pubDate': baseEpoch + 2,
      'title': 'emoji 🎧🚀 与中文混排 — عربى RIGHT-TO-LEFT — 日本語',
      'description': 'cjk/rtl/emoji title'
    },
    {'duration': 0, 'pubDate': baseEpoch + 3, 'title': '', 'description': ''},
  ];
  for (var i = 0; i < dirty.length; i++) {
    await db.insert('feedEpisode', {
      'title': dirty[i]['title'] ?? 'dirty row $i',
      'description': dirty[i]['description'],
      'duration': dirty[i]['duration'],
      'enclosureUrl': 'https://dirty.example.com/ep-$i.mp3',
      'pubDate': dirty[i]['pubDate'],
      'imageUrl': i.isEven ? null : '',
      'channelTitle': i == 4 ? '' : null,
      'rssFeedUrl': 'https://dirty.example.com/feed.xml',
    });
  }
  await db.close();

  await writeCacheMetaDb(dir, eps.take(2).map((e) => e.enclosureUrl!).toList());
}

Future<void> buildV3() async {
  final dir = '${dbRoot.path}/db_v3';
  await Directory(dir).create(recursive: true);
  final path = '$dir/anycast.db';
  await File('${dbRoot.path}/db_light/anycast.db').copy(path);

  final db = await databaseFactory.openDatabase(absPath(path));
  await db.execute('ALTER TABLE settings DROP COLUMN continuousPlaying');
  await db.execute('PRAGMA user_version = 3');
  await db.close();
}

Future<void> buildCrashed() async {
  final dir = '${dbRoot.path}/db_crashed';
  await Directory(dir).create(recursive: true);

  // copy db_heavy, then open a transaction, write mid-flight, and snapshot
  // BOTH the db and the rollback journal = faithful crashed-mid-txn state
  await File('${dbRoot.path}/db_heavy/anycast.db').copy('$dir/anycast.db');
  final db = await databaseFactory.openDatabase(absPath('$dir/anycast.db'));
  await db.execute('BEGIN IMMEDIATE');
  await db.insert('historyEpisode', {
    'title': 'crashed mid-transaction episode',
    'description': 'this row was in flight when the process died',
    'duration': 1800000,
    'enclosureUrl': 'https://crashed.example.com/in-flight.mp3',
    'pubDate': baseEpoch,
  });
  await db.execute('UPDATE playlistEpisode SET playedDuration = 123456 '
      'WHERE enclosureUrl = (SELECT enclosureUrl FROM playlistEpisode '
      'ORDER BY position ASC LIMIT 1)');

  File('$dir/anycast.db').copySync('$dir/anycast.db.snapshot');
  final journal = File('$dir/anycast.db-journal');
  if (journal.existsSync()) {
    journal.copySync('$dir/anycast.db-journal.snapshot');
  }
  await db.execute('ROLLBACK');
  await db.close();

  // restore the mid-txn snapshot as the fixture
  File('$dir/anycast.db.snapshot').renameSync('$dir/anycast.db');
  final js = File('$dir/anycast.db-journal.snapshot');
  if (js.existsSync()) {
    js.renameSync('$dir/anycast.db-journal');
  }

  // carry the cache meta db + audio files from db_heavy (real-device layout:
  // Library/Caches/anycast_episode/, db_device evidence, 01 §4.1 correction)
  await _copyDir('${dbRoot.path}/db_heavy/Library', '$dir/Library');
}

Future<void> buildCorrupt() async {
  // truncated: valid header, cut mid-page
  final truncated = '${dbRoot.path}/db_corrupt_truncated';
  await Directory(truncated).create(recursive: true);
  final bytes = File('${dbRoot.path}/db_light/anycast.db').readAsBytesSync();
  File('$truncated/anycast.db')
      .writeAsBytesSync(bytes.sublist(0, (bytes.length * 0.4).round()));

  // notadb: plain text bytes
  final notadb = '${dbRoot.path}/db_corrupt_notadb';
  await Directory(notadb).create(recursive: true);
  File('$notadb/anycast.db')
      .writeAsStringSync('this file is not a sqlite database at all\n' * 100);

  // partial: valid sqlite header + half-written tail garbage
  final partial = '${dbRoot.path}/db_corrupt_partial';
  await Directory(partial).create(recursive: true);
  final head = bytes.sublist(0, 4096);
  final tail =
      List<int>.generate(4096, (i) => (i * 31 + 7) % 256); // deterministic
  File('$partial/anycast.db').writeAsBytesSync(head + tail);
}

Future<void> buildEdgeSubs(FixtureSources sources) async {
  final dir = '${dbRoot.path}/db_edge_subs';
  await Directory(dir).create(recursive: true);
  final db = await createDb('$dir/anycast.db');

  final sub = SubscriptionModel.fromMap({
    'rssFeedUrl': 'https://edge.example.com/feed-a.xml',
    'title': 'Collision Channel',
    'description': 'the resident subscription (title owner)',
    'imageUrl': null,
    'link': 'https://edge-a.example.com/',
    'categories': null,
    'author': null,
    'email': null,
    'lastUpdated': baseEpoch,
  });
  await SubscriptionModel.addMany(db, [sub]);
  await normalizeSettings(db);

  // episode present in Default playlist (cross-list move test needs a
  // resident enclosureUrl)
  final ep = PlaylistEpisodeModel.fromMap({
    'title': 'Cross-list episode',
    'description': 'moved between playlists',
    'duration': 2400000,
    'enclosureUrl': 'https://edge.example.com/ep-cross.mp3',
    'pubDate': baseEpoch,
    'imageUrl': null,
    'channelTitle': 'Collision Channel',
    'rssFeedUrl': 'https://edge.example.com/feed-a.xml',
  });
  ep.playlistId = 1;
  await PlaylistEpisodeModel.insertOrUpdateByIndex(db, 1, 0, ep);
  // second list to move into
  await db.insert('playlist', {'id': 2, 'title': 'Second', 'position': 2});
  await db.close();

  File('$dir/edge_cases.json')
      .writeAsStringSync(const JsonEncoder.withIndent('  ').convert({
    'title_collision': {
      'resident': {'rssFeedUrl': sub.rssFeedUrl, 'title': sub.title, 'id': 1},
      'incoming': {
        'rssFeedUrl': 'https://edge.example.com/feed-b.xml',
        'title': 'Collision Channel',
        'note': 'INSERT OR REPLACE by title: replaces resident row, id changes'
      },
    },
    'cross_list_move': {
      'enclosureUrl': 'https://edge.example.com/ep-cross.mp3',
      'from_playlist': 1,
      'to_playlist': 2,
      'note': 'INSERT OR REPLACE by enclosureUrl: moves to the new list'
    },
  }));
}

Future<void> writeOpmlFixture(FixtureSources sources) async {
  // app's own export format over db_heavy-like subscription set (real code)
  final subs = sources.subscriptions(minCount: 30);
  final opmlText = generateOPML(subs);
  File('test/fixtures/opml/app_export.opml').writeAsStringSync(opmlText);
}

Future<void> _copyDir(String from, String to) async {
  final src = Directory(from);
  if (!src.existsSync()) return;
  await Directory(to).create(recursive: true);
  for (final e in src.listSync(recursive: true)) {
    if (e is File) {
      final rel = e.path.substring(src.path.length + 1);
      final dest = File('$to/$rel');
      await dest.parent.create(recursive: true);
      e.copySync(dest.path);
    }
  }
}
