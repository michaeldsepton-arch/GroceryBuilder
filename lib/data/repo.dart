import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../models/models.dart';
import '../models/units.dart';
import 'db.dart';

enum SortMode { unitPrice, price, name }

class Repo {
  Repo(this.app);
  final AppDb app;
  Database get db => app.db;

  static const _itemSelect = '''SELECT i.*, m.favourite, m.aisle, m.spot, m.note,
      m.times_bought FROM items i LEFT JOIN item_meta m ON m.item_id = i.id''';

  // ---- stores ----
  Future<List<Store>> stores() async {
    final rows = await db.query('stores', orderBy: 'sort_order, name');
    return rows.map(Store.fromMap).toList();
  }

  Future<void> saveStore(Store s) =>
      db.insert('stores', s.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);

  // ---- items ----
  Future<List<Item>> search(String query,
      {Set<String> storeIds = const {}, bool customOnly = false, int limit = 300}) async {
    final where = <String>[];
    final args = <Object?>[];
    for (final tok in query.toLowerCase().split(RegExp(r'\s+')).where((t) => t.isNotEmpty)) {
      where.add("(LOWER(i.name) LIKE ? OR LOWER(i.brand) LIKE ? OR LOWER(i.category) LIKE ?)");
      args.addAll(['%$tok%', '%$tok%', '%$tok%']);
    }
    if (storeIds.isNotEmpty) {
      where.add('i.store_id IN (${List.filled(storeIds.length, '?').join(',')})');
      args.addAll(storeIds);
    }
    if (customOnly) where.add('i.custom = 1');
    final rows = await db.rawQuery(
        '$_itemSelect ${where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}'} LIMIT $limit', args);
    return rows.map(Item.fromMap).toList();
  }

  Future<Item?> item(String id) async {
    final rows = await db.rawQuery('$_itemSelect WHERE i.id = ?', [id]);
    return rows.isEmpty ? null : Item.fromMap(rows.first);
  }

  Future<List<Item>> favourites() async {
    final rows = await db.rawQuery(
        '$_itemSelect WHERE m.favourite = 1 ORDER BY m.times_bought DESC, i.name');
    return rows.map(Item.fromMap).toList();
  }

  Future<List<Item>> oftenBought() async {
    final rows = await db.rawQuery(
        '$_itemSelect WHERE m.times_bought > 0 AND IFNULL(m.favourite,0) = 0 '
        'ORDER BY m.times_bought DESC LIMIT 30');
    return rows.map(Item.fromMap).toList();
  }

  Future<void> saveCustomItem(Item it) =>
      db.insert('items', it.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);

  Future<void> deleteCustomItem(String id) async {
    await db.delete('items', where: 'id = ? AND custom = 1', whereArgs: [id]);
    await db.delete('cart', where: 'item_id = ?', whereArgs: [id]);
  }

  Future<int> catalogCount() async => Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM items WHERE custom = 0')) ??
      0;

  // ---- meta ----
  Future<void> updateMeta(String itemId,
      {bool? favourite, String? aisle, String? spot, String? note}) async {
    await db.insert('item_meta', {'item_id': itemId},
        conflictAlgorithm: ConflictAlgorithm.ignore);
    final vals = <String, Object?>{
      if (favourite != null) 'favourite': favourite ? 1 : 0,
      if (aisle != null) 'aisle': aisle,
      if (spot != null) 'spot': spot,
      if (note != null) 'note': note,
    };
    if (vals.isNotEmpty) {
      await db.update('item_meta', vals, where: 'item_id = ?', whereArgs: [itemId]);
    }
  }

  // ---- cart ----
  Future<List<CartLine>> cart() async {
    final rows = await db.rawQuery(
        'SELECT i.*, m.favourite, m.aisle, m.spot, m.note, m.times_bought, '
        'c.qty AS cart_qty, c.got AS cart_got FROM cart c '
        'JOIN items i ON i.id = c.item_id LEFT JOIN item_meta m ON m.item_id = i.id '
        'ORDER BY i.store_id, i.name');
    return rows
        .map((r) => CartLine(Item.fromMap(r), (r['cart_qty'] as num).toDouble(),
            (r['cart_got'] as int? ?? 0) == 1))
        .toList();
  }

  Future<void> setQty(String itemId, double qty) async {
    if (qty <= 0) {
      await db.delete('cart', where: 'item_id = ?', whereArgs: [itemId]);
    } else {
      await db.insert('cart', {'item_id': itemId, 'qty': qty},
          conflictAlgorithm: ConflictAlgorithm.ignore);
      await db.update('cart', {'qty': qty}, where: 'item_id = ?', whereArgs: [itemId]);
    }
  }

  Future<void> setGot(String itemId, bool got) => db.update(
      'cart', {'got': got ? 1 : 0}, where: 'item_id = ?', whereArgs: [itemId]);

  Future<void> clearCart() => db.delete('cart');

  /// Archive the cart as a finished trip and bump "times bought" counters.
  Future<void> completeTrip(List<CartLine> lines) async {
    if (lines.isEmpty) return;
    final sub = lines.fold<double>(0, (a, l) => a + l.cost);
    final tax = lines.fold<double>(0, (a, l) => a + l.tax);
    await db.transaction((t) async {
      await t.insert('trips', {
        'date': DateTime.now().toIso8601String(),
        'subtotal': sub,
        'tax': tax,
        'item_count': lines.length,
      });
      for (final l in lines) {
        await t.insert('item_meta', {'item_id': l.item.id},
            conflictAlgorithm: ConflictAlgorithm.ignore);
        await t.rawUpdate(
            'UPDATE item_meta SET times_bought = times_bought + 1 WHERE item_id = ?',
            [l.item.id]);
      }
      await t.delete('cart');
    });
  }

