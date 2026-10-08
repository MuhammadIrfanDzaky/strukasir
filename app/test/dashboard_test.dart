import 'package:berrybrew_pos/features/reports/dashboard_charts.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('rupiah ringkas untuk sumbu & label', () {
    expect(rpShort(950), '950');
    expect(rpShort(15000), '15rb');
    expect(rpShort(500000), '500rb');
    expect(rpShort(1000000), '1jt');
    expect(rpShort(1500000), '1,5jt');
    expect(rpShort(1250000), '1,25jt');
    expect(rpShort(12500000), '13jt');
  });

  test('skala sumbu bulat', () {
    expect(niceAxis(2060000, ticks: 5), (max: 2500000.0, step: 500000.0));
    expect(niceAxis(2060000), (max: 3000000.0, step: 1000000.0));
    expect(niceAxis(744000, ticks: 2), (max: 1000000.0, step: 500000.0));
    expect(niceAxis(0), (max: 4.0, step: 1.0));
    expect(niceAxis(90000), (max: 100000.0, step: 25000.0));
  });
}
