import 'dart:async';
import 'dart:convert';

import 'package:anycast/api/subtitles.dart';
import 'package:anycast/models/translation.dart';
import 'package:anycast/states/translation.dart';
import 'package:flutter_test/flutter_test.dart';

Subtitle _segment(double start, double end, String text) {
  return Subtitle()
    ..start = start
    ..end = end
    ..text = text;
}

void main() {
  group('TranslationController', () {
    test('does nothing when translation is disabled', () async {
      var detectedLanguageCalls = 0;
      final controller = TranslationController(
        targetLanguage: () => '',
        detectedLanguage: (_) async {
          detectedLanguageCalls++;
          return 'en';
        },
      );

      await controller.loadTranslation('episode.mp3');

      expect(detectedLanguageCalls, 0);
      expect(controller.translationUrls, isEmpty);
    });

    test('does not translate missing or already-target-language subtitles',
        () async {
      var fetchCalls = 0;
      Future<List<Subtitle>?> fetch(String _, String __) async {
        fetchCalls++;
        return <Subtitle>[];
      }

      final missingLanguageController = TranslationController(
        targetLanguage: () => 'zh',
        detectedLanguage: (_) async => null,
        fetchTranslation: fetch,
      );
      final matchingLanguageController = TranslationController(
        targetLanguage: () => 'zh',
        detectedLanguage: (_) async => 'zh',
        fetchTranslation: fetch,
      );

      await missingLanguageController.loadTranslation('missing.mp3');
      await matchingLanguageController.loadTranslation('already-zh.mp3');

      expect(fetchCalls, 0);
      expect(missingLanguageController.translationUrls, isEmpty);
      expect(matchingLanguageController.translationUrls, isEmpty);
    });

    test('uses a cached translation without making a network request',
        () async {
      var fetchCalls = 0;
      final cached = TranslationModel.empty()
        ..enclosureUrl = 'cached.mp3'
        ..language = 'zh'
        ..status = 'succeeded';
      final controller = TranslationController(
        targetLanguage: () => 'zh',
        detectedLanguage: (_) async => 'en',
        loadCachedTranslation: (url, language) async {
          expect(url, 'cached.mp3');
          expect(language, 'zh');
          return cached;
        },
        fetchTranslation: (_, __) async {
          fetchCalls++;
          return null;
        },
      );

      await controller.loadTranslation('cached.mp3');

      expect(controller.translationUrls['cached.mp3'], 'succeeded');
      expect(fetchCalls, 0);
    });

    test('persists a fetched translation before marking it succeeded',
        () async {
      final saved = <TranslationModel>[];
      String? stateDuringSave;
      late final TranslationController controller;
      controller = TranslationController(
        targetLanguage: () => 'zh',
        detectedLanguage: (_) async => 'en',
        loadCachedTranslation: (_, __) async => null,
        fetchTranslation: (url, language) async {
          expect(url, 'episode.mp3');
          expect(language, 'zh');
          return <Subtitle>[_segment(3.0, 4.5, '你好')];
        },
        saveTranslation: (translation) async {
          stateDuringSave = controller.translationUrls['episode.mp3'];
          saved.add(translation);
        },
      );

      await controller.loadTranslation('episode.mp3');

      expect(stateDuringSave, 'processing');
      expect(controller.translationUrls['episode.mp3'], 'succeeded');
      expect(saved, hasLength(1));
      expect(saved.single.enclosureUrl, 'episode.mp3');
      expect(saved.single.language, 'zh');
      expect(saved.single.status, 'succeeded');
      expect(jsonDecode(saved.single.translation!), <Object?>[
        <String, Object?>{'start': 3.0, 'end': 4.5, 'text': '你好'},
      ]);
    });

    test('keeps a null network result processing so polling can retry it',
        () async {
      var saveCalls = 0;
      final controller = TranslationController(
        targetLanguage: () => 'zh',
        detectedLanguage: (_) async => 'en',
        loadCachedTranslation: (_, __) async => null,
        fetchTranslation: (_, __) async => null,
        saveTranslation: (_) async => saveCalls++,
      );

      await controller.loadTranslation('retry.mp3');

      expect(controller.translationUrls['retry.mp3'], 'processing');
      expect(saveCalls, 0);
    });

    test('deduplicates an in-flight request and retries after it completes',
        () async {
      final firstResult = Completer<List<Subtitle>?>();
      final firstFetchStarted = Completer<void>();
      var fetchCalls = 0;
      final controller = TranslationController(
        targetLanguage: () => 'zh',
        detectedLanguage: (_) async => 'en',
        loadCachedTranslation: (_, __) async => null,
        fetchTranslation: (_, __) {
          fetchCalls++;
          if (fetchCalls == 1) {
            firstFetchStarted.complete();
            return firstResult.future;
          }
          return Future<List<Subtitle>?>.value(null);
        },
      );

      final firstLoad = controller.loadTranslation('slow.mp3');
      await firstFetchStarted.future;

      await controller.loadTranslation('slow.mp3');
      expect(fetchCalls, 1);

      firstResult.complete(null);
      await firstLoad;

      await controller.loadTranslation('slow.mp3');
      expect(fetchCalls, 2);
      expect(controller.translationUrls['slow.mp3'], 'processing');
    });

    test('refresh translates only succeeded subtitles not already completed',
        () async {
      final fetched = <String>[];
      final controller = TranslationController(
        targetLanguage: () => 'zh',
        subtitleStatuses: () => <String, String>{
          'ready.mp3': 'succeeded',
          'still-processing.mp3': 'processing',
          'already-translated.mp3': 'succeeded',
        },
        detectedLanguage: (_) async => 'en',
        loadCachedTranslation: (_, __) async => null,
        fetchTranslation: (url, _) async {
          fetched.add(url);
          return <Subtitle>[_segment(0, 1, 'translated')];
        },
        saveTranslation: (_) async {},
      );
      controller.translationUrls['already-translated.mp3'] = 'succeeded';

      await controller.refreshSucceededSubtitles();

      expect(fetched, <String>['ready.mp3']);
      expect(controller.translationUrls['ready.mp3'], 'succeeded');
      expect(
        controller.translationUrls['already-translated.mp3'],
        'succeeded',
      );
      expect(
        controller.translationUrls,
        isNot(contains('still-processing.mp3')),
      );
    });

    test('refresh continues with later URLs when one translation fails',
        () async {
      final fetched = <String>[];
      final saved = <String>[];
      final controller = TranslationController(
        targetLanguage: () => 'zh',
        subtitleStatuses: () => <String, String>{
          'fails.mp3': 'succeeded',
          'succeeds.mp3': 'succeeded',
        },
        detectedLanguage: (_) async => 'en',
        loadCachedTranslation: (_, __) async => null,
        fetchTranslation: (url, _) async {
          fetched.add(url);
          if (url == 'fails.mp3') {
            throw StateError('translation failed');
          }
          return <Subtitle>[_segment(0, 1, 'translated')];
        },
        saveTranslation: (translation) async {
          saved.add(translation.enclosureUrl!);
        },
      );

      await expectLater(
        controller.refreshSucceededSubtitles(),
        throwsA(isA<StateError>()),
      );

      expect(fetched, containsAll(<String>['fails.mp3', 'succeeds.mp3']));
      expect(saved, <String>['succeeds.mp3']);
      expect(controller.translationUrls['succeeds.mp3'], 'succeeded');
    });

    test('periodic lifecycle refreshes an eligible subtitle and cancels timer',
        () async {
      final saved = Completer<void>();
      final fetched = <String>[];
      late final RecordingTranslationTimer timer;
      final controller = TranslationController(
        targetLanguage: () => 'zh',
        subtitleStatuses: () => <String, String>{
          'ready.mp3': 'succeeded',
        },
        detectedLanguage: (_) async => 'en',
        loadCachedTranslation: (_, __) async => null,
        fetchTranslation: (url, _) async {
          fetched.add(url);
          return <Subtitle>[_segment(0, 1, 'translated')];
        },
        saveTranslation: (_) async => saved.complete(),
        periodicTimer: (duration, callback) {
          expect(duration, const Duration(seconds: 10));
          timer = RecordingTranslationTimer(callback);
          return timer;
        },
      );

      controller.onInit();
      timer.fire();
      await saved.future;
      await Future<void>.delayed(Duration.zero);

      expect(fetched, <String>['ready.mp3']);
      expect(controller.translationUrls['ready.mp3'], 'succeeded');

      controller.onClose();
      expect(timer.isActive, isFalse);
    });

    test('remove updates memory and awaits persisted deletion', () async {
      final deleted = <String>[];
      final controller = TranslationController(
        deleteTranslation: (url) async => deleted.add(url),
      );
      controller.translationUrls['episode.mp3'] = 'succeeded';

      await controller.remove('episode.mp3');

      expect(controller.translationUrls, isEmpty);
      expect(deleted, <String>['episode.mp3']);
    });
  });
}

class RecordingTranslationTimer implements Timer {
  RecordingTranslationTimer(this._callback);

  final void Function(Timer timer) _callback;
  var _isActive = true;
  var _tick = 0;

  @override
  bool get isActive => _isActive;

  @override
  int get tick => _tick;

  void fire() {
    if (!_isActive) {
      return;
    }
    _tick += 1;
    _callback(this);
  }

  @override
  void cancel() {
    _isActive = false;
  }
}
