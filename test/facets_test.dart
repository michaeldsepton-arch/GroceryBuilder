import 'package:budget_basket/data/facets.dart';
import 'package:budget_basket/data/search_filters.dart';
import 'package:budget_basket/models/models.dart';
import 'package:budget_basket/models/units.dart';
import 'package:flutter_test/flutter_test.dart';

Item it(String id, String name, double size, Unit unit, {double price = 5, String brand = '', bool variable = false}) =>
    Item(id: id, storeId: 'superstore', name: name, price: price, sizeValue: size, sizeUnit: unit, brand: brand, variable: variable);

String sizeOf(Item i) => Facets.labelOf('size', Facets.factsOf(i)['size']!.single);
Set<String> keys(Item i, String facet) => Facets.factsOf(i)[facet] ?? {};

void main() {
  final milk = [
    it('a', 'Homogenized Milk 3.25%', 4, Unit.l, price: 6.69, brand: 'Beatrice'),
    it('b', 'Partly Skimmed Milk 2%', 4, Unit.l, price: 6.35, brand: 'Beatrice'),
    it('c', 'Partly Skimmed Milk 1%', 4, Unit.l, price: 6.35, brand: 'Beatrice'),
    it('d', 'Partly Skimmed Milk 2%', 2, Unit.l, price: 5.08, brand: 'Beatrice'),
    it('e', 'Lactose Free 2% Milk', 2, Unit.l, price: 6.49, brand: 'Natrel'),
    it('f', 'Skim Milk', 1, Unit.l, price: 2.99, brand: 'Dairyland'),
    it('g', 'Microfiltered Whole Milk', 1, Unit.l, price: 3.49, brand: 'Natrel'),
  ];

  group('sizes', () {
    test('volumes, weights with lb, packs and counts', () {
      expect(sizeOf(milk[0]), '4 L');
      expect(sizeOf(it('x', 'Coconut Milk', 400, Unit.ml)), '400 mL');
      expect(sizeOf(it('x', 'Butter Salted', 454, Unit.g)), '454 g (1 lb)');
      expect(sizeOf(it('x', 'Basmati Rice', 10, Unit.lb)), '10 lb (4.54 kg)');
      expect(sizeOf(it('x', 'Cola 12 Pack', 4260, Unit.ml)), '12 × 355 mL');
      expect(sizeOf(it('x', 'Greek Yogurt 4 x 100 g', 400, Unit.g)), '4 × 100 g (0.22 lb)');
      expect(sizeOf(it('x', 'Large Eggs', 12, Unit.each)), '12 count');
      expect(sizeOf(it('x', 'Chicken Thighs', 1, Unit.kg, variable: true)), 'Sold by weight');
    });

    test('a size written only in the name is used; none at all says so', () {
      expect(sizeOf(it('x', 'Dairyland 2% Milk 4L', 1, Unit.each)), '4 L');
      expect(sizeOf(it('x', 'Dairyland 2% Milk', 1, Unit.each)), 'Each / size not listed');
      expect(sizeOf(it('x', '4 Lettuce Hearts', 1, Unit.each)), 'Each / size not listed');
    });

    test('labels come back for remembered keys never seen this session', () {
      expect(Facets.labelOf('size', 'v12x355.0'), '12 × 355 mL');
      expect(Facets.labelOf('size', 'g907.0'), '907 g (2 lb)');
      expect(Facets.labelOf('pct', '3.25'), '3.25%');
      expect(Facets.labelOf('diet', 'lactosefree'), 'Lactose free');
    });
  });

  test('percent, dietary and form words', () {
    expect(keys(milk[1], 'pct'), {'2'});
    expect(keys(milk[0], 'pct'), {'3.25'});
    expect(keys(milk[5], 'pct'), {'0'});
    expect(keys(milk[6], 'pct'), {'3.25'}); // whole milk
    expect(keys(milk[4], 'diet'), contains('lactosefree'));
    expect(keys(it('x', 'Lactose-Free Skim Milk', 2, Unit.l), 'diet'), contains('lactosefree'));
    expect(keys(it('x', 'Chicken Thighs Boneless Skinless', 1, Unit.kg), 'form'), containsAll(['boneless', 'skinless']));
    expect(keys(it('x', 'Aged Basmati Rice', 4.54, Unit.kg), 'type'), containsAll(['aged', 'basmati', 'rice']));
  });

  group('filtering like McMaster-Carr', () {
    String sizeKey(String label) => Facets.factsOf(milk.firstWhere((i) => sizeOf(i) == label))['size']!.single;

    test('the filters on offer fit the search, with counts', () {
      final f = Facets.build(milk, {}, 'milk');
      final ids = f.map((x) => x.id).toList();
      expect(ids, containsAll(['size', 'pct', 'brand']));
      final size = f.firstWhere((x) => x.id == 'size');
      expect(size.options.map((o) => o.label), ['1 L', '2 L', '4 L']); // smallest first
      expect(size.options.last.count, 3);
      final type = f.where((x) => x.id == 'type');
      if (type.isNotEmpty) {
        expect(type.single.options.map((o) => o.key), isNot(contains('milk'))); // the search word itself
        expect(type.single.options.map((o) => o.key), isNot(contains('natrel'))); // brands are not types
      }
    });

    test('options in one group are alternatives, groups narrow each other', () {
      final four = sizeKey('4 L'), two = sizeKey('2 L');
      expect(milk.where((i) => Facets.passes(i, {'size': {four}})).length, 3);
      expect(milk.where((i) => Facets.passes(i, {'size': {four, two}})).length, 5);
      expect(milk.where((i) => Facets.passes(i, {'size': {four, two}, 'pct': {'2'}})).map((i) => i.id), ['b', 'd', 'e']);
    });

    test('counts in a group ignore that group but follow the others', () {
      final four = sizeKey('4 L');
      final f = Facets.build(milk, {'size': {four}}, 'milk');
      final pct = f.firstWhere((x) => x.id == 'pct');
      expect({for (final o in pct.options) o.label: o.count}, {'1%': 1, '2%': 1, '3.25%': 1});
      final size = f.firstWhere((x) => x.id == 'size');
      expect(size.options.length, 3); // other sizes still offered while 4 L is ticked
    });
  });

  test('search filters: best matches only, real matches first, saved form round-trips', () {
    final sf = SearchFilters();
    final ranked = [...milk, it('z', 'Milk Chocolate Bar', 100, Unit.g)];
    var r = sf.apply(ranked, milk.length, 'milk');
    expect(r.items.length, 8);
    sf.setBestOnly(true);
    r = sf.apply(ranked, milk.length, 'milk');
    expect(r.items.length, 7);
    sf.toggle('pct', '2', true);
    r = sf.apply(ranked, milk.length, 'milk');
    expect(r.items.map((i) => i.id), ['b', 'd', 'e']);
    expect(r.matches, 3);
    final back = Facets.decode(Facets.encode(sf.sel));
    expect(back['pct'], {'2'});
    expect(back[SearchFilters.bestOnlyId], {'1'});
  });
}
