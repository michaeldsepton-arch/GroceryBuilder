import 'package:budget_basket/state/app_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the budget week starts on Friday morning', () {
    expect(weekKey(DateTime(2026, 10, 29, 23, 59)), '2026-10-23'); // Thursday night: still last week
    expect(weekKey(DateTime(2026, 10, 30, 0, 1)), '2026-10-30'); // Friday morning: new week
    expect(weekKey(DateTime(2026, 11, 5, 12)), '2026-10-30'); // next Thursday
    expect(weekKey(DateTime(2026, 11, 6, 8)), '2026-11-06');
  });
}
