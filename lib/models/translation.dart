import 'dart:convert';

import 'package:anycast/api/subtitles.dart';
import 'package:anycast/utils/formatters.dart';
import 'package:sqflite/sqflite.dart';

var tableName = 'translation';

Future<void> translationCreateTable(DatabaseExecutor db) async {
  await db.execute("""
    CREATE TABLE IF NOT EXISTS $tableName (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      enclosureUrl TEXT UNIQUE,
      status TEXT,
      translation TEXT,
      language TEXT
    )
  """);
}

class TranslationModel {
  int? id;
  String? enclosureUrl;
  String? status;
  String? translation;
  String? language;

  TranslationModel.empty();

  Map<String, dynamic> toMap() {
    var map = <String, dynamic>{
      'enclosureUrl': enclosureUrl,
      'status': status,
      'translation': translation,
      'language': language,
    };
    if (id != null) {
      map['id'] = id;
    }

    return map;
  }

  TranslationModel.fromMap(Map<String, dynamic> map) {
    id = map['id'];
    enclosureUrl = map['enclosureUrl'];
    status = map['status'];
    translation = map['translation'];
    language = map['language'];
  }

  static Future<TranslationModel?> get(
      DatabaseExecutor db, String enclosureUrl, String language) async {
    var result = await db.query(
      tableName,
      where: 'enclosureUrl = ? AND language = ?',
      whereArgs: [enclosureUrl, language],
    );
    if (result.isEmpty) {
      return null;
    }
    return TranslationModel.fromMap(result.first);
  }

  static Future<void> insert(
      DatabaseExecutor db, TranslationModel model) async {
    await db.insert(
      tableName,
      model.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  String toLrc() {
    List<Subtitle> translations = [];
    if (translation == null) {
      return '';
    }
    for (var item in jsonDecode(translation!)) {
      translations.add(Subtitle.fromMap(item));
    }
    var lrc = '';
    for (var i = 0; i < translations.length; i++) {
      var t = translations[i];
      lrc += '[${formatLrcTime(t.start!)}]${t.text}\n';
      lrc += '[${formatLrcTime(t.end!)}]\n';
    }
    return lrc;
  }
}
