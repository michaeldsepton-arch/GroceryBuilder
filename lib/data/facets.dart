import 'dart:convert';
import 'dart:math' as math;

import '../models/models.dart';
import '../models/units.dart';

/// Selected filters: facet id -> option keys. Inside one facet the options are alternatives
/// (4 L or 2 L); different facets must all hold (4 L and 2%), like McMaster-Carr.
typedef FilterSel = Map<String, Set<String>>;

class FacetOption {
  FacetOption(this.key, this.label, this.order, this.count);
  final String key;
  final String label;
  final double order;
  final int count;
}

class Facet {
  Facet(this.id, this.title, this.options);
  final String id;
  final String title;
  final List<FacetOption> options;
}

/// A named attribute found in product names ("Lactose free" from "lactose-free" or "lactose free").
class _Attr {
  const _Attr(this.key, this.label, this.phrases);
  final String key;
  final String label;
  final List<String> phrases;
}

const _diet = [
  _Attr('organic', 'Organic', ['organic']),
  _Attr('lactosefree', 'Lactose free', ['lactose free', 'lactose reduced']),
  _Attr('dairyfree', 'Dairy free / plant based', ['dairy free', 'non dairy', 'plant based', 'vegan']),
  _Attr('glutenfree', 'Gluten free', ['gluten free']),
  _Attr('nosugar', 'No sugar / unsweetened', ['sugar free', 'no sugar', 'no sugar added', 'zero sugar', 'unsweetened', 'diet']),
  _Attr('lowfat', 'Low fat / light', ['low fat', 'fat free', 'reduced fat', 'light', 'lite', 'lean', 'extra lean']),
  _Attr('lowsodium', 'Low sodium / unsalted', ['low sodium', 'reduced sodium', 'no salt added', 'unsalted', 'salt free', 'less salt']),
  _Attr('salted', 'Salted', ['salted']),
  _Attr('protein', 'High protein', ['high protein', 'protein']),
  _Attr('halal', 'Halal', ['halal', 'zabiha']),
  _Attr('wholegrain', 'Whole grain / whole wheat', ['whole grain', 'whole wheat', 'multigrain', 'multi grain']),
  _Attr('grassfed', 'Grass fed / free range', ['grass fed', 'free range', 'free run', 'pasture raised']),
];

const _form = [
  _Attr('boneless', 'Boneless', ['boneless']),
  _Attr('skinless', 'Skinless', ['skinless']),
  _Attr('bonein', 'Bone-in', ['bone in']),
  _Attr('skinon', 'Skin on', ['skin on', 'with skin']),
  _Attr('ground', 'Ground / minced', ['ground', 'minced', 'mince', 'qeema', 'keema']),
  _Attr('fillet', 'Fillets', ['fillet', 'fillets', 'filet', 'filets']),
  _Attr('sliced', 'Sliced', ['sliced', 'slices', 'slice']),
  _Attr('shredded', 'Shredded / grated', ['shredded', 'grated']),
  _Attr('block', 'Block', ['block', 'brick']),
  _Attr('diced', 'Diced / chopped', ['diced', 'chopped', 'cubed', 'cubes']),
  _Attr('crushed', 'Crushed', ['crushed']),
  _Attr('whole', 'Whole', ['whole']),
  _Attr('frozen', 'Frozen', ['frozen']),
  _Attr('fresh', 'Fresh', ['fresh']),
  _Attr('canned', 'Canned', ['canned', 'can', 'cans', 'tin', 'tinned']),
  _Attr('dried', 'Dried', ['dried', 'dry']),
  _Attr('powder', 'Powder', ['powder', 'powdered']),
  _Attr('paste', 'Paste', ['paste']),
  _Attr('liquid', 'Liquid', ['liquid']),
  _Attr('concentrate', 'Concentrate', ['concentrate', 'concentrated', 'frozen concentrate']),
  _Attr('instant', 'Instant', ['instant']),
  _Attr('cooked', 'Cooked / ready to eat', ['cooked', 'precooked', 'pre cooked', 'ready to eat', 'fully cooked']),
  _Attr('raw', 'Raw', ['raw']),
  _Attr('smoked', 'Smoked', ['smoked']),
  _Attr('breaded', 'Breaded / crispy', ['breaded', 'battered', 'crispy']),
  _Attr('marinated', 'Marinated / seasoned', ['marinated', 'seasoned']),
];

