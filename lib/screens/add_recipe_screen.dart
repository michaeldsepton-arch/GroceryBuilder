import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../data/halal.dart';
import '../models/recipe.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/common.dart' show ImagePolicy;

/// Add a recipe by typing, or edit one that is already there (ours, from the
/// book, or from Discover). Edits to a built-in recipe are saved on the phone and
/// can be undone with "Restore original" on the recipe page.
class AddRecipeScreen extends StatefulWidget {
  const AddRecipeScreen({super.key, this.existing});
  final Recipe? existing;
  @override
  State<AddRecipeScreen> createState() => _AddRecipeScreenState();
}

class _AddRecipeScreenState extends State<AddRecipeScreen> {
  final title = TextEditingController();
  final cuisine = TextEditingController();
  final minutes = TextEditingController();
  final servings = TextEditingController(text: '4');
  final ingredients = TextEditingController();
  final steps = TextEditingController();
  String meal = 'dinner';
  String? photoFile;

  /// Ingredient lines as shown, so an unchanged line keeps its store search term.
  final Map<String, Ingredient> _original = {};

  static const _meals = ['breakfast', 'lunch', 'dinner', 'dessert', 'bread', 'snack', 'drink', 'side'];

  static String _line(Ingredient i) => [i.qty, i.name].where((s) => s.trim().isNotEmpty).join(' ');

  @override
  void initState() {
    super.initState();
    final r = widget.existing;
    if (r == null) return;
    title.text = r.title;
    cuisine.text = r.cuisine;
    minutes.text = r.minutes?.toString() ?? '';
    servings.text = '${r.servings}';
    meal = _meals.contains(r.meal) ? r.meal : 'dinner';
    photoFile = r.photoPath;
    for (final i in r.ingredients) {
      _original[_line(i)] = i;
    }
    ingredients.text = r.ingredients.map(_line).join('\n');
    steps.text = r.steps.join('\n');
  }

  static final _qtyRe = RegExp(
      r'^\s*([\d½¼¾⅓⅔][\d\s/.½¼¾⅓⅔-]*\s*(?:cups?|tbsp|tsp|tablespoons?|teaspoons?|g|kg|ml|l|lb|lbs|oz|cloves?|pinch|cans?|pieces?|slices?|bunch|sprigs?)?\b\.?)\s+(.+)$',
      caseSensitive: false);

  Ingredient _parse(String line) {
    final kept = _original[line.trim()];
    if (kept != null) return kept;
    final m = _qtyRe.firstMatch(line);
    final qty = m?.group(1)?.trim() ?? '';
    var name = (m?.group(2) ?? line).trim();
    final search = name.split(',').first.replaceAll(RegExp(r'\(.*?\)'), '').trim();
    return Ingredient(name: name, qty: qty, search: search);
  }

