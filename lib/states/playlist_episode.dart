import 'dart:io';

import 'package:anycast/models/helper.dart';
import 'package:anycast/models/playlist_episode.dart';
import 'package:anycast/states/player.dart';
import 'package:anycast/states/playlist.dart';
import 'package:get/get.dart';

class PlaylistEpisodeController extends GetxController {
  final episodes = <PlaylistEpisodeModel>[].obs;

  final int playlistId;
  PlaylistEpisodeController({required this.playlistId});

  final DatabaseHelper helper = DatabaseHelper();

  Future<void> loadManually() async {
    var db = await helper.db;
    var episodes = await PlaylistEpisodeModel.listByPlaylistId(db!, playlistId);
    this.episodes.value = episodes;
    Get.find<PlaylistController>()
        .addToSet(episodes.map((e) => e.enclosureUrl!).toList());
  }

  Future<PlaylistEpisodeModel> add(
      int position, PlaylistEpisodeModel episode) async {
    // if exist, only move it
    var oldIndex = episodes.indexWhere((e) => e.guid == episode.guid);
    if (oldIndex != -1) {
      var ep = episodes[oldIndex];
      if (oldIndex == position) {
        return ep;
      }
      episodes.removeAt(oldIndex);
      episodes.insert(position, ep);
      // 更新到数据库去
      helper.db.then((db) => PlaylistEpisodeModel.insertOrUpdateByIndex(
          db!, playlistId, position, ep));
      return ep;
    }
    episodes.insert(position, episode);
    // episodes.insert(position, episode);
    Get.find<PlaylistController>().addToSet([episode.enclosureUrl!]);
    helper.db.then((db) => PlaylistEpisodeModel.insertOrUpdateByIndex(
        db!, playlistId, position, episode));
    return episode;
  }

  void remove(String guid) {
    var oldIndex = episodes.indexWhere((e) => e.guid == guid);
    if (oldIndex == -1) {
      return;
    }
    var enclosureUrl = episodes[oldIndex].enclosureUrl;
    episodes.removeAt(oldIndex);
    Get.find<PlaylistController>().removeFromSet(enclosureUrl!);

    helper.db.then((db) => {PlaylistEpisodeModel.deleteByGuid(db!, guid)});
  }

  void removeTop() {
    var guid = episodes[0].guid;
    remove(guid!);
  }

  Future<void> moveToTop(PlaylistEpisodeModel episode) async {
    var oldIndex = episodes.indexWhere((e) => e.id == episode.id);
    episodes.removeAt(oldIndex);
    episodes.insert(0, episode);

    return helper.db.then((db) => PlaylistEpisodeModel.insertOrUpdateByIndex(
        db!, playlistId, 0, episode));
  }

  Future<void> updatePlayedDuration(Duration duration) async {
    var episode = episodes[0];
    episode.playedDuration = duration.inMilliseconds;
    episodes[0] = PlaylistEpisodeModel.fromMap(episode.toMap());
    return helper.db.then((db) {
      episode.updatePlayedDuration(db!);
    });
  }

  Future<void> move(int from, int to) async {
    if (from == to) {
      return;
    }
    if (from == 0) {
      var playerController = Get.find<PlayerController>();

      playerController.pause().then((_) {
        // wait for episodes reorder
        sleep(const Duration(milliseconds: 100));
        playerController.setByEpisode(episodes[0]);
      });
    }
    if (to == 0) {
      var playerController = Get.find<PlayerController>();
      playerController.pause().then((_) {
        sleep(const Duration(milliseconds: 100));
        playerController.setByEpisode(episodes[0]);
      });
    }

    var episode = episodes.removeAt(from);
    if (to > from) {
      to -= 1;
    }
    episodes.insert(to, episode);

    helper.db.then((db) => PlaylistEpisodeModel.insertOrUpdateByIndex(
        db!, playlistId, to, episode));
  }
}
