import 'dart:async';

import 'package:anycast/models/helper.dart';
import 'package:anycast/models/playlist_episode.dart';
import 'package:anycast/models/player.dart';
import 'package:anycast/models/settings.dart';
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
  var refreshFrameTime = 0.obs;

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
          clear();
        } else {
          playByEpisode(peController.episodes[0]);
        }
      }

      Timer.periodic(const Duration(milliseconds: 20), (timer) {
        var now = DateTime.now();
        refreshFrameTime.value = now.hour * 3600000 +
            now.minute * 60000 +
            now.second * 1000 +
            now.millisecond;
      });
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

  Future<void> seek(Duration position) async {
    if (playlistEpisode.value.guid == null) {
      return;
    }
    return myAudioHandler.seekAndPlayByEpisode(playlistEpisode.value, position);
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

  bool isPlayingEpisode(String enclosureUrl) {
    if (playlistEpisode.value.guid == null || isPlaying.value == false) {
      return false;
    }
    return playlistEpisode.value.enclosureUrl == enclosureUrl;
  }

  void clear() {
    pause();
    positionData.value = PositionData(
      position: Duration.zero,
      bufferedPosition: Duration.zero,
      duration: Duration.zero,
    );
    playlistEpisode.value = PlaylistEpisodeModel.empty();
    player.value = PlayerModel.empty();

    helper.db.then((db) {
      PlayerModel.delete(db!);
    });
  }
}

class SettingsController extends GetxController {
  var isCounting = false.obs;
  var countdownDuration = Duration.zero.obs;

  var darkMode = false.obs;
  var speed = 1.0.obs;
  var skipSilence = false.obs;
  var autoSleepStartHourIndex = 0.obs;
  var autoSleepEndHourIndex = 0.obs;
  var autoSleepCountdownMinIndex = 0.obs;

  var hours = List.generate(24, (index) => index);
  var sleepMins = List.generate(7, (index) => index * 10);
  var sleepMinsText = [
    'OFF',
    '10 min',
    '20 min',
    '30 min',
    '40 min',
    '50 min',
    '1 hour',
  ];

  Timer? timer;

  final MyAudioHandler myAudioHandler = MyAudioHandler();
  final DatabaseHelper helper = DatabaseHelper();

  void _load() {
    helper.db.then((db) => {
          SettingsModel.get(db!).then((settings) {
            darkMode.value = settings.darkMode!;
            speed.value = settings.speed!;
            skipSilence.value = settings.skipSilence!;
            var autoSleepTimer = settings.autoSleepTimer!;
            var autoSleepTimers = autoSleepTimer.split(',');
            autoSleepStartHourIndex.value = int.parse(autoSleepTimers[0]);
            autoSleepEndHourIndex.value = int.parse(autoSleepTimers[1]);
            autoSleepCountdownMinIndex.value = int.parse(autoSleepTimers[2]);
          })
        });
  }

  @override
  void onInit() {
    super.onInit();

    _load();

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

  // only for display
  void onChangeCountdown(Duration duration) {
    countdownDuration.value = duration;
    isCounting.value = false;
  }

  void setSpeed(double speed) {
    this.speed.value = speed;
    myAudioHandler.setSpeed(speed);

    helper.db.then((db) {
      SettingsModel.setSpeed(db!, speed);
    });
  }

  void setSkipSilence(bool skipSilence) {
    this.skipSilence.value = skipSilence;
    myAudioHandler.setSkipSilence(skipSilence);

    helper.db.then((db) {
      SettingsModel.setSkipSilence(db!, skipSilence);
    });
  }

  void setAutoSleepStartHourIndex(int index) {
    autoSleepStartHourIndex.value = index;

    helper.db.then((db) {
      SettingsModel.setAutoSleepTimer(db!, autoSleepStartHourIndex.value,
          autoSleepEndHourIndex.value, autoSleepCountdownMinIndex.value);
    });
  }

  void setAutoSleepEndHourIndex(int index) {
    autoSleepEndHourIndex.value = index;

    helper.db.then((db) {
      SettingsModel.setAutoSleepTimer(db!, autoSleepStartHourIndex.value,
          autoSleepEndHourIndex.value, autoSleepCountdownMinIndex.value);
    });
  }

  void setAutoSleepCountdownMinIndex(int index) {
    autoSleepCountdownMinIndex.value = index;

    helper.db.then((db) {
      SettingsModel.setAutoSleepTimer(db!, autoSleepStartHourIndex.value,
          autoSleepEndHourIndex.value, autoSleepCountdownMinIndex.value);
    });
  }

  void autoSetCountdown() {
    if (isCounting.value) {
      return;
    }
    var startHour = autoSleepStartHourIndex.value;
    var endHour = autoSleepEndHourIndex.value;
    var countdownMin = autoSleepCountdownMinIndex.value;
    if (countdownMin == 0) {
      return;
    }
    var now = DateTime.now();
    // if not in range, return
    var small = startHour < endHour ? startHour : endHour;
    var big = startHour > endHour ? startHour : endHour;
    var exchanged = startHour > endHour;
    if (exchanged) {
      if (now.hour >= small && now.hour < big) {
        return;
      }
    } else {
      if (now.hour < small || now.hour >= big) {
        return;
      }
    }

    var duration = sleepMins[countdownMin];
    if (duration == 0) {
      return;
    }
    start(Duration(minutes: duration));
  }
}
