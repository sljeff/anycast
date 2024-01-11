import 'dart:async';

import 'package:anycast/models/playlist_episode.dart';
import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';

class PositionData {
  final Duration position;
  final Duration bufferedPosition;
  final Duration duration;

  PositionData({
    required this.position,
    required this.bufferedPosition,
    required this.duration,
  });
}

class MyAudioHandler extends BaseAudioHandler {
  static final _instance = MyAudioHandler._internal();
  factory MyAudioHandler() => _instance;

  MyAudioHandler._internal();

  final _player = AudioPlayer();

  bool get isPlaying => _player.playing;
  Duration get playedDuration => _player.position;
  AudioSource? get audioSource => _player.audioSource;

  Stream<PlayerState> get playbackStateStream => _player.playerStateStream;
  Stream<PositionData> get positionDataStream =>
      _player.positionStream.map((event) => PositionData(
            position: event,
            bufferedPosition: _player.bufferedPosition,
            duration: _player.duration ?? Duration.zero,
          ));

  Future<void> playByEpisode(PlaylistEpisodeModel episode) async {
    if (mediaItem.value?.id == episode.enclosureUrl) {
      play();
      return;
    }

    var source = _createAudioSource(episode.toMediaItem());

    await _player.setAudioSource(source,
        initialPosition: Duration(milliseconds: episode.playedDuration ?? 0));

    play();
  }

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> skipToQueueItem(int index) async {
    var playedDuration = queue.value[index].extras!['playedDuration'];
    await _player.seek(Duration(milliseconds: playedDuration), index: index);
    play();
  }

  @override
  Future<void> play() async {
    await _player.play();
    return super.play();
  }

  @override
  Future<void> pause() async {
    await _player.pause();
    await super.pause();
  }

  @override
  Future<void> stop() async {
    await _player.stop();
    await super.stop();
  }

  Future<void> seekByRelative(Duration relativePosition) async {
    var newPosition = _player.position + relativePosition;
    if (newPosition < Duration.zero) {
      newPosition = Duration.zero;
    }
    if (newPosition > _player.duration!) {
      newPosition = _player.duration!;
    }
    await _player.seek(newPosition);
  }

  @override
  Future<void> setRepeatMode(AudioServiceRepeatMode repeatMode) async {
    await _player.setLoopMode(
        repeatMode == AudioServiceRepeatMode.all ? LoopMode.all : LoopMode.off);
    await super.setRepeatMode(repeatMode);
  }

  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode) async {
    await _player
        .setShuffleModeEnabled(shuffleMode == AudioServiceShuffleMode.all);
    await super.setShuffleMode(shuffleMode);
  }

  @override
  Future<void> setSpeed(double speed) async {
    await _player.setSpeed(speed);
    await super.setSpeed(speed);
  }

  UriAudioSource _createAudioSource(MediaItem item) {
    return ProgressiveAudioSource(Uri.parse(item.id));
  }
}
