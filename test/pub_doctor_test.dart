import 'package:pub_doctor/pub_doctor.dart';
import 'package:test/test.dart';

void main() {
  test('pub_doctor exports ScanService', () {
    expect(ScanService(), isNotNull);
  });

  test('pub_doctor exports RiskScorer', () {
    expect(RiskScorer(), isNotNull);
  });

  test('pub_doctor exports domain models', () {
    expect(RiskLevel.healthy.label, 'Healthy');
    expect(RiskLevel.critical.label, 'Critical');
  });
}
