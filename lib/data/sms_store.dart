import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models/allowed_sender.dart';
import '../models/sms_entry.dart';

class SmsStore {
  SmsStore({String? dbPath}) : _dbPath = dbPath;

  final String? _dbPath;
  Database? _db;

  static const String createTableSql = '''
CREATE TABLE IF NOT EXISTS sms_entries (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  address TEXT NOT NULL,
  body TEXT NOT NULL,
  timestamp INTEGER NOT NULL,
  received_at INTEGER NOT NULL,
  forwarded INTEGER NOT NULL DEFAULT 0,
  UNIQUE(address, body, timestamp)
)
''';

  static const String _createSendersSql = '''
CREATE TABLE IF NOT EXISTS allowed_senders (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  number TEXT NOT NULL UNIQUE,
  created_at INTEGER NOT NULL
)
''';

  static const String _createSettingsSql = '''
CREATE TABLE IF NOT EXISTS app_settings (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL
)
''';

  Future<Database> init() async {
    final existing = _db;
    if (existing != null && existing.isOpen) return existing;
    final path = _dbPath ?? p.join(await getDatabasesPath(), 'sms.db');
    final db = await openDatabase(path, version: 1);
    await db.execute(createTableSql);
    await db.execute(_createSendersSql);
    await db.execute(_createSettingsSql);
    await _ensureColumns(db);
    _db = db;
    return db;
  }

  Future<void> _ensureColumns(Database db) async {
    final info = await db.rawQuery('PRAGMA table_info(sms_entries)');
    if (!info.any((row) => row['name'] == 'forwarded')) {
      await db.execute(
        'ALTER TABLE sms_entries ADD COLUMN forwarded INTEGER NOT NULL DEFAULT 0',
      );
    }
  }

  bool get isReady {
    final db = _db;
    return db != null && db.isOpen;
  }

  Database _requireDb() {
    final db = _db;
    if (db == null || !db.isOpen) {
      throw StateError('SmsStore.init() harus dipanggil dulu');
    }
    return db;
  }

  Future<void> insert(SmsEntry entry) {
    return _requireDb().insert(
      'sms_entries',
      entry.toMap(),
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  Future<void> insertAll(List<SmsEntry> entries) async {
    if (entries.isEmpty) return;
    final db = _requireDb();
    final batch = db.batch();
    for (final entry in entries) {
      batch.insert(
        'sms_entries',
        entry.toMap(),
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<List<SmsEntry>> getAll() async {
    final rows = await _requireDb().query(
      'sms_entries',
      orderBy: 'timestamp DESC, id DESC',
    );
    return rows.map(SmsEntry.fromMap).toList();
  }

  Future<int?> maxTimestamp() async {
    final rows = await _requireDb()
        .rawQuery('SELECT MAX(timestamp) AS max_ts FROM sms_entries');
    final value = rows.first['max_ts'];
    if (value == null) return null;
    return (value as num).toInt();
  }

  Future<void> deleteById(int id) {
    return _requireDb().delete(
      'sms_entries',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> clearAll() {
    return _requireDb().delete('sms_entries');
  }

  Future<int> count() async {
    final rows = await _requireDb().rawQuery('SELECT COUNT(*) AS n FROM sms_entries');
    return (rows.first['n'] as num?)?.toInt() ?? 0;
  }

  Future<List<AllowedSender>> getAllowedSenders() async {
    final rows = await _requireDb().query(
      'allowed_senders',
      orderBy: 'number ASC',
    );
    return rows.map(AllowedSender.fromMap).toList();
  }

  Future<bool> containsAllowedSender(String normalizedNumber) async {
    final rows = await _requireDb().query(
      'allowed_senders',
      where: 'number = ?',
      whereArgs: [normalizedNumber],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  Future<void> addAllowedSender(String normalizedNumber) async {
    await _requireDb().insert(
      'allowed_senders',
      {
        'number': normalizedNumber,
        'created_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  Future<void> removeAllowedSender(int id) {
    return _requireDb().delete(
      'allowed_senders',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<List<SmsEntry>> getUnforwarded() async {
    final rows = await _requireDb().query(
      'sms_entries',
      where: 'forwarded = 0',
      orderBy: 'timestamp ASC, id ASC',
    );
    return rows.map(SmsEntry.fromMap).toList();
  }

  Future<void> markForwarded(int id) async {
    await _requireDb().update(
      'sms_entries',
      {'forwarded': 1},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> countUnforwarded() async {
    final rows = await _requireDb().rawQuery(
      'SELECT COUNT(*) AS n FROM sms_entries WHERE forwarded = 0',
    );
    return (rows.first['n'] as num?)?.toInt() ?? 0;
  }

  Future<String?> getSetting(String key) async {
    final rows = await _requireDb().query(
      'app_settings',
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['value'] as String?;
  }

  Future<void> setSetting(String key, String value) async {
    await _requireDb().insert(
      'app_settings',
      {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }
}
