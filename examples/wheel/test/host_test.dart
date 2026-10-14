import 'package:flutter_test/flutter_test.dart';
import 'package:kiln/kiln.dart';
import 'package:wheel/main.dart';

void main() {
  test('the host data produces the slices variable the Wheel parses, with its rates', () {
    final d = WheelData();
    final parsed = sliceList(d.spec);
    expect(parsed.map((s) => s.label), d.prizes.map((p) => p.label));
    expect(parsed.map((s) => s.weight), d.prizes.map((p) => p.weight));
    expect(d.rates.reduce((a, b) => a + b), closeTo(1, 1e-9));
    d.prizes.first.label = 'a|b;c'; // no escaping needed any more
    expect(sliceList(d.spec).first.label, 'a|b;c');
  });
}
