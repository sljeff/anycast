import 'dart:async';

import 'package:anycast/models/player.dart';
import 'package:anycast/models/playlist_episode.dart';
import 'package:anycast/states/player.dart';
import 'package:anycast/states/playlist_episode.dart';
import 'package:anycast/utils/audio_handler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';

void main() {
  group('player progress', () {
    test('empty and missing progress data initialize to safe zero values', () {
      final controller = PlayerController(audio: FakePlayerAudio());

      controller.initProgress();
      expectPosition(
        controller.positionData.value,
        position: Duration.zero,
        bufferedPosition: Duration.zero,
        duration: Duration.zero,
      );

      controller.playlistEpisode.value = episode(
        url: 'https://example.com/current.mp3',
      );
      controller.initProgress();
      expectPosition(
        controller.positionData.value,
        position: Duration.zero,
        bufferedPosition: Duration.zero,
        duration: Duration.zero,
      );
    });

    test('restores persisted position and duration for the current episode',
        () {
      final controller = PlayerController(audio: FakePlayerAudio());
      controller.playlistEpisode.value = episode(
        url: 'https://example.com/current.mp3',
        playedDuration: 42000,
        duration: 180000,
      );

      controller.initProgress();

      expectPosition(
        controller.positionData.value,
        position: const Duration(seconds: 42),
        bufferedPosition: Duration.zero,
        duration: const Duration(minutes: 3),
      );
    });

    test('selecting a saved queue restores its first episode progress', () {
      final queuedEpisode = episode(
        url: 'https://example.com/queued.mp3',
        playedDuration: 12000,
        duration: 90000,
      );
      final queue = FakePlaylistEpisodeController(playlistId: 7);
      queue.episodes.value = [queuedEpisode];
      final controller = PlayerController(
        audio: FakePlayerAudio(),
        playlistEpisodeControllerForId: (playlistId) {
          expect(playlistId, 7);
          return queue;
        },
      );
      controller.player.value = PlayerModel.fromMap({
        'currentPlaylistId': 7,
      });

      expect(controller.playlistEpisodeController, same(queue));
      expect(controller.playlistEpisode.value, same(queuedEpisode));
      expectPosition(
        controller.positionData.value,
        position: const Duration(seconds: 12),
        bufferedPosition: Duration.zero,
        duration: const Duration(seconds: 90),
      );
    });

    test('accepts only usable live progress while playback is active', () {
      final audio = FakePlayerAudio();
      final controller = PlayerController(audio: audio);
      final initial = controller.positionData.value;
      final valid = PositionData(
        position: const Duration(seconds: 4),
        bufferedPosition: const Duration(seconds: 8),
        duration: const Duration(minutes: 1),
      );

      controller.handlePositionData(valid);
      expect(controller.positionData.value, same(initial));

      audio.isPlaying = true;
      controller.isLoading.value = true;
      controller.handlePositionData(valid);
      expect(controller.positionData.value, same(initial));

      controller.isLoading.value = false;
      controller.handlePositionData(PositionData(
        position: Duration.zero,
        bufferedPosition: const Duration(seconds: 8),
        duration: const Duration(minutes: 1),
      ));
      controller.handlePositionData(PositionData(
        position: const Duration(seconds: 4),
        bufferedPosition: Duration.zero,
        duration: const Duration(minutes: 1),
      ));
      expect(controller.positionData.value, same(initial));

      controller.handlePositionData(valid);
      expect(controller.positionData.value, same(valid));
    });
  });

  group('player controls', () {
    test('current episode is reported only while that exact episode is playing',
        () {
      final controller = PlayerController(audio: FakePlayerAudio());
      const currentUrl = 'https://example.com/current.mp3';

      expect(controller.isPlayingEpisode(currentUrl), isFalse);

      controller.playlistEpisode.value = episode(url: currentUrl);
      expect(controller.isPlayingEpisode(currentUrl), isFalse);

      controller.isPlaying.value = true;
      expect(controller.isPlayingEpisode(currentUrl), isTrue);
      expect(
        controller.isPlayingEpisode('https://example.com/other.mp3'),
        isFalse,
      );
    });

    test('toggle ignores an empty player and otherwise chooses pause or play',
        () async {
      final controller = RecordingPlayerController(audio: FakePlayerAudio());

      controller.togglePlay();
      expect(controller.playCalls, 0);
      expect(controller.pauseCalls, 0);

      controller.playlistEpisode.value =
          episode(url: 'https://example.com/current.mp3');
      controller.togglePlay();
      expect(controller.playCalls, 1);
      expect(controller.pauseCalls, 0);

      controller.isPlaying.value = true;
      controller.togglePlay();
      expect(controller.playCalls, 1);
      expect(controller.pauseCalls, 1);
    });

    test('seek ignores an empty player and forwards episode and position',
        () async {
      final audio = FakePlayerAudio();
      final controller = PlayerController(audio: audio);
      const target = Duration(seconds: 55);

      await controller.seek(target);
      expect(audio.seekCalls, isEmpty);

      final current = episode(url: 'https://example.com/current.mp3');
      controller.playlistEpisode.value = current;
      await controller.seek(target);

      expect(audio.seekCalls, hasLength(1));
      expect(audio.seekCalls.single.episode, same(current));
      expect(audio.seekCalls.single.position, target);
    });
  });

  group('playback completion', () {
    test('does nothing to a queue when there is no current playlist', () async {
      final queue = FakePlaylistEpisodeController(playlistId: 1);
      queue.episodes.value = [
        episode(url: 'https://example.com/current.mp3'),
      ];
      final controller = RecordingPlayerController(
        audio: FakePlayerAudio(),
        queueForPlaylist: (_) => queue,
      );

      await controller.handlePlaybackState(
        PlayerState(false, ProcessingState.completed),
      );

      expect(queue.removeTopCalls, 0);
      expect(queue.episodes, hasLength(1));
      expect(controller.pauseCalls, 0);
      expect(controller.clearCalls, 0);
      expect(controller.playedEpisodes, isEmpty);
    });

    test('removes the completed final episode then pauses and clears',
        () async {
      final current = episode(url: 'https://example.com/current.mp3');
      final queue = FakePlaylistEpisodeController(playlistId: 1);
      queue.episodes.value = [current];
      final controller = RecordingPlayerController(
        audio: FakePlayerAudio(),
        queueForPlaylist: (_) => queue,
      )
        ..player.value = PlayerModel.fromMap({'currentPlaylistId': 1})
        ..playlistEpisode.value = current;

      await controller.handlePlaybackState(
        PlayerState(false, ProcessingState.completed),
      );

      expect(queue.removeTopCalls, 1);
      expect(queue.episodes, isEmpty);
      expect(controller.pauseCalls, 1);
      expect(controller.clearCalls, 1);
      expect(controller.playedEpisodes, isEmpty);
    });

    test('removes the completed episode and starts the next one continuously',
        () async {
      final current = episode(url: 'https://example.com/current.mp3');
      final next = episode(url: 'https://example.com/next.mp3');
      final queue = FakePlaylistEpisodeController(playlistId: 1);
      queue.episodes.value = [current, next];
      final controller = RecordingPlayerController(
        audio: FakePlayerAudio(),
        queueForPlaylist: (_) => queue,
        continuousPlaying: () => true,
      )
        ..player.value = PlayerModel.fromMap({'currentPlaylistId': 1})
        ..playlistEpisode.value = current;

      await controller.handlePlaybackState(
        PlayerState(false, ProcessingState.completed),
      );

      expect(queue.removeTopCalls, 1);
      expect(queue.episodes, [same(next)]);
      expect(controller.playedEpisodes, [same(next)]);
      expect(controller.pauseCalls, 0);
      expect(controller.clearCalls, 0);
      expect(controller.initProgressCalls, 0);
    });

    test('loads but pauses the next episode when continuous play is disabled',
        () async {
      final current = episode(url: 'https://example.com/current.mp3');
      final next = episode(url: 'https://example.com/next.mp3');
      final delays = <Duration>[];
      final queue = FakePlaylistEpisodeController(playlistId: 1);
      queue.episodes.value = [current, next];
      final controller = RecordingPlayerController(
        audio: FakePlayerAudio(),
        queueForPlaylist: (_) => queue,
        continuousPlaying: () => false,
        delay: (duration) async => delays.add(duration),
      )
        ..player.value = PlayerModel.fromMap({'currentPlaylistId': 1})
        ..playlistEpisode.value = current;

      await controller.handlePlaybackState(
        PlayerState(false, ProcessingState.completed),
      );

      expect(queue.removeTopCalls, 1);
      expect(controller.playedEpisodes, [same(next)]);
      expect(controller.pauseCalls, 1);
      expect(delays, [const Duration(milliseconds: 100)]);
      expect(controller.initProgressCalls, 1);
      expect(controller.clearCalls, 0);
    });

    test('updates observable loading and playing state for stream events',
        () async {
      final controller = RecordingPlayerController(audio: FakePlayerAudio());

      await controller.handlePlaybackState(
        PlayerState(true, ProcessingState.buffering),
      );
      expect(controller.isPlaying.value, isTrue);
      expect(controller.isLoading.value, isTrue);

      await controller.handlePlaybackState(
        PlayerState(false, ProcessingState.ready),
      );
      expect(controller.isPlaying.value, isFalse);
      expect(controller.isLoading.value, isFalse);
    });
  });

  group('player lifecycle', () {
    test('periodically saves progress and cleans up lifecycle resources',
        () async {
      final playbackStates = StreamController<PlayerState>.broadcast();
      final positionData = StreamController<PositionData>.broadcast();
      final current = episode(url: 'https://example.com/current.mp3');
      final queue = FakePlaylistEpisodeController(playlistId: 1)
        ..episodes.value = [current];
      final audio = FakePlayerAudio(
        playbackStateStream: playbackStates.stream,
        positionDataStream: positionData.stream,
      )
        ..isPlaying = true
        ..playedDuration = const Duration(seconds: 42);
      late final RecordingTimer timer;
      final controller = RecordingPlayerController(
        audio: audio,
        queueForPlaylist: (playlistId) {
          expect(playlistId, 1);
          return queue;
        },
        periodicTimer: (duration, callback) {
          expect(duration, const Duration(seconds: 2));
          timer = RecordingTimer(callback);
          return timer;
        },
      )
        ..player.value = PlayerModel.fromMap({'currentPlaylistId': 1})
        ..playlistEpisode.value = current;

      controller.onInit();

      expect(playbackStates.hasListener, isTrue);
      expect(positionData.hasListener, isTrue);
      expect(timer.isActive, isTrue);

      timer.fire();
      expect(queue.playedDurationUpdates, [const Duration(seconds: 42)]);

      controller.onClose();
      await Future<void>.delayed(Duration.zero);

      expect(timer.isActive, isFalse);
      expect(playbackStates.hasListener, isFalse);
      expect(positionData.hasListener, isFalse);

      await playbackStates.close();
      await positionData.close();
    });
  });
}

