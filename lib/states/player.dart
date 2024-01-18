import 'dart:async';

import 'package:anycast/models/helper.dart';
import 'package:anycast/models/playlist_episode.dart';
import 'package:anycast/models/player.dart';
import 'package:anycast/states/playlist.dart';
import 'package:anycast/states/playlist_episode.dart';
import 'package:anycast/utils/audio_handler.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:just_audio/just_audio.dart';

class PlayerController extends GetxController {
  var player = PlayerModel.empty().obs;
  var isPlaying = false.obs;
  var isLoading = false.obs;
  var positionData = PositionData(
    position: Duration.zero,
    bufferedPosition: Duration.zero,
    duration: Duration.zero,
  ).obs;
  var pageIndex = 2.obs;
  var playlistEpisode = PlaylistEpisodeModel.empty().obs;

  var pageController = PageController(
    viewportFraction: 1,
    initialPage: 2,
  );
  final DatabaseHelper helper = DatabaseHelper();
  final MyAudioHandler myAudioHandler = MyAudioHandler();

  PlaylistEpisodeController? get playlistEpisodeController {
    if (player.value.currentPlaylistId == null) {
      return null;
    }
    return Get.find<PlaylistController>()
        .getEpisodeControllerByPlaylistId(player.value.currentPlaylistId!);
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
      if (playlistEpisode.value.guid == null) {
        return;
      }
      peController.updatePlayedDuration(myAudioHandler.playedDuration);
    });

    myAudioHandler.playbackStateStream.listen((state) {
      isPlaying.value = state.playing;
      // loading or buffering
      isLoading.value = [
        ProcessingState.loading,
        ProcessingState.buffering,
      ].contains(state.processingState);
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

    myAudioHandler.positionDataStream.listen((event) {
      if (isLoading.value ||
          [
            event.bufferedPosition,
            event.position,
          ].contains(Duration.zero)) {
        return;
      }
      positionData.value = event;
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
    playlistEpisode.value = episode;

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
      if (playlistEpisode.value.guid == null) {
        return;
      }
      playByEpisode(playlistEpisode.value);
      return;
    }
    return myAudioHandler.play();
  }

  void initProgress() {
    var pe = playlistEpisode.value;
    if (pe.guid == null) {
      return;
    }
    positionData.value = PositionData(
      position: Duration(milliseconds: pe.playedDuration ?? 0),
      bufferedPosition: Duration.zero,
      duration: Duration(milliseconds: pe.duration ?? 0),
    );
  }
}

class SettinigsController extends GetxController {
  var isCounting = false.obs;
  var countdownDuration = Duration.zero.obs;
  var speed = 1.0.obs;
  var skipSilence = false.obs;
  Timer? timer;

  final MyAudioHandler myAudioHandler = MyAudioHandler();

  @override
  void onInit() {
    super.onInit();
    timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!isCounting.value) {
        return;
      }
      if (countdownDuration.value.inSeconds <= 0) {
        Get.find<PlayerController>().pause();
        isCounting.value = false;
        return;
      }
      countdownDuration.value =
          countdownDuration.value - const Duration(seconds: 1);
    });

    myAudioHandler.speedStream.listen((event) {
      speed.value = event;
    });

    myAudioHandler.skipSilenceEnabledStream.listen((event) {
      skipSilence.value = event;
    });
  }

  void start(Duration duration) {
    countdownDuration.value = duration;
    isCounting.value = true;
  }

  void stop() {
    countdownDuration.value = Duration.zero;
    isCounting.value = false;
  }

  void onChangeCountdown(Duration duration) {
    countdownDuration.value = duration;
    isCounting.value = false;
  }

  void setSpeed(double speed) {
    this.speed.value = speed;
    myAudioHandler.setSpeed(speed);
  }

  void setSkipSilence(bool skipSilence) {
    this.skipSilence.value = skipSilence;
    myAudioHandler.setSkipSilence(skipSilence);
  }
}
