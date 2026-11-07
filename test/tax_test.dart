import 'dart:io';

import 'package:budget_basket/data/scope.dart';
import 'package:budget_basket/data/tax.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUpAll(() {
    Scope.configure(File('assets/seed/scope_terms.json').readAsStringSync());
    Tax.configure(File('assets/seed/tax_terms.json').readAsStringSync());
  });
  bool t(String n, [String c = '']) => Tax.isTaxable(n, '', c);

  test('basic groceries carry no GST', () {
    for (final n in [
      'Chicken Leg (with skin)', 'Whole Milk 4 L', 'Large Eggs 12 ct', 'Basmati Rice 4kg', 'Bananas',
      'White Bread 675 g', '100% Orange Juice 1.75 L', 'Chocolate Chips Semi-Sweet 300 g', 'Peanut Butter Creamy 1 kg',
      'Baking Soda 2 kg', 'Infant Formula Powder', 'Ground Beef Lean 454 g', 'High Liner Popcorn Shrimp 330 g',
      'Chocolate Milk 1 L', 'Chips Ahoy Cookies', 'Butter Salted 454 g',
    ]) {
      expect(t(n), isFalse, reason: n);
    }
  });

  test('snacks, candy, pop, prepared food, pet and non-food carry GST', () {
    for (final n in [
      'Lays Potato Chips 235 g', 'Doritos Tortilla Chips', 'Milk Chocolate Bar 100 g', 'Gummy Bears 200 g', 'Coca-Cola Cola 12 x 355 mL',
      'Canada Dry Ginger Ale 2L', 'Lemon Iced Tea', 'Rotisserie Chicken', 'Kit Kat 4 Finger', 'Ice Cream Bars 6 pack',
      'Dog Food Wet Chicken', 'Cat Litter 10 kg', 'Diapers Size 3 84 ct', 'Tide Laundry Detergent', 'Toilet Paper 12 Rolls',
      'Dove Beauty Bar Cucumber and Green Tea', 'Aluminum Foil 25ft', 'Ziploc Freezer Bags', 'Toothpaste Mint',
    ]) {
      expect(t(n), isTrue, reason: n);
    }
  });
}
