import '../../constants.dart';
import '../../domain/models.dart';
import 'risk_signal.dart';

/// Measures how regularly a package ships new versions.
///
/// A long average interval between releases correlates with reduced maintenance
/// activity, increasing the risk that bugs go unfixed for extended periods.
/// At least two releases are required to compute a meaningful cadence.
///
/// Weight: 8.
class ReleaseFrequencySignal extends RiskSignal {
  /// Creates a [ReleaseFrequencySignal].
  const ReleaseFrequencySignal();

  @override
  String get id => SignalIds.releaseFrequency;

  @override
  double get weight => 8;

  @override
  SignalResult evaluate(PackageMetadata meta) {
    final releases = meta.releases;

    if (releases.length < 2) {
      return SignalResult(
        signalId: id,
        risk: 0.5,
        reason: releases.isEmpty
            ? 'No release history available'
            : 'Single release — no frequency data',
      );
    }

    // Compute the average gap in days between consecutive releases.
    final sorted = [...releases]
      ..sort((a, b) => a.publishedAt.compareTo(b.publishedAt));
    var total = 0;
    for (var i = 1; i < sorted.length; i++) {
      total +=
          sorted[i].publishedAt.difference(sorted[i - 1].publishedAt).inDays;
    }
    final avg = total / (sorted.length - 1);

    if (avg < 90) {
      return SignalResult(
          signalId: id,
          risk: 0.0,
          reason: 'Frequent releases (~${avg.round()}d avg)');
    }
    if (avg < 180) {
      return SignalResult(
          signalId: id,
          risk: 0.3,
          reason: 'Moderate cadence (~${avg.round()}d avg)');
    }
    if (avg < 365) {
      return SignalResult(
          signalId: id,
          risk: 0.6,
          reason: 'Slow cadence (~${avg.round()}d avg)');
    }
    return SignalResult(
      signalId: id,
      risk: 1.0,
      reason: 'Very infrequent releases (~${avg.round()}d avg)',
      detail: 'Sparse release history is a strong signal of low maintenance.',
    );
  }
}
