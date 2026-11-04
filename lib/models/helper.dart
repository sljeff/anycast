import 'package:anycast/models/history_episode.dart';
import 'package:anycast/models/settings.dart';
import 'package:anycast/models/subtitle.dart';
import 'package:anycast/models/translation.dart';

import 'feed_episode.dart';
import 'player.dart';
import 'playlist.dart';
import 'playlist_episode.dart';
import 'subscription.dart';
import 'table_creator.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

const int databaseSchemaVersion = 5;

List<TableCreator> tableCreators = [
  feedEpisodeTableCreator,
  playlistEpisodeTableCreator,
  subscriptionTableCreator,
  playlistTableCreator,
  playerTableCreator,
  settingsTableCreator,
  subtitleTableCreator,
  historyEpisodeTableCreator,
  translationCreateTable,
];

const Map<int, List<String>> migrations = {
  // 3 -> 4
  4: <String>[
    'ALTER TABLE settings ADD COLUMN continuousPlaying INTEGER DEFAULT 1',
  ],
  // 4 -> 5. lastPlayedAt is the history sort key. Copying id gives rows
  // that predate the column a monotonic fallback, so the old id-DESC order
  // is preserved until something is played again.
  5: <String>[
    'ALTER TABLE historyEpisode ADD COLUMN lastPlayedAt INTEGER',
    'UPDATE historyEpisode SET lastPlayedAt = id WHERE lastPlayedAt IS NULL',
  ],
};

Future<void> createLatestDatabaseSchema(DatabaseExecutor db) async {
  for (final tableCreator in tableCreators) {
    await tableCreator(db);
  }
}

Future<void> migrateDatabase(
  DatabaseExecutor db,
  int oldVersion,
  int newVersion, {
  Map<int, List<String>> migrationSteps = migrations,
}) async {
  final targetVersions = migrationSteps.keys.toList()..sort();

  for (final targetVersion in targetVersions) {
    if (oldVersion < targetVersion && targetVersion <= newVersion) {
      for (final sql in migrationSteps[targetVersion]!) {
        await db.execute(sql);
      }
    }
  }
}

Future<Database> openAnycastDatabase(
  String path, {
  DatabaseFactory? factory,
}) {
  final options = OpenDatabaseOptions(
    version: databaseSchemaVersion,
    onCreate: (db, _) => createLatestDatabaseSchema(db),
    onUpgrade: migrateDatabase,
  );
  return (factory ?? databaseFactory).openDatabase(path, options: options);
}

class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper.internal();
  factory DatabaseHelper() => _instance;
  static Database? _db;

  DatabaseHelper.internal();

  Future<Database> get db async {
    if (_db != null) return _db!;
    _db = await initDb();
    return _db!;
  }

  Future<Database> initDb() async {
    String databasesPath = await getDatabasesPath();
    String path = join(databasesPath, 'anycast.db');

    // delete existing if any
    // await deleteDatabase(path);

    // create new
    return openAnycastDatabase(path);
  }

  Future<void> close() async {
    final dbClient = _db;
    _db = null;
    await dbClient?.close();
  }
}
