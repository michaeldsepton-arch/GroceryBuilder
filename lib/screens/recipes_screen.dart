import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/recipe_widgets.dart';
import 'add_recipe_screen.dart';
import 'recipe_detail_screen.dart';

const _meals = {
  'all': 'All',
  'breakfast': 'Breakfast',
  'lunch': 'Lunch',
  'dinner': 'Dinner',
  'dessert': 'Desserts',
  'bread': 'Breads',
  'snack': 'Snacks & sweets',
  'drink': 'Drinks',
};

class RecipesScreen extends StatefulWidget {
  const RecipesScreen({super.key});
  @override
  State<RecipesScreen> createState() => _RecipesScreenState();
}

class _RecipesScreenState extends State<RecipesScreen> {
  int section = 1; // 0 book, 1 discover, 2 saved
  String meal = 'all';
  String? cuisine;
  final q = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final rr = s.recipes;
    final base = section == 0 ? rr.book : section == 1 ? rr.catalog : rr.all.where((r) => rr.favourites.contains(r.id)).toList();
    final cuisines = (base.map((r) => r.cuisine).where((c) => c.isNotEmpty).toSet().toList()..sort());
    final words = q.text.toLowerCase().split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
    final shown = base.where((r) {
      if (meal != 'all' && r.meal != meal) return false;
      if (cuisine != null && r.cuisine != cuisine) return false;
      final hay = '${r.title} ${r.cuisine} ${r.tags.join(' ')} ${r.ingredients.map((i) => i.name).join(' ')}'.toLowerCase();
      return words.every(hay.contains);
    }).toList()
      ..sort((a, b) => a.title.compareTo(b.title));
    return SafeArea(
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
          child: Row(children: [
            Text('Recipes', style: serif(28)),
            const Spacer(),
            FilledButton.tonalIcon(
              onPressed: () async {
                await Navigator.push(context, MaterialPageRoute(builder: (_) => const AddRecipeScreen()));
                s.touch();
              },
              icon: const Icon(Icons.add),
              label: const Text('Add'),
            ),
            const SizedBox(width: 8),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: SegmentedButton<int>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: 0, label: Text('Our book'), icon: Icon(Icons.menu_book_outlined)),
              ButtonSegment(value: 1, label: Text('Discover'), icon: Icon(Icons.explore_outlined)),
              ButtonSegment(value: 2, label: Text('Saved'), icon: Icon(Icons.favorite_border)),
            ],
            selected: {section},
            onSelectionChanged: (v) => setState(() {
              section = v.first;
              cuisine = null;
            }),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TextField(
            controller: q,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: 'Search recipes or ingredients',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: q.text.isEmpty
                  ? null
                  : IconButton(icon: const Icon(Icons.close), onPressed: () => setState(q.clear)),
            ),
          ),
        ),
        SizedBox(
          height: 52,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            children: [
              for (final e in _meals.entries)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                      label: Text(e.value), selected: meal == e.key, onSelected: (_) => setState(() => meal = e.key)),
                ),
            ],
          ),
        ),
        if (cuisines.isNotEmpty)
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                      label: const Text('Any cuisine'),
                      selected: cuisine == null,
                      onSelected: (_) => setState(() => cuisine = null)),
                ),
                for (final c in cuisines)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                        label: Text(c),
                        selected: cuisine == c,
                        onSelected: (_) => setState(() => cuisine = cuisine == c ? null : c)),
                  ),
              ],
            ),
          ),
        Expanded(
          child: shown.isEmpty
              ? _Empty(section: section)
              : GridView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2, mainAxisSpacing: 10, crossAxisSpacing: 10, childAspectRatio: 0.82),
                  itemCount: shown.length,
                  itemBuilder: (_, i) => RecipeCard(
                    shown[i],
                    favourite: rr.favourites.contains(shown[i].id),
                    onTap: () async {
                      await Navigator.push(
                          context, MaterialPageRoute(builder: (_) => RecipeDetailScreen(shown[i])));
                      s.touch();
                    },
                  ),
                ),
        ),
      ]),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.section});
  final int section;
  @override
  Widget build(BuildContext context) {
    final msg = switch (section) {
      0 => 'Your recipe book is empty here for now. Send the photos of your wife\'s recipes and they\'ll be added in the next update, or tap Add to type one in.',
      2 => 'Tap the heart on a recipe to save it here.',
      _ => 'No recipes match. Try fewer filters.',
    };
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.menu_book_outlined, size: 52, color: BB.green500),
          const SizedBox(height: 10),
          Text(msg, textAlign: TextAlign.center, style: const TextStyle(color: BB.muted)),
        ]),
      ),
    );
  }
}
