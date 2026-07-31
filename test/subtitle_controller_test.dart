import 'dart:async';
import 'dart:convert';

import 'package:anycast/api/subtitles.dart';
import 'package:anycast/models/subtitle.dart';
import 'package:anycast/states/subtitle.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

SubtitleResult _result(
  String status, {
  String? language,
  List<Subtitle>? subtitles,
}) {
  return SubtitleResult()
    ..status = status
    ..language = language
    ..subtitles = subtitles;
}

Subtitle _segment(double start, double end, String text) {
  return Subtitle()
    ..start = start
    ..end = end
    ..text = text;
}

void main() {
  group('SubtitleController', () {
    test('onInit restores statuses, polls processing entries, and cancels',
        () async {
      final fetched = <String>[];
      final saved = <SubtitleModel>[];
      final deleted = <String>[];
      final pollCompleted = Completer<void>();
      late Duration pollInterval;
      late _ManualTimer pollTimer;
      final controller = SubtitleController(
        loadStatuses: () async => <String, String>{
          'already-ready.mp3': 'succeeded',
          'retry-success.mp3': 'processing',
          'retry-failure.mp3': 'processing',
        },
        fetchSubtitles: (url) async {
          fetched.add(url);
          if (url == 'retry-success.mp3') {
            return _result(
              'succeeded',
              language: 'en',
              subtitles: <Subtitle>[_segment(0, 1, 'done')],
            );
          }
          return _result('failed');
        },
        saveSubtitle: (subtitle) async => saved.add(subtitle),
        deleteSubtitle: (url) async {
          deleted.add(url);
          pollCompleted.complete();
        },
        periodicTimer: (interval, callback) {
          pollInterval = interval;
          pollTimer = _ManualTimer(callback);
          return pollTimer;
        },
      );

      controller.onInit();
      await Future<void>.delayed(Duration.zero);

      expect(pollInterval, const Duration(seconds: 15));
      expect(pollTimer.isActive, isTrue);
      expect(controller.subtitleUrls, <String, String>{
        'already-ready.mp3': 'succeeded',
        'retry-success.mp3': 'processing',
        'retry-failure.mp3': 'processing',
      });

      pollTimer.fire();
      await pollCompleted.future;

      expect(fetched, <String>['retry-success.mp3', 'retry-failure.mp3']);
      expect(controller.subtitleUrls['already-ready.mp3'], 'succeeded');
      expect(controller.subtitleUrls['retry-success.mp3'], 'succeeded');
      expect(controller.subtitleUrls, isNot(contains('retry-failure.mp3')));
      expect(saved.single.enclosureUrl, 'retry-success.mp3');
      expect(deleted, <String>['retry-failure.mp3']);

      controller.onClose();

      expect(pollTimer.isActive, isFalse);
    });

    test('persists processing and succeeded states through SQLite', () async {
      sqfliteFfiInit();
      final db = await databaseFactoryFfi.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(singleInstance: false),
      );
      addTearDown(db.close);
      await subtitleTableCreator(db);

      final fetchStarted = Completer<void>();
      final fetchResult = Completer<SubtitleResult>();
      final segments = <Subtitle>[_segment(1.25, 2.5, 'hello')];
      final controller = SubtitleController(
        saveSubtitle: (subtitle) => SubtitleModel.insert(db, subtitle),
        fetchSubtitles: (url) async {
          expect(url, 'episode.mp3');
          fetchStarted.complete();
          return fetchResult.future;
        },
      );

      final addFuture = controller.add('episode.mp3');
      await fetchStarted.future;

      final processing = await SubtitleModel.get(db, 'episode.mp3');
      expect(processing.status, 'processing');
      expect(processing.language, isNull);
      expect(processing.subtitle, isEmpty);

      fetchResult.complete(
        _result(
          'succeeded',
          language: 'en',
          subtitles: segments,
        ),
      );
      await addFuture;

      expect(controller.subtitleUrls['episode.mp3'], 'succeeded');
      final succeeded = await SubtitleModel.get(db, 'episode.mp3');
      expect(succeeded.status, 'succeeded');
      expect(succeeded.enclosureUrl, 'episode.mp3');
      expect(succeeded.language, 'en');
      expect(jsonDecode(succeeded.subtitle!), <Object?>[
        <String, Object?>{'start': 1.25, 'end': 2.5, 'text': 'hello'},
      ]);
    });

    test('removes state and persisted data when subtitle generation fails',
        () async {
      final saved = <SubtitleModel>[];
      final deleted = <String>[];
      final controller = SubtitleController(
        saveSubtitle: (subtitle) async => saved.add(subtitle),
        deleteSubtitle: (url) async => deleted.add(url),
        fetchSubtitles: (_) async => _result('failed'),
      );

      await controller.add('failed.mp3');

      expect(saved.map((item) => item.status), <String?>['processing']);
      expect(controller.subtitleUrls, isNot(contains('failed.mp3')));
      expect(deleted, <String>['failed.mp3']);
    });

    test('remove updates memory and awaits the persistence delete', () async {
      final deleted = <String>[];
      final controller = SubtitleController(
        deleteSubtitle: (url) async => deleted.add(url),
      );
      controller.subtitleUrls['episode.mp3'] = 'succeeded';

      await controller.remove('episode.mp3');

      expect(controller.subtitleUrls, isEmpty);
      expect(deleted, <String>['episode.mp3']);
    });
  });
}

class _ManualTimer implements Timer {
  _ManualTimer(this._callback);

  final void Function(Timer timer) _callback;
  var _isActive = true;
  var _tick = 0;

  @override
  bool get isActive => _isActive;

  @override
  int get tick => _tick;

  void fire() {
    if (!_isActive) {
      throw StateError('Cannot fire a cancelled timer.');
    }
    _tick++;
    _callback(this);
  }

  @override
  void cancel() {
    _isActive = false;
  }
}
