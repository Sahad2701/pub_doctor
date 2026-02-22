import '../../constants.dart';
import '../../domain/models.dart';
import 'risk_signal.dart';

/// Evaluates how actively a package is maintained by its author(s).
///
/// The primary indicator is the date of the last commit on the default branch.
/// A package that has been officially discontinued on pub.dev is always scored
/// at maximum risk regardless of its commit history.
///
/// Weight: 25 — the single highest-weighted signal in the scorer, reflecting
/// how strongly inactivity predicts future breakage.
class MaintenanceSignal extends RiskSignal {
  /// Creates a [MaintenanceSignal].
  const MaintenanceSignal();

  @override
  String get id => SignalIds.maintenance;

  @override
  double get weight => 25;

  @override
  SignalResult evaluate(PackageMetadata meta) {
    if (meta.isDiscontinued == true) {
      return const SignalResult(
        signalId: SignalIds.maintenance,
        risk: 1.0,
        reason: 'Officially discontinued on pub.dev',
        detail:
            'Publisher has marked this package discontinued. Migrate immediately.',
      );
    }

    final commit = meta.repoHealth?.lastCommitDate;

    if (commit == null) {
      if (meta.repositoryUrl == null) {
        return const SignalResult(
          signalId: SignalIds.maintenance,
          risk: 0.6,
          reason: 'No repository URL on pub.dev',
        );
      }
      return const SignalResult(
        signalId: SignalIds.maintenance,
        risk: 0.5,
        reason: 'Could not fetch commit history',
        didFail: true,
      );
    }

    final days = DateTime.now().difference(commit).inDays;

    if (days <= 90) {
      return SignalResult(
          signalId: id, risk: 0.0, reason: 'Active — last commit ${days}d ago');
    }
    if (days <= 180) {
      return SignalResult(
          signalId: id,
          risk: 0.3,
          reason: 'Slowing down — last commit ${days}d ago');
    }
    if (days <= 365) {
      return SignalResult(
        signalId: id,
        risk: 0.6,
        reason: 'Low activity — last commit ${days}d ago',
        detail: 'No commits in 6–12 months. Evaluate alternatives.',
      );
    }
    return SignalResult(
      signalId: id,
      risk: 1.0,
      reason: 'Possibly abandoned — ${days}d since last commit',
      detail:
          'No commits in over a year. Unpatched bugs and future breakage are likely.',
    );
  }
}
