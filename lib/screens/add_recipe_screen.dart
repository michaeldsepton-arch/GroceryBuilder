import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../data/halal.dart';
import '../models/recipe.dart';
import '../state/app_state.dart';
import '../theme.dart';

/// Quick way to add a recipe by typing. (Photos of recipe books are
/// transcribed by Claude and arrive with app updates.)
class AddRecipeScreen extends StatefulWidget {
  const AddRecipeScreen({super.key});
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

  static final _qtyRe = RegExp(
      r'^\s*([\d½¼¾⅓⅔][\d\s/.½¼¾⅓⅔-]*\s*(?:cups?|tbsp|tsp|tablespoons?|teaspoons?|g|kg|ml|l|lb|lbs|oz|cloves?|pinch|cans?|pieces?|slices?|bunch|sprigs?)?\b\.?)\s+(.+)$',
      caseSensitive: false);

  Ingredient _parse(String line) {
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
      id: 'mine:${DateTime.now().millisecondsSinceEpoch}',
      title: title.text.trim(),
      source: RecipeSource.mine,
      cuisine: cuisine.text.trim(),
      meal: meal,
      minutes: int.tryParse(minutes.text),
      servings: int.tryParse(servings.text) ?? 4,
      photoPath: photoFile,
      ingredients: ings,
      steps: stepList,
    );
    if (Halal.isHaram(r.title) || ings.any((i) => Halal.isHaram(i.name)) || stepList.any(Halal.isHaram)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('This recipe has pork, alcohol or gelatin in it, so it can\'t be saved here.')));
      return;
    }
    await s.recipes.saveUserRecipe(r);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final photo = photoFile == null ? null : File(p.join(s.photoDir, photoFile!));
    return Scaffold(
      appBar: AppBar(title: const Text('Add a recipe')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        GestureDetector(
          onTap: _photo,
          child: Container(
            height: 150,
            decoration: BoxDecoration(
              color: BB.green100,
              borderRadius: BorderRadius.circular(20),
              image: photo != null ? DecorationImage(image: FileImage(photo), fit: BoxFit.cover) : null,
            ),
            child: photo == null
                ? const Center(child: Icon(Icons.add_a_photo_outlined, size: 36, color: BB.green700))
                : null,
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
          maxLines: 14,
          decoration: const InputDecoration(
              labelText: 'Ingredients (one per line)', hintText: '2 cups basmati rice\n500 g chicken thighs\n1 tsp cumin'),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: steps,
          minLines: 5,
          maxLines: 20,
          decoration: const InputDecoration(labelText: 'Method (one step per line)'),
        ),
        const SizedBox(height: 16),
        FilledButton(onPressed: _save, child: const Text('Save recipe')),
      ]),
    );
  }
}
