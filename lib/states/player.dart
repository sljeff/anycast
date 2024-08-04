import 'dart:async';

import 'package:anycast/models/helper.dart';
import 'package:anycast/models/history_episode.dart';
import 'package:anycast/models/playlist_episode.dart';
import 'package:anycast/models/player.dart';
import 'package:anycast/models/settings.dart';
import 'package:anycast/models/subscription.dart';
import 'package:anycast/states/cache.dart';
import 'package:anycast/states/feed_episode.dart';
import 'package:anycast/states/history.dart';
import 'package:anycast/states/playlist.dart';
import 'package:anycast/states/playlist_episode.dart';
import 'package:anycast/states/translation.dart';
import 'package:anycast/utils/audio_handler.dart';
import 'package:anycast/utils/formatters.dart';
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
  var pageIndex = 1.obs;
  var playlistEpisode = PlaylistEpisodeModel.empty().obs;
  var backgroundColor =
      const Color(0xFF111316).obs; // The color caculated by palette generator
  var channel = SubscriptionModel.empty().obs;

  var pageController = PageController(
    viewportFraction: 1,
    initialPage: 1,
  );
  final DatabaseHelper helper = DatabaseHelper();
  final MyAudioHandler myAudioHandler = MyAudioHandler();

  PlaylistEpisodeController? get playlistEpisodeController {
    if (player.value.currentPlaylistId == null) {
      return null;
    }
    var peController = Get.find<PlaylistController>()
        .getEpisodeControllerByPlaylistId(player.value.currentPlaylistId!);

    if (peController.episodes.isNotEmpty &&
        playlistEpisode.value.enclosureUrl == null) {
      _updateEpisode(peController.episodes[0]);
    }

    return peController;
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
      if (playlistEpisode.value.enclosureUrl == null) {
        return;
      }
      peController.updatePlayedDuration(myAudioHandler.playedDuration);
    });

    myAudioHandler.playbackStateStream.listen((state) async {
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
          playByEpisode(peController.episodes[0]).then((_) {
            if (!Get.find<SettingsController>().continuousPlaying.value) {
              pause();
              Future.delayed(const Duration(milliseconds: 100), () {
                initProgress();
              });
            }
          });
        }
      }
    });

    myAudioHandler.positionDataStream.listen((event) {
      if (!myAudioHandler.isPlaying ||
          isLoading.value ||
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
          PlayerModel.get(db).then((player) {
            this.player.value = player;
          })
        });
  }

  // The final method interact with the AudioHandler
  Future<void> playByEpisode(PlaylistEpisodeModel episode) async {
    var playlistId = episode.playlistId!;
    var player = PlayerModel.fromMap({
      'currentPlaylistId': playlistId,
    });

    this.player.value = player;
    _updateEpisode(episode);

    Get.find<HistoryController>()
        .insert(HistoryEpisodeModel.fromMap(episode.toMap()));

    helper.db.then((db) {
      PlayerModel.update(db, player);
    });
    return await myAudioHandler.playByEpisode(episode);
  }

  Future<void> setByEpisode(PlaylistEpisodeModel episode) async {
    var playlistId = episode.playlistId!;
    var player = PlayerModel.fromMap({
      'currentPlaylistId': playlistId,
    });

    this.player.value = player;
    _updateEpisode(episode);

    helper.db.then((db) {
      PlayerModel.update(db, player);
    });

    return await myAudioHandler.setByEpisode(episode);
  }

  Future<void> pause() async {
    return await myAudioHandler.pause();
  }

  Future<void> play() async {
    if (myAudioHandler.audioSource == null) {
      if (playlistEpisode.value.enclosureUrl == null) {
        return;
      }
      playByEpisode(playlistEpisode.value);
      return;
    }
    Get.find<HistoryController>()
        .insert(HistoryEpisodeModel.fromMap(playlistEpisode.value.toMap()));
    return myAudioHandler.play();
  }

  Future<void> seek(Duration position) async {
    if (playlistEpisode.value.enclosureUrl == null) {
      return;
    }
    return myAudioHandler.seekAndPlayByEpisode(playlistEpisode.value, position);
  }

  void initProgress() {
    var pe = playlistEpisode.value;
    if (pe.enclosureUrl == null) {
      positionData.value = PositionData(
        position: Duration.zero,
        bufferedPosition: Duration.zero,
        duration: Duration.zero,
      );

      return;
    }
    positionData.value = PositionData(
      position: Duration(milliseconds: pe.playedDuration ?? 0),
      bufferedPosition: Duration.zero,
      duration: Duration(milliseconds: pe.duration ?? 0),
    );
  }

  bool isPlayingEpisode(String enclosureUrl) {
    if (playlistEpisode.value.enclosureUrl == null ||
        isPlaying.value == false) {
      return false;
    }
    return playlistEpisode.value.enclosureUrl == enclosureUrl;
  }

  void clear() {
    pause();
    _updateEpisode(PlaylistEpisodeModel.empty());
    player.value = PlayerModel.empty();

    helper.db.then((db) {
      PlayerModel.delete(db);
    });
  }

  void togglePlay() {
    if (playlistEpisode.value.enclosureUrl == null) {
      return;
    }
    if (isPlaying.value) {
      pause();
    } else {
      play();
    }
  }

  void _updateEpisode(PlaylistEpisodeModel episode) {
    playlistEpisode.value = episode;
    initProgress();

    if (episode.imageUrl != null) {
      updatePaletteGenerator(playlistEpisode.value.imageUrl!)
          .then((value) => backgroundColor.value = value);
    }
    if (episode.rssFeedUrl != null) {
      DatabaseHelper().db.then((db) {
        SubscriptionModel.getOrFetch(db, episode.rssFeedUrl!).then((s) {
          if (s != null) {
            channel.value = s;
          }
        });
      });
    }
  }
}

