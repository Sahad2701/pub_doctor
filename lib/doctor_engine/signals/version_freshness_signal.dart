import '../../constants.dart';
import '../../domain/models.dart';
import 'risk_signal.dart';

/// Compares the project's locked version against the latest published version.
///
/// Scores escalate from a low-risk patch-behind to maximum risk for a full
/// major-version gap, which typically implies breaking API changes.
///
/// Weight: 20.
class VersionFreshnessSignal extends RiskSignal {
  /// Creates a [VersionFreshnessSignal].
  const VersionFreshnessSignal();

  @override
  String get id => SignalIds.versionFreshness;

  @override
  double get weight => 20;

  @override
  SignalResult evaluate(PackageMetadata meta) {
    final latest = meta.latestStableVersion ?? meta.latestVersion;

    if (latest == null) {
      return const SignalResult(
        signalId: SignalIds.versionFreshness,
        risk: 0.3,
        reason: 'Latest version unavailable',
        didFail: true,
      );
    }

    final current = meta.currentVersion;

    if (current >= latest) {
      return SignalResult(
          signalId: id, risk: 0.0, reason: 'Up to date ($current)');
    }

    if (current.isPreRelease && !latest.isPreRelease) {
      return SignalResult(
        signalId: id,
        risk: 0.4,
        reason: 'On pre-release $current, stable $latest available',
      );
    }

    if (latest.major > current.major) {
      return SignalResult(
        signalId: id,
        risk: 1.0,
        reason: 'Major version behind: $current → $latest',
        detail:
            'Major bumps usually mean breaking API changes. Plan the migration.',
      );
    }
    if (latest.minor > current.minor) {
      return SignalResult(
        signalId: id,
        risk: 0.5,
        reason: 'Minor version behind: $current → $latest',
      );
    }
    return SignalResult(
      signalId: id,
      risk: 0.2,
      reason: 'Patch behind: $current → $latest',
    );
  }
}
