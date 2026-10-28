import 'package:budget_basket/models/recipe.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('scales whole numbers, fractions and decimals', () {
    expect(scaleQty('2 cups', 2), '4 cups');
    expect(scaleQty('1 1/2 cups', 2), '3 cups');
    expect(scaleQty('1/2 tsp', 3), '1½ tsp');
    expect(scaleQty('250 g', 0.5), '125 g');
    expect(scaleQty('a pinch', 2), 'a pinch');
    expect(scaleQty('1.5 kg', 2), '3 kg');
  });
}
