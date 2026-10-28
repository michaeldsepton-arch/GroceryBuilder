import 'dart:math' as math;

import '../models/models.dart';
import '../models/units.dart';

/// What a recipe line needs, in base units.
enum NeedKind { weight, volume, count, pack }

class Need {
  Need(this.amount, this.kind);
  final double amount; // grams, millilitres, pieces, or packs
  final NeedKind kind;
}

const _unitMl = {
  'ml': 1.0, 'millilitre': 1.0, 'millilitres': 1.0, 'milliliter': 1.0, 'milliliters': 1.0,
  'l': 1000.0, 'litre': 1000.0, 'litres': 1000.0, 'liter': 1000.0, 'liters': 1000.0,
  'cup': 240.0, 'cups': 240.0, 'tbsp': 15.0, 'tablespoon': 15.0, 'tablespoons': 15.0, 'tbs': 15.0,
  'tsp': 5.0, 'teaspoon': 5.0, 'teaspoons': 5.0,
};
const _unitG = {
  'g': 1.0, 'gram': 1.0, 'grams': 1.0, 'kg': 1000.0, 'kilogram': 1000.0, 'kilograms': 1000.0,
  'lb': gramsPerLb, 'lbs': gramsPerLb, 'pound': gramsPerLb, 'pounds': gramsPerLb,
  'oz': 28.349523125, 'ounce': 28.349523125, 'ounces': 28.349523125,
};
/// Whole packs: "2 cans" means two cans.
const _packWords = {
  'can', 'cans', 'tin', 'tins', 'jar', 'jars', 'package', 'packages', 'pkg', 'packet', 'packets', 'box',
  'boxes', 'bag', 'bags', 'bunch', 'bunches', 'head', 'heads', 'bottle', 'bottles',
};

/// Bits of something: "3 cloves" of garlic is one bulb, not three packs.
const _smallWords = {
  'clove', 'cloves', 'pinch', 'dash', 'sprig', 'sprigs', 'handful', 'stick', 'sticks', 'sheet', 'sheets',
  'stalk', 'stalks', 'rib', 'ribs', 'slice', 'slices', 'leaf', 'leaves', 'piece', 'pieces',
};
const _vulgar = {'½': 0.5, '¼': 0.25, '¾': 0.75, '⅓': 1 / 3, '⅔': 2 / 3, '⅛': 0.125};

/// "1 1/2 cups", "500 g", "2-3 tbsp", "a pinch", "4". [factor] scales servings.
Need? parseNeed(String qty, [double factor = 1]) {
  var q = qty.toLowerCase().trim();
  if (q.isEmpty) return null;
  double? n;
  var rest = q;
  _vulgar.forEach((k, v) => q = q.replaceAll(k, ' ${v.toString()} '));
  rest = q.trim();
  RegExpMatch? m;
  if ((m = RegExp(r'^(\d+)\s+(\d+)\s*/\s*(\d+)').firstMatch(rest)) != null) {
    n = double.parse(m!.group(1)!) + double.parse(m.group(2)!) / double.parse(m.group(3)!);
  } else if ((m = RegExp(r'^(\d+)\s*/\s*(\d+)').firstMatch(rest)) != null) {
    n = double.parse(m!.group(1)!) / double.parse(m.group(2)!);
  } else if ((m = RegExp(r'^(\d+(?:\.\d+)?)\s*(?:-|–|to)\s*(\d+(?:\.\d+)?)').firstMatch(rest)) != null) {
    n = double.parse(m!.group(2)!); // upper end of a range
  } else if ((m = RegExp(r'^(\d+(?:\.\d+)?)').firstMatch(rest)) != null) {
    n = double.parse(m!.group(1)!);
  } else if (RegExp(r'^(a|an|one)\b').hasMatch(rest) || RegExp(r'pinch|dash|handful').hasMatch(rest)) {
    return Need(1, NeedKind.pack);
  }
  if (n == null) return null;
  rest = rest.substring(m!.end).trim();
  // "2 x 400g" style: multiplier then amount
  final mult = RegExp(r'^[x×]\s*(\d+(?:\.\d+)?)\s*([a-z]+)').firstMatch(rest);
  if (mult != null) {
    n *= double.parse(mult.group(1)!);
    rest = mult.group(2)!;
  }
  final um = RegExp(r'^([a-z]+)').firstMatch(rest);
  final unit = um?.group(1);
  n *= factor;
  if (unit == null) return Need(n, NeedKind.count);
  if (_unitG.containsKey(unit)) return Need(n * _unitG[unit]!, NeedKind.weight);
  if (_unitMl.containsKey(unit)) return Need(n * _unitMl[unit]!, NeedKind.volume);
  if (_packWords.contains(unit)) return Need(math.max(1, n), NeedKind.pack);
  if (_smallWords.contains(unit)) return Need(1, NeedKind.pack);
  return Need(n, NeedKind.count);
}

