class Ingredient {
  Ingredient({required this.name, this.qty = '', String? search, this.optional = false})
      : search = (search == null || search.isEmpty) ? name : search;

  final String name;
  final String qty;

  /// What to look for in store search ("chicken thighs").
  final String search;
  final bool optional;

  Map<String, Object?> toJson() =>
      {'name': name, 'qty': qty, 'search': search, if (optional) 'optional': true};

  factory Ingredient.fromJson(Map<String, dynamic> m) => Ingredient(
        name: m['name'] as String,
        qty: (m['qty'] as String?) ?? '',
        search: m['search'] as String?,
        optional: (m['optional'] ?? false) == true,
      );
}

enum RecipeSource { book, catalog, mine }

class Recipe {
  Recipe({
    required this.id,
    required this.title,
    required this.source,
    required this.ingredients,
    required this.steps,
    this.cuisine = '',
    this.meal = 'dinner',
    this.minutes,
    this.servings = 4,
    this.image,
    this.photoPath,
    this.notes = '',
    this.tags = const [],
  });

  final String id;
  final String title;
  final RecipeSource source;
  final List<Ingredient> ingredients;
  final List<String> steps;
  final String cuisine;
  final String meal;
  final int? minutes;
  final int servings;

  /// Remote URL or "asset:..." path.
  final String? image;

  /// File name inside the app photo folder (recipes the user added).
  final String? photoPath;
  final String notes;
  final List<String> tags;

  Map<String, Object?> toJson() => {
        'id': id,
        'title': title,
        'cuisine': cuisine,
        'meal': meal,
        'minutes': minutes,
        'servings': servings,
        'image': image,
        'photo': photoPath,
        'notes': notes,
        'tags': tags,
        'ingredients': [for (final i in ingredients) i.toJson()],
        'steps': steps,
      };

  factory Recipe.fromJson(Map<String, dynamic> m, RecipeSource source) => Recipe(
        id: m['id'] as String,
        title: m['title'] as String,
        source: source,
        cuisine: (m['cuisine'] as String?) ?? '',
        meal: (m['meal'] as String?) ?? 'dinner',
        minutes: (m['minutes'] as num?)?.toInt(),
        servings: (m['servings'] as num?)?.toInt() ?? 4,
        image: m['image'] as String?,
        photoPath: m['photo'] as String?,
        notes: (m['notes'] as String?) ?? '',
        tags: ((m['tags'] as List?) ?? const []).cast<String>(),
        ingredients: ((m['ingredients'] as List?) ?? const [])
            .map((e) => Ingredient.fromJson(e as Map<String, dynamic>))
            .toList(),
        steps: ((m['steps'] as List?) ?? const []).cast<String>(),
      );
}

/// Scales the leading number in a quantity text ("1 1/2 cups" x2 = "3 cups").
/// Leaves text alone when there is no leading number.
String scaleQty(String qty, double factor) {
  if (factor == 1 || qty.trim().isEmpty) return qty;
  final m = RegExp(r'^(\s*)(\d+\s+\d+/\d+|\d+/\d+|\d+(?:\.\d+)?)').firstMatch(qty);
  if (m == null) return qty;
  final tok = m.group(2)!;
  double v;
  if (tok.contains('/')) {
    final parts = tok.split(RegExp(r'\s+'));
    final frac = parts.last.split('/');
    v = (parts.length == 2 ? double.parse(parts.first) : 0) + int.parse(frac[0]) / int.parse(frac[1]);
  } else {
    v = double.parse(tok);
  }
  return '${m.group(1)}${_fmt(v * factor)}${qty.substring(m.end)}';
}

String _fmt(double v) {
  final whole = v.floor();
  final frac = v - whole;
  final fr = {0.25: '¼', 0.5: '½', 0.75: '¾', 0.33: '⅓', 0.67: '⅔', 0.125: '⅛'};
  for (final e in fr.entries) {
    if ((frac - e.key).abs() < 0.04) return whole == 0 ? e.value : '$whole${e.value}';
  }
  if (frac < 0.04) return '$whole';
  if (frac > 0.96) return '${whole + 1}';
  return v.toStringAsFixed(1).replaceFirst(RegExp(r'\.0$'), '');
}