PlaylistEpisodeModel episode({
  required String url,
  int? playedDuration,
  int? duration,
}) {
  return PlaylistEpisodeModel.fromMap({
    'playlistId': 1,
    'enclosureUrl': url,
    'playedDuration': playedDuration,
    'duration': duration,
  });
}

void expectPosition(
  PositionData actual, {
  required Duration position,
  required Duration bufferedPosition,
  required Duration duration,
}) {
  expect(actual.position, position);
  expect(actual.bufferedPosition, bufferedPosition);
  expect(actual.duration, duration);
}

class FakePlayerAudio implements PlayerAudio {
  FakePlayerAudio({
    Stream<PlayerState>? playbackStateStream,
    Stream<PositionData>? positionDataStream,
  })  : _playbackStateStream = playbackStateStream ?? const Stream.empty(),
        _positionDataStream = positionDataStream ?? const Stream.empty();

  final Stream<PlayerState> _playbackStateStream;
  final Stream<PositionData> _positionDataStream;

  @override
  bool hasAudioSource = false;

  @override
  bool isPlaying = false;

  @override
  Duration playedDuration = Duration.zero;

  final seekCalls = <SeekCall>[];

  @override
  Stream<PlayerState> get playbackStateStream => _playbackStateStream;

  @override
  Stream<PositionData> get positionDataStream => _positionDataStream;

