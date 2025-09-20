import 'package:sqflite/sqflite.dart';
import 'package:tinode/src/services/database-manager.dart';

mixin StoreMixin {
  Database get db => DatabaseManager.instance.database;
}
