@Tags(<String>['compatibility'])
library;

import 'dart:io';
import 'package:anycast/models/feed_episode.dart';
import 'package:anycast/models/helper.dart';
import 'package:anycast/models/history_episode.dart';
import 'package:anycast/models/player.dart';
import 'package:anycast/models/playlist.dart';
import 'package:anycast/models/playlist_episode.dart';
import 'package:anycast/models/settings.dart';
import 'package:anycast/models/subscription.dart';
import 'package:anycast/models/subtitle.dart';
import 'package:anycast/models/translation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'database_fixture.dart';

const _releasedFeedEpisodeUrl = 'https://released.example/feed-episode.mp3';
const _releasedPlaylistEpisodeUrl =
    'https://released.example/playlist-episode.mp3';
const _releasedHistoryEpisodeUrl =
    'https://released.example/history-episode.mp3';
const _currentFeedEpisodeUrl = 'https://current.example/feed-episode.mp3';
const _currentPlaylistEpisodeUrl =
    'https://current.example/playlist-episode.mp3';
const _currentHistoryEpisodeUrl = 'https://current.example/history-episode.mp3';
const _currentSubscriptionUrl = 'https://current.example/feed.xml';
const _currentSubtitleUrl = 'https://current.example/subtitle-episode.mp3';
const _currentTranslationUrl =
    'https://current.example/translation-episode.mp3';
const _requiredSeedIdentities = <String, List<int>>{
  'settings': <int>[1],
  'playlist': <int>[1],
  'player': <int>[1],
};
const _expectedFreshRequiredSeeds = <String, Object?>{
  'settings': <Map<String, Object?>>[
    <String, Object?>{
      'id': 1,
      'darkMode': 0,
      'speed': 1.0,
      'skipSilence': 0,
      'autoSleepTimer': '0,0,0',
      'maxCacheCount': 10,
      'autoRefreshInterval': 300,
      'maxFeedEpisodes': 100,
      'maxHistoryEpisodes': 100,
      'continuousPlaying': 1,
    },
  ],
  'playlist': <Map<String, Object?>>[
    <String, Object?>{'id': 1, 'title': 'Default', 'position': 1},
  ],
  'player': <Map<String, Object?>>[
    <String, Object?>{'id': 1, 'currentPlaylistId': null},
  ],
};

