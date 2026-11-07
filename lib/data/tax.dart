import 'dart:convert';

import 'scope.dart';

/// Which items carry 5% GST (Alberta has no provincial sales tax). Basic groceries are
/// zero-rated; snacks, candy, pop and sweetened drinks, prepared hot food, pet food and
/// everything that is not food are taxed. Terms live in assets/seed/tax_terms.json
/// (mirrored by tools/tax_check.py).
class Tax {
  static List<String> _nonfood = [], _zero = [], _taxable = [], _categories = [], _baby = [];
  static bool _ready = false;
  static final Map<String, bool> _memo = {};

  static void configure(String json) {
    final m = jsonDecode(json) as Map<String, dynamic>;
    List<String> list(String k) => (m[k] as List? ?? const []).cast<String>().map((s) => s.toLowerCase()).toList();
    _nonfood = list('nonfood');
    _zero = list('zero');
    _taxable = list('taxable');
    _baby = list('baby_taxable');
    _categories = (m['taxable_categories'] as List? ?? const []).cast<String>();
    _memo.clear();
    _ready = true;
  }

  /// [fallback] is used only when the rules are not loaded.
  static bool isTaxable(String name, String brand, String category, {bool fallback = false}) {
    if (!_ready || !Scope.ready) return fallback;
    final key = '$name|$brand|$category';
    return _memo.putIfAbsent(key, () => _decide(name, brand, category));
  }

  static bool _decide(String name, String brand, String category) {
    final text = '$name $brand';
    if (Scope.anyTerm(text, _nonfood)) return true;
    final shop = Scope.categoryOf(name, category);
    if (_categories.contains(shop)) return true;
    if (Scope.anyTerm(text, _zero)) return false;
    if (Scope.anyTerm(text, _taxable)) return true;
    return shop == 'Baby' && Scope.anyTerm(text, _baby);
  }
}