const noCountdown = Duration(days: -1000);

class SettingsController extends GetxController {
  final countdownDuration = noCountdown.obs;
  final darkMode = false.obs;
  final speed = 1.0.obs;
  final skipSilence = false.obs;
  final autoSleepStartHourIndex = 0.obs;
  final autoSleepEndHourIndex = 0.obs;
  final autoSleepCountdownMinIndex = 0.obs;
  final maxCacheCount = 10.obs;
  final countryCode = 'US'.obs;
  final targetLanguage = 'en'.obs;
  final autoRefreshInterval = 180.obs;
  final maxFeedEpisodes = 100.obs;
  final maxHistoryEpisodes = 100.obs;
  final continuousPlaying = true.obs;

  double get countdownValue => countdownDuration.value.inMinutes < 0
      ? 0
      : countdownDuration.value.inMinutes.toDouble();
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

  Timer? countdownTimer;

  final MyAudioHandler myAudioHandler = MyAudioHandler();
  final DatabaseHelper helper = DatabaseHelper();

  void _load() {
    helper.db.then((db) => {
          SettingsModel.get(db).then((settings) {
            darkMode.value = settings.darkMode!;
            setSpeed(settings.speed ?? 1);
            skipSilence.value = settings.skipSilence!;
            var autoSleepTimer = settings.autoSleepTimer!;
            var autoSleepTimers = autoSleepTimer.split(',');
            autoSleepStartHourIndex.value = int.parse(autoSleepTimers[0]);
            autoSleepEndHourIndex.value = int.parse(autoSleepTimers[1]);
            autoSleepCountdownMinIndex.value = int.parse(autoSleepTimers[2]);

            maxCacheCount.value = settings.maxCacheCount!;
            countryCode.value = settings.countryCode!;
            targetLanguage.value = settings.targetLanguage!;
            autoRefreshInterval.value = settings.autoRefreshInterval!;
            maxFeedEpisodes.value = settings.maxFeedEpisodes!;
            maxHistoryEpisodes.value = settings.maxHistoryEpisodes!;
            continuousPlaying.value = settings.continuousPlaying!;
          })
        });
  }

