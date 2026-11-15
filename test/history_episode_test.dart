import 'dart:io';

import 'package:anycast/models/helper.dart';
import 'package:anycast/models/history_episode.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('history upsert ignores caller ids and sorts by lastPlayedAt', () async {
    final directory = await Directory.systemTemp.createTemp('history-upsert-');
    final databasePath = path.join(directory.path, 'anycast.db');
    final db = await openAnycastDatabase(
      databasePath,
      factory: databaseFactoryFfi,
    );
    try {
      await HistoryEpisodeModel.insert(
        db,
        HistoryEpisodeModel.fromMap(<String, dynamic>{
          'id': 42,
          'title': 'older',
          'enclosureUrl': 'https://example.test/older.mp3',
        }),
      );
      final stored = await db.query('historyEpisode');
      expect(stored, hasLength(1));
      expect(stored.single['id'], isNot(42));
      expect(stored.single['lastPlayedAt'], isNotNull);

      await HistoryEpisodeModel.insert(
        db,
        HistoryEpisodeModel.fromMap(<String, dynamic>{
          'id': stored.single['id'],
          'title': 'other',
          'enclosureUrl': 'https://example.test/other.mp3',
        }),
      );
      final both = await db.query('historyEpisode');
      expect(both, hasLength(2));
      expect(
        both.singleWhere(
          (row) => row['enclosureUrl'] == 'https://example.test/older.mp3',
        )['title'],
        'older',
      );

      await Future<void>.delayed(const Duration(milliseconds: 20));
      await HistoryEpisodeModel.insert(
        db,
        HistoryEpisodeModel.fromMap(<String, dynamic>{
          'id': 42,
          'title': 'older-again',
          'enclosureUrl': 'https://example.test/older.mp3',
        }),
      );
      final listed = await HistoryEpisodeModel.listAll(db);
      expect(listed, hasLength(2));
      expect(listed.first.enclosureUrl, 'https://example.test/older.mp3');
      expect(listed.first.title, 'older-again');
      expect(listed.first.id, stored.single['id']);
    } finally {
      await db.close();
      await directory.delete(recursive: true);
    }
  });

  test('a v4 history table gains a NULL lastPlayedAt and keeps its rows',
      () async {
    final directory = await Directory.systemTemp.createTemp('history-v4-');
    final databasePath = path.join(directory.path, 'anycast.db');
    final created = await databaseFactoryFfi.openDatabase(
      databasePath,
      options: OpenDatabaseOptions(
        version: 4,
        singleInstance: false,
        onCreate: (db, _) async {
          await db.execute('''
            CREATE TABLE historyEpisode (
              id INTEGER PRIMARY KEY,
              title TEXT,
              description TEXT,
              duration INTEGER,
              enclosureUrl TEXT UNIQUE,
              pubDate INTEGER,
              imageUrl TEXT,
              channelTitle TEXT,
              rssFeedUrl TEXT
            )
          ''');
          await db.insert('historyEpisode', <String, Object?>{
            'id': 2,
            'title': 'older',
            'enclosureUrl': 'https://example.test/older.mp3',
          });
          await db.insert('historyEpisode', <String, Object?>{
            'id': 9,
            'title': 'newer',
            'description': 'keep me',
            'enclosureUrl': 'https://example.test/newer.mp3',
          });
        },
      ),
    );
    await created.close();

    final upgraded = await openAnycastDatabase(
      databasePath,
      factory: databaseFactoryFfi,
    );
    try {
      expect(await upgraded.getVersion(), databaseSchemaVersion);
      final listed = await HistoryEpisodeModel.listAll(upgraded);
      expect(
        listed.map((episode) => episode.enclosureUrl).toList(),
        <String?>[
          'https://example.test/newer.mp3',
          'https://example.test/older.mp3',
        ],
      );
      expect(
        listed.map((episode) => episode.lastPlayedAt).toList(),
        <int?>[null, null],
      );
      expect(listed.first.id, 9);
      expect(listed.first.description, 'keep me');

      final freshDirectory = await Directory.systemTemp.createTemp('history-fresh-');
      final fresh = await openAnycastDatabase(
        path.join(freshDirectory.path, 'anycast.db'),
        factory: databaseFactoryFfi,
      );
      try {
        final upgradedColumns = await upgraded.rawQuery(
          'PRAGMA table_info(historyEpisode)',
        );
        final freshColumns = await fresh.rawQuery(
          'PRAGMA table_info(historyEpisode)',
        );
        expect(
          upgradedColumns.map((column) => column['name']).toList(),
          freshColumns.map((column) => column['name']).toList(),
        );
      } finally {
        await fresh.close();
        await freshDirectory.delete(recursive: true);
      }
    } finally {
      await upgraded.close();
      await directory.delete(recursive: true);
    }
  });
  group('upgraded v4 file', () {
    Future<String> writeV4(Directory directory) async {
      final databasePath = path.join(directory.path, 'anycast.db');
      final created = await databaseFactoryFfi.openDatabase(
        databasePath,
        options: OpenDatabaseOptions(
          version: 4,
          singleInstance: false,
          onCreate: (db, _) async {
            await db.execute('''
              CREATE TABLE historyEpisode (
                id INTEGER PRIMARY KEY,
                title TEXT,
                description TEXT,
                duration INTEGER,
                enclosureUrl TEXT UNIQUE,
                pubDate INTEGER,
                imageUrl TEXT,
                channelTitle TEXT,
                rssFeedUrl TEXT
              )
            ''');
            await db.insert('historyEpisode', <String, Object?>{
              'id': 2,
              'title': 'older',
              'enclosureUrl': 'https://example.test/older.mp3',
            });
            await db.insert('historyEpisode', <String, Object?>{
              'id': 9,
              'title': 'newer',
              'enclosureUrl': 'https://example.test/newer.mp3',
            });
          },
        ),
      );
      await created.close();
      return databasePath;
    }

    test('a newly played row sorts above NULL rows and reopen is idempotent',
        () async {
      final directory = await Directory.systemTemp.createTemp('history-null-');
      final databasePath = await writeV4(directory);
      var db = await openAnycastDatabase(databasePath, factory: databaseFactoryFfi);
      try {
        await HistoryEpisodeModel.insert(
          db,
          HistoryEpisodeModel.fromMap(<String, dynamic>{
            'title': 'fresh',
            'enclosureUrl': 'https://example.test/fresh.mp3',
          }),
        );
        var listed = await HistoryEpisodeModel.listAll(db);
        expect(
          listed.map((episode) => episode.enclosureUrl).toList(),
          <String?>[
            'https://example.test/fresh.mp3',
            'https://example.test/newer.mp3',
            'https://example.test/older.mp3',
          ],
        );
        expect(listed.first.lastPlayedAt, isNotNull);
        expect(listed.skip(1).every((e) => e.lastPlayedAt == null), isTrue);

        await db.close();
        db = await openAnycastDatabase(databasePath, factory: databaseFactoryFfi);
        expect(await db.getVersion(), databaseSchemaVersion);
        listed = await HistoryEpisodeModel.listAll(db);
        expect(listed, hasLength(3));
        expect(listed.skip(1).every((e) => e.lastPlayedAt == null), isTrue);
      } finally {
        await db.close();
        await directory.delete(recursive: true);
      }
    });

    test('a failing migration leaves the v4 file at version 4', () async {
      final directory = await Directory.systemTemp.createTemp('history-fail-');
      final databasePath = await writeV4(directory);
      final prepared = await databaseFactoryFfi.openDatabase(
        databasePath,
        options: OpenDatabaseOptions(singleInstance: false),
      );
      // Make the 4 -> 5 ALTER fail: the column already exists.
      await prepared.execute(
          'ALTER TABLE historyEpisode ADD COLUMN lastPlayedAt INTEGER');
      await prepared.close();

      await expectLater(
        openAnycastDatabase(databasePath, factory: databaseFactoryFfi),
        throwsA(anything),
      );

      final check = await databaseFactoryFfi.openDatabase(
        databasePath,
        options: OpenDatabaseOptions(singleInstance: false),
      );
      try {
        expect(await check.getVersion(), 4);
        final rows = await check.query('historyEpisode', orderBy: 'id');
        expect(rows.map((row) => row['title']).toList(), <Object?>['older', 'newer']);
      } finally {
        await check.close();
        await directory.delete(recursive: true);
      }
    });
  });
}
