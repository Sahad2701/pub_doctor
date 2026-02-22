import '../../constants.dart';
import '../../domain/models.dart';
import 'risk_signal.dart';

/// Evaluates the pub.dev automated quality score for a package.
///
/// The score is normalised from the raw `grantedPoints/maxPoints` ratio that
/// pub.dev publishes. Packages with a very low score typically have missing
/// documentation, no example project, or failing static analysis.
///
/// Weight: 10.
class PubScoreSignal extends RiskSignal {
  /// Creates a [PubScoreSignal].
  const PubScoreSignal();

  @override
  String get id => SignalIds.pubScore;

  @override
  double get weight => 10;

  @override
  SignalResult evaluate(PackageMetadata meta) {
    final score = meta.pubScore;
    if (score == null) {
      return const SignalResult(
        signalId: SignalIds.pubScore,
        risk: 0.4,
        reason: 'pub.dev score unavailable',
        didFail: true,
      );
    }

    final risk = (1.0 - (score / 100.0)).clamp(0.0, 1.0);
    final label = score.toStringAsFixed(0);

    if (score >= 80) {
      return SignalResult(
          signalId: id,
          risk: risk,
          reason: 'pub.dev score $label/100 — excellent');
    }
    if (score >= 60) {
      return SignalResult(
          signalId: id,
          risk: risk,
          reason: 'pub.dev score $label/100 — acceptable');
    }
    if (score >= 40) {
      return SignalResult(
          signalId: id, risk: risk, reason: 'pub.dev score $label/100 — low');
    }
    return SignalResult(
      signalId: id,
      risk: risk,
      reason: 'pub.dev score $label/100 — very low',
      detail:
          'Low scores usually mean missing docs, no example, or failing analysis.',
    );
  }
}
