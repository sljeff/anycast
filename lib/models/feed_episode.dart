import 'package:sqflite/sqflite.dart';
import 'episode.dart';

String tableName = 'feedEpisode';

Future<void> feedEpisodeTableCreator(DatabaseExecutor db) {
  return db.execute("""
    CREATE TABLE IF NOT EXISTS $tableName (
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
  """);
}

class FeedEpisodeModel extends Episode {
  Map<String, dynamic> toMap() {
    var map = <String, dynamic>{
      'channelTitle': channelTitle,
      'rssFeedUrl': rssFeedUrl,
      'title': title,
      'description': description,
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

  FeedEpisodeModel.fromMap(Map<String, dynamic> map) {
    id = map['id'];
    channelTitle = map['channelTitle'];
    rssFeedUrl = map['rssFeedUrl'];
    title = map['title'];
    description = map['description'];
    duration = map['duration'];
    enclosureUrl = map['enclosureUrl'];
    pubDate = map['pubDate'];
    imageUrl = map['imageUrl'];
  }

  static Future<List<FeedEpisodeModel>> listAll(DatabaseExecutor db) async {
    return db
        .rawQuery('SELECT * FROM $tableName ORDER BY pubDate DESC')
        .then((List<Map<String, dynamic>> maps) {
      return List.generate(maps.length, (i) {
        return FeedEpisodeModel.fromMap(maps[i]);
      });
    });
  }

  Future<void> save(DatabaseExecutor db) async {
    if (id == null) {
      id = await db.insert(tableName, toMap());
    } else {
      await db.update(tableName, toMap(), where: 'id = ?', whereArgs: [id]);
    }
  }

  static Future<void> removeByEnclosureUrls(
      DatabaseExecutor db, List<String> enclosureUrls) async {
    await db.rawDelete(
      'DELETE FROM $tableName WHERE enclosureUrl IN (${enclosureUrls.map((e) => '?').join(',')})',
    );
  }

  static Future<void> insertMany(
      DatabaseExecutor db, List<FeedEpisodeModel> episodes) async {
    var batch = db.batch();
    for (var episode in episodes) {
      batch.insert(tableName, episode.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }
}
