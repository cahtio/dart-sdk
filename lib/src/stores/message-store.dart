import 'dart:convert';

import 'package:get_it/get_it.dart';
import 'package:sqflite/sqflite.dart';

import 'package:tinode/src/models/server-messages.dart';
import 'package:tinode/src/services/logger.dart';
import 'package:tinode/src/stores/store-mixins.dart';

class MessageStore with StoreMixin {
  static const kTableName = 'message';

  static const kColumnId = 'id';
  static const kColumnTopic = 'topic';
  static const kColumnFrom = 'msg_from';
  static const kColumnContent = 'content';
  static const kColumnSeq = 'seq';
  static const kColumnTs = 'ts';
  static const kColumnHigh = 'high';
  static const kColumnHead = 'head';

  late LoggerService _loggerService;

  MessageStore() {
    _loggerService = GetIt.I.get<LoggerService>();
  }

  Future<void> createTable(Database db) {
    return db.execute('''
      CREATE TABLE IF NOT EXISTS $kTableName (
        $kColumnId INTEGER PRIMARY KEY AUTOINCREMENT,
        $kColumnTopic TEXT NOT NULL,
        $kColumnFrom TEXT NOT NULL,
        $kColumnHead TEXT,
        $kColumnContent TEXT,
        $kColumnSeq INTEGER NOT NULL,
        $kColumnHigh INTEGER,
        $kColumnTs INTEGER
      )
    ''');
  }

  Future<void> destoryTable() async {
    return db.execute('DROP TABLE IF EXISTS $kTableName');
  }

  Future<List<DataMessage>> query(String topic) async {
    final maps = await db.query(kTableName,
        where: '$kColumnTopic = ?', whereArgs: [topic], orderBy: kColumnSeq);
    return maps.map((row) {
      dynamic content;
      if (row[kColumnContent] == null) {
        content = null;
      } else {
        try {
          content = jsonDecode(row[kColumnContent] as String);
        } catch (e) {
          content = row[kColumnContent];
        }
      }
      return DataMessage(
          topic: row[kColumnTopic] as String,
          from: row[kColumnFrom] as String,
          head: row[kColumnHead] != null
              ? jsonDecode(row[kColumnHead] as String)
              : null,
          content: content,
          seq: row[kColumnSeq] as int?,
          hi: row[kColumnHigh] as int?,
          ts: row[kColumnTs] != null
              ? DateTime.fromMillisecondsSinceEpoch(row[kColumnTs] as int)
              : null);
    }).toList();

    //     $kColumnSeq INTEGER NOT NULL,
    //     $kColumnHigh INTEGER,
    //     $kColumnTs INTEGER
  }

  Future<void> msgReceived(DataMessage message) async {
    if (message.topic?.isEmpty ?? true) {
      _logError('Received error, message topic is empty or null!');
      return null;
    }

    if (message.from?.isEmpty ?? true) {
      _logError('Received error, message from is empty or null!');
      return null;
    }

    if (message.seq == null) {
      _logError('Received error, message seq is null!');
      return null;
    }

    final count = await _count(message.topic!, message.from!, message.seq!);
    if (count > 0) {
      await _update(message);
    } else {
      await _insert(message);
    }
  }

  Future<int> _count(String topic, String from, int seq) async {
    final count = Sqflite.firstIntValue(await db.query(kTableName,
        columns: ['COUNT(*)'],
        where: '$kColumnTopic = ? AND $kColumnFrom = ? AND $kColumnSeq = ?',
        whereArgs: [topic, from, seq]));
    if (count == null) {
      _logError('select count error; topic: $topic, from: $from, seq: $seq');
    }
    return count ?? 0;
  }

  Future<int?> _insert(DataMessage message) async {
    if (message.topic?.isEmpty ?? true) {
      _logError('insert error, message topic is empty or null!');
      return null;
    }

    if (message.from?.isEmpty ?? true) {
      _logError('insert error, message from is empty or null!');
      return null;
    }

    if (message.seq == null) {
      _logError('insert error, message seq is null!');
      return null;
    }

    return db.insert(kTableName, {
      kColumnTopic: message.topic,
      kColumnFrom: message.from,
      kColumnHead: message.head == null ? null : jsonEncode(message.head),
      kColumnContent: message.content is String
          ? message.content
          : jsonEncode(message.content),
      kColumnSeq: message.seq,
      kColumnHigh: message.hi,
      kColumnTs: message.ts?.millisecondsSinceEpoch
    });
  }

  Future<int?> _update(DataMessage message) async {
    if (message.topic?.isEmpty ?? true) {
      _logError('update error, message topic is empty or null!');
      return null;
    }

    if (message.from?.isEmpty ?? true) {
      _logError('update error, message from is empty or null!');
      return null;
    }

    if (message.seq == null) {
      _logError('update error, message seq is null!');
      return null;
    }

    final values = <String, dynamic>{};
    if (message.head != null) {
      values[kColumnHead] = jsonEncode(message.head);
    }
    if (message.content != null) {
      values[kColumnContent] = message.content is String
          ? message.content
          : jsonEncode(message.content);
    }
    if (message.hi != null) {
      values[kColumnHigh] = message.hi;
    }
    if (message.ts != null) {
      values[kColumnTs] = message.ts!.millisecondsSinceEpoch;
    }

    return db.update(kTableName, values,
        where: '$kColumnTopic = ? AND $kColumnFrom = ? AND $kColumnSeq = ?',
        whereArgs: [message.topic!, message.from!, message.seq!]);
  }

  void _logError(String msg) {
    _loggerService.error('Database Message - $msg');
  }

  // void _logInfo(String msg) {
  //   _loggerService.log('Database Message - $msg');
  // }
}
