import 'package:anycast/models/helper.dart';
import 'package:anycast/models/playlist_episode.dart';
import 'package:anycast/utils/audio_handler.dart';
import 'package:get/get.dart';

class PlaylistEpisodeController extends GetxController {
  final episodes = <PlaylistEpisodeModel>[].obs;

  final int playlistId;
  PlaylistEpisodeController({required this.playlistId});

  final DatabaseHelper helper = DatabaseHelper();

  @override
  void onInit() {
    super.onInit();
    load();
  }

  void load() {
    helper.db.then((db) => {
          PlaylistEpisodeModel.listByPlaylistId(db!, playlistId)
              .then((episodes) {
            this.episodes.value = episodes;
          })
        });
  }

  Future<void> add(int position, PlaylistEpisodeModel episode) async {
    episodes.insert(position, episode);
    helper.db.then((db) => {
          PlaylistEpisodeModel.insertOrUpdateByIndex(
              db!, playlistId, position, episode)
        });
    return await MyAudioHandler().insertQueueItem(
        position, MyAudioHandler.playlistepisodeToMediaItem(episode));
  }

  void remove(int playlistId) {
    var oldIndex = episodes.indexWhere((e) => e.id == playlistId);
    episodes.removeAt(oldIndex);
    var myAudioHandler = MyAudioHandler();
    myAudioHandler.removeQueueItemAt(oldIndex);

    helper.db.then((db) => {PlaylistEpisodeModel.delete(db!, playlistId)});
  }

  Future<void> moveToTop(PlaylistEpisodeModel episode) async {
    var oldIndex = episodes.indexWhere((e) => e.id == episode.id);
    episodes.removeAt(oldIndex);
    episodes.insert(0, episode);

    var myAudioHandler = MyAudioHandler();
    var mediaItem = MyAudioHandler.playlistepisodeToMediaItem(episode);
    myAudioHandler.removeQueueItemAt(oldIndex);
    myAudioHandler.insertQueueItem(0, mediaItem);

    return helper.db.then((db) => PlaylistEpisodeModel.insertOrUpdateByIndex(
        db!, playlistId, 0, episode));
  }
}
