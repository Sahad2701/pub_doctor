import 'package:pub_semver/pub_semver.dart';

import '../constants.dart';

/// pub.dev publisher verification tiers for a package.
enum PackageVerification {
  /// No publisher verification or Flutter Favourite status.
  none,

  /// Package belongs to a verified publisher on pub.dev.
  verifiedPublisher,

  /// Package is a Flutter Favourite.
  flutterFavourite,

  /// Package is both from a verified publisher and a Flutter Favourite.
  verifiedPublisherAndFlutterFavourite,
}

/// Five-tier risk classification derived from a package's aggregate score.
enum RiskLevel {
  /// Score 0–20: no actionable concerns.
  healthy(label: 'Healthy', range: '0–20'),

  /// Score 21–40: minor issues worth monitoring.
  low(label: 'Low Risk', range: '21–40'),

  /// Score 41–60: attention recommended before the next release.
  warning(label: 'Warning', range: '41–60'),

  /// Score 61–80: significant problems — plan remediation soon.
  risky(label: 'Risky', range: '61–80'),

  /// Score 81–100: blocking issues — act immediately.
  critical(label: 'Critical', range: '81–100');

  const RiskLevel({required this.label, required this.range});

  /// Human-readable label shown in CLI output and reports.
  final String label;

  /// Score range this level covers, e.g. `'21–40'`.
  final String range;

  /// Maps a numeric score in [0, 100] to the corresponding [RiskLevel].
  static RiskLevel fromScore(double score) {
    if (score <= 20) return healthy;
    if (score <= 40) return low;
    if (score <= 60) return warning;
    if (score <= 80) return risky;
    return critical;
  }
}

/// A single version-and-publication-date pair from a package's release history.
class Release {
  /// Creates a [Release].
  const Release({required this.version, required this.publishedAt});

  /// The semver version string for this release.
  final Version version;

  /// When this version was published to pub.dev.
  final DateTime publishedAt;
}

/// GitHub-specific health data for a repository.
///
/// Null fields indicate the data was unavailable — either no repository URL
/// was listed, the repo is not hosted on GitHub, or the API rate limit was hit.
class RepoHealth {
  /// Creates a [RepoHealth].
  const RepoHealth({
    this.openIssues,
    this.closedIssues,
    this.openPullRequests,
    this.stars,
    this.forks,
    this.contributors,
    this.avgIssueCloseTimeDays,
    this.lastCommitDate,
    this.isArchived,
    this.hasIssuesEnabled,
    this.defaultBranch,
  });

  /// Number of currently open issues.
  final int? openIssues;

  /// Count of the last 100 closed issues used for latency averaging.
  final int? closedIssues;

  /// Number of currently open pull requests.
  final int? openPullRequests;

  /// GitHub star count.
  final int? stars;

  /// GitHub fork count.
  final int? forks;

  /// Number of unique contributors (capped at the GitHub API page size).
  final int? contributors;

  /// Average days from issue open to close across the last 100 closed issues.
  final double? avgIssueCloseTimeDays;

  /// Date of the most recent commit on the default branch.
  final DateTime? lastCommitDate;

  /// `true` if the repository has been archived on GitHub.
  final bool? isArchived;

  /// `true` if the GitHub Issues tab is enabled for this repository.
  final bool? hasIssuesEnabled;

  /// Name of the default branch (e.g. `main`, `master`).
  final String? defaultBranch;

  /// Fraction of issues closed vs total, in [0.0, 1.0].
  ///
  /// Returns `null` when [openIssues] or [closedIssues] is unavailable, or
  /// when the total issue count is zero.
  double? get issueResolutionRate {
    final open = openIssues;
    final closed = closedIssues;
    if (open == null || closed == null) return null;
    final total = open + closed;
    if (total == 0) return null;
    return closed / total;
  }
}