  Future<void> _photo() async {
    final s = context.read<AppState>();
    final x = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1400, imageQuality: 82);
    if (x == null) return;
    final fn = 'r_${DateTime.now().millisecondsSinceEpoch}${p.extension(x.path).isEmpty ? '.jpg' : p.extension(x.path)}';
    await File(x.path).copy(p.join(s.photoDir, fn));
    setState(() => photoFile = fn);
  }

  Future<void> _save() async {
    final s = context.read<AppState>();
    final old = widget.existing;
    // Vanilla extract (alcohol-based) becomes vanilla bean paste, 1:1.
    final ings = ingredients.text
        .split('\n')
        .where((l) => l.trim().isNotEmpty)
        .map((l) => _parse(Halal.halalize(l)))
        .toList();
    final stepList = steps.text
        .split('\n')
        .where((l) => l.trim().isNotEmpty)
        .map((l) => Halal.halalize(l.trim()))
        .toList();
    if (title.text.trim().isEmpty || ings.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Add a title and at least one ingredient')));
      return;
    }
    final r = Recipe(
      id: old?.id ?? 'mine:${DateTime.now().millisecondsSinceEpoch}',
      title: title.text.trim(),
      source: old?.source ?? RecipeSource.mine,
      cuisine: cuisine.text.trim(),
      meal: meal,
      minutes: int.tryParse(minutes.text),
      servings: int.tryParse(servings.text) ?? 4,
      image: old?.image,
      photoPath: photoFile,
      notes: old?.notes ?? '',
      tags: old?.tags ?? const [],
      ingredients: ings,
      steps: stepList,
    );
    if (Halal.isHaram(r.title) || ings.any((i) => Halal.isHaram(i.name)) || stepList.any(Halal.isHaram)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('This recipe has pork, alcohol or gelatin in it, so it can\'t be saved here.')));
      return;
    }
    await s.recipes.saveUserRecipe(r);
    s.touch();
    if (mounted) Navigator.pop(context, r.id);
  }

  ImageProvider? _provider(AppState s) {
    if (photoFile != null) return FileImage(File(p.join(s.photoDir, photoFile!)));
    final img = widget.existing?.image;
    if (img == null || img.isEmpty) return null;
    if (img.startsWith('asset:')) return AssetImage(img.substring(6));
    return ImagePolicy.network ? NetworkImage(img) : null;
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final editing = widget.existing != null;
    final provider = _provider(s);
    return Scaffold(
      appBar: AppBar(title: Text(editing ? 'Edit recipe' : 'Add a recipe')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        GestureDetector(
          onTap: _photo,
          child: Container(
            height: 150,
            decoration: BoxDecoration(
              color: BB.green100,
              borderRadius: BorderRadius.circular(20),
              image: provider != null ? DecorationImage(image: provider, fit: BoxFit.cover) : null,
            ),
            child: provider == null
                ? const Center(child: Icon(Icons.add_a_photo_outlined, size: 36, color: BB.green700))
                : Align(
                    alignment: Alignment.bottomRight,
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Chip(
                          avatar: const Icon(Icons.photo_library_outlined, size: 16),
                          label: const Text('Change photo')),
                    ),
                  ),
          ),
        ),
        if (editing && photoFile != null && (widget.existing!.image ?? '').isNotEmpty)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => setState(() => photoFile = null),
              icon: const Icon(Icons.undo, size: 18),
              label: const Text('Use the original photo'),
            ),
          ),
        const SizedBox(height: 12),
        TextField(controller: title, textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Recipe name')),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: DropdownButtonFormField<String>(
              initialValue: meal,
              decoration: const InputDecoration(labelText: 'Meal'),
              items: const [
                DropdownMenuItem(value: 'breakfast', child: Text('Breakfast')),
                DropdownMenuItem(value: 'lunch', child: Text('Lunch')),
                DropdownMenuItem(value: 'dinner', child: Text('Dinner')),
                DropdownMenuItem(value: 'dessert', child: Text('Dessert')),
                DropdownMenuItem(value: 'bread', child: Text('Bread')),
                DropdownMenuItem(value: 'snack', child: Text('Snack / sweet')),
                DropdownMenuItem(value: 'drink', child: Text('Drink')),
                DropdownMenuItem(value: 'side', child: Text('Side')),
              ],
              onChanged: (v) => setState(() => meal = v!),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(child: TextField(controller: cuisine, decoration: const InputDecoration(labelText: 'Cuisine'))),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
              child: TextField(controller: servings, keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Servings'))),
          const SizedBox(width: 10),
          Expanded(
              child: TextField(controller: minutes, keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Minutes'))),
        ]),
        const SizedBox(height: 10),
        TextField(
          controller: ingredients,
          minLines: 5,
          maxLines: 30,
          decoration: const InputDecoration(
              labelText: 'Ingredients (one per line)', hintText: '2 cups basmati rice\n500 g chicken thighs\n1 tsp cumin'),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: steps,
          minLines: 5,
          maxLines: 40,
          decoration: const InputDecoration(labelText: 'Method (one step per line)'),
        ),
        const SizedBox(height: 16),
        FilledButton(onPressed: _save, child: Text(editing ? 'Save changes' : 'Save recipe')),
      ]),
    );
  }
}
