import 'dart:async';
import 'dart:convert';

import 'package:anycast/api/subtitles.dart';
import 'package:anycast/models/helper.dart';
import 'package:anycast/models/subtitle.dart';
import 'package:anycast/models/translation.dart';
import 'package:anycast/states/player.dart';
import 'package:anycast/states/subtitle.dart';
import 'package:get/get.dart';

typedef TargetLanguageProvider = String Function();
typedef SubtitleStatusProvider = Map<String, String> Function();
typedef DetectedLanguageLoader = Future<String?> Function(String url);
typedef CachedTranslationLoader = Future<TranslationModel?> Function(
  String url,
  String language,
);
typedef TranslationFetcher = Future<List<Subtitle>?> Function(
  String url,
  String language,
);
typedef TranslationSaver = Future<void> Function(TranslationModel translation);
typedef TranslationDeleter = Future<void> Function(String url);
typedef TranslationPeriodicTimerFactory = Timer Function(
  Duration duration,
  void Function(Timer timer) callback,
);

class TranslationController extends GetxController {
  TranslationController({
    DatabaseHelper? helper,
    TargetLanguageProvider? targetLanguage,
    SubtitleStatusProvider? subtitleStatuses,
    DetectedLanguageLoader? detectedLanguage,
    CachedTranslationLoader? loadCachedTranslation,
    TranslationFetcher? fetchTranslation,
    TranslationSaver? saveTranslation,
    TranslationDeleter? deleteTranslation,
    TranslationPeriodicTimerFactory? periodicTimer,
  })  : helper = helper ?? DatabaseHelper(),
        _targetLanguage = targetLanguage,
        _subtitleStatuses = subtitleStatuses,
        _detectedLanguage = detectedLanguage ?? getDetectedLanguage,
        _loadCachedTranslation = loadCachedTranslation,
        _fetchTranslation = fetchTranslation ?? getTranslation,
        _saveTranslation = saveTranslation,
        _deleteTranslation = deleteTranslation,
        _periodicTimer = periodicTimer ?? Timer.periodic;

  final translationUrls = <String, String>{}.obs;
  final DatabaseHelper helper;
  final TargetLanguageProvider? _targetLanguage;
  final SubtitleStatusProvider? _subtitleStatuses;
  final DetectedLanguageLoader _detectedLanguage;
  final CachedTranslationLoader? _loadCachedTranslation;
  final TranslationFetcher _fetchTranslation;
  final TranslationSaver? _saveTranslation;
  final TranslationDeleter? _deleteTranslation;
  final TranslationPeriodicTimerFactory _periodicTimer;
  final Set<String> _inFlightUrls = <String>{};
  Timer? _pollTimer;

  @override
  void onInit() {
    super.onInit();

    _pollTimer = _periodicTimer(
      const Duration(seconds: 10),
      (_) => refreshSucceededSubtitles(),
    );
  }

  @override
  void onClose() {
    _pollTimer?.cancel();
    super.onClose();
  }

  Future<void> refreshSucceededSubtitles() async {
    if (_currentTargetLanguage().isEmpty) {
      return;
    }

    final subtitleStatus = _subtitleStatuses?.call() ??
        Get.find<SubtitleController>().subtitleUrls;
    final loads = <Future<void>>[];
    for (final url in subtitleStatus.keys.toList()) {
      if (subtitleStatus[url] == 'succeeded' &&
          translationUrls[url] != 'succeeded') {
        loads.add(loadTranslation(url));
      }
    }
    await Future.wait(loads, eagerError: false);
  }

  Future<void> loadTranslation(String url) async {
    if (translationUrls[url] == 'succeeded' || !_inFlightUrls.add(url)) {
      return;
    }

    try {
      final lang = _currentTargetLanguage();
      if (lang.isEmpty) {
        return;
      }
      final detectedLanguage = await _detectedLanguage(url);
      if (detectedLanguage == null || detectedLanguage == lang) {
        return;
      }

      final cached = _loadCachedTranslation != null
          ? await _loadCachedTranslation(url, lang)
          : await helper.db.then(
              (db) => TranslationModel.get(db, url, lang),
            );
      if (cached != null) {
        translationUrls[url] = 'succeeded';
        return;
      }

      translationUrls[url] = 'processing';

      final translation = await _fetchTranslation(url, lang);
      if (translation == null) {
        return;
      }

      final model = TranslationModel.fromMap({
        'enclosureUrl': url,
        'status': 'succeeded',
        'translation': jsonEncode(translation),
        'language': lang,
      });
      if (_saveTranslation != null) {
        await _saveTranslation(model);
      } else {
        final db = await helper.db;
        await TranslationModel.insert(db, model);
      }

      translationUrls[url] = 'succeeded';
    } finally {
      _inFlightUrls.remove(url);
    }
  }

  Future<void> remove(String url) async {
    translationUrls.remove(url);

    if (_deleteTranslation != null) {
      await _deleteTranslation(url);
      return;
    }
    final db = await helper.db;
    await TranslationModel.delete(db, url);
  }

  String _currentTargetLanguage() {
    return _targetLanguage?.call() ??
        Get.find<SettingsController>().targetLanguage.value;
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
