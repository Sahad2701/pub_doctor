import '../../constants.dart';
import '../../domain/models.dart';
import 'risk_signal.dart';

/// Measures how quickly a maintainer closes issues on average.
///
/// The average is computed over the last 100 closed issues fetched from
/// GitHub. Long close times indicate that the maintainer is slow to triage
/// bugs and feature requests, which increases the risk that your own issues
/// will go unaddressed.
///
/// Weight: 5.
class IssueResponseSignal extends RiskSignal {
  /// Creates an [IssueResponseSignal].
  const IssueResponseSignal();

  @override
  String get id => SignalIds.issueResponse;

  @override
  double get weight => 5;

  @override
  SignalResult evaluate(PackageMetadata meta) {
    final health = meta.repoHealth;
    final avg = health?.avgIssueCloseTimeDays;

    if (avg == null) {
      return const SignalResult(
        signalId: SignalIds.issueResponse,
        risk: 0.3,
        reason: 'Issue response time unavailable',
        didFail: true,
      );
    }

    if (avg <= 7) {
      return SignalResult(
          signalId: id,
          risk: 0.0,
          reason: 'Issues closed fast (~${avg.toStringAsFixed(0)}d avg)');
    }
    if (avg <= 30) {
      return SignalResult(
          signalId: id,
          risk: 0.2,
          reason: 'Reasonable response time (~${avg.toStringAsFixed(0)}d avg)');
    }
    if (avg <= 90) {
      return SignalResult(
          signalId: id,
          risk: 0.5,
          reason: 'Slow issue response (~${avg.toStringAsFixed(0)}d avg)');
    }
    if (avg <= 180) {
      return SignalResult(
          signalId: id,
          risk: 0.75,
          reason: 'Very slow issue response (~${avg.toStringAsFixed(0)}d avg)');
    }
    return SignalResult(
      signalId: id,
      risk: 1.0,
      reason: 'Issues take >180d to close on average',
      detail:
          'Maintainer is not actively triaging. Bug reports may never get addressed.',
    );
  }
}
