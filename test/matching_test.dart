import 'package:budget_basket/data/matching.dart';
import 'package:budget_basket/models/models.dart';
import 'package:budget_basket/models/units.dart';
import 'package:flutter_test/flutter_test.dart';

Item it(String id, String name, double price, double size, Unit unit,
        {String store = 'superstore', bool variable = false, String brand = ''}) =>
    Item(id: id, storeId: store, name: name, price: price, sizeValue: size, sizeUnit: unit, variable: variable, brand: brand);

void main() {
  group('parseNeed', () {
    test('weights and volumes', () {
      expect(parseNeed('500 g')!.amount, 500);
      expect(parseNeed('500 g')!.kind, NeedKind.weight);
      expect(parseNeed('1 kg')!.amount, 1000);
      expect(parseNeed('2 lb')!.amount, closeTo(907.18, 0.01));
      expect(parseNeed('1 1/2 cups')!.amount, 360);
      expect(parseNeed('1 1/2 cups')!.kind, NeedKind.volume);
      expect(parseNeed('2 tbsp')!.amount, 30);
      expect(parseNeed('½ tsp')!.amount, 2.5);
      expect(parseNeed('250ml')!.amount, 250);
      expect(parseNeed('2-3 tbsp')!.amount, 45);
    });
    test('counts, packs, scaling and unknowns', () {
      expect(parseNeed('4')!.kind, NeedKind.count);
      expect(parseNeed('4')!.amount, 4);
      expect(parseNeed('2 cans')!.kind, NeedKind.pack);
      expect(parseNeed('3 cloves')!.kind, NeedKind.pack);
      expect(parseNeed('a pinch')!.kind, NeedKind.pack);
      expect(parseNeed('2 x 400g')!.amount, 800);
      expect(parseNeed('500 g', 2)!.amount, 1000);
      expect(parseNeed('to taste'), isNull);
      expect(parseNeed(''), isNull);
    });
  });

  group('relevance and picking', () {
    test('plain butter beats peanut butter and butter chicken sauce', () {
      final items = [
        it('1', 'Peanut Butter Creamy 1 kg', 6.0, 1, Unit.kg),
        it('2', 'Butter Chicken Simmer Sauce 350 mL', 3.5, 350, Unit.ml),
        it('3', 'Salted Butter 454 g', 5.99, 454, Unit.g),
      ];
      final best = pickBest(items, 'butter', null)!;
      expect(best.item.id, '3');
    });

    test('chips do not match the plain ingredient', () {
      final items = [
        it('1', 'Salt & Vinegar Chips 220 g', 3.0, 220, Unit.g),
        it('2', 'Iodized Table Salt 1 kg', 1.5, 1, Unit.kg),
      ];
      expect(pickBest(items, 'salt', null)!.item.id, '2');
    });

    test('buys the pack that covers the need for least money, not lowest unit price', () {
      final items = [
        it('big', 'All Purpose Flour 10 kg', 12.99, 10, Unit.kg), // cheapest per kg
        it('mid', 'All Purpose Flour 2.5 kg', 5.49, 2.5, Unit.kg),
        it('small', 'All Purpose Flour 1 kg', 3.49, 1, Unit.kg),
      ];
      final need = parseNeed('3 cups'); // volume: not comparable to kg packs -> unknown
      expect(need!.kind, NeedKind.volume);
      final byWeight = pickBest(items, 'all purpose flour', parseNeed('500 g'))!;
      expect(byWeight.item.id, 'small');
      expect(byWeight.cover.qty, 1);
    });

    test('2 kg need: one 2.5 kg bag beats two 1 kg bags', () {
      final items = [
        it('mid', 'All Purpose Flour 2.5 kg', 5.49, 2.5, Unit.kg),
        it('small', 'All Purpose Flour 1 kg', 3.49, 1, Unit.kg),
      ];
      final best = pickBest(items, 'all purpose flour', parseNeed('2 kg'))!;
      expect(best.item.id, 'mid');
      expect(best.cover.qty, 1);
      expect(best.cover.cost, closeTo(5.49, 1e-9));
    });

    test('eggs by count: 6 eggs from a 12 count carton is one carton', () {
      final items = [it('e12', 'Large Eggs 12 ct', 4.99, 12, Unit.each), it('e18', 'Large Eggs 18 ct', 6.99, 18, Unit.each)];
      final best = pickBest(items, 'eggs', parseNeed('6'))!;
      expect(best.item.id, 'e12');
      expect(best.cover.qty, 1);
      expect(pickBest(items, 'eggs', parseNeed('14'))!.item.id, 'e18'); // 18ct covers 14 for less than 2 x 12ct
    });

    test('halal by-weight meat is bought by grams', () {
      final chicken = it('c', 'Chicken Thighs', 5.99, 1, Unit.lb, store: 'halal', variable: true);
      final best = pickBest([chicken], 'chicken thighs', parseNeed('1 kg'))!;
      expect(best.cover.qty, 1000);
      expect(best.cover.cost, closeTo(5.99 / gramsPerLb * 1000, 0.01));
    });

    test('unknown amount avoids a bulk bag when a small jar costs about the same per unit', () {
      final items = [
        it('bulk', 'Ground Cumin 500 g', 12.0, 500, Unit.g),
        it('jar', 'Ground Cumin 45 g', 1.2, 45, Unit.g), // ~2.7c/g vs 2.4c/g
      ];
      expect(pickBest(items, 'cumin', parseNeed('1 tsp'))!.item.id, 'jar');
    });
  });

  group('real product names that must not match a plain ingredient', () {
    final cases = {
      'garlic': 'Lactantia® Provençal Garlic Butter',
      'parsley': 'Gay Lea Garlic Parsley Butter Roll 125g',
      'tomatoes': 'Dempster’s® Sundried Tomato Large Tortillas',
      'flour': 'Tia Rosa® White Flour Tortillas, 384 g',
      'salt': 'Becel Margarine Unsalted Sticks',
      'sugar': 'International Delight Zero Sugar Hazelnut, Sugar Free Coffee Creamer',
      'lemon': 'Oikos Extra Creamy Yogurt, Strawberry Cheesecake/Cappuccino/Lemon Meringue/Black Cherry, 4% M.F., 12x95g',
      'olive oil': 'Becel with Olive Oil',
      'black tea': 'Black River Philly Steaks, 600g',
      'ice': 'La Baguetterie Sliced Sourdough Miche',
      'cinnamon': 'Dempster’s® Cinnamon Raisin Bagels',
      'brown sugar': 'Great Value Frozen Dry Rub Brown Sugar BBQ Chicken Wings, 825g',
      'water': 'Kosa Can Quail Eggs in Water',
      'mango': 'iÖGO nanö Mango Yogurt Pouch 2.9%, 4x90g',
      'lamb': 'Beef-Veal-Lamb Chevapi Kebab, Authentic Balkan-style halal minced kebabs',
      'strawberries': 'OIKOS High Protein Vanilla/Strawberry/Peach/Banana, 0% M.F., 12x100g',
      'cream': 'Great Value Sour Cream',
      'vanilla': 'Natrel Coffee Creamer Vanilla 1L',
    };
    cases.forEach((term, name) {
      test('"$term" is not "$name"', () {
        expect(relevance(it('x', name, 4.0, 1, Unit.each), term), 0);
      });
    });
    test('and the real thing still matches', () {
      for (final c in {
        'butter': 'Great Value Salted Butter',
        'eggs': 'Great Value Large 12 Eggs',
        'milk': 'Sealtest 2% Milk 473ml',
        'ghee': 'Verka Pure Desi Ghee, 400g',
        'plain yogurt': 'Olympic Organic Plain Yogurt 3.5%',
        'cheddar cheese': 'Great Value Medium Cheddar Cheese',
        'mozzarella': 'Great Value Mozzarella Cheese Slices',
        'tortillas': 'Great Value 7" White Tortillas, Source of 7 Essential Nutrients, 10 Count, 340 g',
        'heavy cream': 'Sealtest 35% Whipping Cream 473ml',
        'basmati rice': 'Tilda Basmati Rice 4 kg',
        'cumin': 'Club House Ground Cumin 45 g',
      }.entries) {
        final term = c.key == 'heavy cream' ? 'whipping cream' : c.key;
        expect(relevance(it('x', c.value, 4.0, 1, Unit.each), term), greaterThan(0), reason: '${c.key} / ${c.value}');
      }
    });
    test('count inferred from the name: 6 eggs from "Large 12 Eggs" is one carton', () {
      final c = cover(it('e', 'Great Value Large 12 Eggs', 3.93, 1, Unit.each), parseNeed('6'));
      expect(c.qty, 1);
      expect(c.exact, isTrue);
      expect(cover(it('e', 'Great Value Large 12 Eggs', 3.93, 1, Unit.each), parseNeed('14')).qty, 2);
    });
    test('3 cloves of garlic is one purchase, not three', () {
      expect(parseNeed('3 cloves')!.amount, 1);
    });
  });
}