/// Words that say nothing about what kind of product it is.
const _stop = {
  'and', 'with', 'the', 'for', 'from', 'made', 'pack', 'value', 'family', 'size', 'club', 'original', 'classic',
  'new', 'each', 'per', 'style', 'brand', 'product', 'premium', 'select', 'great', 'natural', 'pure', 'real',
  'extra', 'large', 'small', 'medium', 'mini', 'jumbo', 'bag', 'box', 'bottle', 'jug', 'carton', 'case', 'count',
  'assorted', 'variety', 'flavour', 'flavor', 'flavoured', 'flavored', 'partly', 'partially', 'approx',
  'approximately', 'kg', 'lb', 'lbs', 'oz', 'pkg', 'tray', 'pouch', 'jar', 'tub', 'container', 'one', 'two',
  'three', 'only', 'our', 'your', 'free', 'added', 'less', 'reduced', 'low', 'high', 'zero', 'non', 'based',
  'grade', 'canada', 'canadian', 'ml', 'litre', 'liter', 'gram', 'grams', 'piece', 'pieces', 'pcs',
  'ct', 'pk', 'ea', 'sharing', 'bulk', 'twin', 'multipack', 'refill', 'bonus', 'limited', 'edition', 'favourite',
  'favorite', 'everyday', 'home', 'kitchen', 'quality', 'choice', 'compliment', 'compliments', 'name',
  'pound', 'year', 'naturally', 'ounce', 'gm', 'pc', 'mf',
};

String _singular(String w) {
  if (w.length < 4) return w;
  if (w.endsWith('ies')) return '${w.substring(0, w.length - 3)}y';
  if (w.endsWith('oes')) return w.substring(0, w.length - 2);
  if (w.endsWith('ss') || w.endsWith('us')) return w;
  if (w.endsWith('s')) return w.substring(0, w.length - 1);
  return w;
}

final Set<String> _vocabWords = {
  for (final a in [..._diet, ..._form])
    for (final p in a.phrases) ...p.split(' ').map(_singular),
  'skim', 'skimmed', 'homo', 'homogenized', 'homogenised',
};

final _nonWord = RegExp(r'[^a-z0-9]+');
final _letters = RegExp(r'^[a-z]+$');
final _nameSize = RegExp(r'(\d+(?:\.\d+)?)\s*(kg|g|lbs|lb|oz|ml|l|litres|litre|liters|liter)(?![a-z])');
final _pct = RegExp(r'(\d{1,3}(?:\.\d{1,2})?)\s*%');
final _packRes = [
  RegExp(r'(\d{1,3})\s*[x×]\s*\d'),
  RegExp(r'(\d{1,3})\s*-?\s*(?:pack|pk|cans|bottles|boxes|pouches|cups|bars)\b'),
  RegExp(r'(?:pack|case|box) of (\d{1,3})\b'),
];

String _trimNum(double v) {
  final s = v.toStringAsFixed(2);
  return s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
}

/// Rounds to three significant digits so 1.89 L and 1890 mL land together.
double _sig3(double x) {
  if (x >= 100) {
    final p = math.pow(10, (math.log(x) / math.ln10).floor() - 2).toDouble();
    return (x / p).round() * p;
  }
  return x >= 10 ? x.roundToDouble() : (x * 10).round() / 10;
}

class Facets {
  static const _titles = {
    'size': 'Size',
    'pct': 'Percent (fat, juice…)',
    'type': 'Type',
    'diet': 'Dietary',
    'form': 'Form & cut',
    'brand': 'Brand',
    'price': 'Price',
  };
  static const ids = ['size', 'pct', 'type', 'diet', 'form', 'brand', 'price'];

  static final Map<String, Map<String, String>> _labels = {for (final id in ids) id: {}};
  static final Map<String, Map<String, double>> _orders = {for (final id in ids) id: {}};
  static final Map<String, Map<String, Set<String>>> _memo = {};

  /// Label for a selected option, even if it is not in the current results.
  static String labelOf(String facet, String key) {
    final l = _labels[facet]?[key];
    if (l != null) return l;
    switch (facet) {
      case 'type':
      case 'brand':
        return key.isEmpty ? key : key[0].toUpperCase() + key.substring(1);
      case 'pct':
        return '$key%';
      case 'diet':
      case 'form':
        for (final a in [..._diet, ..._form]) {
          if (a.key == key) return a.label;
        }
        return key;
      case 'price':
        return const {
              'p0': 'Under \$2',
              'p1': '\$2 – \$5',
              'p2': '\$5 – \$10',
              'p3': '\$10 – \$20',
              'p4': '\$20 – \$50',
              'p5': '\$50 and up',
            }[key] ??
            key;
      case 'size':
        if (key == 'var') return 'Sold by weight';
        if (key == 'e1') return 'Each / size not listed';
        final x = RegExp(r'^([vge])(?:(\d+)x)?([\d.]+)$').firstMatch(key);
        if (x == null) return key;
        final v = double.parse(x.group(3)!);
        if (x.group(1) == 'e') return '${v.round()} count';
        final one = sizeBoth(v, x.group(1) == 'v' ? Unit.ml : Unit.g);
        return x.group(2) == null ? one : '${x.group(2)} × $one';
    }
    return key;
  }

