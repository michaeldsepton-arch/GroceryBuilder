import 'dart:convert';

/// App-wide halal filter. Pork and alcohol (and gelatin) never appear in
/// products, recipes or substitutes. Terms live in assets/recipes/haram_terms.json
/// so the app and the recipe builder share one list.
class Halal {
  static List<RegExp> _hard = [];
  static Map<RegExp, List<String>> _conditional = {};
  static List<String> _allow = [];
  static List<RegExp> _meat = [];
  static List<String> _meatNot = [];
  static bool _ready = false;

  static RegExp _word(String t) =>
      RegExp('(?<![a-z0-9])${RegExp.escape(t)}(?![a-z0-9])', caseSensitive: false);

  static void configure(String json) {
    final m = jsonDecode(json) as Map<String, dynamic>;
    _hard = [for (final t in (m['hard'] as List).cast<String>()) _word(t)];
    _conditional = {
      for (final e in (m['conditional'] as Map<String, dynamic>).entries)
        _word(e.key): (e.value as List).cast<String>().map((s) => s.toLowerCase()).toList()
    };
    _allow = (m['allow'] as List).cast<String>().map((s) => s.toLowerCase()).toList();
    _meat = [for (final t in (m['meat_words'] as List).cast<String>()) _word(t)];
    _meatNot = (m['meat_not'] as List).cast<String>().map((s) => s.toLowerCase()).toList();
    _ready = true;
  }

  static bool get ready => _ready;

  static final _vanilla = RegExp(r'\b(?:pure |natural |real |imitation )?vanilla (?:extract|essence)\b', caseSensitive: false);

  /// Vanilla extract is alcohol-based; we use vanilla bean paste (1:1) instead.
  static String halalize(String text) => text.replaceAllMapped(
      _vanilla, (m) => m.group(0)![0] == m.group(0)![0].toUpperCase() ? 'Vanilla bean paste' : 'vanilla bean paste');

  static String _stripAllowed(String text) {
    var s = text.toLowerCase();
    for (final a in _allow) {
      s = s.replaceAll(a, ' ');
    }
    return s;
  }

  /// True when the text mentions pork, alcohol or gelatin.
  static bool isHaram(String? text) {
    if (!_ready || text == null || text.isEmpty) return false;
    final s = _stripAllowed(text);
    for (final r in _hard) {
      if (r.hasMatch(s)) return true;
    }
    for (final e in _conditional.entries) {
      if (e.key.hasMatch(s) && !e.value.any((x) => x.isNotEmpty && s.contains(x))) {
        return true;
      }
    }
    return false;
  }

  /// Any meat product (halal-labelled or not). The family buys meat at the halal
  /// market, so supermarket meat is left out of the catalog entirely. Soups, broths,
  /// seasonings, sauces and seafood are not meat products.
  static bool isMeatProduct(String name, String category) {
    if (!_ready) return false;
    final s = '$name $category'.toLowerCase();
    if (s.contains('seafood') || s.contains('fish')) return false;
    if (_meatNot.any(s.contains)) return false;
    return _meat.any((r) => r.hasMatch(s));
  }

  /// Raw/processed meat that is not from a halal source: used to hide
  /// supermarket meat (not halal-slaughtered) when "halal meat only" is on.
  static bool isNonHalalMeatProduct(String name, String category, String storeId) {
    if (!_ready || storeId == 'halal') return false;
    final s = '$name $category'.toLowerCase();
    if (s.contains('halal') || s.contains('seafood') || s.contains('fish')) return false;
    if (_meatNot.any(s.contains)) return false;
    return _meat.any((r) => r.hasMatch(s));
  }
}
