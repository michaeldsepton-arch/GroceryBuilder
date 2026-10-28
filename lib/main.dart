import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'data/db.dart';
import 'data/repo.dart';
import 'screens/cart_screen.dart';
import 'screens/frequent_screen.dart';
import 'screens/my_items_screen.dart';
import 'screens/search_screen.dart';
import 'screens/settings_screen.dart';
import 'state/app_state.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final db = await AppDb.open();
  final state = AppState(Repo(db));
  await state.init();
  runApp(ChangeNotifierProvider.value(value: state, child: const BudgetBasketApp()));
}

class BudgetBasketApp extends StatelessWidget {
  const BudgetBasketApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Budget Basket',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        home: const Shell(),
      );
}

class Shell extends StatefulWidget {
  const Shell({super.key});
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int tab = 0;
  static const pages = [
    SearchScreen(),
    CartScreen(),
    FrequentScreen(),
    MyItemsScreen(),
    SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    return Scaffold(
      body: IndexedStack(index: tab, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (i) => setState(() => tab = i),
        destinations: [
          const NavigationDestination(icon: Icon(Icons.search), label: 'Search'),
          NavigationDestination(
            icon: Badge(
                isLabelVisible: s.cartCount > 0,
                label: Text('${s.cartCount}'),
                child: const Icon(Icons.shopping_cart_outlined)),
            label: 'Cart',
          ),
          const NavigationDestination(icon: Icon(Icons.favorite_border), label: 'Frequent'),
          const NavigationDestination(icon: Icon(Icons.add_a_photo_outlined), label: 'Add'),
          NavigationDestination(
            icon: Badge(
                isLabelVisible: s.update != null,
                smallSize: 9,
                child: const Icon(Icons.more_horiz)),
            label: 'More',
          ),
        ],
      ),
    );
  }
}
