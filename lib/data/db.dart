import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models/models.dart';

/// Stores shipped with the app. Colours come from the Budget Basket palette
/// family; ids are stable so catalog data and personal data keep matching.
final List<Store> seedStores = [
  Store(id: 'superstore', name: 'Real Canadian Superstore', color: 0xFFD9232D, location: 'Red Deer', sortOrder: 1),
  Store(id: 'walmart', name: 'Walmart', color: 0xFF0071CE, location: 'Red Deer (Blackfalds side)', sortOrder: 2),
  Store(id: 'freshco', name: 'FreshCo', color: 0xFF2E8B3D, location: 'Red Deer', sortOrder: 3),
  Store(id: 'wholesaleclub', name: 'Wholesale Club', color: 0xFFE8731A, location: 'Red Deer', sortOrder: 4),
  Store(id: 'shoppers', name: 'Shoppers Drug Mart', color: 0xFFC8102E, location: 'Clearview', hasOnline: true, sortOrder: 5),
  Store(id: 'dollarama', name: 'Dollarama', color: 0xFF0B8A3E, location: 'Clearview & beside Superstore', hasOnline: false, sortOrder: 6),
  Store(id: 'halal', name: 'Red Deer Halal Meat & Asian Food', color: 0xFF7A1F2B, location: 'Red Deer', hasOnline: false, sortOrder: 7),
];

class AppDb {
  AppDb._(this.db);
  final Database db;

  static Future<AppDb> open({String? path}) async {
    path ??= p.join(await getDatabasesPath(), 'budget_basket.db');
    final db = await openDatabase(path, version: 3, onCreate: _create, onUpgrade: _upgrade);
    final app = AppDb._(db);
    await app._seedStores();
    return app;
  }

  static Future<void> _recipeTables(Database db) async {
    await db.execute('''CREATE TABLE IF NOT EXISTS user_recipes(
      id TEXT PRIMARY KEY, json TEXT NOT NULL, created TEXT)''');
    await db.execute('''CREATE TABLE IF NOT EXISTS recipe_meta(
      recipe_id TEXT PRIMARY KEY, favourite INTEGER DEFAULT 0, cooked INTEGER DEFAULT 0)''');
  }

  static Future<void> _historyTable(Database db) async {
    await db.execute('''CREATE TABLE IF NOT EXISTS price_history(
      item_id TEXT NOT NULL, price REAL NOT NULL, was_price REAL, seen TEXT NOT NULL,
      PRIMARY KEY(item_id, seen))''');
  }

  static Future<void> _upgrade(Database db, int from, int to) async {
    if (from < 2) await _recipeTables(db);
    if (from < 3) await _historyTable(db);
  }

  static Future<void> _create(Database db, int v) async {
    await _recipeTables(db);
    await _historyTable(db);
    await db.execute('''CREATE TABLE stores(
      id TEXT PRIMARY KEY, name TEXT NOT NULL, color INTEGER NOT NULL,
      location TEXT, has_online INTEGER DEFAULT 1, sort_order INTEGER DEFAULT 0)''');
    await db.execute('''CREATE TABLE items(
      id TEXT PRIMARY KEY, store_id TEXT NOT NULL, name TEXT NOT NULL,
      brand TEXT, image_url TEXT, photo_path TEXT, price REAL NOT NULL,
      was_price REAL, size_value REAL, size_unit TEXT, variable INTEGER DEFAULT 0,
      taxable INTEGER DEFAULT 0, category TEXT, url TEXT,
      custom INTEGER DEFAULT 0, updated TEXT)''');
    await db.execute('CREATE INDEX idx_items_store ON items(store_id)');
    await db.execute('CREATE INDEX idx_items_custom ON items(custom)');
    await db.execute('''CREATE TABLE item_meta(
      item_id TEXT PRIMARY KEY, favourite INTEGER DEFAULT 0,
      aisle TEXT DEFAULT '', spot TEXT DEFAULT '', note TEXT DEFAULT '',
      times_bought INTEGER DEFAULT 0)''');
    await db.execute('''CREATE TABLE cart(
      item_id TEXT PRIMARY KEY, qty REAL NOT NULL, got INTEGER DEFAULT 0)''');
    await db.execute('''CREATE TABLE trips(
      id INTEGER PRIMARY KEY AUTOINCREMENT, date TEXT NOT NULL,
      subtotal REAL, tax REAL, item_count INTEGER)''');
    await db.execute('CREATE TABLE settings(key TEXT PRIMARY KEY, value TEXT)');
    await db.execute(
        'CREATE TABLE budgets(week_start TEXT PRIMARY KEY, amount REAL NOT NULL)');
  }

  Future<void> _seedStores() async {
    final batch = db.batch();
    for (final s in seedStores) {
      batch.insert('stores', s.toMap(), conflictAlgorithm: ConflictAlgorithm.ignore);
    }
    await batch.commit(noResult: true);
  }
}
