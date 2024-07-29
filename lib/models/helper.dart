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

var migrations = {
  // 3 -> 4
  4: [
    'ALTER TABLE settings ADD COLUMN continuousPlaying INTEGER DEFAULT 1',
  ],
};

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
    Database db = await openDatabase(
      path,
      version: 4,
      onCreate: (Database db, version) async {
        for (TableCreator tableCreator in tableCreators) {
          await tableCreator(db);
        }
      },
      onUpgrade: (db, oldVersion, newVersion) {
        var sorted = migrations.keys.toList()..sort();

        for (int version in sorted) {
          if (oldVersion < version) {
            for (String sql in migrations[version]!) {
              db.execute(sql);
              print('executed $sql');
            }
          }
        }
      },
    );
    return db;
  }

  Future close() async {
    var dbClient = await db;
    return dbClient.close();
  }
}
