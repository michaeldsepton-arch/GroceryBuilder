import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../models/units.dart';
import '../state/app_state.dart';
import '../theme.dart';
import 'common.dart';

class ItemCard extends StatelessWidget {
  const ItemCard(this.item, {super.key, this.best = false, this.onTap});
  final Item item;
  final bool best;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final store = s.storeById(item.storeId);
    final up = item.unitPrice;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap ?? () => showItemSheet(context, item),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Stack(children: [
              ItemImage(item, size: 88),
              if (item.onSale)
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    decoration: const BoxDecoration(
                        color: BB.tomato,
                        borderRadius: BorderRadius.vertical(bottom: Radius.circular(16))),
                    child: Text('SAVE ${item.discountPct}%',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800)),
                  ),
                ),
              if (item.favourite)
                const Positioned(
                    top: 4, left: 4,
                    child: Icon(Icons.favorite, color: BB.tomato, size: 18)),
            ]),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                StoreTag(store),
                const SizedBox(height: 4),
                Text(item.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 15, height: 1.2)),
                if (item.brand.isNotEmpty)
                  Text(item.brand,
                      style: const TextStyle(color: BB.muted, fontSize: 12.5)),
                const SizedBox(height: 6),
                Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text(money(item.price), style: serif(22)),
                  const SizedBox(width: 6),
                  if (item.sizeText.isNotEmpty)
                    Flexible(
                      child: Text(item.sizeText,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: BB.muted, fontSize: 12.5)),
                    ),
                ]),
                if (item.onSale)
                  Text('Was ${money(item.wasPrice!)} · save ${money(item.wasPrice! - item.price)}',
                      style: const TextStyle(
                          color: BB.tomato,
                          fontSize: 12,
                          decoration: TextDecoration.lineThrough)),
                const SizedBox(height: 4),
                Wrap(spacing: 6, runSpacing: 4, children: [
                  _Pill(up.primary, best ? BB.gold : BB.green100,
                      best ? Colors.white : BB.green900,
                      icon: best ? Icons.emoji_events : null),
                  if (up.secondary.isNotEmpty)
                    Text(up.secondary,
                        style: const TextStyle(color: BB.muted, fontSize: 11.5)),
                  if (item.taxable)
                    const Text('+GST',
                        style: TextStyle(color: BB.goldDark, fontSize: 11.5, fontWeight: FontWeight.w700)),
                ]),
                const SizedBox(height: 8),
                Align(alignment: Alignment.centerRight, child: CartControl(item)),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill(this.text, this.bg, this.fg, {this.icon});
  final String text;
  final Color bg, fg;
  final IconData? icon;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) Icon(icon, size: 13, color: fg),
          if (icon != null) const SizedBox(width: 3),
          Text(text, style: TextStyle(color: fg, fontSize: 12, fontWeight: FontWeight.w800)),
        ]),
      );
}

Future<void> showItemSheet(BuildContext context, Item item) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: BB.cream,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    builder: (_) => ChangeNotifierProvider.value(
        value: context.read<AppState>(), child: ItemSheet(item.id)),
  );
}

class ItemSheet extends StatefulWidget {
  const ItemSheet(this.itemId, {super.key});
  final String itemId;
  @override
  State<ItemSheet> createState() => _ItemSheetState();
}

class _ItemSheetState extends State<ItemSheet> {
  Item? item;
  final aisle = TextEditingController();
  final spot = TextEditingController();
  final note = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final i = await context.read<AppState>().repo.item(widget.itemId);
    if (!mounted || i == null) return;
    setState(() {
      item = i;
      aisle.text = i.aisle;
      spot.text = i.spot;
      note.text = i.note;
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final it = item;
    if (it == null) return const SizedBox(height: 200);
    final store = s.storeById(it.storeId);
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 12, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      child: SingleChildScrollView(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Center(
              child: Container(
                  width: 44, height: 5,
                  decoration: BoxDecoration(
                      color: BB.green900.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4)))),
          const SizedBox(height: 14),
          Center(child: ItemImage(it, size: 200, radius: 24)),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(child: Text(it.name, style: serif(24))),
            IconButton.filledTonal(
              onPressed: () async {
                await s.setFavourite(it, !it.favourite);
                _load();
              },
              icon: Icon(it.favourite ? Icons.favorite : Icons.favorite_border,
                  color: BB.tomato),
            ),
          ]),
          Row(children: [StoreTag(store), const SizedBox(width: 8), if (it.brand.isNotEmpty) Text(it.brand, style: const TextStyle(color: BB.muted))]),
          const SizedBox(height: 10),
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(money(it.price), style: serif(32)),
            const SizedBox(width: 8),
            Text(it.sizeText, style: const TextStyle(color: BB.muted)),
          ]),
          const SizedBox(height: 4),
          Text('${it.unitPrice.primary}   ${it.unitPrice.secondary}',
              style: const TextStyle(fontWeight: FontWeight.w700, color: BB.green700)),
          if (it.taxable)
            const Text('5% GST applies', style: TextStyle(color: BB.goldDark)),
          const SizedBox(height: 14),
          Align(alignment: Alignment.centerLeft, child: CartControl(it)),
          const Divider(height: 32),
          Text('Where to find it in the store', style: serif(18)),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
                child: TextField(
                    controller: aisle,
                    decoration: const InputDecoration(
                        labelText: 'Aisle', hintText: 'e.g. 12'))),
            const SizedBox(width: 10),
            Expanded(
                flex: 2,
                child: TextField(
                    controller: spot,
                    decoration: const InputDecoration(
                        labelText: 'Freezer / fridge / shelf',
                        hintText: 'e.g. Freezer F4'))),
          ]),
          const SizedBox(height: 10),
          TextField(
              controller: note,
              decoration: const InputDecoration(labelText: 'Note')),
          const SizedBox(height: 12),
          FilledButton.tonal(
            onPressed: () async {
              await s.saveMeta(it,
                  aisle: aisle.text.trim(), spot: spot.text.trim(), note: note.text.trim());
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('Save location'),
          ),
        ]),
      ),
    );
  }
}
