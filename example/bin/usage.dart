// Run: cd example && dart run pub_doctor_example:usage

import 'dart:io';

import 'package:pub_doctor/application/scan_service.dart';

void main() async {
  final service = ScanService();
  try {
    final diagnosis = await service.scan(
      '../pubspec.yaml',
      const ScanOptions(includeDev: true),
    );

    stdout.writeln('Packages: ${diagnosis.totalPackages}');
    stdout.writeln(
        '  Healthy: ${diagnosis.healthyCount} | Warning: ${diagnosis.warningCount}');
    stdout.writeln(
        '  Risky: ${diagnosis.riskyCount} | Critical: ${diagnosis.criticalCount}');

    if (diagnosis.criticalCount > 0 || diagnosis.riskyCount > 0) {
      stdout.writeln('\nReview these packages:');
      for (final r in diagnosis.results) {
        if (r.riskLevel.index >= 3) {
          stdout.writeln(
              '  - ${r.packageName} (${r.riskScore.toStringAsFixed(0)}/100)');
        }
      }
    }
  } finally {
    service.dispose();
  }
}
