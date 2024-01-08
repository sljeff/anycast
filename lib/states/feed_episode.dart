import 'package:anycast/models/feed_episode.dart';
import 'package:anycast/models/helper.dart';
import 'package:anycast/models/playlist_episode.dart';
import 'package:anycast/states/playlist.dart';
import 'package:anycast/states/playlist_episode.dart';
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
          FeedEpisodeModel.insertMany(db!, episodes).then((v) {
            load(episodes);
          })
        });
  }

  Future<void> removeByGuids(List<String> guids) async {
    helper.db.then((db) => {
          FeedEpisodeModel.removeByGuids(db!, guids).then((v) {
            episodes.removeWhere((episode) => guids.contains(episode.guid));
          })
        });
  }

  void load(List<FeedEpisodeModel> episodes) {
    helper.db.then((db) => {
          FeedEpisodeModel.listAll(db!).then((episodes) {
            this.episodes.value = episodes;
          })
        });
  }

  Future<PlaylistEpisodeModel> addToPlaylist(FeedEpisodeModel episode) async {
    var playlistId = 1;

    // add to default playlist; remove from feeds
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
    return helper.db.then((db) {
      if (db == null) {
        throw Exception('Unable to open database');
      }

      PlaylistEpisodeController? playlistEpisodeController;
      var playlists = Get.find<PlaylistController>().playlists;
      var controllers = Get.find<PlaylistController>().episodesControllers;
      for (var i = 0; i < playlists.length; i++) {
        if (playlists[i].id == playlistId) {
          playlistEpisodeController = controllers[i];
          break;
        }
      }
      playlistEpisodeController!.add(playlistEpisode);

      MyAudioHandler().insertQueueItem(
        0,
        MyAudioHandler.playlistepisodeToMediaItem(playlistEpisode),
      );
      removeByGuids([episode.guid!]);
      return playlistEpisode;
    });
  }
}
