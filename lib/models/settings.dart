import 'dart:io';

import 'package:sqflite/sqflite.dart';

var tableName = 'settings';
Future<void> settingsTableCreator(DatabaseExecutor db) {
  return db.execute("""
    CREATE TABLE IF NOT EXISTS $tableName (
      id INTEGER PRIMARY KEY,
      darkMode INTEGER,
      speed REAL,
      skipSilence INTEGER,
      autoSleepTimer TEXT,
      maxCacheCount INTEGER,
      countryCode TEXT,
      targetLanguage TEXT,
      autoRefreshInterval INTEGER,
      maxFeedEpisodes INTEGER,
      maxHistoryEpisodes INTEGER
    )
  """).then((v) {
    var code = Platform.localeName;
    // en_US / zh_Hans_CN / zh_CN
    var languageAndCountry = code.split('_');
    var language = 'en';
    var country = 'US';
    if (languageAndCountry.length > 1) {
      language = code.split('_')[0];
      country = code.split('_')[languageAndCountry.length - 1];
    }

    db.rawInsert("""
      INSERT OR IGNORE INTO $tableName (id, darkMode, speed, skipSilence, autoSleepTimer, maxCacheCount, countryCode, targetLanguage, autoRefreshInterval, maxFeedEpisodes, maxHistoryEpisodes)
      VALUES (1, 0, 1.0, 0, '0,0,0', 10, '$country', '$language', 300, 100, 100)
    """);
  });
}

class SettingsModel {
  int? id;
  bool? darkMode;
  double? speed;
  bool? skipSilence;
  String? autoSleepTimer; // startHour,endHour,countdownMinIndex
  int? maxCacheCount;
  String? countryCode;
  String? targetLanguage;
  int? autoRefreshInterval; // seconds
  int? maxFeedEpisodes;
  int? maxHistoryEpisodes;

  Map<String, dynamic> toMap() {
    var map = <String, dynamic>{
      'darkMode': darkMode,
      'speed': speed,
      'skipSilence': skipSilence,
      'autoSleepTimer': autoSleepTimer,
      'maxCacheCount': maxCacheCount,
      'countryCode': countryCode,
      'targetLanguage': targetLanguage,
      'autoRefreshInterval': autoRefreshInterval,
      'maxFeedEpisodes': maxFeedEpisodes,
      'maxHistoryEpisodes': maxHistoryEpisodes,
    };
    if (id != null) {
      map['id'] = id;
    }

    return map;
  }

  SettingsModel.fromMap(Map<String, dynamic> map) {
    id = map['id'];
    darkMode = map['darkMode'] == 1;
    speed = map['speed'];
    skipSilence = map['skipSilence'] == 1;
    autoSleepTimer = map['autoSleepTimer'];
    maxCacheCount = map['maxCacheCount'];
    countryCode = map['countryCode'];
    targetLanguage = map['targetLanguage'];
    autoRefreshInterval = map['autoRefreshInterval'];
    maxFeedEpisodes = map['maxFeedEpisodes'];
    maxHistoryEpisodes = map['maxHistoryEpisodes'];
  }

  static Future<SettingsModel> get(DatabaseExecutor db) async {
    return db
        .rawQuery('SELECT * FROM $tableName WHERE id = 1')
        .then((List<Map<String, dynamic>> maps) {
      return SettingsModel.fromMap(maps[0]);
    });
  }

  static Future<int> setDarkMode(DatabaseExecutor db, bool darkMode) async {
    return db.rawUpdate("""
      UPDATE $tableName
      SET darkMode = ?
      WHERE id = 1
    """, [darkMode ? 1 : 0]);
  }

  static Future<int> setSpeed(DatabaseExecutor db, double speed) async {
    return db.rawUpdate("""
      UPDATE $tableName
      SET speed = ?
      WHERE id = 1
    """, [speed]);
  }

  static Future<int> setSkipSilence(
      DatabaseExecutor db, bool skipSilence) async {
    return db.rawUpdate("""
      UPDATE $tableName
      SET skipSilence = ?
      WHERE id = 1
    """, [skipSilence ? 1 : 0]);
  }

  static Future<int> setAutoSleepTimer(
      DatabaseExecutor db, int start, int end, int minsIndex) async {
    var autoSleepTimer = '$start,$end,$minsIndex';
    return db.rawUpdate("""
      UPDATE $tableName
      SET autoSleepTimer = ?
      WHERE id = 1
    """, [autoSleepTimer]);
  }

  static Future<void> set(
      DatabaseExecutor db, String field, dynamic value) async {
    await db.rawUpdate("""
      UPDATE $tableName
      SET $field = ?
      WHERE id = 1
    """, [value]);
  }
}
