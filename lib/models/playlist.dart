import 'package:sqflite/sqflite.dart';

var tableName = 'playlist';
Future<void> playlistTableCreator(DatabaseExecutor db) {
  return db.execute("""
    CREATE TABLE IF NOT EXISTS $tableName (
      id INTEGER PRIMARY KEY,
      title TEXT,
      position INTEGER
    )
  """).then((v) {
    // create default 1 if not exists
    db.rawInsert("""
      INSERT OR IGNORE INTO $tableName (id, title, position)
      VALUES (1, 'Default', 1)
    """);
  });
}

class PlaylistModel {
  int? id;
  String? title;
  int? position;

  Map<String, dynamic> toMap() {
    var map = <String, dynamic>{
      'title': title,
      'position': position,
    };
    if (id != null) {
      map['id'] = id;
    }

    return map;
  }

  PlaylistModel.fromMap(Map<String, dynamic> map) {
    id = map['id'];
    title = map['title'];
    position = map['position'];
  }

  static Future<List<PlaylistModel>> listAll(DatabaseExecutor db) async {
    return db
        .rawQuery('SELECT * FROM $tableName ORDER BY position ASC')
        .then((List<Map<String, dynamic>> maps) {
      return List.generate(maps.length, (i) {
        return PlaylistModel.fromMap(maps[i]);
      });
    });
  }
}
