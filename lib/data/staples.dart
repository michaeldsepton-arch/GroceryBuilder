import 'dart:convert';

import '../models/models.dart';
import '../models/units.dart';
import 'matching.dart';

class _Entry {
  _Entry(this.group, this.name, this.x, this.b, this.fresh, this.end, this.litres);
  final String group, name;
  final List<String> x, b;
  final bool fresh, end;
  final List<List<double>>? litres;
}

/// The everyday items the app shows (assets/seed/staples.json, mirrored by tools/staples_check.py).
/// The full price list stays stored; this only marks items as everyday ("typical") and flags
/// prices that cannot be right ("sane" false), and the app hides accordingly.
class Staples {
  /// Bump when staples.json changes so prices are re-marked on the next refresh.
  static const version = 1;

  static final List<_Entry> _entries = [];
  static final Map<String, List<(int, String)>> _index = {};
  static final Map<String, RegExp> _rx = {};
  static Set<String> _tailOk = {}, _badPrefix = {};
  static double _maxPrice = 30, _minWeight = 0.04, _minVolume = 0.02;
  static List<String> _volumeExempt = [];
  static List<String> scopeKeep = [];
  static bool _ready = false;
  static final _nameSize = RegExp(r'(\d+(?:\.\d+)?)\s*(ml|l|litres?|liters?)(?![a-z])');

  static bool get ready => _ready;

  static void configure(String json) {
    final m = jsonDecode(json) as Map<String, dynamic>;
    final rules = m['rules'] as Map<String, dynamic>;
    _maxPrice = (rules['max_price'] as num).toDouble();
    _minWeight = (rules['min_per_100_weight'] as num).toDouble();
    _minVolume = (rules['min_per_100_volume'] as num).toDouble();
    _volumeExempt = (rules['volume_exempt_words'] as List).cast<String>();
    _tailOk = {...noiseWords, ...(rules['tail_ok'] as List).cast<String>()};
    _badPrefix = (rules['bad_prefix'] as List).cast<String>().toSet();
    scopeKeep = (m['scope_keep'] as List? ?? const []).cast<String>();
    _entries.clear();
    _index.clear();
    for (final g in (m['groups'] as List).cast<Map<String, dynamic>>()) {
      final gopts = (g['opts'] as Map<String, dynamic>?) ?? const {};
      for (final e in (g['items'] as List).cast<List<dynamic>>()) {
        final opts = e.length > 3 ? (e[3] as Map<String, dynamic>) : const <String, dynamic>{};
        List<String> lower(dynamic l) => ((l as List?) ?? const []).cast<String>().map((s) => s.toLowerCase()).toList();
        final end = opts['e'] ?? gopts['e'] ?? false;
        final idx = _entries.length;
        _entries.add(_Entry(
          g['id'] as String,
          e[0] as String,
          [...lower(opts['x']), ...lower(gopts['x'])],
          lower(opts['b']),
          end == 'fresh',
          end != false,
          (opts['l'] as List?)?.map((r) => (r as List).map((v) => (v as num).toDouble()).toList()).toList(),
        ));
        for (final p in (e[1] as String).split('|')) {
          final phrase = p.trim().toLowerCase();
          final toks = tokenize(phrase);
          if (toks.isEmpty) continue;
          (_index[toks.first] ??= []).add((idx, phrase));
        }
      }
    }
    _ready = true;
  }

  static bool _phraseIn(String text, String phrase) =>
      _rx.putIfAbsent(phrase, () => RegExp('(?<![a-z0-9])${RegExp.escape(phrase)}s?(?![a-z0-9])')).hasMatch(text);

  /// Fresh food names are plain: the food is the last word, only package and size words may follow,
  /// and (for fresh produce) no "processed" word may come before it.
  static bool _plain(String name, String brand, List<String> pt, bool fresh) {
    final nt = mainTokens(name);
    final bset = tokenize(brand).toSet();
    final n = pt.length;
    for (var k = nt.length - n; k >= 0; k--) {
      var same = true;
      for (var j = 0; j < n; j++) {
        if (nt[k + j] != pt[j]) {
          same = false;
          break;
        }
      }
      if (!same) continue;
      final tail = nt.sublist(k + n).where((t) => !bset.contains(t) && t.length > 1);
      final head = nt.sublist(0, k).where((t) => !bset.contains(t));
      if (tail.every(_tailOk.contains) && !(fresh && head.any(_badPrefix.contains))) return true;
    }
    return false;
  }

  static double? _litres(String name, double sizeValue, Unit unit) {
    if (unit.kind == UnitKind.volume) return sizeValue * unit.baseFactor / 1000;
    final m = _nameSize.firstMatch(name.toLowerCase());
    if (m == null) return null;
    final v = double.parse(m.group(1)!);
    return m.group(2)!.startsWith('l') ? v : v / 1000;
  }

  /// True when the item is one of the everyday items.
  static bool isTypical(Item i) {
    if (!_ready) return true;
    final lower = i.name.toLowerCase();
    final toks = mainTokens(i.name).toSet();
    for (final t in toks) {
      for (final (k, phrase) in _index[t] ?? const <(int, String)>[]) {
        final e = _entries[k];
        if (relevance(i, phrase) <= 0) continue;
        if (e.x.any((x) => _phraseIn(lower, x))) continue;
        if (e.end && !_plain(i.name, i.brand, tokenize(phrase), e.fresh)) continue;
        if (e.litres != null) {
          final v = _litres(i.name, i.sizeValue, i.sizeUnit);
          if (v == null || !e.litres!.any((r) => v >= r[0] && v <= r[1])) continue;
        }
        return true;
      }
    }
    final brand = i.brand.toLowerCase();
    if (brand.isNotEmpty) {
      for (final e in _entries) {
        if (e.b.isNotEmpty && e.litres == null && e.b.any((b) => _phraseIn(brand, b))) return true;
      }
    }
    return false;
  }

  /// False for prices that cannot be right or are too dear for one item.
  static bool isSane(String name, double price, double sizeValue, Unit unit) {
    if (!_ready) return true;
    if (price > _maxPrice) return false;
    if (unit.kind == UnitKind.each) return true;
    final base = sizeValue * unit.baseFactor;
    if (base <= 0) return true;
    final per = price / base * 100;
    final vol = unit.kind == UnitKind.volume;
    if (per < (vol ? _minVolume : _minWeight)) {
      final lower = name.toLowerCase();
      if (vol && _volumeExempt.any((w) => _phraseIn(lower, w))) return true;
      return false;
    }
    return true;
  }
}
