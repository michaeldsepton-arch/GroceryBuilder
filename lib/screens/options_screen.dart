import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/repo.dart';
import '../models/models.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/item_widgets.dart';

/// "Browse options": every store's products for a term. Tap a card to pick it
/// (returns the Item); the Add button still adds straight to the cart.
class OptionsScreen extends StatefulWidget {
  const OptionsScreen({super.key, required this.term, this.title});
  final String term;
  final String? title;
  @override
  State<OptionsScreen> createState() => _OptionsScreenState();
}

class _OptionsScreenState extends State<OptionsScreen> {
  late final TextEditingController ctrl = TextEditingController(text: widget.term);
  final Set<String> stores = {};
  SortMode sort = SortMode.unitPrice;
  List<Item> results = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    final repo = context.read<AppState>().repo;
    setState(() => loading = true);
    final r = await repo.search(ctrl.text, storeIds: stores);
    r.sort((a, b) => compareItems(a, b, sort));
    if (!mounted) return;
    setState(() {
      results = r;
      loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(title: Text(widget.title ?? 'Browse options')),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: TextField(
            controller: ctrl,
            onSubmitted: (_) => _run(),
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              suffixIcon: IconButton(icon: const Icon(Icons.arrow_forward), onPressed: _run),
            ),
          ),
        ),
        SizedBox(
          height: 48,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              for (final st in s.stores)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: Text(st.name.split(' ').first),
                    selected: stores.contains(st.id),
                    onSelected: (v) {
                      setState(() => v ? stores.add(st.id) : stores.remove(st.id));
                      _run();
                    },
                  ),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
          child: Row(children: [
            Expanded(
              child: Text(loading ? 'Searching…' : '${results.length} options',
                  overflow: TextOverflow.ellipsis, style: const TextStyle(color: BB.muted)),
            ),
            SizedBox(
              width: 170,
              child: DropdownButton<SortMode>(
              isExpanded: true,
              value: sort,
              underline: const SizedBox(),
              items: const [
                DropdownMenuItem(value: SortMode.unitPrice, child: Text('Best unit price')),
                DropdownMenuItem(value: SortMode.price, child: Text('Lowest price')),
                DropdownMenuItem(value: SortMode.discount, child: Text('Biggest discount')),
              ],
              onChanged: (v) {
                setState(() => sort = v!);
                _run();
              },
            ),
            ),
          ]),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text('Tap an item to choose it for this recipe', style: TextStyle(color: BB.goldDark, fontSize: 12)),
          ),
        ),
        Expanded(
          child: results.isEmpty && !loading
              ? const Center(
                  child: Padding(
                  padding: EdgeInsets.all(32),
                  child: Text('Nothing found in the stores yet for this. Try a simpler word, or add it yourself in My stuff.',
                      textAlign: TextAlign.center, style: TextStyle(color: BB.muted)),
                ))
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  itemCount: results.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (_, i) => ItemCard(results[i], onTap: () => Navigator.pop(context, results[i])),
                ),
        ),
      ]),
    );
  }
}
