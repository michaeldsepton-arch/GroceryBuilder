import 'dart:convert';

/// What belongs in the app: groceries and things bought on a typical grocery
/// trip. Rarely bought things (appliances, mops, electronics, furniture, toys,
/// tools...) are dropped when prices load. Terms live in assets/seed/scope_terms.json.
/// A term with a space (or dash) matches as a phrase, a single word matches a whole word.
class Scope {
  /// Bump when the rules change so the app re-imports prices with the new rules.
  static const version = 4;

  static List<String> _block = [];
  static List<String> _keep = [];
  static List<String> _blockCategory = [];
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
    _categories.clear();
    for (final c in (m['categories'] as List? ?? const []).cast<Map<String, dynamic>>()) {
      _categories.add(MapEntry(c['name'] as String,
          (c['terms'] as List).cast<String>().map((s) => s.toLowerCase()).toList()));
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

  static bool _has(String lower, Set<String> tokens, String term) =>
      term.contains(' ') || term.contains('-') ? lower.contains(term) : tokens.contains(term);

  static bool _any(String text, List<String> terms) {
    final lower = text.toLowerCase();
    final tokens = _tokens(lower);
    for (final t in terms) {
      if (_has(lower, tokens, t)) return true;
    }
    return false;
  }

  /// False for rarely bought things (appliances, mops, toys, furniture, tools...).
  static bool inScope(String name, String brand, String category) {
    if (!_ready) return true;
    final text = '$name $brand';
    if (_any(text, _keep)) return true;
    if (_any(text, _block)) return false;
    if (category.isNotEmpty && _any(category, _blockCategory)) return false;
    return true;
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
    _memo[key] = out;
    return out;
  }
}
