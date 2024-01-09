import 'package:anycast/models/helper.dart';
import 'package:anycast/models/playlist_episode.dart';
import 'package:anycast/models/player.dart';
import 'package:anycast/states/playlist.dart';
import 'package:anycast/utils/audio_handler.dart';
import 'package:get/get.dart';

class PlayerController extends GetxController {
  var player = PlayerModel.empty().obs;

  final DatabaseHelper helper = DatabaseHelper();

  PlaylistEpisodeModel? get playlistEpisode {
    if (player.value.currentPlaylistId == null) {
      return null;
    }
    var es = Get.find<PlaylistController>()
        .getEpisodeControllerByPlaylistId(player.value.currentPlaylistId!)
        .episodes;
    if (es.isEmpty) {
      return null;
    }
    return es[0];
  }

  @override
  void onInit() {
    super.onInit();
    load();
  }

  void load() {
    helper.db.then((db) => {
          PlayerModel.get(db!).then((player) {
            this.player.value = player;
          })
        });
  }

  void setPlayer(PlayerModel player) {
    this.player.value = player;

    helper.db.then((db) => {PlayerModel.update(db!, player)});
  }

  void playByEpisode(PlaylistEpisodeModel episode) {
    var playlistId = episode.playlistId!;
    var player = PlayerModel.fromMap({
      'currentPlaylistId': playlistId,
    });

    setPlayer(player);

    MyAudioHandler().play();

    helper.db.then((db) {
      PlayerModel.update(db!, player);
    });
  }

  Future<void> pause() async {
    // var player = PlayerModel.fromMap({
    //   'currentPlaylistId': null,
    // });

    // setPlayer(player);

    var myAudioHandler = MyAudioHandler();
    return myAudioHandler.pause();
  }

  bool isPlaying(int playlistId) {
    return MyAudioHandler().isPlaying &&
        player.value.currentPlaylistId == playlistId;
  }
}
