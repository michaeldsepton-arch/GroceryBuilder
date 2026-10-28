import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../models/recipe.dart';
import '../models/units.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/recipe_widgets.dart';
import 'options_screen.dart';

class _Line {
  _Line(this.ing) : term = ing.search;
  final Ingredient ing;
  String term;
  Item? suggested;
  Item? chosen;
  String? subLabel;
  bool have = false;
  bool loading = true;
  Item? get item => chosen ?? suggested;
}

class RecipeDetailScreen extends StatefulWidget {
  const RecipeDetailScreen(this.recipe, {super.key});
  final Recipe recipe;
  @override
  State<RecipeDetailScreen> createState() => _RecipeDetailScreenState();
}

class _RecipeDetailScreenState extends State<RecipeDetailScreen> {
  late int servings = widget.recipe.servings;
  late final List<_Line> lines = [for (final i in widget.recipe.ingredients) _Line(i)];
  static const _pantry = {'salt', 'water', 'ice', 'black pepper', 'pepper', 'ice cubes'};

  @override
  void initState() {
    super.initState();
    for (final l in lines) {
      l.have = _pantry.contains(l.ing.name.toLowerCase().trim());
      _suggest(l);
    }
  }

  Future<void> _suggest(_Line l) async {
    final rr = context.read<AppState>().recipes;
    setState(() => l.loading = true);
    final it = await rr.suggest(l.term);
    if (!mounted) return;
    setState(() {
      l.suggested = it;
      l.loading = false;
    });
  }

  Future<void> _browse(_Line l) async {
    final it = await Navigator.push<Item>(context,
        MaterialPageRoute(builder: (_) => OptionsScreen(term: l.term, title: l.ing.name)));
    if (it != null) setState(() => l.chosen = it);
  }

  void _substitute(_Line l) {
    final rr = context.read<AppState>().recipes;
    final subs = rr.substitutesFor(l.ing);
    showModalBottomSheet(
      context: context,
      backgroundColor: BB.cream,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Substitutes for ${l.ing.name}', style: serif(20)),
            const SizedBox(height: 10),
            if (subs.isEmpty)
              const Text('No ready-made substitutes for this one. Use Browse options to pick a similar product.',
                  style: TextStyle(color: BB.muted)),
            for (final o in subs)
              Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  title: Text(o.label, style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text(o.note),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.pop(ctx);
                    setState(() {
                      l.subLabel = o.label;
                      l.term = o.search;
                      l.chosen = null;
                    });
                    _suggest(l);
                  },
                ),
              ),
            if (l.subLabel != null)
              TextButton.icon(
                onPressed: () {
                  Navigator.pop(ctx);
                  setState(() {
                    l.subLabel = null;
                    l.term = l.ing.search;
                    l.chosen = null;
                  });
                  _suggest(l);
                },
                icon: const Icon(Icons.undo),
                label: const Text('Use the original ingredient'),
              ),
          ]),
        ),
      ),
    );
  }

  List<_Line> get _toBuy => lines.where((l) => !l.have && l.item != null).toList();
  double get _estimate => _toBuy.fold(0, (a, l) => a + l.item!.price);

  Future<void> _addAll() async {
    final s = context.read<AppState>();
    for (final l in _toBuy) {
      if (s.qtyOf(l.item!.id) == 0) await s.add(l.item!);
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('${_toBuy.length} items added to your cart')));
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final r = widget.recipe;
    final fav = s.recipes.favourites.contains(r.id);
    final factor = servings / r.servings;
    return Scaffold(
      appBar: AppBar(
        actions: [
          IconButton(
            icon: Icon(fav ? Icons.favorite : Icons.favorite_border, color: BB.tomato),
            onPressed: () async {
              await s.recipes.toggleFavourite(r);
              s.touch();
            },
          ),
          if (r.source == RecipeSource.mine)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                await s.recipes.deleteUserRecipe(r.id);
                s.touch();
                if (context.mounted) Navigator.pop(context);
              },
            ),
        ],
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 120), children: [
        RecipeImage(r, height: 210, radius: 24),
        const SizedBox(height: 14),
        Text(r.title, style: serif(28)),
        const SizedBox(height: 4),
        Text(
            [
              if (r.cuisine.isNotEmpty) r.cuisine,
              if (r.meal.isNotEmpty) r.meal[0].toUpperCase() + r.meal.substring(1),
              if (r.minutes != null) '${r.minutes} min',
              r.source == RecipeSource.book ? "From our recipe book" : null,
            ].whereType<String>().join(' · '),
            style: const TextStyle(color: BB.muted)),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text('Ingredients', style: serif(22)),
            ),
          ),
          IconButton.filledTonal(
              visualDensity: VisualDensity.compact,
              onPressed: servings > 1 ? () => setState(() => servings--) : null,
              icon: const Icon(Icons.remove)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Text('$servings servings', style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
          IconButton.filledTonal(
              visualDensity: VisualDensity.compact,
              onPressed: () => setState(() => servings++),
              icon: const Icon(Icons.add)),
        ]),
        const SizedBox(height: 6),
        for (final l in lines) _IngredientCard(
          line: l,
          factor: factor,
          onHave: (v) => setState(() => l.have = v),
          onBrowse: () => _browse(l),
          onSub: () => _substitute(l),
        ),
        const SizedBox(height: 16),
        Text('Method', style: serif(22)),
        const SizedBox(height: 8),
        for (var i = 0; i < r.steps.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              CircleAvatar(
                  radius: 13,
                  backgroundColor: BB.green700,
                  child: Text('${i + 1}', style: const TextStyle(color: Colors.white, fontSize: 12))),
              const SizedBox(width: 10),
              Expanded(child: Text(r.steps[i], style: const TextStyle(height: 1.35))),
            ]),
          ),
        if (r.notes.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(r.notes, style: const TextStyle(color: BB.muted, fontStyle: FontStyle.italic)),
        ],
      ]),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton.icon(
            onPressed: _toBuy.isEmpty ? null : _addAll,
            icon: const Icon(Icons.add_shopping_cart),
            label: Text(_toBuy.isEmpty
                ? 'Nothing to buy yet'
                : 'Add ${_toBuy.length} items to cart · about ${money(_estimate)}'),
          ),
        ),
      ),
    );
  }
}

