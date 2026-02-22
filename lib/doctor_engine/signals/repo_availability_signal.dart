import '../../constants.dart';
import '../../domain/models.dart';
import 'risk_signal.dart';

/// Checks whether the package's declared repository URL is accessible.
///
/// A missing or unreachable repository makes it impossible to audit the
/// source, browse issue history, or track ongoing development.
///
/// Weight: 5.
class RepositoryAvailabilitySignal extends RiskSignal {
  /// Creates a [RepositoryAvailabilitySignal].
  ///
  /// [isReachable] is the result of a HEAD probe performed earlier in the
  /// scan. Pass `null` when the probe was not attempted (e.g. offline mode).
  const RepositoryAvailabilitySignal({this.isReachable});

  /// Whether the repository URL responded successfully to a HEAD request.
  ///
  /// `null` means the probe was skipped; `false` means it failed.
  final bool? isReachable;

  @override
  String get id => SignalIds.repoAvailability;

  @override
  double get weight => 5;

  @override
  SignalResult evaluate(PackageMetadata meta) {
    if (meta.repositoryUrl == null) {
      return const SignalResult(
        signalId: SignalIds.repoAvailability,
        risk: 0.8,
        reason: 'No repository URL on pub.dev',
        detail: 'Cannot inspect source, issues, or history.',
      );
    }

    if (isReachable == false) {
      return SignalResult(
        signalId: id,
        risk: 1.0,
        reason: 'Repository unreachable: ${meta.repositoryUrl}',
        detail: 'Repo returned an error. It may have been deleted or moved.',
      );
    }

    if (isReachable == null) {
      return SignalResult(
          signalId: id,
          risk: 0.1,
          reason: 'Repository declared: ${meta.repositoryUrl}');
    }

    return SignalResult(
        signalId: id, risk: 0.0, reason: 'Repository reachable');
  }
}
