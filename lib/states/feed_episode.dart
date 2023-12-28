import 'package:flutter/foundation.dart';
import 'package:anycast/models/feed_episode.dart';

class FeedEpisodeProvider extends ChangeNotifier {
  List<FeedEpisodeModel> _episodes = [];

  List<FeedEpisodeModel> get episodes => _episodes;

  void addMany(List<FeedEpisodeModel> episodes) {
    _episodes.addAll(episodes);
    // sort by pubDate desc
    _episodes.sort((a, b) => b.pubDate!.compareTo(a.pubDate!));
    notifyListeners();
  }

  void removeByGuids(List<String> guids) {
    _episodes.removeWhere((episode) => guids.contains(episode.guid));
    notifyListeners();
  }

  void load(List<FeedEpisodeModel> episodes) {
    _episodes = episodes;
    notifyListeners();
  }
}
