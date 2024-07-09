import 'package:anycast/models/helper.dart';
import 'package:anycast/models/playlist_episode.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:get/get.dart';

class CacheController extends GetxController {
  var key2FileResponse = <String, FileResponse>{}.obs;

  @override
  void onInit() {
    super.onInit();

    DatabaseHelper().db.then((db) {
      PlaylistEpisodeModel.listByPlaylistId(db, 1).then((list) {
        for (var e in list) {
          DefaultCacheManager().getFileFromCache(e.enclosureUrl!).then((info) {
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
    DefaultCacheManager()
        .getFileStream(url, withProgress: true)
        .listen((event) {
      set(url, event);
    });
  }
}
