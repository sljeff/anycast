import 'dart:async';

import 'package:anycast/models/feed_episode.dart';
import 'package:anycast/models/helper.dart';
import 'package:anycast/models/playlist_episode.dart';
import 'package:anycast/models/subscription.dart';
import 'package:anycast/states/player.dart';
import 'package:anycast/states/playlist.dart';
import 'package:anycast/utils/audio_handler.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class FeedEpisodeController extends GetxController {
  final episodes = <FeedEpisodeModel>[].obs;

  final DatabaseHelper helper = DatabaseHelper();
  final MyAudioHandler audioHandler = MyAudioHandler();
  final scrollController = ScrollController();
  final GlobalKey<RefreshIndicatorState> refreshIndicatorKey =
      GlobalKey<RefreshIndicatorState>();
  Timer? refresher;

  @override
  void onInit() {
    super.onInit();
    load(episodes);
    autoFetch();

    initAutoRefresher();
  }

  void addMany(List<FeedEpisodeModel> episodes) {
    helper.db.then((db) => {
          FeedEpisodeModel.insertMany(db, episodes).then((db) {
            load(episodes);
          })
        });
  }

  Future<void> removeByEnclosureUrls(List<String> urls) async {
    episodes.removeWhere((episode) => urls.contains(episode.enclosureUrl));
    helper.db.then((db) => {FeedEpisodeModel.removeByEnclosureUrls(db, urls)});
  }

  void load(List<FeedEpisodeModel> episodes) {
    helper.db.then((db) => {
          FeedEpisodeModel.listAll(db).then((episodes) {
            this.episodes.value = episodes;
          })
        });
  }

  static PlaylistEpisodeModel feed2playlist(
      int playlistId, FeedEpisodeModel episode) {
    var playlistEpisode =
        PlaylistEpisodeModel.fromMap(Map<String, dynamic>.from({
      'title': episode.title,
      'description': episode.description,
      'duration': episode.duration,
      'enclosureUrl': episode.enclosureUrl,
      'pubDate': episode.pubDate,
      'imageUrl': episode.imageUrl,
      'channelTitle': episode.channelTitle,
      'rssFeedUrl': episode.rssFeedUrl,
      'playlistId': playlistId,
      'position': double.infinity,
      'playedDuration': 0,
    }));

    return playlistEpisode;
  }

  Future<PlaylistEpisodeModel> addToPlaylist(
      int playlistId, FeedEpisodeModel episode) async {
    // add to default playlist; remove from feeds
    var playlistEpisode = feed2playlist(playlistId, episode);

    var position = 0;
    var playerController = Get.find<PlayerController>();
    if (playerController.player.value.currentPlaylistId == playlistId) {
      if (playerController.playlistEpisode.value.enclosureUrl ==
          episode.enclosureUrl) {
        return playerController.playlistEpisode.value;
      }
      position = 1;
    }

    var playlistEpisodeController = Get.find<PlaylistController>()
        .getEpisodeControllerByPlaylistId(playlistId);
    await playlistEpisodeController.add(position, playlistEpisode);

    return playlistEpisode;
  }

  Future<PlaylistEpisodeModel> addToTop(
      int playlistId, FeedEpisodeModel episode) async {
    var playlistEpisode = feed2playlist(playlistId, episode);
    var playlistEpisodeController = Get.find<PlaylistController>()
        .getEpisodeControllerByPlaylistId(playlistId);
    return await playlistEpisodeController.add(0, playlistEpisode);
  }

  void autoFetch() async {
    var now = DateTime.now();
    var db = await DatabaseHelper().db;
    var subcriptions = await SubscriptionModel.listAll(db);

    if (subcriptions.isEmpty) {
      return;
    }

    var latestUpdateTSs =
        subcriptions.map((subscription) => subscription.lastUpdated);
    var latestUpdateTS = latestUpdateTSs.reduce((a, b) {
      if (a == null) return b;
      if (b == null) return a;
      return a.compareTo(b) > 0 ? a : b;
    });
    var latestUpdateTime = latestUpdateTS != null
        ? DateTime.fromMillisecondsSinceEpoch(latestUpdateTS)
        : now;

    if (latestUpdateTime.isBefore(now.subtract(const Duration(hours: 1)))) {
      refreshIndicatorKey.currentState?.show();
    }
  }

  void initAutoRefresher() async {
    if (refresher != null) {
      refresher!.cancel();
    }
    var interval = Get.find<SettingsController>().autoRefreshInterval.value;
    refresher = Timer.periodic(
        Duration(
          seconds: interval,
        ), (timer) async {
      autoFetch();
    });
  }

  Future<void> removeOld(int maxCount) async {
    if (episodes.length <= maxCount) {
      return;
    }

    var episodesNeedRemove = episodes.sublist(maxCount);
    var enclosureUrls =
        episodesNeedRemove.map((episode) => episode.enclosureUrl!).toList();

    episodes.removeRange(maxCount, episodes.length);

    helper.db.then(
        (db) => {FeedEpisodeModel.removeByEnclosureUrls(db, enclosureUrls)});
  }
}
