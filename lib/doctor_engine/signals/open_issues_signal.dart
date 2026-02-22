import '../../constants.dart';
import '../../domain/models.dart';
import 'risk_signal.dart';

/// Evaluates the open issue count and resolution rate for a repository.
///
/// Risk is a blend of two factors: the raw count of open issues (high counts
/// suggest a backlog the maintainer cannot keep up with) and the overall
/// resolution rate (closed / total), which reflects how actively issues are
/// triaged and closed.
///
/// Weight: 7.
class OpenIssuesSignal extends RiskSignal {
  /// Creates an [OpenIssuesSignal].
  const OpenIssuesSignal();

  @override
  String get id => SignalIds.openIssues;

  @override
  double get weight => 7;

  @override
  SignalResult evaluate(PackageMetadata meta) {
    final health = meta.repoHealth;
    if (health == null || health.openIssues == null) {
      return const SignalResult(
        signalId: SignalIds.openIssues,
        risk: 0.3,
        reason: 'Issue data unavailable',
        didFail: true,
      );
    }

    final open = health.openIssues!;
    final rate = health.issueResolutionRate;

    // Count-based risk: more open issues → higher risk.
    final countRisk = switch (open) {
      0 => 0.0,
      <= 10 => 0.1,
      <= 30 => 0.3,
      <= 100 => 0.5,
      <= 300 => 0.7,
      _ => 0.9,
    };

    // Resolution-rate risk: lower close rate → higher risk.
    double rateRisk = 0.3;
    if (rate != null) {
      rateRisk = 1.0 - rate.clamp(0.0, 1.0);
    }

    final risk = ((countRisk * 0.5) + (rateRisk * 0.5)).clamp(0.0, 1.0);
    final pct = rate != null
        ? '${(rate * 100).toStringAsFixed(0)}% resolved'
        : 'resolution unknown';

    return SignalResult(
      signalId: id,
      risk: risk,
      reason: '$open open issues — $pct',
      detail: rate != null
          ? 'Total closed: ${health.closedIssues ?? "?"}. Resolution rate reflects maintainer responsiveness.'
          : null,
    );
  }
}
