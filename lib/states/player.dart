import 'package:anycast/models/helper.dart';
import 'package:anycast/models/playlist_episode.dart';
import 'package:anycast/models/player.dart';
import 'package:anycast/utils/audio_handler.dart';
import 'package:get/get.dart';

class PlayerController extends GetxController {
  var player = PlayerModel.empty().obs;
  var playlistEpisode = PlaylistEpisodeModel.empty().obs;

  final DatabaseHelper helper = DatabaseHelper();

  @override
  void onInit() {
    super.onInit();
    load();
  }

  void load() {
    helper.db.then((db) => {
          PlayerModel.get(db!).then((player) {
            this.player.value = player;
            if (player.playlistEpisodeGuid != null) {
              PlaylistEpisodeModel.getByGuid(db, player.playlistEpisodeGuid!)
                  .then((playlistEpisode) {
                this.playlistEpisode.value = playlistEpisode;
              });
            }
          })
        });
  }

  void setPlayer(PlayerModel player, PlaylistEpisodeModel playlistEpisode) {
    this.player.value = player;
    this.playlistEpisode.value = playlistEpisode;

    helper.db.then((db) => {PlayerModel.update(db!, player)});
  }

  Future<void> playByEpisode(PlaylistEpisodeModel episode) async {
    var playlistId = episode.playlistId!;
    var player = PlayerModel.fromMap({
      'playlistEpisodeGuid': episode.guid,
    });

    var db = await helper.db.then((db) => db!);

    PlayerModel.update(db, player).then((_) {
      setPlayer(player, episode);
      MyAudioHandler.setPlaylistByPlaylistId(playlistId).then((_) {
        MyAudioHandler().play();
      });
    });
  }
}
