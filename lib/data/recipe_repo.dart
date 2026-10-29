import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:sqflite/sqflite.dart';

import '../models/models.dart';
import '../models/recipe.dart';
import 'halal.dart';
import 'matching.dart';
import 'repo.dart';

class SubOption {
  SubOption(this.label, this.note, this.search);
  final String label, note, search;
}

class RecipeRepo {
  RecipeRepo(this.repo);
  final Repo repo;
  Database get db => repo.db;

  List<Recipe> all = [];
  Set<String> favourites = {};

  /// Built-in recipes the user has changed (can be restored to the original).
  Set<String> edited = {};
  int hidden = 0; // recipes dropped by the halal filter
  final List<MapEntry<List<String>, List<SubOption>>> _subs = [];
  Map<String, List<String>> aliases = {};

  Future<void> load() async {
    final recipes = <Recipe>[];
    Future<void> loadAsset(String path, RecipeSource src) async {
      try {
        final list = jsonDecode(await rootBundle.loadString(path)) as List;
        for (final m in list.cast<Map<String, dynamic>>()) {
          recipes.add(Recipe.fromJson(m, src));
        }
      } catch (_) {/* optional asset */}
    }

    await loadAsset('assets/recipes/book.json', RecipeSource.book);
    await loadAsset('assets/recipes/catalog.json', RecipeSource.catalog);
    edited = {};
    for (final r in await db.query('user_recipes')) {
      final m = jsonDecode(r['json'] as String) as Map<String, dynamic>;
      // Same id as a built-in recipe: this is the user's edit of it, keep it in its section.
      final at = recipes.indexWhere((x) => x.id == m['id']);
      if (at >= 0) {
        recipes[at] = Recipe.fromJson(m, recipes[at].source);
        edited.add(m['id'] as String);
      } else {
        recipes.add(Recipe.fromJson(m, RecipeSource.mine));
      }
    }
    hidden = 0;
    all = recipes.where((r) {
      final bad = isHaramRecipe(r);
      if (bad) hidden++;
      return !bad;
    }).toList();
    favourites = {
      for (final r in await db.query('recipe_meta', where: 'favourite = 1')) r['recipe_id'] as String
    };
    if (aliases.isEmpty) {
      try {
        final a = jsonDecode(await rootBundle.loadString('assets/recipes/aliases.json')) as Map<String, dynamic>;
        aliases = {for (final e in a.entries) e.key.toLowerCase(): (e.value as List).cast<String>()};
      } catch (_) {}
    }
    if (_subs.isEmpty) {
      final subs = jsonDecode(await rootBundle.loadString('assets/recipes/substitutions.json')) as List;
      for (final m in subs.cast<Map<String, dynamic>>()) {
        _subs.add(MapEntry((m['match'] as List).cast<String>().map((s) => s.toLowerCase()).toList(), [
          for (final o in (m['options'] as List).cast<Map<String, dynamic>>())
            SubOption(o['label'] as String, o['note'] as String, o['search'] as String)
        ]));
      }
    }
  }

  static bool isHaramRecipe(Recipe r) =>
      Halal.isHaram(r.title) ||
      r.ingredients.any((i) => Halal.isHaram('${i.name} ${i.search}')) ||
      r.steps.any(Halal.isHaram);

  List<Recipe> get book => all.where((r) => r.source != RecipeSource.catalog).toList();
  List<Recipe> get catalog => all.where((r) => r.source == RecipeSource.catalog).toList();

  Future<void> toggleFavourite(Recipe r) async {
    final fav = !favourites.contains(r.id);
    await db.insert('recipe_meta', {'recipe_id': r.id, 'favourite': fav ? 1 : 0},
        conflictAlgorithm: ConflictAlgorithm.replace);
    fav ? favourites.add(r.id) : favourites.remove(r.id);
  }

  Future<void> saveUserRecipe(Recipe r) async {
    await db.insert('user_recipes',
        {'id': r.id, 'json': jsonEncode(r.toJson()), 'created': DateTime.now().toIso8601String()},
        conflictAlgorithm: ConflictAlgorithm.replace);
    await load();
  }

  Future<void> deleteUserRecipe(String id) async {
    await db.delete('user_recipes', where: 'id = ?', whereArgs: [id]);
    await load();
  }

  // ---- substitutions ----
  /// Substitutes for an ingredient; most specific table entry wins.
  List<SubOption> substitutesFor(Ingredient ing) {
    final name = '${ing.name} ${ing.search}'.toLowerCase();
    MapEntry<List<String>, List<SubOption>>? best;
    var bestLen = 0;
    for (final e in _subs) {
      for (final k in e.key) {
        if (RegExp('(?<![a-z])${RegExp.escape(k)}(?![a-z])').hasMatch(name) && k.length > bestLen) {
          best = e;
          bestLen = k.length;
        }
      }
    }
    return best?.value.where((o) => !Halal.isHaram('${o.label} ${o.search}')).toList() ?? const [];
  }

  // ---- product suggestions ----
  static final _meatTerm = RegExp(
      r'chicken|beef|lamb|goat|mutton|veal|mince|qeema|keema|steak|drumstick|wings|thigh|brisket|oxtail',
      caseSensitive: false);

  /// Best product for an ingredient: relevance first, then the option that covers
  /// the needed amount for the least money. Meat prefers the halal market.
  /// Null when nothing in the catalog matches.
  Future<Suggestion?> suggest(String term, {Need? need}) async {
    final byId = <String, Item>{};
    final terms = [term, ...?aliases[term.toLowerCase()]];
    for (final t in terms) {
      for (final i in await repo.search(t, limit: 80)) {
        byId[i.id] = i;
      }
      // Try alternatives only when the main term found little.
      if (byId.length >= 6) break;
    }
    var pool = byId.values.toList();
    if (pool.isEmpty) return null;
    if (_meatTerm.hasMatch(term)) {
      final h = pool.where((i) => i.storeId == 'halal').toList();
      if (h.isNotEmpty) pool = h;
    }
    final best = pickBest(pool, terms, need);
    if (best == null) return null;
    return Suggestion(best.item, best.cover);
  }
}

class Suggestion {
  Suggestion(this.item, this.cover);
  final Item item;
  final Cover cover;
}
