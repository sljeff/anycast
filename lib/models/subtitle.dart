import 'dart:convert';

import 'package:anycast/api/subtitles.dart';
import 'package:anycast/utils/formatters.dart';
import 'package:sqflite/sqflite.dart';

var tableName = 'subtitle';
Future<void> subtitleTableCreator(DatabaseExecutor db) async {
  await db.execute("""
    CREATE TABLE IF NOT EXISTS $tableName (
      id INTEGER PRIMARY KEY,
      enclosureUrl TEXT UNIQUE,
      status TEXT,
      subtitle TEXT,
      language TEXT,
      summary TEXT
    )
  """);
}

class SubtitleModel {
  int? id;
  String? enclosureUrl;
  String? status;
  String? subtitle;
  String? language;
  String? summary;

  SubtitleModel.empty();

  Map<String, dynamic> toMap() {
    var map = <String, dynamic>{
      'enclosureUrl': enclosureUrl,
      'status': status,
      'subtitle': subtitle,
      'language': language,
      'summary': summary,
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
    language = map['language'];
    summary = map['summary'];
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
    // validation
    if (model.subtitle == null ||
        model.subtitle!.isEmpty ||
        model.language == null ||
        model.subtitle == 'null') {
      return;
    }

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
    if (subtitle == null || subtitle!.isEmpty || subtitle == 'null') {
      return '';
    }
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
