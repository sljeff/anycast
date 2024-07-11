import 'package:anycast/models/helper.dart';
import 'package:anycast/models/playlist_episode.dart';
import 'package:anycast/states/player.dart';
import 'package:flutter_cache_manager_plus/flutter_cache_manager_plus.dart';
import 'package:get/get.dart';

class CacheController extends GetxController {
  var key2FileResponse = <String, FileResponse>{}.obs;

  var cacheManager = CacheManager(
    Config(
      'anycast_episode',
      maxNrOfCacheObjects: Get.find<SettingsController>().maxCacheCount.value,
    ),
  );

  @override
  void onInit() {
    super.onInit();

    DatabaseHelper().db.then((db) {
      PlaylistEpisodeModel.listByPlaylistId(db, 1).then((list) {
        for (var e in list) {
          cacheManager.checkFileInCache(e.enclosureUrl!).then((info) {
            if (info != null) {
              set(e.enclosureUrl!, info);
            }
          });
        }
      });
    });
  }

  double? get(String key) {
    if (key2FileResponse[key] == null) {
      return null;
    }

    if (key2FileResponse[key]! is FileInfo) {
      return 100;
    } else if (key2FileResponse[key]! is DownloadProgress) {
      return (key2FileResponse[key]! as DownloadProgress).progress;
    }
    return null;
  }

  void set(String key, FileResponse value) {
    key2FileResponse[key] = value;
  }

  void download(String url) {
    print(cacheManager.store.lastCleanupRun);
    print(cacheManager.store.cleanupRunMinInterval);
    cacheManager.getFileStream(url, withProgress: true).listen((event) {
      set(url, event);
    });
  }

  void updateCacheConfig() {
    cacheManager = CacheManager(Config(
      'anycast_episode',
      maxNrOfCacheObjects: Get.find<SettingsController>().maxCacheCount.value,
    ));
  }
}
