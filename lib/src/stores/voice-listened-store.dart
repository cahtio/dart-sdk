import 'package:get_it/get_it.dart';
import 'package:sqflite/sqflite.dart';
import 'package:tinode/src/services/logger.dart';
import 'package:tinode/src/stores/store-mixins.dart';

/// 本地记录“语音消息是否已听过”的表。
///
/// 以 (topic, from, seq) 三元组唯一标识一条消息。
/// 注意：这里只存“已听过”的记录，不存“未听过”，查询时根据是否存在来判断。
class VoiceListenedStore with StoreMixin {
  static const kTableName = 'voice_listened';

  static const kColumnId = 'id';
  static const kColumnTopic = 'topic';
  static const kColumnFrom = 'msg_from';
  static const kColumnSeq = 'seq';

  late LoggerService _loggerService;

  VoiceListenedStore() {
    _loggerService = GetIt.I.get<LoggerService>();
  }

  /// 创建表：
  /// - id 自增主键
  /// - (topic, from, seq) 组合唯一约束
  Future<void> createTable(Database db) {
    return db.execute('''
      CREATE TABLE IF NOT EXISTS $kTableName (
        $kColumnId INTEGER PRIMARY KEY AUTOINCREMENT,
        $kColumnTopic TEXT NOT NULL,
        $kColumnFrom TEXT NOT NULL,
        $kColumnSeq INTEGER NOT NULL,
        UNIQUE ($kColumnTopic, $kColumnFrom, $kColumnSeq)
      )
    ''');
  }

  Future<void> destoryTable(Database db) async {
    return db.execute('DROP TABLE IF EXISTS $kTableName');
  }

  Future<void> clearTable() async {
    await db.delete(kTableName);
  }

  /// 标记某条消息为“已听过”。
  ///
  /// 多次调用不会报错（使用 INSERT OR IGNORE）。
  Future<void> markListened(String topic, String from, int seq) async {
    if (topic.isEmpty || from.isEmpty) {
      _logError(
          'markListened error, topic or from is empty; topic: $topic, from: $from, seq: $seq');
      return;
    }
    await db.insert(
      kTableName,
      {
        kColumnTopic: topic,
        kColumnFrom: from,
        kColumnSeq: seq,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  /// 取消“已听过”标记（一般不常用，但提供接口）。
  Future<void> unmarkListened(String topic, String from, int seq) async {
    if (topic.isEmpty || from.isEmpty) {
      _logError(
          'unmarkListened error, topic or from is empty; topic: $topic, from: $from, seq: $seq');
      return;
    }
    await db.delete(
      kTableName,
      where: '$kColumnTopic = ? AND $kColumnFrom = ? AND $kColumnSeq = ?',
      whereArgs: [topic, from, seq],
    );
  }

  /// 判断某条消息是否已经被标记为“已听过”。
  Future<bool> isListened(String topic, String from, int seq) async {
    if (topic.isEmpty || from.isEmpty) {
      _logError(
          'isListened error, topic or from is empty; topic: $topic, from: $from, seq: $seq');
      return false;
    }
    final count = Sqflite.firstIntValue(await db.query(
      kTableName,
      columns: ['COUNT(*)'],
      where: '$kColumnTopic = ? AND $kColumnFrom = ? AND $kColumnSeq = ?',
      whereArgs: [topic, from, seq],
    ));
    return (count ?? 0) > 0;
  }

  void _logError(String msg) {
    _loggerService.error('Database VoiceListened - $msg');
  }
}

