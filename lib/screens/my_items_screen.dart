import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../models/units.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/item_widgets.dart';

/// Items you add yourselves, for stores without an online shop (Dollarama,
/// the halal market…) or anything the catalog is missing.
class MyItemsScreen extends StatefulWidget {
  const MyItemsScreen({super.key});
  @override
  State<MyItemsScreen> createState() => _MyItemsScreenState();
}

class _MyItemsScreenState extends State<MyItemsScreen> {
  List<Item> items = [];
  final q = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await context.read<AppState>().repo.search(q.text, customOnly: true, limit: 1000);
    r.sort((a, b) => a.storeId == b.storeId ? a.name.compareTo(b.name) : a.storeId.compareTo(b.storeId));
    if (mounted) setState(() => items = r);
  }

  Future<void> _edit([Item? it]) async {
    final saved = await Navigator.push<bool>(
        context, MaterialPageRoute(builder: (_) => ItemFormScreen(existing: it)));
    if (saved == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final byStore = <String, List<Item>>{};
    for (final i in items) {
      byStore.putIfAbsent(i.storeId, () => []).add(i);
    }
    return SafeArea(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => _edit(),
          backgroundColor: BB.green700,
          foregroundColor: Colors.white,
          icon: const Icon(Icons.add_a_photo_outlined),
          label: const Text('Add item'),
        ),
        body: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Row(children: [
              Expanded(child: Text('My items', style: serif(28))),
              TextButton.icon(
                  onPressed: () async {
                    await _addStore(context);
                  },
                  icon: const Icon(Icons.storefront),
                  label: const Text('Add store')),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: q,
              onChanged: (_) => _load(),
              decoration: const InputDecoration(
                  hintText: 'Search your own items', prefixIcon: Icon(Icons.search)),
            ),
          ),
          Expanded(
            child: items.isEmpty
                ? Center(
                    child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.add_a_photo_outlined, size: 52, color: BB.green500),
                      const SizedBox(height: 10),
                      Text('Build your own list', style: serif(20)),
                      const SizedBox(height: 6),
                      const Text(
                          'Snap a photo in the store and save its price, aisle and spot. '
                          'Great for Dollarama and the halal market.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: BB.muted)),
                    ]),
                  ))
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
                    children: [
                      for (final e in byStore.entries) ...[
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Text(s.storeById(e.key).name, style: serif(18)),
                        ),
                        for (final i in e.value)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: ItemCard(i, onTap: () => _edit(i)),
                          ),
                      ],
                    ],
                  ),
          ),
        ]),
      ),
    );
  }
}

Future<void> _addStore(BuildContext context) async {
  final s = context.read<AppState>();
  final name = TextEditingController();
  final loc = TextEditingController();
  bool online = false;
  final ok = await showDialog<bool>(
    context: context,
    builder: (_) => StatefulBuilder(
      builder: (ctx, set) => AlertDialog(
        title: const Text('Add a store'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: name, decoration: const InputDecoration(labelText: 'Store name')),
          const SizedBox(height: 10),
          TextField(controller: loc, decoration: const InputDecoration(labelText: 'Location')),
          SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Has an online shop'),
              value: online,
              onChanged: (v) => set(() => online = v)),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Add')),
        ],
      ),
    ),
  );
  if (ok == true && name.text.trim().isNotEmpty) {
    const palette = [0xFF1F5A43, 0xFFC8553D, 0xFFE8B93A, 0xFF3C7D5B, 0xFF9C7A33];
    await s.repo.saveStore(Store(
        id: 'custom_${DateTime.now().millisecondsSinceEpoch}',
        name: name.text.trim(),
        color: palette[s.stores.length % palette.length],
        location: loc.text.trim(),
        hasOnline: online,
        sortOrder: 100 + s.stores.length));
    await s.reload();
  }
}

const _categories = <String, bool>{
  // name -> GST applies by default
  'Produce': false,
  'Meat & seafood': false,
  'Dairy & eggs': false,
  'Bakery': false,
  'Pantry': false,
  'Frozen': false,
  'Snacks & candy': true,
  'Drinks (pop, juice)': true,
  'Household': true,
  'Health & beauty': true,
  'Pharmacy': true,
  'Baby & pets': true,
  'General merchandise': true,
};

class ItemFormScreen extends StatefulWidget {
  const ItemFormScreen({super.key, this.existing});
  final Item? existing;
  @override
  State<ItemFormScreen> createState() => _ItemFormScreenState();
}

