import 'package:pub_semver/pub_semver.dart';

import '../constants.dart';
import '../domain/models.dart';
import 'signals.dart';

/// Orchestrates all [RiskSignal]s and produces a [DiagnosisResult] for a
/// single package.
///
/// Create one scorer per scan, passing in the local Dart SDK version and
/// any pre-resolved repository reachability data.
class RiskScorer {
  /// Creates a [RiskScorer].
  ///
  /// [dartSdkVersion] is the version of the Dart SDK running on the host
  /// machine — used by [SdkCompatibilitySignal] to detect mismatches.
  ///
  /// [repoReachability] maps repository URL strings to booleans indicating
  /// whether the repository responded to a HEAD probe during this scan.
  RiskScorer({
    Version? dartSdkVersion,
    Map<String, bool> repoReachability = const {},
  })  : _dartSdk = dartSdkVersion,
        _repoReachability = repoReachability;

  final Version? _dartSdk;
  final Map<String, bool> _repoReachability;

  /// Evaluates all signals for [meta] and returns a fully scored
  /// [DiagnosisResult], with signals sorted by descending weight.
  DiagnosisResult diagnose(PackageMetadata meta) {
    final signals = _signals(meta);
    final results = _runAll(signals, meta);
    final score = _score(signals, results);

    // Sort results so the highest-weight signals appear first in the output.
    final sorted = [...results]..sort((a, b) {
        final wa = signals
            .firstWhere((s) => s.id == a.signalId, orElse: () => _dummy)
            .weight;
        final wb = signals
            .firstWhere((s) => s.id == b.signalId, orElse: () => _dummy)
            .weight;
        return wb.compareTo(wa);
      });

    return DiagnosisResult(
      packageName: meta.name,
      currentVersion: meta.currentVersion,
      latestVersion: meta.latestStableVersion ?? meta.latestVersion,
      riskScore: score,
      riskLevel: RiskLevel.fromScore(score),
      signals: sorted,
      recommendations: _recommendations(meta, sorted, score),
      verification: meta.verification,
      repoHealth: meta.repoHealth,
      isFromCache: meta.isFromCache,
    );
  }

  /// Builds the ordered list of [RiskSignal]s for [meta], injecting any
  /// runtime context (SDK version, repo reachability) that individual signals
  /// need.
  List<RiskSignal> _signals(PackageMetadata meta) {
    final reachable = meta.repositoryUrl != null
        ? _repoReachability[meta.repositoryUrl.toString()]
        : null;

    return [
      const MaintenanceSignal(),
      const VersionFreshnessSignal(),
      const PubScoreSignal(),
      const NullSafetySignal(),
      SdkCompatibilitySignal(currentDartSdk: _dartSdk),
      const ReleaseFrequencySignal(),
      RepositoryAvailabilitySignal(isReachable: reachable),
      const OpenIssuesSignal(),
      const IssueResponseSignal(),
      const VerificationSignal(),
    ];
  }

  /// Evaluates every signal in [signals] against [meta].
  ///
  /// If a signal throws, a fallback [SignalResult] is recorded with
  /// `didFail: true` so the rest of the diagnosis is unaffected.
  List<SignalResult> _runAll(List<RiskSignal> signals, PackageMetadata meta) {
    final out = <SignalResult>[];
    for (final s in signals) {
      try {
        out.add(s.evaluate(meta));
      } catch (e) {
        out.add(SignalResult(
            signalId: s.id,
            risk: 0.5,
            reason: 'signal threw: $e',
            didFail: true));
      }
    }
    return out;
  }

  /// Computes a weighted-average risk score in the range [0, 100].
  ///
  /// Failed signals are excluded from the calculation to avoid poisoning the
  /// aggregate with unreliable data.
  double _score(List<RiskSignal> signals, List<SignalResult> results) {
    final byId = {for (final r in results) r.signalId: r};
    var weightedSum = 0.0;
    var totalWeight = 0.0;

    for (final s in signals) {
      final r = byId[s.id];
      if (r == null || r.didFail) continue;
      weightedSum += s.weight * r.risk;
      totalWeight += s.weight;
    }

    if (totalWeight == 0) return 0;
    return (weightedSum / totalWeight * 100).clamp(0.0, 100.0);
  }

  /// Derives human-readable action items from the most significant signal
  /// results and the overall [score].
  List<String> _recommendations(
      PackageMetadata meta, List<SignalResult> results, double score) {
    final recs = <String>[];
    final byId = {for (final r in results) r.signalId: r};

    if (meta.isDiscontinued == true) {
      recs.add('URGENT: package discontinued — replace before next release');
      return recs;
    }

    final freshness = byId[SignalIds.versionFreshness];
    if (freshness != null && freshness.risk >= 1.0) {
      recs.add('Run `dart pub upgrade ${meta.name}` — major version behind');
    } else if (freshness != null && freshness.risk >= 0.5) {
      recs.add('`dart pub upgrade ${meta.name}` — newer version available');
    }

    final nullSafe = byId[SignalIds.nullSafety];
    if (nullSafe != null && nullSafe.risk >= 1.0) {
      recs.add(
          'Find a null-safe fork or alternative — legacy mode hurts your entire build');
    }

    final maint = byId[SignalIds.maintenance];
    if (maint != null && maint.risk >= 1.0) {
      recs.add(
          'No commits in 12+ months — check for forks or alternatives on pub.dev');
    }

    final issues = byId[SignalIds.openIssues];
    if (issues != null && issues.risk >= 0.7) {
      recs.add(
          'High open issue count — check if your use cases are affected before upgrading');
    }

    final verify = byId[SignalIds.verification];
    if (verify != null && verify.risk >= 0.5) {
      recs.add(
          'Unverified package — audit the source before shipping to production');
    }

    if (recs.isEmpty && score < 40) {
      recs.add('Looks healthy — keep deps updated and watch for new releases');
    } else if (recs.isEmpty) {
      recs.add('Multiple risk factors present — review signals above');
    }

    return recs;
  }
}

// Sentinel used when a signal ID can't be matched during sort (should never
// happen in practice, but keeps the sort comparator total).
final _dummy = _DummySignal();

class _DummySignal extends RiskSignal {
  @override
  String get id => '';
  @override
  double get weight => 0;
  @override
  SignalResult evaluate(PackageMetadata meta) =>
      const SignalResult(signalId: '', risk: 0, reason: '');
}
