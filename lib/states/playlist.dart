import 'package:flutter/foundation.dart';
import 'package:anycast/models/playlist.dart';

class PlaylistProvider extends ChangeNotifier {
  List<PlaylistModel> _playlists = [];

  List<PlaylistModel> get playlists => _playlists;

  void addPlaylist(PlaylistModel playlist) {
    _playlists.add(playlist);
    notifyListeners();
  }

  void removePlaylist(PlaylistModel playlist) {
    _playlists.remove(playlist);
    notifyListeners();
  }

  void load(List<PlaylistModel> playlists) {
    _playlists = playlists;
    notifyListeners();
  }
}