/// How much of an item to buy for a need, and what it costs.
class Cover {
  Cover(this.qty, this.cost, this.exact);

  /// Cart quantity: packs for fixed items, grams for by-weight items.
  final double qty;
  final double cost;

  /// False when the recipe amount could not be matched to the product size.
  final bool exact;
}

/// Pieces in a pack when the size field has none: "Large 12 Eggs", "6 ct", "24 pk".
double? inferCount(String name) {
  final m = RegExp(r'(\d+)\s*(?:ct|count|pk|pack|pcs?|pieces|eggs?|rolls?|bagels?|buns?|bars?|bottles?|cans?)\b',
          caseSensitive: false)
      .firstMatch(name);
  return m == null ? null : double.parse(m.group(1)!);
}

Cover cover(Item i, Need? need) {
  if (i.variable) {
    if (need != null && need.kind == NeedKind.weight) {
      final g = math.max(100.0, (need.amount / 50).ceil() * 50.0);
      return Cover(g, i.lineCost(g), true);
    }
    return Cover(gramsPerLb, i.lineCost(gramsPerLb), false);
  }
  var packSize = i.sizeValue * i.sizeUnit.baseFactor;
  if (i.sizeUnit == Unit.each && i.sizeValue == 1) packSize = inferCount(i.name) ?? 1;
  double packs = 1;
  var exact = false;
  if (need != null) {
    if (need.kind == NeedKind.pack) {
      packs = math.max(1, need.amount.ceilToDouble());
      exact = true;
    } else if (packSize > 0 &&
        ((need.kind == NeedKind.weight && i.sizeUnit.kind == UnitKind.weight) ||
            (need.kind == NeedKind.volume && i.sizeUnit.kind == UnitKind.volume) ||
            (need.kind == NeedKind.count && i.sizeUnit.kind == UnitKind.each))) {
      packs = math.max(1, (need.amount / packSize).ceilToDouble());
      exact = true;
    }
  }
  return Cover(packs, packs * i.price, exact);
}

// ---------- relevance ----------

/// Words that make a product a different thing from the plain ingredient.
const _prepared = {
  'chips', 'crisps', 'flavour', 'flavor', 'flavoured', 'flavored', 'cookies', 'cookie', 'cracker',
  'crackers', 'snack', 'snacks', 'bar', 'bars', 'soup', 'cereal', 'candy', 'juice', 'drink', 'soda',
  'pop', 'dip', 'pizza', 'pie', 'cake', 'muffin', 'muffins', 'ready', 'meal', 'kit', 'popcorn',
  'sauce', 'simmer', 'dressing', 'marinade', 'spread', 'seasoning', 'mix', 'bites', 'nuggets', 'jerky', 'ice', 'gum', 'mints', 'syrup', 'granola', 'wrap', 'wraps', 'sandwich', 'tea', 'coffee', 'shampoo',
  'conditioner', 'lotion', 'soap', 'detergent', 'cleaner', 'scent', 'candle', 'toy', 'pet', 'dog', 'cat',
};
/// Tokens are singularised before comparing, so compare against singular forms too.
final Set<String> _preparedSing = _prepared.map(_sing).toSet();

