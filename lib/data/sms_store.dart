import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

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
  UNIQUE(address, body, timestamp)
)
''';

  Future<Database> init() async {
    final existing = _db;
    if (existing != null && existing.isOpen) return existing;
    final path = _dbPath ?? p.join(await getDatabasesPath(), 'sms.db');
    final db = await openDatabase(path, version: 1);
    await db.execute(createTableSql);
    _db = db;
    return db;
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

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }
}
