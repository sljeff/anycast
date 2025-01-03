import 'package:sqflite/sqflite.dart';

var tableName = 'player';
Future<void> playerTableCreator(DatabaseExecutor db) {
  return db.execute("""
    CREATE TABLE IF NOT EXISTS $tableName (
      id INTEGER PRIMARY KEY,
      currentPlaylistId INTEGER
    )
  """).then((v) {
    // create default 1 if not exists
    db.rawInsert("""
      INSERT OR IGNORE INTO $tableName (id, currentPlaylistId)
      VALUES (1, NULL)
    """);
  });
}

class PlayerModel {
  int? id;
  int? currentPlaylistId;

  Map<String, dynamic> toMap() {
    var map = <String, dynamic>{
      'currentPlaylistId': currentPlaylistId,
    };
    if (id != null) {
      map['id'] = id;
    }

    return map;
  }

  PlayerModel.empty();

  PlayerModel.fromMap(Map<String, dynamic> map) {
    id = map['id'];
    currentPlaylistId = map['currentPlaylistId'];
  }

  static Future<void> update(DatabaseExecutor db, PlayerModel player) async {
    // await db.update(tableName, player.toMap(), where: 'id = ?', whereArgs: [1]);
    // insert, on conflict replace
    await db.rawInsert("""
      INSERT OR REPLACE INTO $tableName (id, currentPlaylistId)
      VALUES (1, ?)""", [player.currentPlaylistId]);
  }

  static Future<PlayerModel> get(DatabaseExecutor db) async {
    return db
        .rawQuery('SELECT * FROM $tableName WHERE id = 1')
        .then((List<Map<String, dynamic>> maps) {
      return PlayerModel.fromMap(maps[0]);
    });
  }

  static Future<void> delete(DatabaseExecutor db) async {
    await db.delete(tableName, where: 'id = ?', whereArgs: [1]);
  }
}