const _noise = {
  'the', 'and', 'with', 'for', 'pack', 'family', 'value', 'size', 'fresh', 'organic', 'natural',
  'original', 'classic', 'premium', 'select', 'grade', 'canadian', 'canada', 'product', 'brand',
  'great', 'each', 'per', 'new', 'no', 'name', 'club', 'fine', 'extra', 'large', 'small', 'medium',
};
const _unitWords = {'kg', 'g', 'ml', 'l', 'lb', 'oz', 'ct', 'pk', 'pack', 'count', 'ea', 'litre', 'liter'};

String _sing(String w) {
  if (w.length < 4) return w;
  if (w.endsWith('ies')) return '${w.substring(0, w.length - 3)}y';
  if (w.endsWith('oes')) return w.substring(0, w.length - 2);
  if (w.endsWith('ss')) return w;
  if (w.endsWith('s')) return w.substring(0, w.length - 1);
  return w;
}

List<String> _tokens(String s) => s
    .toLowerCase()
    .split(RegExp(r'[^a-z0-9]+'))
    .where((t) => t.isNotEmpty)
    .map(_sing)
    .toList();

/// Nouns that name a different product when they end a product name:
/// "Garlic Butter", "Flour Tortillas", "Lemon Yogurt" are not garlic, flour or lemon.
const _heads = {
  'butter', 'yogurt', 'yoghurt', 'milk', 'cheese', 'bread', 'bagel', 'tortilla', 'wrap', 'cake', 'cookie',
  'cooky', 'cracker', 'chip', 'crisp', 'cereal', 'bar', 'sauce', 'soup', 'juice', 'drink', 'beverage', 'pop',
  'soda', 'tea', 'coffee', 'margarine', 'spread', 'dip', 'dressing', 'wing', 'nugget', 'burger', 'sausage',
  'pizza', 'pie', 'muffin', 'roll', 'bun', 'pasta', 'noodle', 'powder', 'paste', 'flake', 'extract',
  'seasoning', 'spice', 'mix', 'bite', 'ball', 'patty', 'jam', 'jelly', 'syrup', 'candy', 'chocolate', 'gum',
  'mint', 'popcorn', 'pretzel', 'granola', 'smoothie', 'shake', 'kit', 'biscuit', 'pancake',
  'waffle', 'cream', 'icecream', 'pudding', 'custard', 'egg', 'oil', 'vinegar', 'creamer', 'kebab', 'kabob',
  'chevapi', 'skewer', 'cup', 'pouch', 'meatball', 'sub', 'sandwich', 'tube', 'butr',
};

/// Product types so different from a plain ingredient that they rule it out
/// anywhere in the name ("Mango Yogurt Pouch" is not mango).
const _strict = {
  'butter', 'yogurt', 'yoghurt', 'milk', 'tortilla', 'bagel', 'wing', 'sausage', 'burger', 'pizza', 'pie', 'cake',
  'cookie', 'cooky', 'muffin', 'cereal', 'chip', 'cracker', 'candy', 'juice', 'soup', 'sauce', 'drink', 'creamer',
  'kebab', 'butr', 'tube', 'ice', 'pudding', 'granola', 'smoothie', 'popcorn', 'pretzel', 'biscuit', 'pancake', 'waffle',
};
final Set<String> _strictSing = _strict.map(_sing).toSet();

/// Words that turn the plain thing into something else (peanut butter, sour cream).
const _diverting = {
  'sour', 'peanut', 'almond', 'soy', 'oat', 'coconut', 'chocolate', 'condensed', 'evaporated', 'powdered',
  'shaving', 'body', 'hand', 'face', 'ice', 'frozen',
};
final Set<String> _headsSing = _heads.map(_sing).toSet();

final _cut = RegExp(r'\s(?:with|in|for|from|made|contains)\s|,|\s-\s|\||;', caseSensitive: false);

/// The product's own name: before "with ...", commas and sizes.
List<String> mainTokens(String name) {
  final cut = name.split(_cut).first.replaceAll(RegExp(r'[()®™&]'), ' ');
  return _tokens(cut).where((t) => !RegExp(r'^\d').hasMatch(t) && !_unitWords.contains(t)).toList();
}

