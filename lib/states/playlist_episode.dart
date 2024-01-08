import 'package:flutter/foundation.dart';
import 'package:anycast/models/playlist_episode.dart';

// TODO: optimize with value notifier
class PlaylistEpisodeProvider extends ChangeNotifier {
  // playlistId -> episodes
  final Map<int, List<PlaylistEpisodeModel>> _episodes = {};

  Map<int, List<PlaylistEpisodeModel>> get episodes => _episodes;

  void addToPlaylist(int playlistId, PlaylistEpisodeModel episode) {
    if (_episodes[playlistId] == null) {
      _episodes[playlistId] = [];
    }
    // to the top
    _episodes[playlistId]!.insert(0, episode);
    notifyListeners();
  }

  void syncByPlaylistId(int playlistId, List<PlaylistEpisodeModel> episodes) {
    _episodes[playlistId] = episodes;
    notifyListeners();
  }

  void loadByPlaylistId(int playlistId, List<PlaylistEpisodeModel> episodes) {
    _episodes[playlistId] = episodes;
    notifyListeners();
  }

  void removeFromPlaylist(int playlistId, int id) {
    _episodes[playlistId]!.removeWhere((episode) => episode.id == id);
    notifyListeners();
  }

  void moveToTop(int playlistId, PlaylistEpisodeModel episode) {
    _episodes[playlistId]!.removeWhere((e) => e.id == episode.id);
    _episodes[playlistId]!.insert(0, episode);
    notifyListeners();
  }
}