class _ItemFormScreenState extends State<ItemFormScreen> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController name, brand, price, size, aisle, spot, note;
  String? storeId;
  String category = 'Pantry';
  Unit unit = Unit.g;
  bool variable = false;
  bool taxable = false;
  String? photoFile; // file name inside photoDir
  bool saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    name = TextEditingController(text: e?.name);
    brand = TextEditingController(text: e?.brand);
    price = TextEditingController(text: e == null ? '' : e.price.toStringAsFixed(2));
    size = TextEditingController(text: e == null ? '' : '${e.sizeValue}'.replaceFirst(RegExp(r'\.0$'), ''));
    aisle = TextEditingController(text: e?.aisle);
    spot = TextEditingController(text: e?.spot);
    note = TextEditingController(text: e?.note);
    if (e != null) {
      storeId = e.storeId;
      category = _categories.containsKey(e.category) ? e.category : 'Pantry';
      unit = e.sizeUnit;
      variable = e.variable;
      taxable = e.taxable;
      photoFile = e.photoPath;
    }
  }

  Future<void> _pick(ImageSource src) async {
    final s = context.read<AppState>();
    final x = await ImagePicker().pickImage(source: src, maxWidth: 1200, imageQuality: 82);
    if (x == null) return;
    final fn = 'p_${DateTime.now().millisecondsSinceEpoch}${p.extension(x.path).isEmpty ? '.jpg' : p.extension(x.path)}';
    await File(x.path).copy(p.join(s.photoDir, fn));
    setState(() => photoFile = fn);
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate() || storeId == null) {
      if (storeId == null) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Pick a store')));
      }
      return;
    }
    setState(() => saving = true);
    final s = context.read<AppState>();
    final e = widget.existing;
    final item = Item(
      id: e?.id ?? 'custom:${DateTime.now().millisecondsSinceEpoch}',
      storeId: storeId!,
      name: name.text.trim(),
      brand: brand.text.trim(),
      photoPath: photoFile,
      price: double.parse(price.text),
      sizeValue: variable && size.text.isEmpty ? 1 : (double.tryParse(size.text) ?? 1),
      sizeUnit: unit,
      variable: variable,
      taxable: taxable,
      category: category,
      custom: true,
      updated: DateTime.now().toIso8601String(),
    );
    await s.repo.saveCustomItem(item);
    await s.repo.updateMeta(item.id,
        aisle: aisle.text.trim(), spot: spot.text.trim(), note: note.text.trim());
    await s.reload();
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final photo = photoFile == null ? null : File(p.join(s.photoDir, photoFile!));
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.existing == null ? 'Add item' : 'Edit item'),
        actions: [
          if (widget.existing != null)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                await s.repo.deleteCustomItem(widget.existing!.id);
                await s.reload();
                if (context.mounted) Navigator.pop(context, true);
              },
            ),
        ],
      ),
      body: Form(
        key: _form,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          GestureDetector(
            onTap: () => showModalBottomSheet(
              context: context,
              builder: (ctx) => SafeArea(
                child: Wrap(children: [
                  ListTile(
                      leading: const Icon(Icons.photo_camera),
                      title: const Text('Take photo'),
                      onTap: () {
                        Navigator.pop(ctx);
                        _pick(ImageSource.camera);
                      }),
                  ListTile(
                      leading: const Icon(Icons.photo_library),
                      title: const Text('Choose from gallery'),
                      onTap: () {
                        Navigator.pop(ctx);
                        _pick(ImageSource.gallery);
                      }),
                ]),
              ),
            ),
            child: Container(
              height: 190,
              decoration: BoxDecoration(
                color: BB.green100,
                borderRadius: BorderRadius.circular(22),
                image: photo != null && photo.existsSync()
                    ? DecorationImage(image: FileImage(photo), fit: BoxFit.cover)
                    : null,
              ),
              child: photo == null
                  ? const Center(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.add_a_photo_outlined, size: 40, color: BB.green700),
                      SizedBox(height: 6),
                      Text('Add a photo', style: TextStyle(color: BB.green700, fontWeight: FontWeight.w700)),
                    ]))
                  : null,
            ),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: storeId,
            decoration: const InputDecoration(labelText: 'Store'),
            items: [
              for (final st in s.stores)
                DropdownMenuItem(value: st.id, child: Text(st.name)),
            ],
            onChanged: (v) => setState(() => storeId = v),
          ),
          const SizedBox(height: 12),
          TextFormField(
              controller: name,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Item name'),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null),
          const SizedBox(height: 12),
          TextFormField(controller: brand, decoration: const InputDecoration(labelText: 'Brand (optional)')),
          const SizedBox(height: 12),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Sold by weight (price per lb / kg)'),
            value: variable,
            onChanged: (v) => setState(() {
              variable = v;
              if (v && unit.kind != UnitKind.weight) unit = Unit.lb;
              if (v && size.text.isEmpty) size.text = '1';
            }),
          ),
          Row(children: [
            Expanded(
              child: TextFormField(
                controller: price,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Price', prefixText: '\$ '),
                validator: (v) => double.tryParse(v ?? '') == null ? 'Enter a price' : null,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextFormField(
                controller: size,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(labelText: variable ? 'Per (amount)' : 'Package size'),
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 92,
              child: DropdownButtonFormField<Unit>(
                initialValue: unit,
                decoration: const InputDecoration(labelText: 'Unit'),
                items: [
                  for (final u in Unit.values)
                    if (!variable || u.kind == UnitKind.weight)
                      DropdownMenuItem(value: u, child: Text(u.label)),
                ],
                onChanged: (v) => setState(() => unit = v!),
              ),
            ),
          ]),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: category,
            decoration: const InputDecoration(labelText: 'Category'),
            items: [for (final c in _categories.keys) DropdownMenuItem(value: c, child: Text(c))],
            onChanged: (v) => setState(() {
              category = v!;
              taxable = _categories[v]!;
            }),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Charge 5% GST'),
            subtitle: const Text('Basic groceries are GST-free; snacks, drinks and household items are not'),
            value: taxable,
            onChanged: (v) => setState(() => taxable = v),
          ),
          const SizedBox(height: 8),
          Text('Where to find it', style: serif(18)),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: TextFormField(controller: aisle, decoration: const InputDecoration(labelText: 'Aisle'))),
            const SizedBox(width: 10),
            Expanded(
                flex: 2,
                child: TextFormField(
                    controller: spot,
                    decoration: const InputDecoration(labelText: 'Freezer / fridge / shelf'))),
          ]),
          const SizedBox(height: 12),
          TextFormField(controller: note, decoration: const InputDecoration(labelText: 'Note')),
          const SizedBox(height: 20),
          FilledButton(onPressed: saving ? null : _save, child: const Text('Save item')),
        ]),
      ),
    );
  }
}