/// 0..1ish: how plainly this product is the ingredient asked for.
double relevance(Item i, String term) {
  final tt = _tokens(term);
  final nt = mainTokens(i.name);
  if (tt.isEmpty || nt.isEmpty) return 0;
  if ('/'.allMatches(i.name.split(',').first).length >= 2) return 0; // flavour variety list
  final termSet = tt.toSet();
  // Every word asked for must be a whole word of the product's own name
  // ("salt" is not in "unsalted", "tea" is not in "steaks").
  for (final t in tt) {
    if (!nt.contains(t)) return 0;
  }
  // If the name ends in some other product noun, it is that product.
  final whole = _tokens(i.name.split(RegExp(r'\s(?:with|in|for|from|made|contains)\s', caseSensitive: false)).first
          .replaceAll(RegExp(r'[()®™&]'), ' '))
      .where((t) => !RegExp(r'^\d').hasMatch(t) && !_unitWords.contains(t) && t.length > 1)
      .toList();
  for (final last in {nt.last, if (whole.isNotEmpty) whole.last}) {
    if (_headsSing.contains(last) && !termSet.contains(last)) return 0;
  }
  for (final n in nt) {
    if (termSet.contains(n)) continue;
    if (_strictSing.contains(n) || _diverting.contains(n)) return 0;
  }
  final brand = _tokens(i.brand).toSet();
  var extra = 0;
  var bad = 0;
  for (final n in nt) {
    if (termSet.contains(n)) continue;
    if (n.length < 3 || _noise.contains(n) || brand.contains(n)) continue;
    extra++;
    if (_preparedSing.contains(n)) bad++;
  }
  var score = 1 / (1 + 0.25 * extra) - 0.5 * math.min(bad, 2);
  if (nt.take(tt.length).join(' ') == tt.join(' ')) score += 0.2;
  // The ingredient is the last word(s): "Salted Butter" is butter.
  if (nt.length >= tt.length && nt.sublist(nt.length - tt.length).join(' ') == tt.join(' ')) score += 0.3;
  if (i.name.contains('/')) score -= 0.3; // variety pack
  return score;
}

/// Pick the best product for a need from candidates (already searched).
({Item item, Cover cover})? pickBest(List<Item> candidates, Object term, Need? need) {
  final terms = term is List<String> ? term : [term as String];
  if (candidates.isEmpty) return null;
  final scored = [for (final c in candidates) (item: c, score: terms.map((t) => relevance(c, t)).reduce(math.max))]
      .where((e) => e.score > 0)
      .toList();
  if (scored.isEmpty) return null;
  final top = scored.map((e) => e.score).reduce(math.max);
  var tier = scored.where((e) => e.score >= top - 0.12).map((e) => e.item).toList();
  // Compare like with like when sizes are matched; otherwise rank by unit price.
  final covers = {for (final i in tier) i.id: cover(i, need)};
  final exactOnes = tier.where((i) => covers[i.id]!.exact).toList();
  if (exactOnes.isNotEmpty) tier = exactOnes;
  tier.sort((a, b) {
    final c = covers[a.id]!.cost.compareTo(covers[b.id]!.cost);
    return c != 0 ? c : a.unitPrice.compareValue.compareTo(b.unitPrice.compareValue);
  });
  if (need == null || !covers[tier.first.id]!.exact) {
    // Unknown amount: cheapest unit price, but avoid bulk packs when a much smaller
    // pack costs about the same per unit (a spice jar, not a 1 kg bag).
    final minUnit = tier.map((i) => i.unitPrice.compareValue).reduce(math.min);
    final near = tier.where((i) => i.unitPrice.compareValue <= minUnit * 1.6 && i.unitPrice.kind == tier.first.unitPrice.kind).toList()
      ..sort((a, b) => a.price.compareTo(b.price));
    if (near.isNotEmpty) return (item: near.first, cover: cover(near.first, need));
  }
  return (item: tier.first, cover: covers[tier.first.id]!);
}
