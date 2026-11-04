import 'package:sqflite/sqflite.dart';
import 'episode.dart';

String tableName = 'historyEpisode';

Future<void> historyEpisodeTableCreator(DatabaseExecutor db) {
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
      rssFeedUrl TEXT,
      lastPlayedAt INTEGER
    )
  """);
}

class HistoryEpisodeModel extends Episode {
  /// Unix milliseconds of the latest play. Null only for a model that has
  /// not been written yet; stored rows always have a value.
  int? lastPlayedAt;

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
    if (lastPlayedAt != null) {
      map['lastPlayedAt'] = lastPlayedAt;
    }

    return map;
  }

  HistoryEpisodeModel.fromMap(Map<String, dynamic> map) {
    id = map['id'];
    channelTitle = map['channelTitle'];
    rssFeedUrl = map['rssFeedUrl'];
    title = map['title'];
    description = map['description'];
    duration = map['duration'];
    enclosureUrl = map['enclosureUrl'];
    pubDate = map['pubDate'];
    imageUrl = map['imageUrl'];
    lastPlayedAt = map['lastPlayedAt'];
  }

  static Future<List<HistoryEpisodeModel>> listAll(DatabaseExecutor db) async {
    return db
        .rawQuery(
            'SELECT * FROM $tableName ORDER BY lastPlayedAt DESC, id DESC')
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

  /// Upsert by enclosure URL. The history primary key is independent of any
  /// id the caller carries (playlist rowids used to be copied through and
  /// could REPLACE a different history row). Re-listening bumps lastPlayedAt
  /// and keeps the existing history id.
  static Future<void> insert(
      DatabaseExecutor db, HistoryEpisodeModel model) async {
    final playedAt = DateTime.now().millisecondsSinceEpoch;
    await db.rawInsert('''
      INSERT INTO $tableName (
        title, description, duration, enclosureUrl, pubDate, imageUrl,
        channelTitle, rssFeedUrl, lastPlayedAt
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(enclosureUrl) DO UPDATE SET
        title = excluded.title,
        description = excluded.description,
        duration = excluded.duration,
        pubDate = excluded.pubDate,
        imageUrl = excluded.imageUrl,
        channelTitle = excluded.channelTitle,
        rssFeedUrl = excluded.rssFeedUrl,
        lastPlayedAt = excluded.lastPlayedAt
    ''', <Object?>[
      model.title,
      model.description,
      model.duration,
      model.enclosureUrl,
      model.pubDate,
      model.imageUrl,
      model.channelTitle,
      model.rssFeedUrl,
      playedAt,
    ]);
  }

  static Future<void> deleteMany(
      DatabaseExecutor db, List<String> enclosureUrls) async {
    await db.delete(
      tableName,
      where: 'enclosureUrl IN (${enclosureUrls.map((e) => '?').join(',')})',
      whereArgs: enclosureUrls,
    );
  }
}
