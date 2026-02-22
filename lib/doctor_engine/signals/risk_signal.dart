import '../../domain/models.dart';

/// Base class for all risk evaluation signals.
///
/// Each [RiskSignal] focuses on one measurable dimension of package health
/// (maintenance, version freshness, pub.dev score, etc.). Subclasses must
/// implement [id], [weight], and [evaluate].
///
/// Signals are stateless and `const`-constructible wherever possible, so a
/// single instance can be safely reused across scans.
abstract class RiskSignal {
  /// Creates a [RiskSignal].
  const RiskSignal();

  /// Stable identifier for this signal — see [SignalIds] for the canonical set.
  String get id;

  /// Relative importance of this signal when computing the weighted-average
  /// risk score. Higher values have more influence on the final score.
  double get weight;

  /// Evaluates [meta] and returns a [SignalResult] with a risk in [0.0, 1.0].
  SignalResult evaluate(PackageMetadata meta);
}
