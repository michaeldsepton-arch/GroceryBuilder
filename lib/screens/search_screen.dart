import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/repo.dart';
import '../data/scope.dart';
import '../data/search_filters.dart';
import '../models/models.dart';
import '../models/units.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/filter_panel.dart';
import '../widgets/item_widgets.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});
  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final ctrl = TextEditingController();
  Timer? _debounce;
  final Set<String> storeFilter = {};
  bool onSaleOnly = false;
  String? categoryFilter;
  int saleCount = 0;
  SortMode sort = SortMode.relevance;
  int matches = 0;
  List<Item> results = [];
  bool loading = false;
  int _seq = 0;
  final filters = SearchFilters();
  final _scaffold = GlobalKey<ScaffoldState>();
  List<Item> _ranked = [];
  int _rankedMatches = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    ctrl.dispose();
    super.dispose();
  }

  void _onChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), _run);
  }

  Future<void> _run() async {
    final repo = context.read<AppState>().repo;
    final seq = ++_seq;
    setState(() => loading = true);
    final r = await repo.search(ctrl.text,
        storeIds: storeFilter, onSaleOnly: onSaleOnly, category: categoryFilter);
    final sc = await repo.onSaleCount();
    await filters.loadFor(repo, ctrl.text);
    if (!mounted || seq != _seq) return;
    final ranked = rankItems(r, ctrl.text, sort);
    setState(() {
      _ranked = ranked.items;
      _rankedMatches = ranked.matches;
      _applyFilters();
      saleCount = sc;
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

  void _remember(bool on) {
    setState(() => filters.remember = on);
    filters.persist(context.read<AppState>().repo);
  }

  /// Ids of the cheapest item per unit kind (needs 2+ comparable results).
  Set<String> _best() {
    final byKind = <UnitKind, List<Item>>{};
    for (final i in matches > 0 ? results.take(matches) : results) {
      byKind.putIfAbsent(i.unitPrice.kind, () => []).add(i);
    }
    final ids = <String>{};
    for (final list in byKind.values) {
      if (list.length < 2) continue;
      list.sort((a, b) => a.unitPrice.compareValue.compareTo(b.unitPrice.compareValue));
      ids.add(list.first.id);
    }
    return ids;
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final best = ctrl.text.trim().isEmpty ? <String>{} : _best();
    return Scaffold(
      key: _scaffold,
      endDrawer: FilterPanel(
        filters: filters,
        term: ctrl.text,
        resultCount: results.length,
        hasOthers: _rankedMatches > 0 && _rankedMatches < _ranked.length,
        onToggle: _toggle,
        onClear: _clearFilters,
        onRemember: _remember,
      ),
      body: SafeArea(
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Row(children: [
            Image.asset('assets/brand/basket.png', height: 40),
            const SizedBox(width: 10),
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text('Budget Basket', style: serif(26)),
              ),
            ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: BudgetBar(compact: true),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TextField(
            controller: ctrl,
            onChanged: _onChanged,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'Search milk, chicken thighs, tissue…',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: ctrl.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () {
                        ctrl.clear();
                        _run();
                      }),
            ),
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
                child: FilterChip(
                  avatar: const Icon(Icons.local_offer, size: 16, color: BB.tomato),
                  label: Text(saleCount > 0 ? 'On sale ($saleCount)' : 'On sale'),
                  selected: onSaleOnly,
                  selectedColor: const Color(0xFFF6D5CD),
                  onSelected: (v) {
                    setState(() {
                      onSaleOnly = v;
                      if (v) sort = SortMode.discount;
                    });
                    _run();
                  },
                ),
              ),
              for (final st in s.stores)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: Text(st.chipLabel),
                    selected: storeFilter.contains(st.id),
                    onSelected: (v) {
                      setState(() => v ? storeFilter.add(st.id) : storeFilter.remove(st.id));
                      _run();
                    },
                  ),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                child: Text(
                    loading
                        ? 'Searching…'
                        : (matches > 0 && matches < results.length
                            ? '$matches best matches, then ${results.length - matches} others'
                            : '${results.length} results'),
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: BB.muted)),
              ),
              FilterButton(
                filters: filters,
                onPressed: ctrl.text.trim().isEmpty ? null : () => _scaffold.currentState?.openEndDrawer(),
              ),
            ]),
            Row(children: [
              Expanded(
                child: DropdownButton<String?>(
                  isExpanded: true,
                  value: categoryFilter,
                  underline: const SizedBox(),
                  hint: const Text('All categories'),
                  items: [
                    const DropdownMenuItem<String?>(value: null, child: Text('All categories')),
                    for (final c in Scope.categoryNames)
                      DropdownMenuItem<String?>(value: c, child: Text(c)),
                  ],
                  onChanged: (v) {
                    setState(() => categoryFilter = v);
                    _run();
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButton<SortMode>(
                  isExpanded: true,
                  value: sort,
                  underline: const SizedBox(),
                  items: const [
                    DropdownMenuItem(value: SortMode.relevance, child: Text('Most relevant')),
                    DropdownMenuItem(value: SortMode.unitPrice, child: Text('Best unit price')),
                    DropdownMenuItem(value: SortMode.price, child: Text('Lowest price')),
                    DropdownMenuItem(value: SortMode.discount, child: Text('Biggest discount')),
                    DropdownMenuItem(value: SortMode.category, child: Text('By category')),
                    DropdownMenuItem(value: SortMode.name, child: Text('Name')),
                  ],
                  onChanged: (v) {
                    setState(() => sort = v!);
                    _run();
                  },
                ),
              ),
            ]),
          ]),
        ),
        ActiveFilterChips(
          filters: filters,
          onRemove: (f, k) => _toggle(f, k, false),
          onClear: _clearFilters,
        ),
        Expanded(
          child: results.isEmpty && !loading
              ? (filters.count > 0 ? _NoMatch(onClear: _clearFilters) : _Empty(s))
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                  itemCount: results.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (_, i) =>
                      ItemCard(results[i], best: best.contains(results[i].id)),
                ),
        ),
      ]),
      ),
    );
  }
}

class _NoMatch extends StatelessWidget {
  const _NoMatch({required this.onClear});
  final VoidCallback onClear;
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.filter_alt_off_outlined, size: 48, color: BB.green500),
            const SizedBox(height: 12),
            Text('Nothing matches these filters', style: serif(20)),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: onClear, child: const Text('Clear filters')),
          ]),
        ),
      );
}

class _Empty extends StatelessWidget {
  const _Empty(this.s);
  final AppState s;
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.search_off, size: 48, color: BB.green500),
          const SizedBox(height: 12),
          Text(s.catalogCount == 0 ? 'No store prices loaded yet' : 'Nothing found',
              style: serif(20)),
          const SizedBox(height: 8),
          Text(
              s.catalogCount == 0
                  ? (s.syncError ?? 'Pull the latest prices in More → Refresh prices, or add your own items in the Add tab.')
                  : 'Try another word or clear the store filters.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: BB.muted)),
        ]),
      ),
    );
  }
}
