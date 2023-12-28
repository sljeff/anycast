import 'package:sqflite/sqflite.dart';

typedef TableCreator = Future<void> Function(DatabaseExecutor db);