class _IngredientCard extends StatelessWidget {
  const _IngredientCard({
    required this.line,
    required this.factor,
    required this.onHave,
    required this.onBrowse,
    required this.onSub,
  });
  final _Line line;
  final double factor;
  final ValueChanged<bool> onHave;
  final VoidCallback onBrowse, onSub;

  @override
  Widget build(BuildContext context) {
    final s = context.read<AppState>();
    final it = line.item;
    final store = it == null ? null : s.storeById(it.storeId);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Checkbox(value: line.have, onChanged: (v) => onHave(v ?? false)),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(line.ing.name + (line.ing.optional ? ' (optional)' : ''),
                    style: TextStyle(
                        fontWeight: FontWeight.w700,
                        decoration: line.have ? TextDecoration.lineThrough : null)),
                if (line.ing.qty.isNotEmpty)
                  Text(scaleQty(line.ing.qty, factor), style: const TextStyle(color: BB.muted)),
                if (line.subLabel != null)
                  Text('Substituting: ${line.subLabel}',
                      style: const TextStyle(color: BB.goldDark, fontWeight: FontWeight.w700, fontSize: 12.5)),
              ]),
            ),
            if (line.have) const Text('Have it', style: TextStyle(color: BB.green700, fontWeight: FontWeight.w700)),
          ]),
          if (!line.have) ...[
            const SizedBox(height: 6),
            if (line.loading)
              const LinearProgressIndicator()
            else if (it != null)
              InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: onBrowse,
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: BB.cream, borderRadius: BorderRadius.circular(14)),
                  child: Row(children: [
                    ItemImage(it, size: 48, radius: 10),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(it.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                        Text('${store!.name} · ${it.unitPrice.primary}',
                            style: const TextStyle(color: BB.muted, fontSize: 12)),
                      ]),
                    ),
                    Text(money(it.price), style: serif(17)),
                  ]),
                ),
              )
            else
              const Text('No store match yet. Try Browse options.', style: TextStyle(color: BB.muted, fontSize: 12.5)),
            const SizedBox(height: 6),
            Row(children: [
              OutlinedButton.icon(
                onPressed: onSub,
                icon: const Icon(Icons.swap_horiz, size: 18),
                label: const Text('Substitute'),
              ),
              const SizedBox(width: 8),
              FilledButton.tonalIcon(
                onPressed: onBrowse,
                icon: const Icon(Icons.storefront, size: 18),
                label: const Text('Browse options'),
              ),
            ]),
          ],
        ]),
      ),
    );
  }
}
