import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class ReleasedDatabaseBaseline {
  const ReleasedDatabaseBaseline({
    required this.appVersions,
    required this.schemaVersion,
    required this.fixtureFileName,
    required this.expectedContinuousPlayingAfterUpgrade,
  });

  final String appVersions;
  final int schemaVersion;
  final String fixtureFileName;
  final bool expectedContinuousPlayingAfterUpgrade;
}

// Keep one independent fixture for every released schema users can still carry.
// Build 26 introduced schema 4; every later published build through the current
// 1.2.1 release still opens that same schema version.
const releasedDatabaseBaselines = <ReleasedDatabaseBaseline>[
  ReleasedDatabaseBaseline(
    appVersions: 'early 1.0.0 releases before build 26',
    schemaVersion: 3,
    fixtureFileName: 'schema_v3.sql',
    expectedContinuousPlayingAfterUpgrade: true,
  ),
  ReleasedDatabaseBaseline(
    appVersions: '1.0.0+26 through 1.2.1+38',
    schemaVersion: 4,
    fixtureFileName: 'schema_v4.sql',
    expectedContinuousPlayingAfterUpgrade: false,
  ),
];

Future<void> installReleasedSchemaFixture(
  DatabaseFactory factory,
  String databasePath,
  ReleasedDatabaseBaseline baseline,
) async {
  if (!releasedDatabaseBaselines.contains(baseline)) {
    throw ArgumentError.value(
      baseline.fixtureFileName,
      'baseline',
      'The baseline is not in the released-schema manifest',
    );
  }

  final fixturePath = path.join(
    Directory.current.path,
    'test',
    'compatibility',
    'fixtures',
    baseline.fixtureFileName,
  );
  final fixtureSql = await File(fixturePath).readAsString();
  final statements = fixtureSql
      .split(';')
      .map((statement) => statement.trim())
      .where((statement) => statement.isNotEmpty);

  final db = await factory.openDatabase(
    databasePath,
    options: OpenDatabaseOptions(singleInstance: false),
  );
  try {
    for (final statement in statements) {
      await db.execute(statement);
    }
  } finally {
    await db.close();
  }
}

Future<Map<String, Object?>> readSchemaSnapshot(Database db) async {
  final tableRows = await db.rawQuery('''
    SELECT name
    FROM sqlite_master
    WHERE type = 'table'
      AND name NOT LIKE 'sqlite_%'
    ORDER BY name
  ''');
  final result = <String, Object?>{};

  for (final tableRow in tableRows) {
    final tableName = tableRow['name']! as String;
    final quotedTableName = _quoteIdentifier(tableName);
    final rawColumns = await db.rawQuery('PRAGMA table_info($quotedTableName)');
    final columns = rawColumns
        .map(
          (column) => <String, Object?>{
            'name': column['name'],
            'type': column['type'],
            'notnull': column['notnull'],
            'default': column['dflt_value'],
            'primaryKey': column['pk'],
          },
        )
        .toList();

    final rawIndexes = await db.rawQuery('PRAGMA index_list($quotedTableName)');
    final indexes = <Map<String, Object?>>[];
    for (final rawIndex in rawIndexes) {
      final indexName = rawIndex['name']! as String;
      final rawIndexColumns = await db.rawQuery(
        'PRAGMA index_info(${_quoteIdentifier(indexName)})',
      );
      indexes.add(<String, Object?>{
        'unique': rawIndex['unique'],
        'partial': rawIndex['partial'],
        'columns': rawIndexColumns.map((column) => column['name']).toList(),
      });
    }
    indexes.sort(
      (left, right) =>
          left['columns'].toString().compareTo(right['columns'].toString()),
    );

    result[tableName] = <String, Object?>{
      'columns': columns,
      'indexes': indexes,
    };
  }

  return result;
}

Future<Map<String, List<Map<String, Object?>>>> readAllUserData(
  Database db,
) async {
  final tableRows = await db.rawQuery('''
    SELECT name
    FROM sqlite_master
    WHERE type = 'table'
      AND name NOT LIKE 'sqlite_%'
    ORDER BY name
  ''');
  final result = <String, List<Map<String, Object?>>>{};

  for (final tableRow in tableRows) {
    final tableName = tableRow['name']! as String;
    final quotedTableName = _quoteIdentifier(tableName);
    result[tableName] = await db.rawQuery(
      'SELECT * FROM $quotedTableName ORDER BY id',
    );
  }

  return result;
}

Future<Map<String, Object?>> readRequiredSeedSnapshot(Database db) async {
  final settings = await db.rawQuery('''
    SELECT
      id,
      darkMode,
      speed,
      skipSilence,
      autoSleepTimer,
      maxCacheCount,
      autoRefreshInterval,
      maxFeedEpisodes,
      maxHistoryEpisodes,
      continuousPlaying
    FROM settings
    WHERE id = 1
  ''');
  final playlists = await db.rawQuery('''
    SELECT id, title, position
    FROM playlist
    WHERE id = 1
  ''');
  final players = await db.rawQuery('''
    SELECT id, currentPlaylistId
    FROM player
    WHERE id = 1
  ''');

  return <String, Object?>{
    'settings': settings,
    'playlist': playlists,
    'player': players,
  };
}

String _quoteIdentifier(String identifier) {
  return '"${identifier.replaceAll('"', '""')}"';
}
