enum UnitKind { weight, volume, each }

enum Unit {
  g('g', UnitKind.weight, 1),
  kg('kg', UnitKind.weight, 1000),
  lb('lb', UnitKind.weight, 453.59237),
  oz('oz', UnitKind.weight, 28.349523125),
  ml('mL', UnitKind.volume, 1),
  l('L', UnitKind.volume, 1000),
  each('ea', UnitKind.each, 1);

  const Unit(this.label, this.kind, this.baseFactor);
  final String label;
  final UnitKind kind;

  /// Grams for weight, millilitres for volume, 1 for each.
  final double baseFactor;

  static Unit parse(String? s) {
    final v = (s ?? '').toLowerCase().trim();
    for (final u in Unit.values) {
      if (u.name == v || u.label.toLowerCase() == v) return u;
    }
    return Unit.each;
  }
}

const double gramsPerLb = 453.59237;

String money(double v) => '\$${v.toStringAsFixed(2)}';

String _trim(double v, [int digits = 2]) {
  final s = v.toStringAsFixed(digits);
  if (!s.contains('.')) return s;
  return s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
}

/// "1.5 lb (680 g)" style size text showing lb and kg/g for weights.
String sizeBoth(double value, Unit unit) {
  switch (unit.kind) {
    case UnitKind.weight:
      final g = value * unit.baseFactor;
      final lb = g / gramsPerLb;
      final metric = g >= 1000 ? '${_trim(g / 1000)} kg' : '${_trim(g, 0)} g';
      final imperial = '${_trim(lb)} lb';
      return unit == Unit.lb || unit == Unit.oz
          ? '$imperial ($metric)'
          : '$metric ($imperial)';
    case UnitKind.volume:
      final ml = value * unit.baseFactor;
      return ml >= 1000 ? '${_trim(ml / 1000)} L' : '${_trim(ml, 0)} mL';
    case UnitKind.each:
      return value == 1 ? '1 each' : '${_trim(value)} ct';
  }
}

/// Comparable price per base unit, e.g. per 100 g, so different brands and
/// pack sizes can be ranked fairly.
class UnitPrice {
  UnitPrice(this.kind, this.perBase);
  final UnitKind kind;

  /// Price per gram, per millilitre, or per each.
  final double perBase;

  double get compareValue {
    switch (kind) {
      case UnitKind.weight:
        return perBase * 100; // per 100 g
      case UnitKind.volume:
        return perBase * 100; // per 100 mL
      case UnitKind.each:
        return perBase;
    }
  }

  String get primary {
    switch (kind) {
      case UnitKind.weight:
        return '${money(perBase * 100)}/100g';
      case UnitKind.volume:
        return '${money(perBase * 100)}/100mL';
      case UnitKind.each:
        return '${money(perBase)}/ea';
    }
  }

  /// Secondary text such as "$11.00/kg · $4.99/lb".
  String get secondary {
    switch (kind) {
      case UnitKind.weight:
        return '${money(perBase * 1000)}/kg · ${money(perBase * gramsPerLb)}/lb';
      case UnitKind.volume:
        return '${money(perBase * 1000)}/L';
      case UnitKind.each:
        return '';
    }
  }
}
