import 'package:pub_semver/pub_semver.dart';

import '../../constants.dart';
import '../../domain/models.dart';
import 'risk_signal.dart';

/// Checks whether a package has opted into Dart null safety.
///
/// A non-null-safe package forces the entire project into legacy
/// `--no-sound-null-safety` mode, which disables type-system guarantees
/// across all transitive dependencies.
///
/// Weight: 8.
class NullSafetySignal extends RiskSignal {
  /// Creates a [NullSafetySignal].
  const NullSafetySignal();

  @override
  String get id => SignalIds.nullSafety;

  @override
  double get weight => 8;

  @override
  SignalResult evaluate(PackageMetadata meta) {
    bool? safe = meta.isNullSafe;

    // Fall back to inferring null-safety from the SDK constraint if the
    // pre-computed flag is absent.
    if (safe == null) {
      final c = meta.sdkConstraint;
      if (c is VersionRange) {
        final min = c.min;
        safe = min != null && min >= Version(2, 12, 0);
      }
    }

    if (safe == null) {
      return const SignalResult(
          signalId: SignalIds.nullSafety,
          risk: 0.3,
          reason: 'Cannot determine null safety status',
          didFail: true);
    }

    return safe
        ? const SignalResult(
            signalId: SignalIds.nullSafety, risk: 0.0, reason: 'Null safe')
        : const SignalResult(
            signalId: SignalIds.nullSafety,
            risk: 1.0,
            reason: 'Not null safe — requires --no-sound-null-safety',
            detail:
                'Non-null-safe packages force legacy mode on your entire build.',
          );
  }
}
