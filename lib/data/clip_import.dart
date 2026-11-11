import 'dart:convert';
import 'dart:io';

import 'package:sqflite/sqflite.dart';

import '../models/models.dart';
import '../models/units.dart';
import 'repo.dart';
import 'tax.dart';

class ClipResult {
  ClipResult(this.added, this.duplicates, this.skipped);
  final int added, duplicates, skipped;

  String get message {
    if (added == 0 && duplicates == 0 && skipped == 0) return 'No items found in that file';
    final parts = <String>[
      if (added > 0) '$added added' else 'Nothing new',
      if (duplicates > 0) '$duplicates already in the app',
      if (skipped > 0) '$skipped could not be read',
    ];
    return parts.join(' · ');
  }
}

/// Adds items saved by the Budget Basket phone extension ("Add to app"). Only ever adds: an item
/// that is already there (same id, or same store, name and size) is left exactly as it is, and
/// nothing in the app is changed or removed. Added items are kept like items made by hand, so a
/// price refresh never replaces or drops them.
class ClipImport {
  static const _palette = [0xFF6B4FA0, 0xFF1F7A8C, 0xFFB5651D, 0xFF4A6FA5, 0xFF8C3B5E];

  /// [bytes] is the file as saved by the extension (JSON, or gzip of it).
  static Future<ClipResult> importBytes(Repo repo, List<int> bytes) async {
    final raw = bytes.length > 2 && bytes[0] == 0x1f && bytes[1] == 0x8b ? gzip.decode(bytes) : bytes;
    final Map<String, dynamic> data;
    try {
      data = jsonDecode(utf8.decode(raw)) as Map<String, dynamic>;
    } catch (_) {
      throw const FormatException('That is not a Budget Basket items file');
    }
    if (data['type'] != 'budget-basket-items' && data['items'] is! List) {
      throw const FormatException('That is not a Budget Basket items file');
    }
    return importData(repo, data);
  }

  static Future<ClipResult> importData(Repo repo, Map<String, dynamic> data) async {
    final db = repo.db;
    var added = 0, dup = 0, skipped = 0;
    final stores = {
      for (final s in (data['stores'] as List? ?? const []).cast<Map<String, dynamic>>()) '${s['id']}': s,
    };
    await db.transaction((t) async {
      final haveStore = {for (final r in await t.query('stores', columns: ['id'])) r['id'] as String};
      var nextOrder = 100 + haveStore.length;
      for (final m in (data['items'] as List? ?? const []).cast<Map<String, dynamic>>()) {
        final store = '${m['store'] ?? ''}'.trim();
        final name = '${m['name'] ?? ''}'.replaceAll(RegExp(r'\s+'), ' ').trim();
        final price = (m['price'] as num?)?.toDouble();
        final pid = '${m['id'] ?? ''}'.trim();
        if (store.isEmpty || name.isEmpty || price == null || price <= 0 || price > 5000 || pid.isEmpty) {
          skipped++;
          continue;
        }
        final id = pid.startsWith('clip:') ? pid : 'clip:$pid';
        final size = (m['size'] as num?)?.toDouble() ?? 1;
        final unit = Unit.parse(m['unit'] as String?);

        // already added before?
        final same = await t.query('items', columns: ['id'], where: 'id = ?', whereArgs: [id], limit: 1);
        if (same.isNotEmpty) {
          dup++;
          continue;
        }
        // same product already there under the store's own listing (and showing)?
        final twin = await t.rawQuery(
            'SELECT id FROM items WHERE store_id = ? AND LOWER(name) = ? AND size_value = ? AND size_unit = ? '
            'AND (custom = 1 OR (typical = 1 AND sane = 1)) LIMIT 1',
            [store, name.toLowerCase(), size, unit.name]);
        final catalogTwin = await t.rawQuery(
            'SELECT id FROM items WHERE id = ? AND custom = 0 AND typical = 1 AND sane = 1 LIMIT 1', [pid]);
        if (twin.isNotEmpty || catalogTwin.isNotEmpty) {
          dup++;
          continue;
        }

        if (!haveStore.contains(store)) {
          final s = stores[store];
          await t.insert(
              'stores',
              {
                'id': store,
                'name': '${s?['name'] ?? store}',
                'color': (s?['color'] as num?)?.toInt() ?? _palette[haveStore.length % _palette.length],
                'location': '${s?['location'] ?? ''}',
                'has_online': 1,
                'sort_order': nextOrder++,
              },
              conflictAlgorithm: ConflictAlgorithm.ignore);
          haveStore.add(store);
        }
        final was = (m['was'] as num?)?.toDouble();
        final item = Item(
          id: id,
          storeId: store,
          name: name,
          brand: '${m['brand'] ?? ''}',
          imageUrl: (m['img'] as String?)?.isEmpty ?? true ? null : m['img'] as String,
          price: price,
          wasPrice: was != null && was > price ? was : null,
          sizeValue: size <= 0 ? 1 : size,
          sizeUnit: unit,
          variable: (m['variable'] ?? false) == true,
          taxable: Tax.isTaxable(name, '${m['brand'] ?? ''}', '${m['cat'] ?? ''}', fallback: (m['taxable'] ?? false) == true),
          category: '${m['cat'] ?? ''}',
          url: m['url'] as String?,
          custom: true,
          updated: DateTime.now().toIso8601String(),
        );
        await t.insert('items', item.toMap(), conflictAlgorithm: ConflictAlgorithm.ignore);
        added++;
      }
    });
    return ClipResult(added, dup, skipped);
  }
}
