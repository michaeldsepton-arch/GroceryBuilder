import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/repo.dart';
import '../data/search_filters.dart';
import '../models/models.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/filter_panel.dart';
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
  SortMode sort = SortMode.relevance;
  List<Item> results = [];
  int matches = 0;
  bool loading = true;
  final filters = SearchFilters();
  final _scaffold = GlobalKey<ScaffoldState>();
  List<Item> _ranked = [];
  int _rankedMatches = 0;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    final repo = context.read<AppState>().repo;
    setState(() => loading = true);
    final r = await repo.search(ctrl.text, storeIds: stores, everything: true);
    await filters.loadFor(repo, ctrl.text);
    final ranked = rankItems(r, ctrl.text, sort);
    if (!mounted) return;
    setState(() {
      _ranked = ranked.items;
      _rankedMatches = ranked.matches;
      _applyFilters();
      loading = false;
    });
  }

  void _applyFilters() {
    final f = filters.apply(_ranked, _rankedMatches, ctrl.text);
    results = f.items;
    matches = f.matches;
  }

  void _toggle(String facet, String key, bool on) {
    setState(() {
      filters.toggle(facet, key, on);
      _applyFilters();
    });
    filters.persist(context.read<AppState>().repo);
  }

  void _clearFilters() {
    setState(() {
      filters.clear();
      _applyFilters();
    });
    filters.persist(context.read<AppState>().repo);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    return Scaffold(
      key: _scaffold,
      appBar: AppBar(title: Text(widget.title ?? 'Browse options'), actions: const [SizedBox()]),
      endDrawer: FilterPanel(
        filters: filters,
        term: ctrl.text,
        resultCount: results.length,
        hasOthers: _rankedMatches > 0 && _rankedMatches < _ranked.length,
        onToggle: _toggle,
        onClear: _clearFilters,
        onRemember: (on) {
          setState(() => filters.remember = on);
          filters.persist(context.read<AppState>().repo);
        },
      ),
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
                    label: Text(st.chipLabel),
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
              child: Text(loading ? 'Searching…' : matches > 0 && matches < results.length ? '$matches best matches, then ${results.length - matches} others' : '${results.length} options',
                  overflow: TextOverflow.ellipsis, style: const TextStyle(color: BB.muted)),
            ),
            FilterButton(filters: filters, onPressed: () => _scaffold.currentState?.openEndDrawer()),
            const SizedBox(width: 8),
            SizedBox(
              width: 150,
              child: DropdownButton<SortMode>(
              isExpanded: true,
              value: sort,
              underline: const SizedBox(),
              items: const [
                DropdownMenuItem(value: SortMode.relevance, child: Text('Most relevant')),
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
        ActiveFilterChips(filters: filters, onRemove: (f, k) => _toggle(f, k, false), onClear: _clearFilters),
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
                  child: Text('Nothing found. Clear the filters, try a simpler word, or add it yourself in My stuff.',
                      textAlign: TextAlign.center, style: TextStyle(color: BB.muted)),
                ))
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  itemCount: results.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (_, i) => ItemCard(results[i], onTap: () => Navigator.pop(context, results[i]), onFlagChanged: _run),
                ),
        ),
      ]),
    );
  }
}
