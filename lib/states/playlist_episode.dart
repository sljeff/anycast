import 'package:anycast/models/helper.dart';
import 'package:anycast/models/playlist_episode.dart';
import 'package:get/get.dart';

class PlaylistEpisodeController extends GetxController {
  final episodes = <PlaylistEpisodeModel>[].obs;

  var playlistId = 0;
  PlaylistEpisodeController({required this.playlistId});

  final DatabaseHelper helper = DatabaseHelper();

  @override
  void onInit() {
    super.onInit();
    load();
  }

  void load() {
    helper.db.then((db) => {
          PlaylistEpisodeModel.listByPlaylistId(db!, playlistId)
              .then((episodes) {
            this.episodes.value = episodes;
          })
        });
  }

  void add(PlaylistEpisodeModel episode) {
    helper.db.then((db) => {
          PlaylistEpisodeModel.insertOrUpdateByIndex(
                  db!, playlistId, 0, episode)
              .then((v) {
            episodes.insert(0, episode);
          })
        });
  }

  void removeFromPlaylist(int id) {
    helper.db.then((db) => {
          PlaylistEpisodeModel.delete(db!, id).then((v) {
            episodes.removeWhere((episode) => episode.id == id);
          })
        });
  }

  Future<void> moveToTop(PlaylistEpisodeModel episode) async {
    episodes.removeWhere((e) => e.id == episode.id);
    episodes.insert(0, episode);
    return await helper.db.then((db) =>
        PlaylistEpisodeModel.insertOrUpdateByIndex(
            db!, playlistId, 0, episode));
  }
}
