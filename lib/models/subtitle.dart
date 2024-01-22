import 'dart:convert';

import 'package:anycast/api/subtitles.dart';
import 'package:sqflite/sqflite.dart';

var tableName = 'subtitle';
Future<void> subtitleTableCreator(DatabaseExecutor db) async {
  await db.execute("""
    CREATE TABLE IF NOT EXISTS $tableName (
      id INTEGER PRIMARY KEY,
      enclosureUrl TEXT UNIQUE,
      language TEXT,
      summary TEXT,
      status TEXT,
      subtitle TEXT
    )
  """);
}

class SubtitleModel {
  int? id;
  String? enclosureUrl;
  String? status;
  String? subtitle;

  SubtitleModel.empty();

  Map<String, dynamic> toMap() {
    var map = <String, dynamic>{
      'enclosureUrl': enclosureUrl,
      'status': status,
      'subtitle': subtitle,
    };
    if (id != null) {
      map['id'] = id;
    }

    return map;
  }

  SubtitleModel.fromMap(Map<String, dynamic> map) {
    id = map['id'];
    enclosureUrl = map['enclosureUrl'];
    status = map['status'];
    subtitle = map['subtitle'];
  }

  static Future<SubtitleModel> get(
      DatabaseExecutor db, String enclosureUrl) async {
    var result = await db.query(
      tableName,
      where: 'enclosureUrl = ?',
      whereArgs: [enclosureUrl],
    );
    if (result.isEmpty) {
      return SubtitleModel.empty();
    }
    return SubtitleModel.fromMap(result.first);
  }

  static Future<void> insert(DatabaseExecutor db, SubtitleModel model) async {
    await db.insert(
      tableName,
      model.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  static Future<Map<String, String>> list(Database db) async {
    var result = await db.query(tableName);
    var map = <String, String>{};
    for (var item in result) {
      map[item['enclosureUrl'] as String] = item['status'] as String;
    }
    return map;
  }

  static Future<void> delete(DatabaseExecutor db, String enclosureUrl) async {
    await db.delete(
      tableName,
      where: 'enclosureUrl = ?',
      whereArgs: [enclosureUrl],
    );
  }

  String toLrc() {
    List<Subtitle> subtitles = [];
    for (var item in jsonDecode(subtitle!)) {
      subtitles.add(Subtitle.fromMap(item));
    }
    var lrc = '';
    for (var i = 0; i < subtitles.length; i++) {
      var subtitle = subtitles[i];
      lrc += '[${formatLrcTime(subtitle.start!)}]${subtitle.text}\n';
      lrc += '[${formatLrcTime(subtitle.end!)}]\n';
    }
    return lrc;
  }
}

// seconds to mm:ss.xx
String formatLrcTime(double time) {
  var minutes = (time / 60).floor();
  var seconds = (time % 60).floor();
  var milliseconds = ((time * 1000) % 1000).floor();
  return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}.${milliseconds.toString().padLeft(3, '0')}';
}