  @override
  Future<void> pause() async {}

  @override
  Future<void> play() async {}

  @override
  Future<void> playByEpisode(PlaylistEpisodeModel episode) async {}

  @override
  Future<void> seekAndPlayByEpisode(
    PlaylistEpisodeModel episode,
    Duration position,
  ) async {
    seekCalls.add(SeekCall(episode, position));
  }

  @override
  Future<void> setByEpisode(PlaylistEpisodeModel episode) async {}
}

class SeekCall {
  SeekCall(this.episode, this.position);

  final PlaylistEpisodeModel episode;
  final Duration position;
}

class FakePlaylistEpisodeController extends PlaylistEpisodeController {
  FakePlaylistEpisodeController({required super.playlistId});

  int removeTopCalls = 0;
  final playedDurationUpdates = <Duration>[];

  @override
  void removeTop() {
    removeTopCalls += 1;
    episodes.removeAt(0);
  }

  @override
  Future<void> updatePlayedDuration(Duration duration) async {
    playedDurationUpdates.add(duration);
  }
}

class RecordingPlayerController extends PlayerController {
  RecordingPlayerController({
    required super.audio,
    PlaylistEpisodeController Function(int playlistId)? queueForPlaylist,
    super.continuousPlaying,
    super.delay,
    super.periodicTimer,
  }) : super(
          playlistEpisodeControllerForId: queueForPlaylist,
        );

  int pauseCalls = 0;
  int playCalls = 0;
  int clearCalls = 0;
  int initProgressCalls = 0;
  final playedEpisodes = <PlaylistEpisodeModel>[];

  @override
  void load() {}

  @override
  Future<void> pause() async {
    pauseCalls += 1;
  }

  @override
  Future<void> play() async {
    playCalls += 1;
  }

  @override
  void clear() {
    clearCalls += 1;
  }

  @override
  void initProgress() {
    initProgressCalls += 1;
  }

  @override
  Future<void> playByEpisode(PlaylistEpisodeModel episode) async {
    playedEpisodes.add(episode);
    playlistEpisode.value = episode;
  }
}

class RecordingTimer implements Timer {
  RecordingTimer(this._callback);

  final void Function(Timer timer) _callback;
  var _isActive = true;
  var _tick = 0;

  @override
  bool get isActive => _isActive;

  @override
  int get tick => _tick;

  void fire() {
    if (!_isActive) {
      return;
    }
    _tick += 1;
    _callback(this);
  }

  @override
  void cancel() {
    _isActive = false;
  }
}