  static void _put(Map<String, Set<String>> m, String facet, String key, String label, double order) {
    (m[facet] ??= {}).add(key);
    _labels[facet]![key] = label;
    _orders[facet]![key] = order;
  }

  /// Every filter option this item has, per facet.
  static Map<String, Set<String>> factsOf(Item i) {
    final memoKey = '${i.id}|${i.name}|${i.brand}|${i.sizeValue}|${i.sizeUnit.name}|${i.variable}|${i.effectivePrice}';
    final hit = _memo[memoKey];
    if (hit != null) return hit;
    final m = <String, Set<String>>{};
    final lower = i.name.toLowerCase();
    final norm = ' ${lower.replaceAll(_nonWord, ' ').trim()} ';

    // Size
    _sizeOf(i, lower, m);

    // Percent: "2%", "3.25%"; skim is 0%, homogenized milk is 3.25%.
    final pcts = <double>{};
    for (final x in _pct.allMatches(lower)) {
      final v = double.parse(x.group(1)!);
      if (v <= 100) pcts.add(v);
    }
    if (pcts.isEmpty) {
      if (norm.contains(' skim ') || norm.contains(' skim milk ')) pcts.add(0);
      if (norm.contains(' homogenized ') || norm.contains(' homo ') || norm.contains(' whole milk ')) pcts.add(3.25);
    }
    for (final v in pcts) {
      _put(m, 'pct', _trimNum(v), '${_trimNum(v)}%', v);
    }

    // Dietary and form words
    for (final (facet, attrs) in [('diet', _diet), ('form', _form)]) {
      for (final a in attrs) {
        if (a.phrases.any((p) => norm.contains(' $p '))) _put(m, facet, a.key, a.label, 0);
      }
    }

    // Type: the other words of the name (basmati, brown, cheddar, almond...)
    final brandWords = i.brand.toLowerCase().split(_nonWord).map(_singular).toSet();
    for (final raw in norm.trim().split(' ')) {
      if (raw.length < 3 || !_letters.hasMatch(raw)) continue;
      final w = _singular(raw);
      if (_stop.contains(w) || _stop.contains(raw) || _vocabWords.contains(w) || brandWords.contains(w)) continue;
      (m['type'] ??= {}).add(w);
    }

    // Brand
    final b = i.brand.trim();
    if (b.isNotEmpty) _put(m, 'brand', b.toLowerCase(), b, 0);

    // Price
    final p = i.effectivePrice;
    final (pk, pl, po) = p < 2
        ? ('p0', 'Under \$2', 0.0)
        : p < 5
            ? ('p1', '\$2 – \$5', 1.0)
            : p < 10
                ? ('p2', '\$5 – \$10', 2.0)
                : p < 20
                    ? ('p3', '\$10 – \$20', 3.0)
                    : p < 50
                        ? ('p4', '\$20 – \$50', 4.0)
                        : ('p5', '\$50 and up', 5.0);
    _put(m, 'price', pk, pl, po);
    if (_memo.length > 60000) _memo.clear();
    return _memo[memoKey] = m;
  }

