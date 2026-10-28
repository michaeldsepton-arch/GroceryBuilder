import 'dart:io';

import 'package:budget_basket/data/db.dart';
import 'package:budget_basket/data/repo.dart';
import 'package:budget_basket/main.dart';
import 'package:budget_basket/widgets/common.dart';
import 'package:budget_basket/state/app_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<AppState> _boot() async {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  final db = await AppDb.open(path: inMemoryDatabasePath);
  final state = AppState(Repo(db));
  final tmp = Directory.systemTemp.createTempSync('bb_photos').path;
  await state.init(photoDirOverride: tmp, background: false);
  await state.repo.applyCatalog({
    'generated': '2026-10-28T00:00:00Z',
    'stores': [],
    'items': [
      {'id': 'superstore:1', 'store': 'superstore', 'name': 'Basmati Rice 4kg', 'price': 11.99, 'size': 4, 'unit': 'kg', 'cat': 'Pantry'},
      {'id': 'walmart:2', 'store': 'walmart', 'name': 'Basmati Rice 2kg', 'price': 7.49, 'was': 8.99, 'size': 2, 'unit': 'kg'},
      {'id': 'walmart:3', 'store': 'walmart', 'name': 'Pork Chops Family Pack', 'price': 14.0, 'size': 1, 'unit': 'kg'},
      {'id': 'superstore:4', 'store': 'superstore', 'name': 'Chicken Thighs Bone-in', 'price': 9.0, 'size': 1, 'unit': 'kg', 'cat': 'Meat'},
      {'id': 'superstore:5', 'store': 'superstore', 'name': 'Plain Yogurt 750g', 'price': 3.99, 'size': 750, 'unit': 'g'},
      {'id': 'walmart:6', 'store': 'walmart', 'name': 'Red Wine Vinegar 500ml', 'price': 3.5, 'size': 500, 'unit': 'ml'},
      {'id': 'walmart:7', 'store': 'walmart', 'name': 'Merlot Red Wine 750ml', 'price': 15.0, 'size': 750, 'unit': 'ml'},
    ],
  });
  await state.reload();
  return state;
}

/// sqflite_ffi answers in real time, outside the test's fake clock.
Future<void> settle(WidgetTester tester) async {
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 400)));
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  late AppState state;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    ImagePolicy.network = false;
    // Network images (CI adds web photos to recipes) use the image cache, which asks for a temp dir.
    final tmp = Directory.systemTemp.createTempSync('bb_cache').path;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'), (call) async => tmp);
    PackageInfo.setMockInitialValues(
        appName: 'Budget Basket', packageName: 'ca.budgetbasket.app', version: '1.0.0', buildNumber: '1',
        buildSignature: '');
    // Real Roboto so text widths match a phone (tests default to a huge box font).
    final root = Platform.environment['FLUTTER_ROOT'] ?? '/opt/fl/flutter';
    final f = File('$root/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf');
    if (f.existsSync()) {
      final loader = FontLoader('Roboto')..addFont(Future.value(ByteData.sublistView(f.readAsBytesSync())));
      await loader.load();
    }
    state = await _boot();
  });

  test('catalog drops pork and alcohol; halal-only hides supermarket chicken', () async {
    final rice = await state.repo.search('rice');
    expect(rice.length, 2);
    expect(await state.repo.search('pork'), isEmpty);
    expect(await state.repo.search('merlot'), isEmpty);
    expect((await state.repo.search('vinegar')).length, 1); // wine vinegar is fine
    expect((await state.repo.search('yogurts')).length, 1); // plural finds singular
    expect(singular('berries'), 'berry');
    expect(singular('tomatoes'), 'tomato');
    expect(singular('rice'), 'rice');
    expect((await state.repo.search('chicken')).where((i) => i.storeId == 'superstore'), isEmpty); // not halal-certified
    state.repo.halalMeatOnly = false;
    expect((await state.repo.search('chicken')).where((i) => i.storeId == 'superstore').length, 1);
    state.repo.halalMeatOnly = true;
    // the halal market's own chicken thighs (seeded, priced per lb) stay visible
    final seeded = await state.repo.search('chicken thighs');
    expect(seeded.map((i) => i.storeId), ['halal']);
    expect(seeded.single.variable, isTrue);
  });

  test('recipes load, none contain haram text, suggestions come from the catalog', () async {
    expect(state.recipes.all.length, greaterThan(80));
    final r = state.recipes.all.firstWhere((r) => r.title == 'Chicken Biryani');
    expect(r.ingredients, isNotEmpty);
    final rice = await state.recipes.suggest('basmati rice');
    expect(rice, isNotNull);
    expect(rice!.id, 'superstore:1'); // 4 kg bag: \$0.30/100g beats 2 kg: \$0.37/100g
    final subs = state.recipes.substitutesFor(r.ingredients.firstWhere((i) => i.name.contains('yogurt')));
    expect(subs, isNotEmpty);
  });

  testWidgets('app shell, search, recipes and recipe detail render without errors', (tester) async {
    tester.view.physicalSize = const Size(1080, 2200);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ChangeNotifierProvider.value(value: state, child: const BudgetBasketApp()));
    await tester.pumpAndSettle(const Duration(milliseconds: 300));
    expect(find.text('Budget Basket'), findsWidgets);

    await tester.enterText(find.byType(TextField).first, 'rice');
    await tester.pump(const Duration(milliseconds: 300));
    await settle(tester);
    expect(find.textContaining('Basmati Rice'), findsWidgets);

    await tester.tap(find.text('Recipes'));
    await tester.pumpAndSettle();
    // recipes grid is lazy: search so the card is on screen
    await tester.enterText(find.byType(TextField).last, 'biryani');
    await tester.pumpAndSettle();
    expect(find.text('Chicken Biryani'), findsOneWidget);
    await tester.tap(find.text('Chicken Biryani'));
    await tester.pump(const Duration(milliseconds: 500)); // progress bars animate until suggestions load
    await settle(tester);
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Ingredients'), findsOneWidget);
    expect(find.text('Substitute'), findsWidgets);
    expect(find.text('Browse options'), findsWidgets);

    await tester.scrollUntilVisible(find.text('Browse options').first, 200, scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Browse options').first);
    await tester.pump(const Duration(milliseconds: 500));
    await settle(tester);
    expect(find.textContaining('options'), findsWidgets);
  });
}
