import 'package:anycast/models/feed_episode.dart';
import 'package:anycast/models/helper.dart';
import 'package:anycast/models/playlist_episode.dart';
import 'package:anycast/states/player.dart';
import 'package:anycast/states/playlist.dart';
import 'package:anycast/utils/audio_handler.dart';
import 'package:get/get.dart';

class FeedEpisodeController extends GetxController {
  final episodes = <FeedEpisodeModel>[].obs;

  final DatabaseHelper helper = DatabaseHelper();
  final MyAudioHandler audioHandler = MyAudioHandler();

  @override
  void onInit() {
    super.onInit();
    load(episodes);
  }

  void addMany(List<FeedEpisodeModel> episodes) {
    helper.db.then((db) => {
          FeedEpisodeModel.insertMany(db!, episodes).then((db) {
            load(episodes);
          })
        });
  }

  Future<void> removeByGuids(List<String> guids) async {
    episodes.removeWhere((episode) => guids.contains(episode.guid));
    helper.db.then((db) => {FeedEpisodeModel.removeByGuids(db!, guids)});
  }

  void load(List<FeedEpisodeModel> episodes) {
    helper.db.then((db) => {
          FeedEpisodeModel.listAll(db!).then((episodes) {
            this.episodes.value = episodes;
          })
        });
  }

  static PlaylistEpisodeModel feed2playlist(
      int playlistId, FeedEpisodeModel episode) {
    var playlistEpisode =
        PlaylistEpisodeModel.fromMap(Map<String, dynamic>.from({
      'title': episode.title,
      'description': episode.description,
      'guid': episode.guid,
      'duration': episode.duration,
      'enclosureUrl': episode.enclosureUrl,
      'pubDate': episode.pubDate,
      'imageUrl': episode.imageUrl,
      'channelTitle': episode.channelTitle,
      'rssFeedUrl': episode.rssFeedUrl,
      'playlistId': playlistId,
      'position': double.infinity,
      'playedDuration': 0,
    }));

    return playlistEpisode;
  }

  Future<PlaylistEpisodeModel> addToPlaylist(
      int playlistId, FeedEpisodeModel episode) async {
    // add to default playlist; remove from feeds
    var playlistEpisode = feed2playlist(playlistId, episode);

    var position = 0;
    if (Get.find<PlayerController>().isPlaying(playlistId)) {
      position = 1;
    }

    removeByGuids([episode.guid!]);

    var playlistEpisodeController = Get.find<PlaylistController>()
        .getEpisodeControllerByPlaylistId(playlistId);
    await playlistEpisodeController.add(position, playlistEpisode);

    return playlistEpisode;
  }

  Future<PlaylistEpisodeModel> addToTop(
      int playlistId, FeedEpisodeModel episode) async {
    var playlistEpisode = feed2playlist(playlistId, episode);
    var playlistEpisodeController = Get.find<PlaylistController>()
        .getEpisodeControllerByPlaylistId(playlistId);
    removeByGuids([episode.guid!]);
    await playlistEpisodeController.add(0, playlistEpisode);
    return playlistEpisode;
  }
}