void main() {
  late Directory testDirectory;
  late Map<String, Object?> latestSchema;

  setUpAll(() async {
    sqfliteFfiInit();
    testDirectory = await Directory.systemTemp.createTemp(
      'anycast-database-compatibility-',
    );

    final freshPath = path.join(testDirectory.path, 'fresh-reference.db');
    final freshDb = await openAnycastDatabase(
      freshPath,
      factory: databaseFactoryFfi,
    );
    try {
      latestSchema = await readSchemaSnapshot(freshDb);
    } finally {
      await freshDb.close();
    }
  });

  tearDownAll(() async {
    await testDirectory.delete(recursive: true);
  });

  test('fresh creation builds the complete latest schema and required seeds',
      () async {
    final databasePath = path.join(testDirectory.path, 'fresh-under-test.db');
    final db = await openAnycastDatabase(
      databasePath,
      factory: databaseFactoryFfi,
    );
    try {
      expect(await db.getVersion(), databaseSchemaVersion);
      expect(
        (await readSchemaSnapshot(db)).keys,
        orderedEquals(<String>[
          'feedEpisode',
          'historyEpisode',
          'player',
          'playlist',
          'playlistEpisode',
          'settings',
          'subscription',
          'subtitle',
          'translation',
        ]),
      );
      expect(await readSchemaSnapshot(db), latestSchema);
      expect(await readRequiredSeedSnapshot(db), _expectedFreshRequiredSeeds);
    } finally {
      await db.close();
    }
  });

  for (final baseline in releasedDatabaseBaselines) {
    test(
      '${baseline.appVersions} (schema v${baseline.schemaVersion}) upgrades '
      'without losing released data',
      () async {
        final databasePath = path.join(
          testDirectory.path,
          'upgrade-from-v${baseline.schemaVersion}.db',
        );
        await installReleasedSchemaFixture(
          databaseFactoryFfi,
          databasePath,
          baseline,
        );

        final beforeUpgrade = await _readFixtureData(databasePath);
        var db = await openAnycastDatabase(
          databasePath,
          factory: databaseFactoryFfi,
        );

        expect(await db.getVersion(), databaseSchemaVersion);
        expect(await readSchemaSnapshot(db), latestSchema);
        expect(await _readRequiredSeedIdentities(db), _requiredSeedIdentities);
        await _expectReleasedDataPreserved(db, beforeUpgrade);
        await _expectReleasedRowsReadableThroughModels(
          db,
          expectedContinuousPlaying:
              baseline.expectedContinuousPlayingAfterUpgrade,
          expectedCurrentPlaylistId: 104,
        );

        final currentState = await _writeCurrentRowsThroughModels(db);
        await _expectCurrentRowsReadableThroughModels(db, currentState);

        await db.close();
        db = await openAnycastDatabase(
          databasePath,
          factory: databaseFactoryFfi,
        );
        try {
          expect(await db.getVersion(), databaseSchemaVersion);
          await _expectReleasedRowsReadableThroughModels(
            db,
            expectedContinuousPlaying: false,
            expectedCurrentPlaylistId: currentState.playlistId,
          );
          await _expectCurrentRowsReadableThroughModels(db, currentState);
          await _expectReleasedRowsStillPresent(
            db,
            beforeUpgrade,
            ignoredColumns: const <String, Set<String>>{
              'player': <String>{'currentPlaylistId'},
              'settings': <String>{'continuousPlaying'},
            },
          );
        } finally {
          await db.close();
        }
      },
    );
  }

  test('a failed migration rolls back all schema changes and data', () async {
    final databasePath = path.join(
      testDirectory.path,
      'failed-migration.db',
    );
    final schema3Baseline = releasedDatabaseBaselines.singleWhere(
      (baseline) => baseline.schemaVersion == 3,
    );
    await installReleasedSchemaFixture(
      databaseFactoryFfi,
      databasePath,
      schema3Baseline,
    );
    final beforeUpgrade = await _readFixtureData(databasePath);

    final failedOpen = databaseFactoryFfi.openDatabase(
      databasePath,
      options: OpenDatabaseOptions(
        version: databaseSchemaVersion,
        singleInstance: false,
        onUpgrade: (db, oldVersion, newVersion) => migrateDatabase(
          db,
          oldVersion,
          newVersion,
          migrationSteps: const <int, List<String>>{
            4: <String>[
              'ALTER TABLE settings ADD COLUMN continuousPlaying INTEGER '
                  'DEFAULT 1',
              'INSERT INTO table_that_does_not_exist (value) VALUES (1)',
            ],
          },
        ),
      ),
    );
    await expectLater(failedOpen, throwsA(isA<DatabaseException>()));

    final rolledBackDb = await databaseFactoryFfi.openDatabase(
      databasePath,
      options: OpenDatabaseOptions(singleInstance: false),
    );
    try {
      expect(await rolledBackDb.getVersion(), 3);
      final settingsColumns = await rolledBackDb.rawQuery(
        'PRAGMA table_info(settings)',
      );
      expect(
        settingsColumns.map((column) => column['name']),
        isNot(contains('continuousPlaying')),
      );
      expect(await readAllUserData(rolledBackDb), beforeUpgrade);
    } finally {
      await rolledBackDb.close();
    }

    final recoveredDb = await openAnycastDatabase(
      databasePath,
      factory: databaseFactoryFfi,
    );
    try {
      expect(await recoveredDb.getVersion(), databaseSchemaVersion);
      expect(await readSchemaSnapshot(recoveredDb), latestSchema);
      await _expectReleasedDataPreserved(recoveredDb, beforeUpgrade);
    } finally {
      await recoveredDb.close();
    }
  });
}

class _CurrentModelState {
  const _CurrentModelState({required this.playlistId});

  final int playlistId;
}

