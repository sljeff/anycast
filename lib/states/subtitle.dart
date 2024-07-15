import 'dart:async';
import 'dart:convert';

import 'package:anycast/api/subtitles.dart';
import 'package:anycast/models/helper.dart';
import 'package:anycast/models/subtitle.dart';
import 'package:get/get.dart';

class SubtitleController extends GetxController {
  // url => status
  final subtitleUrls = <String, String>{}.obs;

  final helper = DatabaseHelper();

  @override
  void onInit() {
    super.onInit();
    helper.db.then((db) {
      SubtitleModel.list(db).then((urls) {
        subtitleUrls.addAll(urls);
      });
    });

    Timer.periodic(
      const Duration(seconds: 15),
      (timer) async {
        for (var url in subtitleUrls.keys) {
          if (subtitleUrls[url] == 'processing') {
            var result = await getSubtitles(url);
            if (result.status == 'succeeded') {
              subtitleUrls[url] = 'succeeded';
              helper.db.then((db) {
                SubtitleModel.insert(
                    db,
                    SubtitleModel.fromMap({
                      'enclosureUrl': url,
                      'status': 'succeeded',
                      'language': result.language,
                      'subtitle': jsonEncode(result.subtitles),
                    }));
              });
            } else if (result.status == 'failed') {
              subtitleUrls.remove(url);
              helper.db.then((db) {
                SubtitleModel.delete(db, url);
              });
            }
          }
        }
      },
    );
  }

  void add(String url) async {
    subtitleUrls[url] = 'processing';
    await helper.db.then((db) {
      SubtitleModel.insert(
          db,
          SubtitleModel.fromMap({
            'enclosureUrl': url,
            'status': 'processing',
            'subtitle': '',
          }));
    });

    getSubtitles(url).then((value) {
      if (value.status == 'succeeded') {
        subtitleUrls[url] = 'succeeded';
        helper.db.then((db) {
          SubtitleModel.insert(
              db,
              SubtitleModel.fromMap({
                'enclosureUrl': url,
                'status': value.status,
                'language': value.language,
                'subtitle': jsonEncode(value.subtitles),
              }));
        });
      } else if (value.status == 'failed') {
        subtitleUrls.remove(url);
      }
    });
  }

  void remove(String url) {
    subtitleUrls.remove(url);
    helper.db.then((db) {
      SubtitleModel.delete(db, url);
    });
  }
}