  Future<List<Trip>> trips({DateTime? since}) async {
    final rows = await db.query('trips',
        where: since == null ? null : 'date >= ?',
        whereArgs: since == null ? null : [since.toIso8601String()],
        orderBy: 'date DESC');
    return rows
        .map((r) => Trip(r['id'] as int, DateTime.parse(r['date'] as String),
            (r['subtotal'] as num).toDouble(), (r['tax'] as num).toDouble(),
            r['item_count'] as int))
        .toList();
  }

  // ---- settings / budget ----
  Future<String?> setting(String key) async {
    final r = await db.query('settings', where: 'key = ?', whereArgs: [key]);
    return r.isEmpty ? null : r.first['value'] as String?;
  }

  Future<void> putSetting(String key, String value) => db.insert(
      'settings', {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace);

  Future<double> budgetFor(String weekStart) async {
    final r = await db.query('budgets', where: 'week_start = ?', whereArgs: [weekStart]);
    if (r.isNotEmpty) return (r.first['amount'] as num).toDouble();
    return double.tryParse(await setting('default_budget') ?? '') ?? 100;
  }

  Future<void> setBudgetForWeek(String weekStart, double amount) => db.insert(
      'budgets', {'week_start': weekStart, 'amount': amount},
      conflictAlgorithm: ConflictAlgorithm.replace);

  // ---- catalog sync ----
  /// Replace the downloaded catalog, leaving personal items and notes alone.
  Future<int> applyCatalog(Map<String, dynamic> data) async {
    final stores = (data['stores'] as List?) ?? const [];
    final items = (data['items'] as List?) ?? const [];
    final stamp = data['generated'] as String?;
    await db.transaction((t) async {
      final b = t.batch();
      for (final s in stores.cast<Map<String, dynamic>>()) {
        b.rawInsert(
            'INSERT INTO stores(id,name,color,location,has_online,sort_order) '
            'VALUES(?,?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET '
            'name=excluded.name, location=excluded.location',
            [
              s['id'], s['name'], s['color'] ?? 0xFF1F4D3A, s['location'] ?? '',
              (s['online'] ?? true) == true ? 1 : 0, s['order'] ?? 50,
            ]);
      }
      b.delete('items', where: 'custom = 0');
      await b.commit(noResult: true);
      var batch = t.batch();
      var n = 0;
      for (final m in items.cast<Map<String, dynamic>>()) {
        final price = (m['price'] as num?)?.toDouble();
        if (price == null || m['id'] == null || m['name'] == null) continue;
        batch.insert(
            'items',
            {
              'id': m['id'],
              'store_id': m['store'],
              'name': m['name'],
              'brand': m['brand'] ?? '',
              'image_url': m['img'],
              'price': price,
              'was_price': (m['was'] as num?)?.toDouble(),
              'size_value': (m['size'] as num?)?.toDouble() ?? 1,
              'size_unit': m['unit'] ?? 'each',
              'variable': (m['variable'] ?? false) == true ? 1 : 0,
              'taxable': (m['taxable'] ?? false) == true ? 1 : 0,
              'category': m['cat'] ?? '',
              'url': m['url'],
              'custom': 0,
              'updated': stamp,
            },
            conflictAlgorithm: ConflictAlgorithm.replace);
        if (++n % 500 == 0) {
          await batch.commit(noResult: true);
          batch = t.batch();
        }
      }
      await batch.commit(noResult: true);
    });
    await putSetting('catalog_generated', stamp ?? '');
    return items.length;
  }

  // ---- backup ----
  Future<Map<String, Object?>> exportData() async => {
        'version': 1,
        'stores': await db.query('stores'),
        'custom_items': await db.query('items', where: 'custom = 1'),
        'item_meta': await db.query('item_meta'),
        'trips': await db.query('trips'),
        'settings': await db.query('settings'),
        'budgets': await db.query('budgets'),
      };

  Future<void> importData(Map<String, dynamic> d) async {
    await db.transaction((t) async {
      Future<void> load(String table, String key, {String? clear}) async {
        if (clear != null) await t.delete(table, where: clear);
        for (final r in (d[key] as List? ?? const []).cast<Map<String, dynamic>>()) {
          await t.insert(table, r, conflictAlgorithm: ConflictAlgorithm.replace);
        }
      }

      await load('stores', 'stores');
      await load('items', 'custom_items', clear: 'custom = 1');
      await load('item_meta', 'item_meta');
      await load('trips', 'trips');
      await load('settings', 'settings');
      await load('budgets', 'budgets');
    });
  }

  String encode(Object o) => const JsonEncoder().convert(o);
}

/// Sort helper: cheapest comparable unit price first, grouped by unit kind.
int compareItems(Item a, Item b, SortMode mode) {
  switch (mode) {
    case SortMode.price:
      return a.price.compareTo(b.price);
    case SortMode.name:
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    case SortMode.unitPrice:
      final ka = a.unitPrice.kind.index, kb = b.unitPrice.kind.index;
      if (ka != kb) return ka.compareTo(kb);
      return a.unitPrice.compareValue.compareTo(b.unitPrice.compareValue);
  }
}

const unitKindLabel = {
  UnitKind.weight: 'per 100g',
  UnitKind.volume: 'per 100mL',
  UnitKind.each: 'each',
};
