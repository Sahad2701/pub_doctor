/// Dependency health diagnostics for Dart and Flutter projects.
///
/// Scans `pubspec.yaml`, fetches metadata from pub.dev and GitHub, and scores
/// each dependency 0–100 based on maintenance activity, version freshness,
/// pub.dev quality, null-safety, SDK compatibility, and more.
///
/// Typical entry-point for CLI consumers is [ScanService]. Library consumers
/// can drive [RiskScorer] directly.
library pub_doctor;

export 'application/scan_service.dart'
    if (dart.library.js_interop) 'constants.dart';
export 'cli/reporter.dart' if (dart.library.js_interop) 'constants.dart';
export 'constants.dart';
export 'data/cache.dart';
export 'doctor_engine/scorer.dart';
export 'doctor_engine/signals.dart';
export 'domain/models.dart';
