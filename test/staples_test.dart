import 'dart:io';

import 'package:budget_basket/data/scope.dart';
import 'package:budget_basket/data/staples.dart';
import 'package:budget_basket/models/models.dart';
import 'package:budget_basket/models/units.dart';
import 'package:flutter_test/flutter_test.dart';

Item it(String name, {double size = 1, Unit unit = Unit.each, double price = 5, String brand = ''}) =>
    Item(id: name, storeId: 'superstore', name: name, price: price, sizeValue: size, sizeUnit: unit, brand: brand);

void main() {
  setUpAll(() {
    Scope.configure(File('assets/seed/scope_terms.json').readAsStringSync());
    Staples.configure(File('assets/seed/staples.json').readAsStringSync());
  });

  test('everyday items from the shopping list and the categories made from it', () {
    for (final i in [
      it('Large Eggs 12 Pack'),
      it('Basmati Rice', size: 4.54, unit: Unit.kg),
      it('Toor Dal', size: 2, unit: Unit.kg),
      it('Salted Butter', size: 454, unit: Unit.g),
      it('Roma Tomatoes'),
      it('Tide Laundry Detergent Pods Original 20 Pods'),
      it('Always Ultra Thin Pads'),
      it('Aluminum Foil'),
      it('Peanut Butter Creamy', size: 1, unit: Unit.kg),
      it('Dark Chocolate Chips', size: 300, unit: Unit.g),
      it('Red Onion 1 Count'),
      it('Cilantro'),
    ]) {
      expect(Staples.isTypical(i), isTrue, reason: i.name);
    }
  });

  test('milk is kept only in 2 L and 4 L', () {
    expect(Staples.isTypical(it('2% Milk', size: 4, unit: Unit.l)), isTrue);
    expect(Staples.isTypical(it('Homogenized Milk 3.25%', size: 2, unit: Unit.l)), isTrue);
    expect(Staples.isTypical(it('Dairyland 2% Milk 4L')), isTrue); // size only in the name
    expect(Staples.isTypical(it('Milk', size: 1, unit: Unit.l)), isFalse);
    expect(Staples.isTypical(it('Dairyland 2% Milk')), isFalse); // size not listed
    expect(Staples.isTypical(it('Chocolate Milk', size: 2, unit: Unit.l)), isFalse);
  });

  test('things that only contain an everyday word are not everyday items', () {
    for (final i in [
      it('Butter Beans', size: 540, unit: Unit.ml),
      it('Ginger Beer'),
      it('Crispy Onions'),
      it('Dog Food Beef', size: 7, unit: Unit.kg),
      it('Sofa Cushion'),
    ]) {
      expect(Staples.isTypical(i), isFalse, reason: i.name);
    }
  });

  test('prices that cannot be right or are over \$30 are not sane', () {
    expect(Staples.isSane('Rice', 31, 1, Unit.kg), isFalse);
    expect(Staples.isSane('Daal Moong split', 1.98, 55, Unit.lb), isFalse); // 55 lb for \$1.98
    expect(Staples.isSane('Garbage Bags 90 L', 8.97, 90, Unit.l), isTrue); // litres are the bag size
    expect(Staples.isSane('Sugar', 9, 10, Unit.kg), isTrue);
    expect(Staples.isSane('Eggs', 5, 12, Unit.each), isTrue);
  });
}
