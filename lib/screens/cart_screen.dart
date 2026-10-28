import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../models/units.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/item_widgets.dart';

class CartScreen extends StatelessWidget {
  const CartScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final byStore = <String, List<CartLine>>{};
    for (final l in s.cart) {
      byStore.putIfAbsent(l.item.storeId, () => []).add(l);
    }
    return SafeArea(
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Row(children: [
            Text('My cart', style: serif(28)),
            const Spacer(),
            if (s.cart.isNotEmpty)
              IconButton(
                tooltip: 'Clear cart',
                icon: const Icon(Icons.delete_sweep_outlined),
                onPressed: () async {
                  final ok = await _confirm(context, 'Clear the whole cart?');
                  if (ok) s.clearCart();
                },
              ),
          ]),
        ),
        Padding(padding: const EdgeInsets.all(16), child: BudgetBar()),
        Expanded(
          child: s.cart.isEmpty
              ? Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.shopping_cart_outlined, size: 56, color: BB.green500),
                  const SizedBox(height: 10),
                  Text('Your cart is empty', style: serif(20)),
                  const Text('Search for items and tap Add',
                      style: TextStyle(color: BB.muted)),
                ]))
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  children: [
                    for (final e in byStore.entries) ...[
                      _StoreHeader(s.storeById(e.key), e.value),
                      for (final l in e.value) _CartRow(l),
                      const SizedBox(height: 12),
                    ],
                    _Totals(s),
                  ],
                ),
        ),
        if (s.cart.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const ShopModeScreen())),
                  icon: const Icon(Icons.checklist),
                  label: const Text('Shop mode'),
                  style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: () async {
                    final ok = await _confirm(context,
                        'Finish this trip? ${money(s.cartTotal)} will count toward this week.');
                    if (ok) s.finishTrip();
                  },
                  icon: const Icon(Icons.check_circle_outline),
                  label: const Text('Finish trip'),
                ),
              ),
            ]),
          ),
      ]),
    );
  }
}

Future<bool> _confirm(BuildContext context, String msg) async =>
    (await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        content: Text(msg),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('No')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Yes')),
        ],
      ),
    )) ??
    false;

class _StoreHeader extends StatelessWidget {
  const _StoreHeader(this.store, this.lines);
  final Store store;
  final List<CartLine> lines;
  @override
  Widget build(BuildContext context) {
    final sub = lines.fold<double>(0, (a, l) => a + l.cost + l.tax);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, top: 4),
      child: Row(children: [
        Container(width: 10, height: 10,
            decoration: BoxDecoration(color: Color(store.color), shape: BoxShape.circle)),
        const SizedBox(width: 8),
        Expanded(child: Text(store.name, style: serif(18))),
        Text(money(sub), style: const TextStyle(fontWeight: FontWeight.w800)),
      ]),
    );
  }
}

class _CartRow extends StatelessWidget {
  const _CartRow(this.line);
  final CartLine line;
  @override
  Widget build(BuildContext context) {
    final s = context.read<AppState>();
    final i = line.item;
    return Dismissible(
      key: ValueKey(i.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(color: BB.tomato, borderRadius: BorderRadius.circular(20)),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      onDismissed: (_) => s.setQty(i, 0),
      child: Card(
        margin: const EdgeInsets.only(bottom: 8),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => showItemSheet(context, i),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(children: [
              ItemImage(i, size: 60, radius: 12),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(i.name, maxLines: 2, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  Text('${money(i.price)} ${i.variable ? '/ ${sizeBoth(i.sizeValue, i.sizeUnit)}' : 'each'}'
                      '${i.taxable ? ' · +GST' : ''}',
                      style: const TextStyle(color: BB.muted, fontSize: 12)),
                  const SizedBox(height: 4),
                  CartControl(i),
                ]),
              ),
              Text(money(line.cost), style: serif(18)),
            ]),
          ),
        ),
      ),
    );
  }
}

class _Totals extends StatelessWidget {
  const _Totals(this.s);
  final AppState s;
  @override
  Widget build(BuildContext context) {
    Widget row(String a, String b, {bool bold = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(children: [
            Text(a, style: TextStyle(fontWeight: bold ? FontWeight.w800 : FontWeight.w500)),
            const Spacer(),
            Text(b, style: bold ? serif(22) : const TextStyle(fontWeight: FontWeight.w600)),
          ]),
        );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          row('Subtotal', money(s.subtotal)),
          row('GST (5%, taxable items only)', money(s.tax)),
          const Divider(),
          row('Total', money(s.cartTotal), bold: true),
          row(s.remaining < 0 ? 'Over budget by' : 'Left this week', money(s.remaining.abs()), bold: true),
        ]),
      ),
    );
  }
}

/// In-store checklist: cart items per store, ordered by aisle.
class ShopModeScreen extends StatelessWidget {
  const ShopModeScreen({super.key});

  static int _aisleOrder(String a) =>
      int.tryParse(RegExp(r'\d+').firstMatch(a)?.group(0) ?? '') ?? 9999;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final byStore = <String, List<CartLine>>{};
    for (final l in s.cart) {
      byStore.putIfAbsent(l.item.storeId, () => []).add(l);
    }
    final done = s.cart.where((l) => l.got).length;
    return Scaffold(
      appBar: AppBar(title: Text('Shop mode · $done/${s.cart.length}')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          for (final e in byStore.entries) ...[
            Text(s.storeById(e.key).name, style: serif(20)),
            const SizedBox(height: 8),
            for (final l in (e.value
              ..sort((a, b) {
                final c = _aisleOrder(a.item.aisle).compareTo(_aisleOrder(b.item.aisle));
                return c != 0 ? c : a.item.name.compareTo(b.item.name);
              })))
              Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: CheckboxListTile(
                  value: l.got,
                  onChanged: (_) => s.toggleGot(l),
                  controlAffinity: ListTileControlAffinity.leading,
                  title: Text(l.item.name,
                      style: TextStyle(
                          fontWeight: FontWeight.w700,
                          decoration: l.got ? TextDecoration.lineThrough : null)),
                  subtitle: Text([
                    if (l.item.aisle.isNotEmpty) 'Aisle ${l.item.aisle}' else 'No aisle set',
                    if (l.item.spot.isNotEmpty) l.item.spot,
                    l.item.variable ? sizeBoth(l.qty, Unit.g) : '× ${l.qty.toStringAsFixed(0)}',
                  ].join(' · ')),
                  secondary: ItemImage(l.item, size: 48, radius: 10),
                ),
              ),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}
