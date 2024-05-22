import 'package:audio_service/audio_service.dart';
import 'package:sqflite/sqflite.dart';

import 'episode.dart';

String tableName = 'playlistEpisode';
Future<void> playlistEpisodeTableCreator(DatabaseExecutor db) {
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
      rssFeedUrl TEXT,
      playlistId INTEGER,
      position REAL,
      playedDuration INTEGER
    )
  """);
}

const minPositionGap = 0.0005;

class PlaylistEpisodeModel extends Episode {
  int? playlistId;
  double? position;
  int? playedDuration; // in milliseconds

  Map<String, dynamic> toMap() {
    var map = <String, dynamic>{
      'playlistId': playlistId,
      'position': position,
      'playedDuration': playedDuration,
      'title': title,
      'description': description,
      'guid': guid,
      'duration': duration,
      'enclosureUrl': enclosureUrl,
      'pubDate': pubDate,
      'imageUrl': imageUrl,
      'channelTitle': channelTitle,
      'rssFeedUrl': rssFeedUrl,
    };
    if (id != null) {
      map['id'] = id;
    }

    return map;
  }

  PlaylistEpisodeModel.empty();

  PlaylistEpisodeModel.fromMap(Map<String, dynamic> map) {
    id = map['id'];
    playlistId = map['playlistId'];
    position = map['position'];
    playedDuration = map['playedDuration'];
    title = map['title'];
    description = map['description'];
    guid = map['guid'];
    duration = map['duration'];
    enclosureUrl = map['enclosureUrl'];
    pubDate = map['pubDate'];
    imageUrl = map['imageUrl'];
    channelTitle = map['channelTitle'];
    rssFeedUrl = map['rssFeedUrl'];
  }

  static Future<List<PlaylistEpisodeModel>> listByPlaylistId(
      DatabaseExecutor db, playlistId) async {
    return db.rawQuery(
        'SELECT * FROM $tableName WHERE playlistId = ? ORDER BY position ASC',
        [playlistId]).then((List<Map<String, dynamic>> maps) {
      return List.generate(maps.length, (i) {
        return PlaylistEpisodeModel.fromMap(maps[i]);
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

  static Future<void> insertOrUpdateByIndex(DatabaseExecutor db, int playlistId,
      int index, PlaylistEpisodeModel ep) async {
    var episode = await getByEnclosureUrl(db, ep.enclosureUrl!);

    episode ??= ep;

    var episodes = await listByPlaylistId(db, playlistId);
    var positionLeft = index > 0 ? episodes[index - 1].position : null;
    var positionRight =
        index < episodes.length ? episodes[index].position : null;
    var isTooClose = false;

    if (positionLeft != null && positionRight != null) {
      episode.position = (positionLeft + positionRight) / 2;
      if (positionRight - positionLeft < minPositionGap) {
        isTooClose = true;
      }
    } else if (positionLeft != null) {
      episode.position = positionLeft + minPositionGap * 3;
    } else if (positionRight != null) {
      episode.position = positionRight - minPositionGap * 3;
    } else {
      episode.position = 0;
    }

    if (episode.id == null) {
      await episode.save(db);
    } else {
      await db.update(tableName, episode.toMap(),
          where: 'id = ?', whereArgs: [episode.id]);
    }

    if (isTooClose) {
      await _reorder(db, playlistId);
    }
  }

  static Future<void> _reorder(DatabaseExecutor db, int playlistId) async {
    var episodes = await listByPlaylistId(db, playlistId);
    episodes.sort((a, b) => a.position!.compareTo(b.position!));
    for (var i = 0; i < episodes.length; i++) {
      episodes[i].position = i.toDouble();
      await db.update(tableName, episodes[i].toMap(),
          where: 'id = ?', whereArgs: [episodes[i].id]);
    }
  }

  static Future<PlaylistEpisodeModel> getByGuid(
      DatabaseExecutor db, String guid) async {
    return db.rawQuery('SELECT * FROM $tableName WHERE guid = ?', [guid]).then(
        (List<Map<String, dynamic>> maps) {
      return PlaylistEpisodeModel.fromMap(maps[0]);
    });
  }

  static Future<PlaylistEpisodeModel?> getByEnclosureUrl(
      DatabaseExecutor db, String enclosureUrl) async {
    return db.rawQuery('SELECT * FROM $tableName WHERE enclosureUrl = ?',
        [enclosureUrl]).then((List<Map<String, dynamic>> maps) {
      if (maps.isEmpty) {
        return null;
      }
      return PlaylistEpisodeModel.fromMap(maps[0]);
    });
  }

  static Future<void> deleteByGuid(DatabaseExecutor db, String guid) async {
    await db.delete(tableName, where: 'guid = ?', whereArgs: [guid]);
  }

  void updatePlayedDuration(DatabaseExecutor db) async {
    await db.update(tableName, {'playedDuration': playedDuration},
        where: 'guid = ?', whereArgs: [guid]);
  }

  // format: 21:32 / 31:56
  static String getPlayedAndTotalTime(int playedDuration, int duration) {
    var played = Duration(milliseconds: playedDuration);
    var total = Duration(milliseconds: duration);
    return '${played.inMinutes}:${(played.inSeconds % 60).toString().padLeft(2, '0')} / ${total.inMinutes}:${(total.inSeconds % 60).toString().padLeft(2, '0')}';
  }

  MediaItem toMediaItem() {
    return MediaItem(
      id: enclosureUrl!,
      album: channelTitle,
      title: title!,
      artUri: Uri.parse(imageUrl!),
      duration: duration != null ? Duration(milliseconds: duration!) : null,
    );
  }
}
