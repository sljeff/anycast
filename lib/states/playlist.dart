import 'package:anycast/models/helper.dart';
import 'package:anycast/states/player.dart';
import 'package:anycast/states/playlist_episode.dart';
import 'package:anycast/models/playlist.dart';
import 'package:get/get.dart';

class PlaylistController extends GetxController {
  final playlists = <PlaylistModel>[].obs;
  final episodesControllers = <PlaylistEpisodeController>[].obs;
  final isLoading = true.obs;

  final DatabaseHelper helper = DatabaseHelper();

  @override
  void onInit() {
    super.onInit();
    load();
  }

  void load() {
    isLoading.value = true;
    helper.db.then((db) => {
          PlaylistModel.listAll(db!).then((playlists) {
            this.playlists.value = playlists;
            List<Future> futures = [];
            for (var playlist in playlists) {
              var c = PlaylistEpisodeController(playlistId: playlist.id!);
              episodesControllers.add(c);
              futures.add(c.loadManually());
            }
            Future.wait(futures).then((value) {
              isLoading.value = false;
              var playerController = Get.find<PlayerController>();
              if (playerController.player.value.currentPlaylistId != null) {
                var episodes =
                    playerController.playlistEpisodeController!.episodes;
                if (episodes.isNotEmpty) {
                  playerController.playlistEpisode.value = episodes[0];
                }
              }
            });
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
