import 'package:anycast/models/playlist_episode.dart';
import 'package:flutter/foundation.dart';
import 'package:anycast/models/player.dart';

class PlayerProvider extends ChangeNotifier {
  PlayerModel? _player;
  PlaylistEpisodeModel? _playlistEpisode;

  PlayerModel? get player => _player;
  PlaylistEpisodeModel? get playlistEpisode => _playlistEpisode;

  void setPlayer(PlayerModel player, PlaylistEpisodeModel playlistEpisode) {
    _player = player;
    _playlistEpisode = playlistEpisode;
    notifyListeners();
  }
}
