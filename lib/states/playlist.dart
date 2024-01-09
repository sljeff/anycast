import 'package:anycast/models/helper.dart';
import 'package:anycast/states/playlist_episode.dart';
import 'package:anycast/models/playlist.dart';
import 'package:get/get.dart';

class PlaylistController extends GetxController {
  final playlists = <PlaylistModel>[].obs;
  final episodesControllers = <PlaylistEpisodeController>[].obs;

  final DatabaseHelper helper = DatabaseHelper();

  @override
  void onInit() {
    super.onInit();
    load();
  }

  void load() {
    helper.db.then((db) => {
          PlaylistModel.listAll(db!).then((playlists) {
            this.playlists.value = playlists;
            for (var playlist in playlists) {
              episodesControllers
                  .add(PlaylistEpisodeController(playlistId: playlist.id!));
            }
          })
        });
  }

  PlaylistEpisodeController getEpisodeControllerByPlaylistId(int playlistId) {
    for (var i = 0; i < playlists.length; i++) {
      if (playlists[i].id == playlistId) {
        return episodesControllers[i];
      }
    }
    throw Exception('Playlist not found');
  }
}
