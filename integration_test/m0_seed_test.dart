// M0 device-data seeding (05 §1.1 fallback path c): boots the real app on a
// simulator/device and drives the SAME code paths the UI uses —
// importPodcastsByUrls (share-dialog import), FeedEpisodeController.addToTop,
// PlayerController.playByEpisode/pause/seek — so the resulting container
// (Documents/anycast.db + Library cache meta DBs + tmp audio) is produced by
// real runtime code on a real iOS filesystem.
//
// Run:
//   flutter test integration_test/m0_seed_test.dart -d <simulator-or-device-id>
// Then pull the container:
//   xcrun simctl get_app_container booted com.kindjeff.anycast data
// and copy Documents/ + Library/Application Support/ + tmp/ into
// test/fixtures/db/db_device/.
//
// ignore_for_file: avoid_print

import 'package:anycast/main.dart' as app;
import 'package:anycast/models/feed_episode.dart';
import 'package:anycast/states/feed_episode.dart';
import 'package:anycast/states/player.dart';
import 'package:anycast/states/subscription.dart';
import 'package:anycast/utils/rss_fetcher.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:integration_test/integration_test.dart';

// tool/m0/feeds_user.txt — author's real subscription export (OPML xmlUrls).
const userFeedUrls = <String>[
  'https://anchor.fm/s/f2cbc0a8/podcast/rss',
  'https://bowuzhi.fm/episodes/feed.xml',
  'https://crazy.capital/feed',
  'https://feed.xyzfm.space/9bmupxfae9qd',
  'https://feed.xyzfm.space/dk4yh3pkpjp3',
  'https://feed.xyzfm.space/h4tfwertttht',
  'https://feed.xyzfm.space/j8yp8gxkmgqr',
  'https://feed.xyzfm.space/mjvd3fknfr4v',
  'https://feed.xyzfm.space/mkkxu98dm89e',
  'https://feed.xyzfm.space/wmnkvmrpwuww',
  'https://feed.xyzfm.space/wqgumr8kx8h8',
  'https://feed.xyzfm.space/x734thm8c63f',
  'https://feeds.fireside.fm/teahour/rss',
  'https://hardimage.pro/episodes/feed.xml',
  'https://miechakucha.com/episodes/feed.xml',
  'https://pan.icu/feed',
  'https://pretro.xyz/feed',
  'https://sspai.typlog.io/episodes/feed.xml',
  'https://storyfm.cn/feed/episodes',
  'https://taiyilaile.com/episodes/feed.xml',
  'https://www.etw.fm/rss',
  'https://www.thetype.com/typechat/feed/',
  'https://www.ximalaya.com/album/41563226.xml',
  'https://www.ximalaya.com/album/4867505.xml',
  'https://yitianshijie.net/episodes/feed.xml',
];

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('m0 seed: real subscription import + playback', (tester) async {
    app.main();
    // real async boot (Firebase, AudioService, db open); pump until settled-ish
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 500));
      if (Get.isRegistered<SubscriptionController>()) break;
    }
    expect(Get.isRegistered<SubscriptionController>(), isTrue);

    // -- subscription import: identical to ShareDialog's Import button -------
    final result = await importPodcastsByUrls(userFeedUrls.toList(),
        onProgress: (p, t) => print('import $p/$t'));
    Get.find<FeedEpisodeController>().addMany(result
        .where((e) => e.feedEpisodes != null && e.feedEpisodes!.isNotEmpty)
        .map((e) => e.feedEpisodes![0])
        .toList());
    Get.find<SubscriptionController>()
        .addMany(result.map((e) => e.subscription!).toList());
    print('imported ${result.length} subscriptions');

    // -- queue a few episodes the way the feeds page does ---------------------
    final feedCtl = Get.find<FeedEpisodeController>();
    final eps = <FeedEpisodeModel>[];
    for (final d in result) {
      if (d.feedEpisodes != null && d.feedEpisodes!.isNotEmpty) {
        eps.add(d.feedEpisodes!.first);
      }
      if (eps.length >= 6) break;
    }
    final playlistEps = [
      for (final e in eps) await feedCtl.addToTop(1, e),
    ];
    print('queued ${playlistEps.length} episodes');

    // -- real playback: produces history row, player row, progress writes,
    //    and the audio cache meta rows --------------------------------------
    final player = Get.find<PlayerController>();
    try {
      await player.playByEpisode(playlistEps.first);
      await Future.delayed(const Duration(seconds: 12));
      await player.seek(const Duration(seconds: 30));
      await Future.delayed(const Duration(seconds: 4));
      await player.pause();
    } catch (e) {
      print('playback attempt failed (kept whatever was written): $e');
    }

    // let the 2s progress-persist timer + async db writes flush, then hold the
    // app alive so `xcrun simctl get_app_container` can pull the data
    // container before flutter test uninstalls the app.
    await Future.delayed(const Duration(seconds: 90));
    print('seed done');
  },
      timeout: const Timeout(Duration(minutes: 8)),
      skip: false);
}
