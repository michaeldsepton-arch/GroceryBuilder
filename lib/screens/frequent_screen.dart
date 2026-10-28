import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../models/units.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/item_widgets.dart';

/// Frequently bought items with where to find them in the store.
class FrequentScreen extends StatefulWidget {
  const FrequentScreen({super.key});
  @override
  State<FrequentScreen> createState() => _FrequentScreenState();
}

class _FrequentScreenState extends State<FrequentScreen> {
  bool showOften = false;
  String? storeFilter;
  List<Item> items = [];
  int _version = -1;

  Future<void> _load() async {
    final repo = context.read<AppState>().repo;
    final r = showOften ? await repo.oftenBought() : await repo.favourites();
    if (mounted) setState(() => items = r);
  }

  static int _aisle(String a) =>
      int.tryParse(RegExp(r'\d+').firstMatch(a)?.group(0) ?? '') ?? 9999;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    // Reload whenever app state notifies (favourite toggles, meta edits).
    final v = s.revision;
    if (v != _version) {
      _version = v;
      WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    }
    final shown = items.where((i) => storeFilter == null || i.storeId == storeFilter).toList()
      ..sort((a, b) {
        final c = a.storeId.compareTo(b.storeId);
        if (c != 0) return c;
        final d = _aisle(a.aisle).compareTo(_aisle(b.aisle));
        return d != 0 ? d : a.name.compareTo(b.name);
      });
    final byStore = <String, List<Item>>{};
    for (final i in shown) {
      byStore.putIfAbsent(i.storeId, () => []).add(i);
    }
    return SafeArea(
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Row(children: [
            Text('Frequent items', style: serif(28)),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text('Favourites'), icon: Icon(Icons.favorite)),
              ButtonSegment(value: true, label: Text('Often bought'), icon: Icon(Icons.history)),
            ],
            selected: {showOften},
            onSelectionChanged: (v) {
              setState(() => showOften = v.first);
              _load();
            },
          ),
        ),
        SizedBox(
          height: 52,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                    label: const Text('All'),
                    selected: storeFilter == null,
                    onSelected: (_) => setState(() => storeFilter = null)),
              ),
              for (final st in s.stores)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                      label: Text(st.name.split(' ').first),
                      selected: storeFilter == st.id,
                      onSelected: (_) => setState(() => storeFilter = st.id)),
                ),
            ],
          ),
        ),
        if (s.alerts.isNotEmpty) _AlertsCard(s),
        Expanded(
          child: shown.isEmpty
              ? Center(
                  child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.favorite_border, size: 48, color: BB.green500),
                    const SizedBox(height: 10),
                    Text(showOften ? 'Nothing bought yet' : 'No favourites yet', style: serif(20)),
                    const SizedBox(height: 6),
                    Text(
                        showOften
                            ? 'Items you finish trips with show up here automatically.'
                            : 'Tap the heart on any item to keep it here, then add its aisle and freezer spot.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: BB.muted)),
                  ]),
                ))
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                  children: [
                    for (final e in byStore.entries) ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text(s.storeById(e.key).name, style: serif(18)),
                      ),
                      for (final i in e.value) _FreqRow(i, onChanged: _load),
                    ],
                  ],
                ),
        ),
      ]),
    );
  }
}

class _FreqRow extends StatelessWidget {
  const _FreqRow(this.item, {required this.onChanged});
  final Item item;
  final VoidCallback onChanged;
  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () async {
          await showItemSheet(context, item);
          onChanged();
        },
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(children: [
            ItemImage(item, size: 64, radius: 14),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(item.name, maxLines: 2, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Wrap(spacing: 6, children: [
                  _Loc(item.aisle.isEmpty ? 'Aisle ?' : 'Aisle ${item.aisle}',
                      item.aisle.isEmpty),
                  if (item.spot.isNotEmpty) _Loc(item.spot, false),
                ]),
                Text('${money(item.price)} · ${item.unitPrice.primary}',
                    style: const TextStyle(color: BB.muted, fontSize: 12)),
              ]),
            ),
            CartControl(item),
          ]),
        ),
      ),
    );
  }
}

class _Loc extends StatelessWidget {
  const _Loc(this.text, this.empty);
  final String text;
  final bool empty;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
            color: empty ? BB.cream : BB.green100,
            border: empty ? Border.all(color: BB.muted.withValues(alpha: 0.4)) : null,
            borderRadius: BorderRadius.circular(8)),
        child: Text(text,
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: empty ? BB.muted : BB.green900)),
      );
}

class _AlertsCard extends StatefulWidget {
  const _AlertsCard(this.s);
  final AppState s;
  @override
  State<_AlertsCard> createState() => _AlertsCardState();
}

class _AlertsCardState extends State<_AlertsCard> {
  bool open = false;

  @override
  Widget build(BuildContext context) {
    final s = widget.s;
    final a = s.alerts;
    final fresh = s.unseenAlerts;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFFFBE9E4),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: BB.tomato.withValues(alpha: 0.25)),
        ),
        child: Column(children: [
          ListTile(
            dense: true,
            leading: const Icon(Icons.local_offer, color: BB.tomato),
            title: Text(
                fresh > 0
                    ? '$fresh new deal${fresh == 1 ? '' : 's'} on your items'
                    : '${a.length} deal${a.length == 1 ? '' : 's'} on your items',
                style: const TextStyle(fontWeight: FontWeight.w800)),
            subtitle: const Text('Price drops and sales on favourites and things you buy often'),
            trailing: Icon(open ? Icons.expand_less : Icons.expand_more),
            onTap: () {
              setState(() => open = !open);
              if (!open) return;
              s.markAlertsSeen();
            },
          ),
          if (open)
            for (final x in a.take(12))
              ListTile(
                dense: true,
                leading: ItemImage(x.item, size: 40, radius: 8),
                title: Text(x.item.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(
                    '${s.storeById(x.item.storeId).name} · ${x.kind == AlertKind.drop ? 'price dropped' : 'on sale'}'),
                trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text(money(x.newPrice), style: serif(16, color: BB.tomato)),
                  Text('was ${money(x.oldPrice)} · -${x.pct}%',
                      style: const TextStyle(fontSize: 11, color: BB.muted)),
                ]),
                onTap: () => showItemSheet(context, x.item),
              ),
        ]),
      ),
    );
  }
}