  static void _sizeOf(Item i, String lower, Map<String, Set<String>> m) {
    if (i.variable) {
      _put(m, 'size', 'var', 'Sold by weight', 3e9);
      return;
    }
    var kind = i.sizeUnit.kind;
    var base = i.sizeValue * i.sizeUnit.baseFactor;
    // The label uses the size as the pack states it ("10 lb (4.54 kg)", not "4.54 kg (10.01 lb)").
    var labelValue = i.sizeValue;
    var labelUnit = i.sizeUnit;
    if (kind == UnitKind.each) {
      final v = i.sizeValue.round();
      if (v > 1) {
        _put(m, 'size', 'e$v', '$v count', 2e9 + v);
        return;
      }
      // Some stores give no size; use one written in the name ("Milk 4 L").
      final x = _nameSize.firstMatch(lower);
      if (x == null) {
        _put(m, 'size', 'e1', 'Each / size not listed', 2e9);
        return;
      }
      final u = Unit.parse(x.group(2)!.startsWith('lit') ? 'l' : x.group(2)!.replaceFirst('lbs', 'lb'));
      kind = u.kind;
      labelValue = double.parse(x.group(1)!);
      labelUnit = u;
      base = labelValue * u.baseFactor;
    }
    if (base <= 0) return;
    final vol = kind == UnitKind.volume;
    final prefix = vol ? 'v' : 'g';
    final offset = vol ? 1e9 : 0.0;
    String fmt(double x) => sizeBoth(x, vol ? Unit.ml : Unit.g);
    var pack = 0;
    for (final r in _packRes) {
      final x = r.firstMatch(lower);
      if (x != null) {
        pack = int.parse(x.group(1)!);
        break;
      }
    }
    if (pack > 1 && pack <= 48) {
      final per = base / pack;
      if (per >= (vol ? 30 : 10)) {
        final s = _sig3(per);
        _put(m, 'size', '$prefix${pack}x$s', '$pack × ${fmt(s)}', offset + base + 0.5);
        return;
      }
    }
    final s = _sig3(base);
    _put(m, 'size', '$prefix$s', sizeBoth(labelValue, labelUnit), offset + s);
  }

  /// True when the item fits every selected facet (ignoring [except], used for counts).
  static bool passes(Item i, FilterSel sel, {String? except}) {
    Map<String, Set<String>>? f;
    for (final e in sel.entries) {
      if (e.value.isEmpty || e.key == except || e.key.startsWith('_')) continue;
      f ??= factsOf(i);
      final have = f[e.key];
      if (have == null || !have.any(e.value.contains)) return false;
    }
    return true;
  }

  static Set<String> termWords(String term) =>
      term.toLowerCase().split(_nonWord).where((w) => w.isNotEmpty).map(_singular).toSet();

  /// The filters that make sense for these results, with how many items each would leave.
  static List<Facet> build(List<Item> source, FilterSel sel, String term) {
    final facts = [for (final i in source) factsOf(i)];
    final skip = termWords(term);
    // Brand names are not a type of product ("Dairyland", "Activia").
    for (final f in facts) {
      for (final b in f['brand'] ?? const <String>{}) {
        skip.addAll(b.split(_nonWord).where((w) => w.length > 2).map(_singular));
      }
    }
    final out = <Facet>[];
    for (final id in ids) {
      final counts = <String, int>{};
      var n = 0;
      for (var k = 0; k < source.length; k++) {
        if (!passes(source[k], sel, except: id)) continue;
        n++;
        for (final key in facts[k][id] ?? const <String>{}) {
          if (id == 'type' && skip.contains(key)) continue;
          counts[key] = (counts[key] ?? 0) + 1;
        }
      }
      final chosen = sel[id] ?? const <String>{};
      var keys = counts.keys.where((k) {
        if (chosen.contains(k)) return true;
        final c = counts[k]!;
        switch (id) {
          case 'type':
            return c >= math.max(2, n * 0.02) && c < n * 0.95;
          case 'diet':
          case 'form':
          case 'pct':
            return c < n || (id == 'pct' && counts.length > 1);
          default:
            return true;
        }
      }).toList();
      for (final k in chosen) {
        if (!keys.contains(k)) keys.add(k);
      }
      if (id == 'size' || id == 'price' || id == 'pct') {
        keys.sort((a, b) => (_orders[id]![a] ?? 1e12).compareTo(_orders[id]![b] ?? 1e12));
      } else {
        keys.sort((a, b) => (counts[b] ?? 0).compareTo(counts[a] ?? 0));
        if (id == 'type') keys = keys.take(16).toList();
        if (id == 'brand') keys = keys.take(40).toList();
      }
      // A facet with one option that every item has narrows nothing.
      final useful = chosen.isNotEmpty ||
          (id == 'type' || id == 'diet' || id == 'form' || id == 'pct' ? keys.isNotEmpty : keys.length >= 2);
      if (!useful) continue;
      out.add(Facet(id, _titles[id]!, [
        for (final k in keys) FacetOption(k, labelOf(id, k), _orders[id]?[k] ?? 0, counts[k] ?? 0),
      ]));
    }
    return out;
  }

  static String encode(FilterSel sel) => jsonEncode({
        for (final e in sel.entries)
          if (e.value.isNotEmpty) e.key: e.value.toList(),
      });

  static FilterSel decode(String s) {
    try {
      final m = jsonDecode(s) as Map<String, dynamic>;
      return {for (final e in m.entries) e.key: (e.value as List).cast<String>().toSet()};
    } catch (_) {
      return {};
    }
  }
}
