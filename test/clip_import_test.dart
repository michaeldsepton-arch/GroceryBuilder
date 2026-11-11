import 'dart:convert';
import 'dart:io';

import 'package:budget_basket/data/clip_import.dart';
import 'package:budget_basket/data/db.dart';
import 'package:budget_basket/data/repo.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Repo repo;

  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final db = await AppDb.open(path: '${Directory.systemTemp.createTempSync('bb_clip').path}/t.db');
    repo = Repo(db);
    await repo.applyCatalog({
      'generated': '2026-11-01T00:00:00Z',
      'stores': [],
      'items': [
        {'id': 'superstore:111', 'store': 'superstore', 'name': 'Basmati Rice', 'price': 11.99, 'size': 4, 'unit': 'kg'},
      ],
    });
  });

  Map<String, dynamic> file() => {
        'type': 'budget-basket-items',
        'version': 1,
        'stores': [
          {'id': 'costco', 'name': 'Costco', 'color': 0xFF005DAA}
        ],
        'items': [
          {'id': 'costco:/p/abc-123', 'store': 'costco', 'name': 'Kirkland Olive Oil 2 L', 'price': 21.99, 'size': 2, 'unit': 'l', 'brand': 'Kirkland'},
          {'id': 'superstore:111', 'store': 'superstore', 'name': 'Basmati Rice', 'price': 12.49, 'size': 4, 'unit': 'kg'},
          {'id': 'walmart:9', 'store': 'walmart', 'name': 'Something', 'price': 0},
        ],
      };

  test('adds new items and stores, leaves existing ones alone, reports what it did', () async {
    final r = await ClipImport.importBytes(repo, utf8.encode(jsonEncode(file())));
    expect([r.added, r.duplicates, r.skipped], [1, 1, 1]);
    final stores = await repo.stores();
    expect(stores.map((s) => s.id), contains('costco'));
    final added = await repo.item('clip:costco:/p/abc-123');
    expect(added, isNotNull);
    expect(added!.custom, isTrue);
    // the store's own item was not touched (price still 11.99, still not a custom item)
    final rice = (await repo.item('superstore:111'))!;
    expect(rice.price, 11.99);
    expect(rice.custom, isFalse);
  });

  test('sending the same file again changes nothing', () async {
    await ClipImport.importBytes(repo, utf8.encode(jsonEncode(file())));
    final again = await ClipImport.importBytes(repo, gzip.encode(utf8.encode(jsonEncode(file()))));
    expect(again.added, 0);
    expect(again.duplicates, 2);
    expect((await repo.search('olive')).length, 1);
  });

  test('a price refresh keeps added items', () async {
    await ClipImport.importBytes(repo, utf8.encode(jsonEncode(file())));
    await repo.applyCatalog({'generated': '2026-11-02T00:00:00Z', 'stores': [], 'items': []});
    expect(await repo.item('clip:costco:/p/abc-123'), isNotNull);
  });

  test('a file that is not ours is refused', () async {
    expect(() => ClipImport.importBytes(repo, utf8.encode('hello')), throwsFormatException);
  });
}
