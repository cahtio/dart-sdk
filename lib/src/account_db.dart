import 'package:sqflite/sqflite.dart';
import 'base_db.dart';

class StoredAccount {
  final int id;
  final String uid;
  final List<String>? credMethods;

  StoredAccount({required this.id, required this.uid, this.credMethods});

  @override
  String toString() {
    return 'StoredAccount{id: $id, uid: $uid, credMethods: $credMethods}';
  }
}

class AccountDb {
  static const String kTableName = 'accounts';
  final Database _db;

  // 表列名
  static const String columnId = 'id';
  static const String columnUid = 'uid';
  static const String columnActive = 'last_active';
  static const String columnCredMethods = 'cred_methods';
  static const String columnDeviceId = 'device_id';

  AccountDb(this._db);

  // 删除表及索引
  Future<void> destroyTable() async {
    await _db.execute('DROP INDEX IF EXISTS idx_uid');
    await _db.execute('DROP INDEX IF EXISTS idx_active');
    await _db.execute('DROP TABLE IF EXISTS $kTableName');
  }

  // 创建表及索引
  Future<void> createTable() async {
    await _db.execute('''
      CREATE TABLE IF NOT EXISTS $kTableName (
        $columnId INTEGER PRIMARY KEY AUTOINCREMENT,
        $columnUid TEXT,
        $columnActive INTEGER,
        $columnCredMethods TEXT,
        $columnDeviceId TEXT
      )
    ''');
    await _db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_uid ON $kTableName($columnUid)',
    );
    await _db.execute(
      'CREATE INDEX IF NOT EXISTS idx_active ON $kTableName($columnActive)',
    );
  }

  // 清空表中所有记录
  Future<void> truncateTable(DatabaseExecutor db) async {
    await db.delete(kTableName);
  }

  // 将所有账户设为非活跃状态
  Future<int> deactivateAll() async {
    return await _db.update(kTableName, {columnActive: 0});
  }

  // 根据uid获取账户
  Future<StoredAccount?> getByUid(String uid) async {
    final List<Map<String, dynamic>> maps = await _db.query(
      kTableName,
      columns: [columnId, columnCredMethods],
      where: '$columnUid = ?',
      whereArgs: [uid],
    );

    if (maps.isNotEmpty) {
      final map = maps.first;
      return StoredAccount(
        id: map[columnId] as int,
        uid: uid,
        credMethods: map[columnCredMethods] != null
            ? (map[columnCredMethods] as String).split(',')
            : null,
      );
    }
    return null;
  }

  // 添加或激活账户
  Future<StoredAccount?> addOrActivateAccount({
    required String uid,
    List<String>? credMethods,
  }) async {
    final serializedCredMeth = credMethods?.join(',');
    StoredAccount? result;

    try {
      await _db.transaction((txn) async {
        // 先将所有账户设为非活跃
        await txn.update(kTableName, {columnActive: 0});

        // 查找现有账户
        final existing = await getByUid(uid);
        if (existing != null) {
          // 更新现有账户
          await txn.update(
            kTableName,
            {columnActive: 1, columnCredMethods: serializedCredMeth},
            where: '$columnId = ?',
            whereArgs: [existing.id],
          );
          result = StoredAccount(
            id: existing.id,
            uid: uid,
            credMethods: credMethods,
          );
        } else {
          // 插入新账户
          final newId = await txn.insert(kTableName, {
            columnUid: uid,
            columnActive: 1,
            columnCredMethods: serializedCredMeth,
          });
          result = StoredAccount(
            id: newId.toInt(),
            uid: uid,
            credMethods: credMethods,
          );
        }
      });
    } catch (e) {
      BaseDb.log.error('Failed to add account for uid $uid: $e');
      result = null;
    }

    return result;
  }

  // 根据ID删除账户
  Future<bool> delete(DatabaseExecutor db, int accountId) async {
    try {
      final rowsAffected = await db.delete(
        kTableName,
        where: '$columnId = ?',
        whereArgs: [accountId],
      );
      return rowsAffected > 0;
    } catch (e) {
      BaseDb.log.error(
        'AccountDb - delete operation failed: accountId = $accountId, error = $e',
      );
      return false;
    }
  }

  // 获取活跃账户
  Future<StoredAccount?> getActiveAccount() async {
    final List<Map<String, dynamic>> maps = await _db.query(
      kTableName,
      columns: [columnId, columnUid, columnCredMethods],
      where: '$columnActive = ?',
      whereArgs: [1],
    );

    if (maps.isNotEmpty) {
      final map = maps.first;
      final uid = map[columnUid] as String?;
      if (uid != null) {
        return StoredAccount(
          id: map[columnId] as int,
          uid: uid,
          credMethods: map[columnCredMethods] != null
              ? (map[columnCredMethods] as String).split(',')
              : null,
        );
      }
    }
    return null;
  }

  // 保存设备令牌
  Future<bool> saveDeviceToken(String? token) async {
    try {
      final rowsAffected = await _db.update(
        kTableName,
        {columnDeviceId: token},
        where: '$columnActive = ?',
        whereArgs: [1],
      );
      return rowsAffected > 0;
    } catch (e) {
      BaseDb.log.error('Failed to save device token: $e');
      return false;
    }
  }

  // 获取设备令牌
  Future<String?> getDeviceToken() async {
    final List<Map<String, dynamic>> maps = await _db.query(
      kTableName,
      columns: [columnDeviceId],
      where: '$columnActive = ?',
      whereArgs: [1],
    );

    if (maps.isNotEmpty) {
      return maps.first[columnDeviceId] as String?;
    }
    return null;
  }
}
