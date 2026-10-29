import 'dart:io';

import 'package:budget_basket/data/scope.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUpAll(() => Scope.configure(File('assets/seed/scope_terms.json').readAsStringSync()));

  test('keeps things bought on a typical grocery trip', () {
    for (final n in [
      'Basmati Rice 4kg',
      'Platinum Plus Dishwasher Detergent Fresh, 30ct',
      'Silicone Spatula',
      'Plastic Wrap 100ft',
      'Toaster Strudel Apple Pastries',
      '3 Piece Cookie Sheet Set',
      'All Beef Frozen Corn Dogs',
      'Kettle Style Blue Corn Tortilla Chips',
      'Light Laundry Scent Booster Beads, No Heavy Perfumes',
    ]) {
      expect(Scope.inScope(n, '', ''), isTrue, reason: n);
    }
  });

  test('drops appliances, mops, toys and furniture', () {
    for (final n in [
      'Sweep and Mop Pro 2-in-1',
      'Pods & Grounds Coffee Maker',
      'Pentantan 6QT Air Fryer',
      'Hot Wheels Custom 62 Chevy Pickup',
      'Cool Max Bed Pillow, 2-Pack',
      'Nutrition First Toy & Small Breed Dog Food',
      'Proactive Health Healthy Adult with Chicken Dry Cat Food',
      "Kid Girls' Printed Legging",
      'Scented Dryer Balls 4Pk',
      '4-Pack Quarter-Crew Socks',
      'Super Stay Up To 24h Skin Tint Foundation',
      'Scented Candle Lavender Cashmere',
      'Gel Air Freshener Lavender',
      'Cat Dry Food',
      'Halloween Greeter',
      'TopLLC Mini Projector Portable',
    ]) {
      expect(Scope.inScope(n, '', ''), isFalse, reason: n);
    }
    expect(Scope.inScope('Anything', '', 'Toys & games'), isFalse);
  });

  test('puts items in shopping categories', () {
    expect(Scope.categoryOf('Whole Milk 2L', ''), 'Dairy & eggs');
    expect(Scope.categoryOf('Chicken Thighs Bone-in', ''), 'Meat');
    expect(Scope.categoryOf('Dish Soap Lemon', ''), 'Household & cleaning');
    expect(Scope.categoryOf('Ziploc Freezer Bags', ''), 'Food storage & wrap');
    expect(Scope.categoryOf('Basmati Rice 4kg', ''), 'Pantry');
    expect(Scope.categoryOf('Cantaloupe', ''), 'Produce');
    expect(Scope.categoryOf('Something unknown xyz', ''), 'Other');
  });
}
