import 'package:sqflite/sqflite.dart';

var tableName = 'translation';

Future<void> createTable(DatabaseExecutor db) async {
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

  static Future<TranslationModel> get(
      DatabaseExecutor db, String enclosureUrl) async {
    var result = await db.query(
      tableName,
      where: 'enclosureUrl = ?',
      whereArgs: [enclosureUrl],
    );
    if (result.isEmpty) {
      return TranslationModel.empty();
    }
    return TranslationModel.fromMap(result.first);
  }
}
