import 'package:anycast/models/helper.dart';
import 'package:anycast/models/playlist_episode.dart';
import 'package:get/get.dart';

class PlaylistEpisodeController extends GetxController {
  final episodes = <PlaylistEpisodeModel>[].obs;

  final int playlistId;
  PlaylistEpisodeController({required this.playlistId});

  final DatabaseHelper helper = DatabaseHelper();

  Future<void> loadManually() async {
    return helper.db.then((db) {
      PlaylistEpisodeModel.listByPlaylistId(db!, playlistId).then((episodes) {
        this.episodes.value = episodes;
      });
    });
  }

  Future<void> add(int position, PlaylistEpisodeModel episode) async {
    episodes.insert(position, episode);
    helper.db.then((db) => {
          PlaylistEpisodeModel.insertOrUpdateByIndex(
              db!, playlistId, position, episode)
        });
  }

  void remove(int id) {
    var oldIndex = episodes.indexWhere((e) => e.id == id);
    episodes.removeAt(oldIndex);

    helper.db.then((db) => {PlaylistEpisodeModel.delete(db!, id)});
  }

  void removeTop() {
    helper.db.then((db) => {PlaylistEpisodeModel.delete(db!, episodes[0].id!)});
    episodes.removeAt(0);
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
}
