import 'package:sqflite/sqflite.dart';
import 'package:tinode/src/db/repository.dart';

class Account {
  final int id;
  final String uid;
  final List<String>? credMethods;

  Account(this.id, this.uid, {this.credMethods});

  @override
  String toString() {
    return 'Account{id: $id, uid: $uid, credMethods: $credMethods}';
  }
}

class AccountRepository extends Repository {
  static const String kTableName = 'accounts';

  // 表列名
  static const String kColumnId = 'id';
  static const String kColumnUid = 'uid';
  static const String kColumnActive = 'last_active';
  static const String kColumnCredMethods = 'cred_methods';
  static const String kColumnDeviceId = 'device_id';

  AccountRepository();

  // 删除表及索引
  Future<void> destroyTable(DatabaseExecutor dbe) async {
    await dbe.execute('DROP INDEX IF EXISTS idx_uid');
    await dbe.execute('DROP INDEX IF EXISTS idx_active');
    await dbe.execute('DROP TABLE IF EXISTS $kTableName');
  }

  // 创建表及索引
  Future<void> createTable(DatabaseExecutor dbe) async {
    await dbe.execute('''
      CREATE TABLE IF NOT EXISTS $kTableName (
        $kColumnId INTEGER PRIMARY KEY AUTOINCREMENT,
        $kColumnUid TEXT,
        $kColumnActive INTEGER,
        $kColumnCredMethods TEXT,
        $kColumnDeviceId TEXT
      )
    ''');
    await dbe.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_uid ON $kTableName($kColumnUid)',
    );
    await dbe.execute(
      'CREATE INDEX IF NOT EXISTS idx_active ON $kTableName($kColumnActive)',
    );
  }

  // 清空表中所有记录
  Future<void> truncateTable(DatabaseExecutor dbe) async {
    await dbe.delete(kTableName);
  }

  // 将所有账户设为非活跃状态
  Future<int> deactivateAll(DatabaseExecutor dbe) async {
    return dbe.update(kTableName, {kColumnActive: 0});
  }

  // 根据uid获取账户
  Future<Account?> getByUid(DatabaseExecutor dbe, String uid) async {
    final List<Map<String, dynamic>> maps = await dbe.query(
      kTableName,
      columns: [kColumnId, kColumnCredMethods],
      where: '$kColumnUid = ?',
      whereArgs: [uid],
    );

    if (maps.isNotEmpty) {
      final map = maps.first;
      return Account(
        map[kColumnId] as int,
        uid,
        credMethods: map[kColumnCredMethods] != null
            ? (map[kColumnCredMethods] as String).split(',')
            : null,
      );
    }
    return null;
  }

  // 添加或激活账户
  Future<Account?> addOrActivateAccount(
    DatabaseExecutor dbe,
    String uid, {
    List<String>? credMethods,
  }) async {
    final serializedCredMeth = credMethods?.join(',');
    Account? result;
    logInfo(
      'Account.addOrActivateAccount uid: $uid; credMethods: $credMethods;',
    );
    try {
      await transaction(dbe, (tx) async {
        // 先将所有账户设为非活跃
        await tx.update(kTableName, {kColumnActive: 0});

        // 查找现有账户
        final existing = await getByUid(tx, uid);

        if (existing != null) {
          // 更新现有账户
          await tx.update(
            kTableName,
            {kColumnActive: 1, kColumnCredMethods: serializedCredMeth},
            where: '$kColumnId = ?',
            whereArgs: [existing.id],
          );
          result = Account(existing.id, uid, credMethods: credMethods);
        } else {
          // 插入新账户
          final newId = await tx.insert(kTableName, {
            kColumnUid: uid,
            kColumnActive: 1,
            kColumnCredMethods: serializedCredMeth,
          });
          result = Account(newId.toInt(), uid, credMethods: credMethods);
        }
      });
    } catch (e) {
      logError('Failed to add account for uid $uid: $e');
      result = null;
    }
    return result;
  }

  // 根据ID删除账户
  Future<bool> delete(DatabaseExecutor dbe, int accountId) async {
    try {
      final rowsAffected = await dbe.delete(
        kTableName,
        where: '$kColumnId = ?',
        whereArgs: [accountId],
      );
      return rowsAffected > 0;
    } catch (e) {
      logError(
        'AccountDb - delete operation failed: accountId = $accountId, error = $e',
      );
      return false;
    }
  }

  // 获取活跃账户
  Future<Account?> getActiveAccount(DatabaseExecutor dbe) async {
    final List<Map<String, dynamic>> maps = await dbe.query(
      kTableName,
      columns: [kColumnId, kColumnUid, kColumnCredMethods],
      where: '$kColumnActive = ?',
      whereArgs: [1],
    );

    if (maps.isNotEmpty) {
      final map = maps.first;
      final uid = map[kColumnUid] as String?;
      if (uid != null) {
        return Account(
          map[kColumnId] as int,
          uid,
          credMethods: map[kColumnCredMethods] != null
              ? (map[kColumnCredMethods] as String).split(',')
              : null,
        );
      }
    }
    return null;
  }

  // 保存设备令牌
  Future<bool> saveDeviceToken(DatabaseExecutor dbe, String? token) async {
    try {
      final rowsAffected = await dbe.update(
        kTableName,
        {kColumnDeviceId: token},
        where: '$kColumnActive = ?',
        whereArgs: [1],
      );
      return rowsAffected > 0;
    } catch (e) {
      logError('Failed to save device token: $e');
      return false;
    }
  }

  // 获取设备令牌
  Future<String?> getDeviceToken(DatabaseExecutor dbe) async {
    final List<Map<String, dynamic>> maps = await dbe.query(
      kTableName,
      columns: [kColumnDeviceId],
      where: '$kColumnActive = ?',
      whereArgs: [1],
    );

    if (maps.isNotEmpty) {
      return maps.first[kColumnDeviceId] as String?;
    }
    return null;
  }
}