Future<void> _expectReleasedRowsReadableThroughModels(
  Database db, {
  required bool expectedContinuousPlaying,
  required int? expectedCurrentPlaylistId,
}) async {
  final feedEpisode = (await FeedEpisodeModel.listAll(db)).singleWhere(
    (episode) => episode.enclosureUrl == _releasedFeedEpisodeUrl,
  );
  expect(
    feedEpisode.toMap(),
    <String, dynamic>{
      'id': 101,
      'channelTitle': 'Released feed',
      'rssFeedUrl': 'https://released.example/feed.xml',
      'title': 'Released feed episode',
      'description': 'Feed data must survive upgrades',
      'duration': 3600000,
      'enclosureUrl': _releasedFeedEpisodeUrl,
      'pubDate': 1700000101,
      'imageUrl': 'https://released.example/feed.jpg',
    },
    reason: 'FeedEpisodeModel could not read the released row',
  );

  final historyEpisode = (await HistoryEpisodeModel.listAll(db)).singleWhere(
    (episode) => episode.enclosureUrl == _releasedHistoryEpisodeUrl,
  );
  expect(
    historyEpisode.toMap(),
    <String, dynamic>{
      'id': 106,
      'channelTitle': 'Released feed',
      'rssFeedUrl': 'https://released.example/feed.xml',
      'title': 'Released history episode',
      'description': 'History data must survive upgrades',
      'duration': 1800000,
      'enclosureUrl': _releasedHistoryEpisodeUrl,
      'pubDate': 1700000106,
      'imageUrl': 'https://released.example/history.jpg',
    },
    reason: 'HistoryEpisodeModel could not read the released row',
  );

  final playlist = (await PlaylistModel.listAll(db)).singleWhere(
    (playlist) => playlist.id == 104,
  );
  expect(
    playlist.toMap(),
    <String, dynamic>{
      'id': 104,
      'title': 'Released playlist',
      'position': 8,
    },
    reason: 'PlaylistModel could not read the released row',
  );

  final playlistEpisode = await PlaylistEpisodeModel.getByEnclosureUrl(
    db,
    _releasedPlaylistEpisodeUrl,
  );
  expect(playlistEpisode, isNotNull);
  expect(
    playlistEpisode!.toMap(),
    <String, dynamic>{
      'id': 102,
      'playlistId': 104,
      'position': 2.5,
      'playedDuration': 4567,
      'title': 'Released playlist episode',
      'description': 'Playback progress must survive upgrades',
      'duration': 4200000,
      'enclosureUrl': _releasedPlaylistEpisodeUrl,
      'pubDate': 1700000102,
      'imageUrl': 'https://released.example/playlist.jpg',
      'channelTitle': 'Released feed',
      'rssFeedUrl': 'https://released.example/feed.xml',
    },
    reason: 'PlaylistEpisodeModel could not read the released row',
  );

  expect(
    (await PlayerModel.get(db)).toMap(),
    <String, dynamic>{
      'id': 1,
      'currentPlaylistId': expectedCurrentPlaylistId,
    },
    reason: 'PlayerModel could not read the singleton row',
  );

  expect(
    (await SettingsModel.get(db)).toMap(),
    <String, dynamic>{
      'id': 1,
      'darkMode': true,
      'speed': 1.75,
      'skipSilence': true,
      'autoSleepTimer': '22,6,3',
      'maxCacheCount': 37,
      'countryCode': 'TW',
      'targetLanguage': 'ja',
      'autoRefreshInterval': 917,
      'maxFeedEpisodes': 321,
      'maxHistoryEpisodes': 654,
      'continuousPlaying': expectedContinuousPlaying,
    },
    reason: 'SettingsModel could not read the released singleton row',
  );

  final subscription = (await SubscriptionModel.listAll(db)).singleWhere(
    (subscription) =>
        subscription.rssFeedUrl == 'https://released.example/feed.xml',
  );
  expect(
    subscription.toMap(),
    <String, dynamic>{
      'id': 103,
      'rssFeedUrl': 'https://released.example/feed.xml',
      'title': 'Released subscription',
      'description': 'Subscription data must survive upgrades',
      'imageUrl': 'https://released.example/subscription.jpg',
      'link': 'https://released.example',
      'categories': 'technology,science',
      'author': 'Released author',
      'email': 'released@example.com',
      'lastUpdated': 1700000103,
    },
    reason: 'SubscriptionModel could not read the released row',
  );

  final subtitle = await SubtitleModel.get(
    db,
    _releasedPlaylistEpisodeUrl,
  );
  expect(
    subtitle.toMap(),
    <String, dynamic>{
      'id': 105,
      'enclosureUrl': _releasedPlaylistEpisodeUrl,
      'status': 'completed',
      'subtitle': '[{"start":0,"end":1000,"text":"released subtitle"}]',
      'language': 'en',
      'summary': 'Released summary',
    },
    reason: 'SubtitleModel could not read the released row',
  );

  final translation = await TranslationModel.get(
    db,
    _releasedPlaylistEpisodeUrl,
    'zh',
  );
  expect(translation, isNotNull);
  expect(
    translation!.toMap(),
    <String, dynamic>{
      'id': 107,
      'enclosureUrl': _releasedPlaylistEpisodeUrl,
      'status': 'completed',
      'translation': '[{"start":0,"end":1000,"text":"released translation"}]',
      'language': 'zh',
    },
    reason: 'TranslationModel could not read the released row',
  );
}

