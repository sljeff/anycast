import 'package:flutter/foundation.dart';
import 'package:anycast/models/player.dart';

class PlayerProvider extends ChangeNotifier {
  PlayerModel? _player;
  bool _isPlaying = false;

  PlayerModel? get player => _player;
  bool get isPlaying => _isPlaying;

  void setPlayer(PlayerModel player, bool isPlaying) {
    _player = player;
    _isPlaying = isPlaying;
    notifyListeners();
  }

  void setIsPlaying(bool isPlaying) {
    _isPlaying = isPlaying;
    notifyListeners();
  }
}
