import 'package:sqflite/sqflite.dart';

var tableName = 'player';
Future<void> playerTableCreator(DatabaseExecutor db) {
  return db.execute("""
    CREATE TABLE IF NOT EXISTS $tableName (
      id INTEGER PRIMARY KEY,
      playlistEpisodeGuid TEXT,
      playedDuration INTEGER
    )
  """).then((v) {
    // create default 1 if not exists
    db.rawInsert("""
      INSERT OR IGNORE INTO $tableName (id, playlistEpisodeGuid, playedDuration)
      VALUES (1, NULL, 0)
    """);
  });
}

class PlayerModel {
  int? id;
  String? playlistEpisodeGuid;
  int? playedDuration; // in milliseconds

  Map<String, dynamic> toMap() {
    var map = <String, dynamic>{
      'playlistEpisodeGuid': playlistEpisodeGuid,
      'playedDuration': playedDuration,
    };
    if (id != null) {
      map['id'] = id;
    }

    return map;
  }

  PlayerModel.fromMap(Map<String, dynamic> map) {
    id = map['id'];
    playlistEpisodeGuid = map['playlistEpisodeGuid'];
    playedDuration = map['playedDuration'];
  }

  static Future<void> update(DatabaseExecutor db, PlayerModel player) async {
    await db.update(tableName, player.toMap(), where: 'id = ?', whereArgs: [1]);
  }

  static Future<PlayerModel> get(DatabaseExecutor db) async {
    return db
        .rawQuery('SELECT * FROM $tableName WHERE id = 1')
        .then((List<Map<String, dynamic>> maps) {
      return PlayerModel.fromMap(maps[0]);
    });
  }
}
