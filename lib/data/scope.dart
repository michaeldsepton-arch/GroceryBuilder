import 'dart:convert';

/// What belongs in the app: groceries and things bought on a typical grocery
/// trip. Rarely bought things (appliances, mops, electronics, furniture, toys,
/// tools...) are dropped when prices load. Terms live in assets/seed/scope_terms.json.
/// A term with a space (or dash) matches as a phrase, a single word matches a whole word.
class Scope {
  /// Bump when the rules change so the app re-imports prices with the new rules.
  static const version = 8;

  static List<String> _block = [];
  static List<String> _keep = [];
  static List<String> _blockCategory = [];
  static List<String> _blockSoft = [];
  static final List<MapEntry<String, String>> _fallback = [];
  static final Map<String, RegExp> _phrases = {};
  static final List<MapEntry<String, List<String>>> _categories = [];
  static final Map<String, String> _memo = {};
  static bool _ready = false;

  static final _wordRe = RegExp(r"[a-z0-9']+");

  static void configure(String json) {
    final m = jsonDecode(json) as Map<String, dynamic>;
    List<String> list(String k) => (m[k] as List? ?? const []).cast<String>().map((s) => s.toLowerCase()).toList();
    _block = list('block');
    _keep = list('keep');
    _blockCategory = list('block_category');
    _blockSoft = list('block_soft');
    _phrases.clear();
    _categories.clear();
    for (final c in (m['categories'] as List? ?? const []).cast<Map<String, dynamic>>()) {
      _categories.add(MapEntry(c['name'] as String,
          (c['terms'] as List).cast<String>().map((s) => s.toLowerCase()).toList()));
    }
    _fallback.clear();
    for (final f in (m['category_fallback'] as List? ?? const []).cast<Map<String, dynamic>>()) {
      _fallback.add(MapEntry((f['match'] as String).toLowerCase(), f['category'] as String));
    }
    _memo.clear();
    _ready = true;
  }

  static bool get ready => _ready;

  static List<String> get categoryNames => [for (final c in _categories) c.key, 'Other'];

  static Set<String> _tokens(String lower) {
    final t = <String>{};
    for (final m in _wordRe.allMatches(lower)) {
      final w = m.group(0)!;
      t.add(w);
      if (w.length > 3 && w.endsWith('s')) t.add(w.substring(0, w.length - 1));
    }
    return t;
  }

  /// A phrase must start and end on a word edge ("air conditioner" is not "hair conditioner").
  static bool _has(String lower, Set<String> tokens, String term) {
    if (!term.contains(' ') && !term.contains('-')) return tokens.contains(term);
    final rx = _phrases.putIfAbsent(
        term, () => RegExp('(?<![a-z0-9])${RegExp.escape(term)}s?(?![a-z0-9])'));
    return rx.hasMatch(lower);
  }

  static bool _any(String text, List<String> terms) {
    final lower = text.toLowerCase();
    final tokens = _tokens(lower);
    for (final t in terms) {
      if (_has(lower, tokens, t)) return true;
    }
    return false;
  }

  /// True when any of the terms is in the text (phrases match on word edges).
  static bool anyTerm(String text, List<String> terms) => _any(text, terms);

  /// False for rarely bought things (appliances, mops, toys, furniture, tools...).
  static bool inScope(String name, String brand, String category) {
    if (!_ready) return true;
    final text = '$name $brand';
    if (_any(text, _keep)) return true;
    if (_any(text, _block)) return false;
    if (category.isNotEmpty && _any(category, _blockCategory)) return false;
    // Characters and clothing words only count when the item fits no shopping category
    // (Barbie crispy squares and men's body wash stay).
    if (_any(text, _blockSoft) && categoryOf(name, category) == 'Other') return false;
    // Allow-list: it must fit a shopping category, otherwise it is not a grocery-trip item.
    return categoryOf(name, category) != 'Other';
  }

  /// Shopping category used to browse and sort. The store's own category text is
  /// tried first, then the product name; "Other" when nothing matches.
  static String categoryOf(String name, String category) {
    if (!_ready) return 'Other';
    final key = '$category|$name';
    final hit = _memo[key];
    if (hit != null) return hit;
    var out = 'Other';
    outer:
    for (final text in [category, name]) {
      if (text.isEmpty) continue;
      final lower = text.toLowerCase();
      final tokens = _tokens(lower);
      for (final c in _categories) {
        for (final t in c.value) {
          if (_has(lower, tokens, t)) {
            out = c.key;
            break outer;
          }
        }
      }
    }
    if (out == 'Other' && category.isNotEmpty) {
      // the store's own tag ("food", "Personal Care") when no word matched
      final lower = category.toLowerCase();
      final tokens = _tokens(lower);
      for (final f in _fallback) {
        if (_has(lower, tokens, f.key)) {
          out = f.value;
          break;
        }
      }
    }
    _memo[key] = out;
    return out;
  }
}
