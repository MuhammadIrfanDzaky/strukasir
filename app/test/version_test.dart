import 'package:berrybrew_pos/features/update/version_gate.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('perbandingan versi semantik', () {
    expect(compareVersions('1.0.0', '1.0.0'), 0);
    expect(compareVersions('1.0.0', '1.0.1'), lessThan(0));
    expect(compareVersions('1.10.0', '1.9.9'), greaterThan(0)); // bukan perbandingan string
    expect(compareVersions('1.2', '1.2.0'), 0);
    expect(compareVersions('1.2.0+7', '1.2.0'), 0); // nomor build diabaikan
  });

  test('wajib update bila di bawah versi minimum', () {
    expect(const UpdateInfo(current: '1.0.0', minVersion: '1.1.0').mustUpdate, isTrue);
    expect(const UpdateInfo(current: '1.1.0', minVersion: '1.1.0').mustUpdate, isFalse);
  });
}