Future<_CurrentModelState> _writeCurrentRowsThroughModels(Database db) async {
  final feedEpisode = FeedEpisodeModel.fromMap(<String, dynamic>{
    'channelTitle': 'Current feed',
    'rssFeedUrl': _currentSubscriptionUrl,
    'title': 'Current feed episode',
    'description': 'Created with the current FeedEpisodeModel',
    'duration': 3000000,
    'enclosureUrl': _currentFeedEpisodeUrl,
    'pubDate': 1800000101,
    'imageUrl': 'https://current.example/feed.jpg',
  });
  await feedEpisode.save(db);
  expect(feedEpisode.id, isNotNull);
  feedEpisode.description = 'Updated with the current FeedEpisodeModel';
  await feedEpisode.save(db);

  final historyEpisode = HistoryEpisodeModel.fromMap(<String, dynamic>{
    'channelTitle': 'Current feed',
    'rssFeedUrl': _currentSubscriptionUrl,
    'title': 'Current history episode',
    'description': 'Created with the current HistoryEpisodeModel',
    'duration': 2000000,
    'enclosureUrl': _currentHistoryEpisodeUrl,
    'pubDate': 1800000102,
    'imageUrl': 'https://current.example/history.jpg',
  });
  await HistoryEpisodeModel.insert(db, historyEpisode);
  final storedHistoryEpisode =
      (await HistoryEpisodeModel.listAll(db)).singleWhere(
    (episode) => episode.enclosureUrl == _currentHistoryEpisodeUrl,
  );
  storedHistoryEpisode.description =
      'Updated with the current HistoryEpisodeModel';
  await HistoryEpisodeModel.insert(db, storedHistoryEpisode);

  // PlaylistModel intentionally has no save method. Exercise its persistence
  // mapping with the same real DatabaseExecutor used by the application models.
  final playlist = PlaylistModel.fromMap(<String, dynamic>{
    'title': 'Current playlist',
    'position': 9,
  });
  playlist.id = await db.insert('playlist', playlist.toMap());
  playlist.title = 'Current playlist updated';
  expect(
    await db.update(
      'playlist',
      playlist.toMap(),
      where: 'id = ?',
      whereArgs: <Object?>[playlist.id],
    ),
    1,
  );

  final playlistEpisode = PlaylistEpisodeModel.empty()
    ..playlistId = playlist.id
    ..position = 3.0
    ..playedDuration = 1000
    ..title = 'Current playlist episode'
    ..description = 'Created with the current PlaylistEpisodeModel'
    ..duration = 2500000
    ..enclosureUrl = _currentPlaylistEpisodeUrl
    ..pubDate = 1800000103
    ..imageUrl = 'https://current.example/playlist.jpg'
    ..channelTitle = 'Current feed'
    ..rssFeedUrl = _currentSubscriptionUrl;
  await playlistEpisode.save(db);
  expect(playlistEpisode.id, isNotNull);
  playlistEpisode.playedDuration = 9876;
  await playlistEpisode.save(db);

  await PlayerModel.update(
    db,
    PlayerModel.empty()..currentPlaylistId = playlist.id,
  );

  expect(await SettingsModel.setContinuousPlaying(db, false), 1);

  final subscription = SubscriptionModel.empty()
    ..rssFeedUrl = _currentSubscriptionUrl
    ..title = 'Current subscription'
    ..description = 'Created with the current SubscriptionModel'
    ..imageUrl = 'https://current.example/subscription.jpg'
    ..link = 'https://current.example'
    ..categories = 'technology,testing'
    ..author = 'Current author'
    ..email = 'current@example.com'
    ..lastUpdated = 1800000104;
  await subscription.save(db);
  expect(subscription.id, isNotNull);
  subscription.description = 'Updated with the current SubscriptionModel';
  await subscription.save(db);

  final subtitle = SubtitleModel.empty()
    ..enclosureUrl = _currentSubtitleUrl
    ..status = 'processing'
    ..subtitle = '[{"start":1,"end":2,"text":"current subtitle"}]'
    ..language = 'en'
    ..summary = 'Current summary';
  await SubtitleModel.insert(db, subtitle);
  final storedSubtitle = await SubtitleModel.get(db, _currentSubtitleUrl)
    ..status = 'completed'
    ..summary = 'Current summary updated';
  await SubtitleModel.insert(db, storedSubtitle);

  final translation = TranslationModel.empty()
    ..enclosureUrl = _currentTranslationUrl
    ..status = 'processing'
    ..translation = '[{"start":1,"end":2,"text":"current translation"}]'
    ..language = 'ja';
  await TranslationModel.insert(db, translation);
  final storedTranslation = await TranslationModel.get(
    db,
    _currentTranslationUrl,
    'ja',
  );
  expect(storedTranslation, isNotNull);
  storedTranslation!.status = 'completed';
  await TranslationModel.insert(db, storedTranslation);

  return _CurrentModelState(playlistId: playlist.id!);
}

