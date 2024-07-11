import 'dart:async';

import 'package:anycast/models/helper.dart';
import 'package:anycast/states/player.dart';
import 'package:anycast/states/subtitle.dart';
import 'package:get/get.dart';

class TranslationController extends GetxController {
  final translationUrls = <String, String>{}.obs;
  final helper = DatabaseHelper();

  @override
  void onInit() {
    super.onInit();
    Timer.periodic(const Duration(seconds: 10), (timer) {
      // check enabled
      if (Get.find<SettingsController>().targetLanguage.value == '') {
        return;
      }

      var subtitleStatus = Get.find<SubtitleController>().subtitleUrls;
      for (var url in subtitleStatus.keys) {
        if (subtitleStatus[url] == 'succeeded') {
          loadTranslation(url);
        }
      }
    });
  }

  Future<void> loadTranslation(String url) async {
    if (translationUrls[url] == 'succeeded') {
      return;
    }

    translationUrls[url] = 'processing';

    // api

    // db
  }
}
