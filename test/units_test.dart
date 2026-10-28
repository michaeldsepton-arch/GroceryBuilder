import 'package:budget_basket/models/models.dart';
import 'package:budget_basket/models/units.dart';
import 'package:flutter_test/flutter_test.dart';

Item _item({
  required double price,
  double size = 1,
  Unit unit = Unit.each,
  bool variable = false,
  bool taxable = false,
}) =>
    Item(
      id: 'x',
      storeId: 's',
      name: 'n',
      price: price,
      sizeValue: size,
      sizeUnit: unit,
      variable: variable,
      taxable: taxable,
    );

void main() {
  test('unit price per 100g compares pack sizes', () {
    final small = _item(price: 2.00, size: 200, unit: Unit.g);
    final big = _item(price: 3.00, size: 500, unit: Unit.g);
    expect(small.unitPrice.compareValue, closeTo(1.0, 1e-9));
    expect(big.unitPrice.compareValue, closeTo(0.6, 1e-9));
    expect(big.unitPrice.primary, '\$0.60/100g');
  });

  test('per-lb price converts to per-kg', () {
    final chicken = _item(price: 5.99, size: 1, unit: Unit.lb, variable: true);
    expect(chicken.unitPrice.secondary, contains('\$13.21/kg'));
    // 2 lb of chicken
    expect(chicken.lineCost(gramsPerLb * 2), closeTo(11.98, 1e-6));
  });

  test('volume unit price', () {
    final milk = _item(price: 5.49, size: 4, unit: Unit.l);
    expect(milk.unitPrice.primary, '\$0.14/100mL');
  });

  test('GST only on taxable lines', () {
    final food = CartLine(_item(price: 10), 2, false);
    final soap = CartLine(_item(price: 10, taxable: true), 2, false);
    expect(food.tax, 0);
    expect(soap.tax, closeTo(1.0, 1e-9));
  });

  test('weights show both metric and imperial', () {
    expect(sizeBoth(1, Unit.lb), '1 lb (454 g)');
    expect(sizeBoth(500, Unit.g), '500 g (1.1 lb)');
  });
}
