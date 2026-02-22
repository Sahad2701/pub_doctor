import 'package:pub_semver/pub_semver.dart';

import '../../constants.dart';
import '../../domain/models.dart';
import 'risk_signal.dart';

/// Checks that the package's declared SDK constraint is compatible with the
/// Dart SDK currently installed on the host machine.
///
/// Also warns when the constraint's upper bound is close to the current SDK
/// version, indicating an imminent breakage risk on the next SDK upgrade.
///
/// Weight: 7.
class SdkCompatibilitySignal extends RiskSignal {
  /// Creates a [SdkCompatibilitySignal].
  ///
  /// [currentDartSdk] is the Dart SDK version detected at scan time. When
  /// `null`, the signal reports a benign failure rather than false positives.
  const SdkCompatibilitySignal({this.currentDartSdk});

  /// The Dart SDK version installed on the host machine.
  final Version? currentDartSdk;

  @override
  String get id => SignalIds.sdkCompat;

  @override
  double get weight => 7;

  @override
  SignalResult evaluate(PackageMetadata meta) {
    final constraint = meta.sdkConstraint;
    if (constraint == null) {
      return const SignalResult(
        signalId: SignalIds.sdkCompat,
        risk: 0.4,
        reason: 'No sdk constraint declared',
        detail:
            'Missing environment.sdk in pubspec. Bad practice but not necessarily broken.',
      );
    }

    final sdk = currentDartSdk;
    if (sdk == null) {
      return const SignalResult(
          signalId: SignalIds.sdkCompat,
          risk: 0.2,
          reason: 'Local Dart SDK version unknown',
          didFail: true);
    }

    if (!constraint.allows(sdk)) {
      return SignalResult(
        signalId: id,
        risk: 1.0,
        reason: 'Incompatible with your Dart SDK $sdk',
        detail: 'Package requires $constraint. This will fail at pub get.',
      );
    }

    // Warn when the constraint's upper bound is within two minor versions of
    // the currently running SDK — next upgrade may break compatibility.
    if (constraint is VersionRange) {
      final max = constraint.max;
      if (max != null) {
        final monthsLeft =
            (max.major - sdk.major) * 12 + (max.minor - sdk.minor);
        if (monthsLeft <= 2) {
          return SignalResult(
            signalId: id,
            risk: 0.4,
            reason: 'SDK constraint upper bound close: $max',
            detail: 'Next SDK upgrade might break compatibility.',
          );
        }
      }
    }

    return SignalResult(
        signalId: id, risk: 0.0, reason: 'Compatible with Dart SDK $sdk');
  }
}