/// All metadata pub_doctor needs to evaluate a single package dependency.
///
/// Populated by [PubApiClient] (pub.dev data) and enriched by [GitHubClient]
/// (repository health). Immutable after construction.
class PackageMetadata {
  /// Creates a [PackageMetadata].
  const PackageMetadata({
    required this.name,
    required this.currentVersion,
    this.latestVersion,
    this.latestStableVersion,
    this.repositoryUrl,
    this.issueTrackerUrl,
    this.publisherDomain,
    this.pubScore,
    this.pubPopularity,
    this.pubLikes,
    this.sdkConstraint,
    this.flutterConstraint,
    this.isNullSafe,
    this.isDiscontinued,
    this.isUnlisted,
    this.releases = const [],
    this.verification = PackageVerification.none,
    this.repoHealth,
    this.fetchedAt,
    this.isFromCache = false,
  });

  /// The package name as it appears on pub.dev.
  final String name;

  /// The version currently declared in the project's `pubspec.lock`.
  final Version currentVersion;

  /// The most recent version of any stability level (including pre-releases).
  final Version? latestVersion;

  /// The most recent stable (non-pre-release) version.
  final Version? latestStableVersion;

  /// Repository URL taken from the package's pubspec.
  final Uri? repositoryUrl;

  /// Issue tracker URL taken from the package's pubspec.
  final Uri? issueTrackerUrl;

  /// Publisher domain, e.g. `dart.dev` or `flutter.dev`.
  final String? publisherDomain;

  /// pub.dev quality score, normalised to the range [0, 100].
  final double? pubScore;

  /// pub.dev popularity score, normalised to the range [0, 100].
  final double? pubPopularity;

  /// Total number of pub.dev likes.
  final int? pubLikes;

  /// Dart SDK constraint declared in the package's pubspec.
  final VersionConstraint? sdkConstraint;

  /// Flutter SDK constraint declared in the package's pubspec.
  final VersionConstraint? flutterConstraint;

  /// Whether the package opts in to Dart null safety.
  final bool? isNullSafe;

  /// Whether the publisher has officially marked this package discontinued.
  final bool? isDiscontinued;

  /// Whether the package is hidden from pub.dev search results.
  final bool? isUnlisted;

  /// Full release history, sorted newest-first.
  final List<Release> releases;

  /// pub.dev publisher verification and Flutter Favourite status.
  final PackageVerification verification;

  /// GitHub repository health metrics, if available.
  final RepoHealth? repoHealth;

  /// When this metadata was last fetched from the network.
  final DateTime? fetchedAt;

  /// `true` when this metadata was served from the local disk cache.
  final bool isFromCache;

  /// `true` when the package belongs to a verified publisher.
  bool get hasVerifiedPublisher =>
      publisherDomain != null &&
      (verification == PackageVerification.verifiedPublisher ||
          verification ==
              PackageVerification.verifiedPublisherAndFlutterFavourite);

  /// `true` when the package has Flutter Favourite status.
  bool get isFlutterFavourite =>
      verification == PackageVerification.flutterFavourite ||
      verification == PackageVerification.verifiedPublisherAndFlutterFavourite;

  /// Returns a copy of this metadata with [repoHealth] replaced.
  PackageMetadata copyWith({RepoHealth? repoHealth}) => PackageMetadata(
        name: name,
        currentVersion: currentVersion,
        latestVersion: latestVersion,
        latestStableVersion: latestStableVersion,
        repositoryUrl: repositoryUrl,
        issueTrackerUrl: issueTrackerUrl,
        publisherDomain: publisherDomain,
        pubScore: pubScore,
        pubPopularity: pubPopularity,
        pubLikes: pubLikes,
        sdkConstraint: sdkConstraint,
        flutterConstraint: flutterConstraint,
        isNullSafe: isNullSafe,
        isDiscontinued: isDiscontinued,
        isUnlisted: isUnlisted,
        releases: releases,
        verification: verification,
        repoHealth: repoHealth ?? this.repoHealth,
        fetchedAt: fetchedAt,
        isFromCache: isFromCache,
      );
}

