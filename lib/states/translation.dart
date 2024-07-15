import 'dart:async';
import 'dart:convert';

import 'package:anycast/api/subtitles.dart';
import 'package:anycast/models/helper.dart';
import 'package:anycast/models/subtitle.dart';
import 'package:anycast/models/translation.dart';
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
          if (translationUrls[url] == 'succeeded') {
            continue;
          }
          loadTranslation(url);
        }
      }
    });
  }

  Future<void> loadTranslation(String url) async {
    if (translationUrls[url] == 'succeeded') {
      return;
    }

    var lang = Get.find<SettingsController>().targetLanguage.value;
    if (lang == '') {
      return;
    }
    var detectedLanguage = await getDetectedLanguage(url);
    if (detectedLanguage == null || detectedLanguage == lang) {
      return;
    }

    var result = await helper.db.then((db) async {
      return await TranslationModel.get(db, url, lang);
    });
    if (result != null) {
      translationUrls[url] = 'succeeded';
      return;
    }

    translationUrls[url] = 'processing';

    var translation = await getTranslation(url, lang);
    if (translation == null) {
      return;
    }

    await helper.db.then((db) async {
      await TranslationModel.insert(
          db,
          TranslationModel.fromMap({
            'enclosureUrl': url,
            'status': 'succeeded',
            'translation': jsonEncode(translation),
            'language': lang,
          }));

      translationUrls[url] = 'succeeded';
    });
  }
}

Future<String?> getDetectedLanguage(String url) async {
  return DatabaseHelper().db.then((db) async {
    var subtitle = await SubtitleModel.get(db, url);
    if (subtitle.id == null) {
      return null;
    }
    return subtitle.language;
  });
}
