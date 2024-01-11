import 'dart:async';

import 'package:anycast/models/helper.dart';
import 'package:anycast/models/playlist_episode.dart';
import 'package:anycast/models/player.dart';
import 'package:anycast/states/playlist.dart';
import 'package:anycast/states/playlist_episode.dart';
import 'package:anycast/utils/audio_handler.dart';
import 'package:get/get.dart';
import 'package:just_audio/just_audio.dart';

class PlayerController extends GetxController {
  var player = PlayerModel.empty().obs;

  final DatabaseHelper helper = DatabaseHelper();
  final MyAudioHandler myAudioHandler = MyAudioHandler();

  PlaylistEpisodeController? get playlistEpisodeController {
    if (player.value.currentPlaylistId == null) {
      return null;
    }
    return Get.find<PlaylistController>()
        .getEpisodeControllerByPlaylistId(player.value.currentPlaylistId!);
  }

  PlaylistEpisodeModel? get playlistEpisode {
    if (player.value.currentPlaylistId == null) {
      return null;
    }
    var es = playlistEpisodeController!.episodes;
    if (es.isEmpty) {
      return null;
    }
    return es[0];
  }

  @override
  void onInit() {
    super.onInit();
    load();

    // interval 2 seconds to save playedDuration
    Timer.periodic(const Duration(seconds: 2), (timer) {
      if (!myAudioHandler.isPlaying) return;
      var peController = playlistEpisodeController;
      if (peController == null) {
        return;
      }
      var pe = playlistEpisode;
      if (pe == null) {
        return;
      }
      peController.updatePlayedDuration(myAudioHandler.playedDuration);
    });

    myAudioHandler.playbackStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed) {
        var peController = playlistEpisodeController;
        if (peController == null) {
          return;
        }
        peController.removeTop();
        if (peController.episodes.isEmpty) {
          pause();
        } else {
          playByEpisode(peController.episodes[0]);
        }
      }
    });
  }

  void load() {
    helper.db.then((db) => {
          PlayerModel.get(db!).then((player) {
            this.player.value = player;
          })
        });
  }

  void playByEpisode(PlaylistEpisodeModel episode) async {
    var playlistId = episode.playlistId!;
    var player = PlayerModel.fromMap({
      'currentPlaylistId': playlistId,
    });

    this.player.value = player;

    myAudioHandler.playByEpisode(episode);

    helper.db.then((db) {
      PlayerModel.update(db!, player);
    });
  }

  Future<void> pause() async {
    return myAudioHandler.pause();
  }

  Future<void> play() async {
    if (myAudioHandler.audioSource == null) {
      var pe = playlistEpisode;
      if (pe == null) {
        return;
      }
      playByEpisode(pe);
      return;
    }
    return myAudioHandler.play();
  }

  bool isPlaying(int playlistId) {
    return player.value.currentPlaylistId == playlistId;
  }
}
