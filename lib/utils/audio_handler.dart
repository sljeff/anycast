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
  final _playlist = ConcatenatingAudioSource(children: []);

  bool get isPlaying => _player.playing;

  Stream<PlayerState> get playbackStateStream => _player.playerStateStream;
  Stream<PositionData> get positionDataStream =>
      _player.positionStream.map((event) => PositionData(
            position: event,
            bufferedPosition: _player.bufferedPosition,
            duration: _player.duration ?? Duration.zero,
          ));

  static MediaItem playlistepisodeToMediaItem(PlaylistEpisodeModel episode) {
    return MediaItem(
      id: episode.enclosureUrl!,
      album: episode.channelTitle,
      title: episode.title!,
      artUri: Uri.parse(episode.imageUrl!),
      duration: episode.duration != null
          ? Duration(seconds: episode.duration!)
          : null,
    );
  }

  // always play the first episode
  // if the first episode is played, do nothing
  @override
  Future<void> play() async {
    if (_playlist.children.isEmpty) {
      return;
    }
    if (_player.playing) {
      return;
    }
    if (_player.currentIndex == 0) {
      await _player.play();
      return;
    }
    await _player.setAudioSource(_playlist);
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

  @override
  Future<void> seek(Duration position) async {
    await _player.seek(position);
    await super.seek(position);
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
  Future<void> addQueueItem(MediaItem mediaItem) async {
    _playlist.add(AudioSource.uri(Uri.parse(mediaItem.id)));
    await super.addQueueItem(mediaItem);
  }

  @override
  Future<void> updateQueue(List<MediaItem> queue) async {
    _playlist.clear();
    addQueueItems(queue);
    await super.updateQueue(queue);
  }

  @override
  Future<void> insertQueueItem(int index, MediaItem mediaItem) async {
    _playlist.insert(index, AudioSource.uri(Uri.parse(mediaItem.id)));
    await super.insertQueueItem(index, mediaItem);
  }

  @override
  Future<void> removeQueueItemAt(int index) async {
    _playlist.removeAt(index);
    await super.removeQueueItemAt(index);
  }

  @override
  Future<void> addQueueItems(List<MediaItem> mediaItems) async {
    _playlist.addAll(
        mediaItems.map((e) => AudioSource.uri(Uri.parse(e.id))).toList());
    await super.addQueueItems(mediaItems);
  }

  @override
  Future<void> skipToNext() async {
    await _player.seekToNext();
    await super.skipToNext();
  }

  @override
  Future<void> skipToPrevious() async {
    await _player.seekToPrevious();
    await super.skipToPrevious();
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

  @override
  Future<void> setCaptioningEnabled(bool enabled) async {
    // TODO: implement setCaptioningEnabled
    await super.setCaptioningEnabled(enabled);
  }
}