  @override
  void onInit() {
    super.onInit();

    _load();
    _scheduleCleanup();

    countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (countdownDuration.value == noCountdown) {
        return;
      }
      if (countdownDuration.value.inSeconds <= 0) {
        countdownDuration.value = noCountdown;
        Get.find<PlayerController>().pause();
        return;
      }
      if (myAudioHandler.isPlaying) {
        countdownDuration.value =
            countdownDuration.value - const Duration(seconds: 1);
      }
    });

    myAudioHandler.speedStream.listen((event) {
      speed.value = event;
    });

    myAudioHandler.skipSilenceEnabledStream.listen((event) {
      skipSilence.value = event;
    });
  }

  void _scheduleCleanup() {
    Timer.periodic(const Duration(minutes: 1), (timer) {
      Get.find<FeedEpisodeController>().removeOld(maxFeedEpisodes.value);
      Get.find<HistoryController>().removeOld(maxHistoryEpisodes.value);
    });
  }

  void setCountdown(Duration duration) {
    countdownDuration.value = duration;
  }

  void stopCountdown() {
    countdownDuration.value = noCountdown;
  }

  void setSpeed(double speed) {
    this.speed.value = speed;
    myAudioHandler.setSpeed(speed);

    helper.db.then((db) {
      SettingsModel.setSpeed(db, speed);
    });
  }

  void setSkipSilence(bool skipSilence) {
    this.skipSilence.value = skipSilence;
    myAudioHandler.setSkipSilence(skipSilence);

    helper.db.then((db) {
      SettingsModel.setSkipSilence(db, skipSilence);
    });
  }

  void setAutoSleepStartHourIndex(int index) {
    autoSleepStartHourIndex.value = index;

    helper.db.then((db) {
      SettingsModel.setAutoSleepTimer(db, autoSleepStartHourIndex.value,
          autoSleepEndHourIndex.value, autoSleepCountdownMinIndex.value);
    });
  }

  void setAutoSleepEndHourIndex(int index) {
    autoSleepEndHourIndex.value = index;

    helper.db.then((db) {
      SettingsModel.setAutoSleepTimer(db, autoSleepStartHourIndex.value,
          autoSleepEndHourIndex.value, autoSleepCountdownMinIndex.value);
    });
  }

  void setAutoSleepCountdownMinIndex(int index) {
    autoSleepCountdownMinIndex.value = index;

    helper.db.then((db) {
      SettingsModel.setAutoSleepTimer(db, autoSleepStartHourIndex.value,
          autoSleepEndHourIndex.value, autoSleepCountdownMinIndex.value);
    });
  }

  void autoSetCountdown() {
    if (countdownDuration.value == noCountdown) {
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
    setCountdown(Duration(minutes: duration));
  }

  Future<void> setMaxCacheCount(int value) async {
    maxCacheCount.value = value;
    helper.db.then((db) {
      SettingsModel.set(db, 'maxCacheCount', value);
    });

    Get.find<CacheController>().updateCacheConfig();
  }

  Future<void> setCountryCode(String value) async {
    countryCode.value = value;
    helper.db.then((db) {
      SettingsModel.set(db, 'countryCode', value);
    });
  }

  Future<void> setTargetLanguage(String value) async {
    targetLanguage.value = value;
    Get.find<TranslationController>().translationUrls.clear();
    helper.db.then((db) {
      SettingsModel.set(db, 'targetLanguage', value);
    });
  }

  Future<void> setAutoRefreshInterval(int value) async {
    autoRefreshInterval.value = value;
    helper.db.then((db) {
      SettingsModel.set(db, 'autoRefreshInterval', value);
    });
    Get.find<FeedEpisodeController>().initAutoRefresher();
  }

  Future<void> setMaxFeedEpisodes(int value) async {
    maxFeedEpisodes.value = value;
    helper.db.then((db) {
      SettingsModel.set(db, 'maxFeedEpisodes', value);
    });
  }

  Future<void> setMaxHistoryEpisodes(int value) async {
    maxHistoryEpisodes.value = value;
    helper.db.then((db) {
      SettingsModel.set(db, 'maxHistoryEpisodes', value);
    });
  }

  Future<void> setContinuousPlaying(bool value) async {
    continuousPlaying.value = value;
    helper.db.then((db) {
      SettingsModel.setContinuousPlaying(db, value);
    });
  }
}
