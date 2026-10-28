import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../models/units.dart';
import '../state/app_state.dart';
import '../theme.dart';

/// Tests switch web images off so the image cache never starts timers.
class ImagePolicy {
  static bool network = true;
}

class ItemImage extends StatelessWidget {
  const ItemImage(this.item, {super.key, this.size = 76, this.radius = 16});
  final Item item;
  final double size;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final fallback = Container(
      width: size,
      height: size,
      color: BB.green100,
      child: Icon(Icons.shopping_basket_outlined,
          color: BB.green500, size: size * 0.42),
    );
    Widget child = fallback;
    if (item.photoPath != null && item.photoPath!.startsWith('asset:')) {
      child = Image.asset(item.photoPath!.substring(6), width: size, height: size,
          fit: BoxFit.cover, errorBuilder: (_, _, _) => fallback);
    } else if (item.photoPath != null && item.photoPath!.isNotEmpty) {
      final f = File('${context.read<AppState>().photoDir}/${item.photoPath}');
      child = Image.file(f, width: size, height: size, fit: BoxFit.cover,
          errorBuilder: (_, _, _) => fallback);
    } else if (ImagePolicy.network && item.imageUrl != null && item.imageUrl!.isNotEmpty) {
      child = CachedNetworkImage(
        imageUrl: item.imageUrl!,
        width: size,
        height: size,
        fit: BoxFit.cover,
        placeholder: (_, _) => fallback,
        errorWidget: (_, _, _) => fallback,
      );
    }
    return ClipRRect(borderRadius: BorderRadius.circular(radius), child: child);
  }
}

class StoreTag extends StatelessWidget {
  const StoreTag(this.store, {super.key});
  final Store store;

  @override
  Widget build(BuildContext context) {
    final c = Color(store.color);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
          color: c.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
      child: Text(store.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: c, fontSize: 11.5, fontWeight: FontWeight.w700)),
    );
  }
}

/// Weekly budget summary: budget, running total (with GST) and what is left.
class BudgetBar extends StatelessWidget {
  const BudgetBar({super.key, this.compact = false});
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final over = s.remaining < 0;
    final frac = s.weekBudget <= 0 ? 1.0 : (s.spentThisWeek / s.weekBudget).clamp(0.0, 1.0);
    return GestureDetector(
      onTap: () => editBudget(context),
      child: Container(
        padding: EdgeInsets.all(compact ? 12 : 16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
              colors: over
                  ? [const Color(0xFF8E3A29), BB.tomato]
                  : [BB.green900, BB.green700]),
          borderRadius: BorderRadius.circular(22),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(flex: 3, child: _Stat('This week', money(s.weekBudget), small: true)),
            Expanded(flex: 3, child: _Stat('In cart', money(s.cartTotal), small: true, center: true)),
            Expanded(
                flex: 4,
                child: _Stat(over ? 'Over by' : 'Left to spend', money(s.remaining.abs()),
                    big: true, alignEnd: true)),
          ]),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: frac,
              minHeight: 8,
              backgroundColor: Colors.white24,
              valueColor: AlwaysStoppedAnimation(over ? Colors.white : BB.gold),
            ),
          ),
          if (!compact && s.spentEarlierThisWeek > 0)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('Already spent earlier this week: ${money(s.spentEarlierThisWeek)}',
                  style: const TextStyle(color: Colors.white70, fontSize: 12)),
            ),
        ]),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value,
      {this.big = false, this.small = false, this.alignEnd = false, this.center = false});
  final String label, value;
  final bool big, small, alignEnd, center;

  @override
  Widget build(BuildContext context) {
    final align = alignEnd
        ? Alignment.centerRight
        : center ? Alignment.center : Alignment.centerLeft;
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: align,
      child: Column(
        crossAxisAlignment: alignEnd
            ? CrossAxisAlignment.end
            : center ? CrossAxisAlignment.center : CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
          Text(value, style: serif(big ? 28 : 18, color: big ? BB.gold : Colors.white)),
        ],
      ),
    );
  }
}

Future<void> editBudget(BuildContext context) async {
  final s = context.read<AppState>();
  final ctrl = TextEditingController(text: s.weekBudget.toStringAsFixed(2));
  final v = await showDialog<double>(
    context: context,
    builder: (_) => AlertDialog(
      title: const Text('Weekly budget'),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: const InputDecoration(prefixText: '\$ ', labelText: 'CAD'),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
            onPressed: () => Navigator.pop(context, double.tryParse(ctrl.text)),
            child: const Text('Save')),
      ],
    ),
  );
  if (v != null && v >= 0) await s.setBudget(v);
}

/// Enter weight for by-weight items in lb or kg; returns grams.
Future<double?> askWeight(BuildContext context, Item item, double currentGrams) async {
  var useLb = true;
  final start = currentGrams > 0 ? currentGrams / gramsPerLb : 1.0;
  final ctrl = TextEditingController(text: start.toStringAsFixed(2));
  return showDialog<double>(
    context: context,
    builder: (_) => StatefulBuilder(builder: (ctx, set) {
      return AlertDialog(
        title: Text(item.name, maxLines: 2),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: true, label: Text('lb')),
              ButtonSegment(value: false, label: Text('kg')),
            ],
            selected: {useLb},
            onSelectionChanged: (v) {
              final cur = double.tryParse(ctrl.text) ?? 0;
              final grams = cur * (useLb ? gramsPerLb : 1000);
              set(() {
                useLb = v.first;
                ctrl.text = (grams / (useLb ? gramsPerLb : 1000)).toStringAsFixed(2);
              });
            },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: ctrl,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: 'Weight (${useLb ? 'lb' : 'kg'})'),
          ),
          const SizedBox(height: 8),
          Builder(builder: (_) {
            final v = double.tryParse(ctrl.text) ?? 0;
            final g = v * (useLb ? gramsPerLb : 1000);
            return Text('${sizeBoth(g, Unit.g)} = ${money(item.lineCost(g))}',
                style: const TextStyle(fontWeight: FontWeight.w600));
          }),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
              onPressed: () {
                final v = double.tryParse(ctrl.text) ?? 0;
                Navigator.pop(ctx, v * (useLb ? gramsPerLb : 1000));
              },
              child: const Text('Set')),
        ],
      );
    }),
  );
}

/// Add button that becomes a +/- stepper once the item is in the cart.
class CartControl extends StatelessWidget {
  const CartControl(this.item, {super.key});
  final Item item;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final qty = s.qtyOf(item.id);
    if (qty <= 0) {
      return FilledButton.icon(
        onPressed: () => s.add(item),
        icon: const Icon(Icons.add_shopping_cart, size: 18),
        label: const Text('Add'),
        style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10)),
      );
    }
    final step = item.variable ? gramsPerLb / 2 : 1.0;
    return Container(
      decoration: BoxDecoration(
          color: BB.green100, borderRadius: BorderRadius.circular(14)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: () => s.setQty(item, qty - step),
            icon: Icon(qty - step <= 0 ? Icons.delete_outline : Icons.remove)),
        GestureDetector(
          onTap: item.variable
              ? () async {
                  final g = await askWeight(context, item, qty);
                  if (g != null) s.setQty(item, g);
                }
              : null,
          child: Text(item.variable ? sizeBoth(qty, Unit.g).split(' (').last.replaceAll(')', '') : qty.toStringAsFixed(0),
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
        ),
        IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: () => s.setQty(item, qty + step),
            icon: const Icon(Icons.add)),
      ]),
    );
  }
}
