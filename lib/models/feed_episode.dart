import 'package:sqflite/sqflite.dart';
import 'episode.dart';

String tableName = 'feedEpisode';

Future<void> feedEpisodeTableCreator(DatabaseExecutor db) {
  return db.execute("""
    CREATE TABLE IF NOT EXISTS $tableName (
      id INTEGER PRIMARY KEY,
      title TEXT,
      description TEXT,
      guid TEXT,
      duration INTEGER,
      enclosureUrl TEXT,
      pubDate INTEGER,
      imageUrl TEXT,
      subscriptionTitle TEXT
    )
  """);
}

class FeedEpisodeModel extends Episode {
  // fields
  String? subscriptionTitle;

  Map<String, dynamic> toMap() {
    var map = <String, dynamic>{
      'subscriptionTitle': subscriptionTitle,
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

  FeedEpisodeModel.fromMap(Map<String, dynamic> map) {
    id = map['id'];
    subscriptionTitle = map['subscriptionTitle'];
    title = map['title'];
    description = map['description'];
    guid = map['guid'];
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

  static Future<void> removeByGuid(DatabaseExecutor db, String guid) async {
    await db.delete(tableName, where: 'guid = ?', whereArgs: [guid]);
  }
}