Future<void> _expectCurrentRowsReadableThroughModels(
  Database db,
  _CurrentModelState state,
) async {
  final feedEpisode = (await FeedEpisodeModel.listAll(db)).singleWhere(
    (episode) => episode.enclosureUrl == _currentFeedEpisodeUrl,
  );
  expect(feedEpisode.description, 'Updated with the current FeedEpisodeModel');

  final historyEpisode = (await HistoryEpisodeModel.listAll(db)).singleWhere(
    (episode) => episode.enclosureUrl == _currentHistoryEpisodeUrl,
  );
  expect(
    historyEpisode.description,
    'Updated with the current HistoryEpisodeModel',
  );

  final playlist = (await PlaylistModel.listAll(db)).singleWhere(
    (playlist) => playlist.id == state.playlistId,
  );
  expect(playlist.title, 'Current playlist updated');
  expect(playlist.position, 9);

  final playlistEpisode = await PlaylistEpisodeModel.getByEnclosureUrl(
    db,
    _currentPlaylistEpisodeUrl,
  );
  expect(playlistEpisode, isNotNull);
  expect(playlistEpisode!.playlistId, state.playlistId);
  expect(playlistEpisode.playedDuration, 9876);

  expect(
    (await PlayerModel.get(db)).currentPlaylistId,
    state.playlistId,
  );
  expect((await SettingsModel.get(db)).continuousPlaying, isFalse);

  final subscription = (await SubscriptionModel.listAll(db)).singleWhere(
    (subscription) => subscription.rssFeedUrl == _currentSubscriptionUrl,
  );
  expect(
    subscription.description,
    'Updated with the current SubscriptionModel',
  );

  final subtitle = await SubtitleModel.get(db, _currentSubtitleUrl);
  expect(subtitle.status, 'completed');
  expect(subtitle.summary, 'Current summary updated');

  final translation = await TranslationModel.get(
    db,
    _currentTranslationUrl,
    'ja',
  );
  expect(translation, isNotNull);
  expect(translation!.status, 'completed');
}

Future<Map<String, List<Map<String, Object?>>>> _readFixtureData(
  String databasePath,
) async {
  final db = await databaseFactoryFfi.openDatabase(
    databasePath,
    options: OpenDatabaseOptions(singleInstance: false),
  );
  try {
    return await readAllUserData(db);
  } finally {
    await db.close();
  }
}

Future<Map<String, List<int>>> _readRequiredSeedIdentities(Database db) async {
  final result = <String, List<int>>{};
  for (final tableName in _requiredSeedIdentities.keys) {
    final rows = await db.rawQuery(
      'SELECT id FROM "$tableName" WHERE id = 1',
    );
    result[tableName] = rows.map((row) => row['id']! as int).toList();
  }
  return result;
}

Future<void> _expectReleasedDataPreserved(
  Database db,
  Map<String, List<Map<String, Object?>>> beforeUpgrade,
) async {
  for (final entry in beforeUpgrade.entries) {
    final releasedColumns = entry.value.first.keys.toList();
    final columnList = releasedColumns
        .map((column) => '"${column.replaceAll('"', '""')}"')
        .join(', ');
    final rows = await db.rawQuery(
      'SELECT $columnList FROM "${entry.key}" ORDER BY id',
    );
    expect(rows, entry.value,
        reason: '${entry.key} rows changed during upgrade');
  }
}

Future<void> _expectReleasedRowsStillPresent(
  Database db,
  Map<String, List<Map<String, Object?>>> beforeUpgrade, {
  Map<String, Set<String>> ignoredColumns = const <String, Set<String>>{},
}) async {
  for (final entry in beforeUpgrade.entries) {
    final ignored = ignoredColumns[entry.key] ?? const <String>{};
    final releasedColumns = entry.value.first.keys
        .where((column) => !ignored.contains(column))
        .toList();
    final columnList = releasedColumns
        .map((column) => '"${column.replaceAll('"', '""')}"')
        .join(', ');

    for (final expectedRow in entry.value) {
      final rows = await db.rawQuery(
        'SELECT $columnList FROM "${entry.key}" WHERE id = ?',
        <Object?>[expectedRow['id']],
      );
      expect(
        rows,
        <Map<String, Object?>>[
          <String, Object?>{
            for (final column in releasedColumns) column: expectedRow[column],
          },
        ],
        reason: '${entry.key} id ${expectedRow['id']} changed after reopen',
      );
    }
  }
}
