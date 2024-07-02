import 'package:sqflite/sqflite.dart';
import 'episode.dart';

String tableName = 'historyEpisode';

Future<void> historyEpisodeTableCreator(DatabaseExecutor db) {
  return db.execute("""
    CREATE TABLE IF NOT EXISTS $tableName (
      id INTEGER PRIMARY KEY,
      title TEXT,
      description TEXT,
      guid TEXT UNIQUE,
      duration INTEGER,
      enclosureUrl TEXT UNIQUE,
      pubDate INTEGER,
      imageUrl TEXT,
      channelTitle TEXT,
      rssFeedUrl TEXT
    )
  """);
}

class HistoryEpisodeModel extends Episode {
  Map<String, dynamic> toMap() {
    var map = <String, dynamic>{
      'channelTitle': channelTitle,
      'rssFeedUrl': rssFeedUrl,
      'title': title,
      'description': description,
      'guid': guid,
      'duration': duration,
      'enclosureUrl': enclosureUrl,
      'pubDate': pubDate,
      'imageUrl': imageUrl,
    };
    if (id != null) {
      map['id'] = id;
    }

    return map;
  }

  HistoryEpisodeModel.fromMap(Map<String, dynamic> map) {
    id = map['id'];
    channelTitle = map['channelTitle'];
    rssFeedUrl = map['rssFeedUrl'];
    title = map['title'];
    description = map['description'];
    guid = map['guid'];
    duration = map['duration'];
    enclosureUrl = map['enclosureUrl'];
    pubDate = map['pubDate'];
    imageUrl = map['imageUrl'];
  }

  static Future<List<HistoryEpisodeModel>> listAll(DatabaseExecutor db) async {
    return db
        .rawQuery('SELECT * FROM $tableName ORDER BY id DESC')
        .then((List<Map<String, dynamic>> maps) {
      return List.generate(maps.length, (i) {
        return HistoryEpisodeModel.fromMap(maps[i]);
      });
    });
  }

  static Future<void> deleteAll(DatabaseExecutor db) async {
    await db.delete(tableName);
  }

  static Future<void> delete(DatabaseExecutor db, String enclosureUrl) async {
    await db.delete(
      tableName,
      where: 'enclosureUrl = ?',
      whereArgs: [enclosureUrl],
    );
  }

  // delete first and then insert
  static Future<void> insert(
      DatabaseExecutor db, HistoryEpisodeModel model) async {
    await db.delete(
      tableName,
      where: 'enclosureUrl = ?',
      whereArgs: [model.enclosureUrl],
    );
    await db.insert(
      tableName,
      model.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}