/// The outcome of a single [RiskSignal] evaluation.
class SignalResult {
  /// Creates a [SignalResult].
  ///
  /// [risk] must be in [0.0, 1.0].
  const SignalResult({
    required this.signalId,
    required this.risk,
    required this.reason,
    this.detail,
    this.didFail = false,
  }) : assert(risk >= 0.0 && risk <= 1.0);

  /// The [SignalIds] constant that identifies which signal produced this result.
  final String signalId;

  /// Normalised risk score in the range [0.0, 1.0].
  final double risk; // [0, 1]

  /// Short human-readable explanation shown in CLI output.
  final String reason;

  /// Optional extended detail shown in verbose mode.
  final String? detail;

  /// `true` when the signal threw an exception and the result is synthetic.
  final bool didFail;
}

/// The fully evaluated diagnosis for a single dependency.
class DiagnosisResult {
  /// Creates a [DiagnosisResult].
  const DiagnosisResult({
    required this.packageName,
    required this.currentVersion,
    required this.latestVersion,
    required this.riskScore,
    required this.riskLevel,
    required this.signals,
    required this.recommendations,
    required this.verification,
    required this.repoHealth,
    required this.isFromCache,
  });

  /// The package name.
  final String packageName;

  /// The version currently in use.
  final Version currentVersion;

  /// The latest available version (stable preferred).
  final Version? latestVersion;

  /// Weighted-average risk score in [0, 100].
  final double riskScore; // 0–100

  /// Tier derived from [riskScore].
  final RiskLevel riskLevel;

  /// All signal results, sorted by descending signal weight.
  final List<SignalResult> signals;

  /// Ordered list of human-readable action items.
  final List<String> recommendations;

  /// Publisher verification and Flutter Favourite status.
  final PackageVerification verification;

  /// Repository health, if it could be fetched.
  final RepoHealth? repoHealth;

  /// `true` when metadata was served from cache rather than the network.
  final bool isFromCache;

  /// Signals that threw an exception during evaluation.
  List<SignalResult> get failedSignals =>
      signals.where((s) => s.didFail).toList();
}

/// Aggregated diagnosis for an entire project's dependency graph.
class ProjectDiagnosis {
  /// Creates a [ProjectDiagnosis].
  const ProjectDiagnosis({
    required this.results,
    required this.scannedAt,
    required this.pubspecPath,
    this.dartSdkVersion,
  });

  /// Per-package results, sorted by descending risk score.
  final List<DiagnosisResult> results;

  /// Timestamp of when this scan was performed.
  final DateTime scannedAt;

  /// Absolute or relative path to the `pubspec.yaml` that was scanned.
  final String pubspecPath;

  /// Dart SDK version string detected on the host machine, if available.
  final String? dartSdkVersion;

  /// Total number of packages evaluated.
  int get totalPackages => results.length;

  /// Number of packages at [RiskLevel.critical].
  int get criticalCount =>
      results.where((r) => r.riskLevel == RiskLevel.critical).length;

  /// Number of packages at [RiskLevel.risky].
  int get riskyCount =>
      results.where((r) => r.riskLevel == RiskLevel.risky).length;

  /// Number of packages at [RiskLevel.warning].
  int get warningCount =>
      results.where((r) => r.riskLevel == RiskLevel.warning).length;

  /// Number of packages at [RiskLevel.healthy] or [RiskLevel.low].
  int get healthyCount => results
      .where((r) =>
          r.riskLevel == RiskLevel.healthy || r.riskLevel == RiskLevel.low)
      .length;

  /// Packages where the [SignalIds.maintenance] signal scored ≥ 1.0
  /// (no commits in over a year).
  List<DiagnosisResult> get abandonedPackages => results
      .where((r) => r.signals
          .any((s) => s.signalId == SignalIds.maintenance && s.risk >= 1.0))
      .toList();
}
