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
];

class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper.internal();
  factory DatabaseHelper() => _instance;
  static Database? _db;

  DatabaseHelper.internal();

  Future<Database?> get db async {
    if (_db != null) return _db;
    _db = await initDb();
    return _db;
  }

  Future<Database> initDb() async {
    String databasesPath = await getDatabasesPath();
    String path = join(databasesPath, 'anycast.db');

    // delete existing if any
    // await deleteDatabase(path);

    // create new
    Database db = await openDatabase(path, version: 1,
        onCreate: (Database db, int version) async {
      for (TableCreator tableCreator in tableCreators) {
        await tableCreator(db);
      }
    });
    return db;
  }

  Future close() async {
    var dbClient = await db;
    return dbClient?.close();
  }
}
