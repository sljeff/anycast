import 'package:sqflite/sqflite.dart';

var tableName = 'settings';
Future<void> settingsTableCreator(DatabaseExecutor db) {
  return db.execute("""
    CREATE TABLE IF NOT EXISTS $tableName (
      id INTEGER PRIMARY KEY,
      darkMode INTEGER,
      speed REAL,
      skipSilence INTEGER,
      autoSleepTimer TEXT
    )
  """).then((v) {
    db.rawInsert("""
      INSERT OR IGNORE INTO $tableName (id, darkMode, speed, skipSilence, autoSleepTimer)
      VALUES (1, 0, 1.0, 0, '0,0,0')
    """);
  });
}

class SettingsModel {
  int? id;
  bool? darkMode;
  double? speed;
  bool? skipSilence;
  String? autoSleepTimer; // startHour,endHour,countdownMinIndex

  Map<String, dynamic> toMap() {
    var map = <String, dynamic>{
      'darkMode': darkMode,
      'speed': speed,
      'skipSilence': skipSilence,
      'autoSleepTimer': autoSleepTimer,
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
}
