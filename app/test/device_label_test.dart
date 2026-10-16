import 'package:berrybrew_pos/features/session/session_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('label tablet: nama bawaan → kode, nama custom → nama (kode)', () {
    const d = DeviceInfo(id: 'd', code: 'T3', name: 'Tablet 3', tenantName: 'Kedai');
    expect(d.label, 'Tablet T3');
    expect(d.copyWith(name: 'Kasir Depan').label, 'Kasir Depan (T3)');
    expect(d.copyWith(name: 'Kasir Depan').toJson()['name'], 'Kasir Depan');
  });
}
