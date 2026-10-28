import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../data/repo.dart';
import '../data/services.dart';
import '../models/models.dart';
import '../models/units.dart';

DateTime weekStartOf(DateTime d) {
  final day = DateTime(d.year, d.month, d.day);
  return day.subtract(Duration(days: day.weekday - 1)); // Monday
}

String weekKey(DateTime d) {
  final w = weekStartOf(d);
  return '${w.year}-${w.month.toString().padLeft(2, '0')}-${w.day.toString().padLeft(2, '0')}';
}

class AppState extends ChangeNotifier {
  AppState(this.repo);
  final Repo repo;

  List<Store> stores = [];
  List<CartLine> cart = [];
  double weekBudget = 100;
  double spentEarlierThisWeek = 0;
  String? catalogStamp;
  int catalogCount = 0;
  bool syncing = false;
  String? syncError;
  UpdateInfo? update;
  late String photoDir;
  int revision = 0;

  @override
  void notifyListeners() {
    revision++;
    super.notifyListeners();
  }

  Store storeById(String id) => stores.firstWhere((s) => s.id == id,
      orElse: () => Store(id: id, name: id, color: 0xFF1F4D3A));

  double get subtotal => cart.fold(0, (a, l) => a + l.cost);
  double get tax => cart.fold(0, (a, l) => a + l.tax);
  double get cartTotal => subtotal + tax;
  double get spentThisWeek => spentEarlierThisWeek + cartTotal;
  double get remaining => weekBudget - spentThisWeek;
  int get cartCount => cart.length;

  double qtyOf(String itemId) {
    for (final l in cart) {
      if (l.item.id == itemId) return l.qty;
    }
    return 0;
  }

  Future<void> init() async {
    final docs = await getApplicationDocumentsDirectory();
    photoDir = p.join(docs.path, 'photos');
    await Directory(photoDir).create(recursive: true);
    await _seedHalal();
    await reload();
    // Background refresh; failures are silent, the UI shows the last data.
    syncCatalog(silent: true);
    checkForUpdate(silent: true);
  }

  /// One-time: add the halal market meats read from the in-store price board.
  Future<void> _seedHalal() async {
    if (await repo.setting('seed_halal_v1') != null) return;
    final seed = jsonDecode(await rootBundle.loadString('assets/seed/halal.json'))
        as Map<String, dynamic>;
    for (final m in (seed['items'] as List).cast<Map<String, dynamic>>()) {
      final id = 'seed:halal:${m['id']}';
      await repo.saveCustomItem(Item(
        id: id,
        storeId: seed['store'] as String,
        name: m['name'] as String,
        price: (m['price'] as num).toDouble(),
        photoPath: 'asset:assets/seed/images/${m['id']}.jpg',
        sizeValue: 1,
        sizeUnit: Unit.lb,
        variable: true,
        category: 'Meat & seafood',
        custom: true,
        updated: DateTime.now().toIso8601String(),
      ));
      await repo.updateMeta(id, spot: 'Meat counter');
    }
    await repo.putSetting('seed_halal_v1', '1');
  }

  Future<void> reload() async {
    stores = await repo.stores();
    cart = await repo.cart();
    final wk = weekKey(DateTime.now());
    weekBudget = await repo.budgetFor(wk);
    final trips = await repo.trips(since: weekStartOf(DateTime.now()));
    spentEarlierThisWeek = trips.fold(0, (a, t) => a + t.total);
    catalogStamp = await repo.setting('catalog_generated');
    catalogCount = await repo.catalogCount();
    notifyListeners();
  }

  Future<void> setBudget(double v) async {
    await repo.setBudgetForWeek(weekKey(DateTime.now()), v);
    await repo.putSetting('default_budget', v.toString());
    await reload();
  }

  Future<void> setQty(Item item, double qty) async {
    await repo.setQty(item.id, qty);
    cart = await repo.cart();
    notifyListeners();
  }

  Future<void> add(Item item) async {
    final cur = qtyOf(item.id);
    // Weight items start at 1 lb.
    await setQty(item, cur > 0 ? cur + (item.variable ? gramsPerLb / 2 : 1) : (item.variable ? gramsPerLb : 1));
  }

  Future<void> toggleGot(CartLine l) async {
    await repo.setGot(l.item.id, !l.got);
    cart = await repo.cart();
    notifyListeners();
  }

  Future<void> clearCart() async {
    await repo.clearCart();
    await reload();
  }

  Future<void> finishTrip() async {
    await repo.completeTrip(cart);
    await reload();
  }

  Future<void> setFavourite(Item i, bool v) async {
    await repo.updateMeta(i.id, favourite: v);
    notifyListeners();
  }

  Future<void> saveMeta(Item i, {String? aisle, String? spot, String? note}) async {
    await repo.updateMeta(i.id, aisle: aisle, spot: spot, note: note);
    cart = await repo.cart();
    notifyListeners();
  }

  Future<void> syncCatalog({bool silent = false}) async {
    syncing = true;
    syncError = null;
    if (!silent) notifyListeners();
    try {
      final data = await CatalogService.download();
      if (data == null) {
        syncError = 'No catalog published yet';
      } else if (data['generated'] != catalogStamp || catalogCount == 0) {
        await repo.applyCatalog(data);
      }
    } catch (e) {
      syncError = 'Could not refresh prices ($e)';
    }
    syncing = false;
    await reload();
  }

  Future<void> checkForUpdate({bool silent = false}) async {
    try {
      update = await UpdateService.check();
    } catch (e) {
      if (!silent) rethrow;
    }
    notifyListeners();
  }

  /// Bumps listeners after items/stores were edited elsewhere.
  void touch() => notifyListeners();
}
