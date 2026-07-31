import 'dart:async';
import 'dart:convert';

import 'package:anycast/api/subtitles.dart';
import 'package:anycast/models/helper.dart';
import 'package:anycast/models/subtitle.dart';
import 'package:get/get.dart';

typedef SubtitleFetcher = Future<SubtitleResult> Function(String url);
typedef SubtitleStatusLoader = Future<Map<String, String>> Function();
typedef SubtitleSaver = Future<void> Function(SubtitleModel subtitle);
typedef SubtitleDeleter = Future<void> Function(String url);
typedef SubtitlePeriodicTimerFactory = Timer Function(
  Duration duration,
  void Function(Timer timer) callback,
);

class SubtitleController extends GetxController {
  SubtitleController({
    DatabaseHelper? helper,
    SubtitleFetcher? fetchSubtitles,
    SubtitleStatusLoader? loadStatuses,
    SubtitleSaver? saveSubtitle,
    SubtitleDeleter? deleteSubtitle,
    SubtitlePeriodicTimerFactory? periodicTimer,
  })  : helper = helper ?? DatabaseHelper(),
        _fetchSubtitles = fetchSubtitles ?? getSubtitles,
        _loadStatuses = loadStatuses,
        _saveSubtitle = saveSubtitle,
        _deleteSubtitle = deleteSubtitle,
        _periodicTimer = periodicTimer ?? Timer.periodic;

  // url => status
  final subtitleUrls = <String, String>{}.obs;

  final DatabaseHelper helper;
  final SubtitleFetcher _fetchSubtitles;
  final SubtitleStatusLoader? _loadStatuses;
  final SubtitleSaver? _saveSubtitle;
  final SubtitleDeleter? _deleteSubtitle;
  final SubtitlePeriodicTimerFactory _periodicTimer;
  Timer? _pollTimer;

  @override
  void onInit() {
    super.onInit();
    loadStoredStatuses();
    _pollTimer = _periodicTimer(
      const Duration(seconds: 15),
      (_) => refreshProcessing(),
    );
  }

  @override
  void onClose() {
    _pollTimer?.cancel();
    super.onClose();
  }

  Future<void> loadStoredStatuses() async {
    final statuses = _loadStatuses != null
        ? await _loadStatuses()
        : await helper.db.then(SubtitleModel.list);
    subtitleUrls.addAll(statuses);
  }

  Future<void> refreshProcessing() async {
    for (final url in subtitleUrls.keys.toList()) {
      if (subtitleUrls[url] == 'processing') {
        await _applyResult(url, await _fetchSubtitles(url));
      }
    }
  }

  Future<void> add(String url) async {
    subtitleUrls[url] = 'processing';
    await _persist(
      SubtitleModel.fromMap({
        'enclosureUrl': url,
        'status': 'processing',
        'subtitle': '',
      }),
    );

    await _applyResult(url, await _fetchSubtitles(url));
  }

  Future<void> _applyResult(String url, SubtitleResult result) async {
    if (result.status == 'succeeded') {
      subtitleUrls[url] = 'succeeded';
      await _persist(
        SubtitleModel.fromMap({
          'enclosureUrl': url,
          'status': result.status,
          'language': result.language,
          'subtitle': jsonEncode(result.subtitles),
          'summary': result.summary,
        }),
      );
    } else if (result.status == 'failed') {
      await remove(url);
    }
  }

  Future<void> _persist(SubtitleModel subtitle) async {
    if (_saveSubtitle != null) {
      await _saveSubtitle(subtitle);
      return;
    }
    final db = await helper.db;
    await SubtitleModel.insert(db, subtitle);
  }

  Future<void> remove(String url) async {
    subtitleUrls.remove(url);
    if (_deleteSubtitle != null) {
      await _deleteSubtitle(url);
      return;
    }
    final db = await helper.db;
    await SubtitleModel.delete(db, url);
  }
}
