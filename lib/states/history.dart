import 'package:anycast/models/feed_episode.dart';
import 'package:anycast/models/helper.dart';
import 'package:anycast/models/history_episode.dart';
import 'package:get/get.dart';

class HistoryController extends GetxController {
  var episodes = <HistoryEpisodeModel>[].obs;
  var isLoading = true.obs;

  static final db = DatabaseHelper().db;

  @override
  void onInit() {
    super.onInit();
    load();
  }

  Future<void> load() async {
    db.then((db) async {
      episodes.value = await HistoryEpisodeModel.listAll(db);
      isLoading.value = false;
    });
  }

  void deleteAll() {
    episodes.value = [];

    db.then((db) async {
      await HistoryEpisodeModel.deleteAll(db);
    });
  }

  void delete(String enclosureUrl) {
    episodes.removeWhere((e) => e.enclosureUrl == enclosureUrl);

    db.then((db) async {
      await HistoryEpisodeModel.delete(db, enclosureUrl);
    });
  }

  void insert(HistoryEpisodeModel episode) {
    episodes.removeWhere((e) => e.enclosureUrl == episode.enclosureUrl);
    episodes.insert(0, episode);

    db.then((db) async {
      await HistoryEpisodeModel.insert(db, episode);
    });
  }

  FeedEpisodeModel toFeedEpisode(HistoryEpisodeModel episode) {
    return FeedEpisodeModel.fromMap(episode.toMap());
  }
}
