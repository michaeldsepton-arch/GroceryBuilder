import 'dart:io';

import 'package:budget_basket/data/halal.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUpAll(() => Halal.configure(File('assets/recipes/haram_terms.json').readAsStringSync()));

  test('hides pork and alcohol', () {
    for (final t in [
      'Pork Chops 1kg', 'Bacon Bits', 'Black Forest Ham', 'Red wine 750ml', 'Lard 454g',
      'Beer-braised onions with lager', 'Prosciutto di Parma', 'Dry white wine', 'Gelatine sheets',
      'Pork sausage', 'Italian sausage', 'Pepperoni slices', 'Spare ribs', 'Non-alcoholic beer',
    ]) {
      expect(Halal.isHaram(t), isTrue, reason: t);
    }
  });

  test('vanilla extract is hidden, vanilla bean paste is not, and recipes convert it', () {
    expect(Halal.isHaram('Pure Vanilla Extract 120 mL'), isTrue);
    expect(Halal.isHaram('Imitation vanilla essence'), isTrue);
    expect(Halal.isHaram('Nielsen-Massey Vanilla Bean Paste 118 mL'), isFalse);
    expect(Halal.halalize('1 tsp pure vanilla extract'), '1 tsp vanilla bean paste');
    expect(Halal.halalize('Vanilla Extract'), 'Vanilla bean paste');
    expect(Halal.halalize('stir in the vanilla essence and mix'), 'stir in the vanilla bean paste and mix');
  });

  test('allows lookalikes and halal alternatives', () {
    for (final t in [
      'Root Beer 2L', 'Ginger beer', 'Red wine vinegar', 'Rice vinegar', 'Turkey bacon', 'Beef sausage',
      'Hamburger buns', 'Chicken breast', 'Ginger root', 'Beef short ribs', 'Gingerbread', 'Cinnamon',
      'Chicken sausage halal', 'Hammer',
    ]) {
      expect(Halal.isHaram(t), isFalse, reason: t);
    }
  });

  test('halal-only meat hides supermarket meat but not the halal market or soup', () {
    expect(Halal.isNonHalalMeatProduct('Chicken Breasts Boneless', 'Meat', 'superstore'), isTrue);
    expect(Halal.isNonHalalMeatProduct('Chicken Breast', 'Meat', 'halal'), isFalse);
    expect(Halal.isNonHalalMeatProduct('Chicken Noodle Soup', '', 'walmart'), isFalse);
    expect(Halal.isNonHalalMeatProduct('Atlantic Salmon Fillet', 'Seafood', 'walmart'), isFalse);
    expect(Halal.isNonHalalMeatProduct('Halal Beef Burgers', '', 'walmart'), isFalse);
  });
}
