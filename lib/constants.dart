/// API URLs, well-known signal IDs, and the package version sentinel.
///
/// All constants are in `abstract` classes to prevent instantiation.
library;

/// Package-level metadata baked in at build time.
abstract class Package {
  /// The current version of pub_doctor, kept in sync with `pubspec.yaml`.
  static const String version = '0.0.2';
}

/// Base URLs for the external APIs pub_doctor talks to.
abstract class Urls {
  /// Root of the pub.dev REST API (v2).
  static const String pubDevApi = 'https://pub.dev/api';

  /// Root of the GitHub REST API (v3/2022-11-28).
  static const String githubApi = 'https://api.github.com';
}

/// Stable string identifiers for each [RiskSignal].
///
/// These IDs appear in [SignalResult.signalId] and are used throughout the
/// codebase to look up results by signal. Keep them stable across releases;
/// changing an ID is a breaking change for anyone persisting cached data.
abstract class SignalIds {
  /// Repository commit-activity signal.
  static const String maintenance = 'maintenance';

  /// Version-behind signal (patch / minor / major).
  static const String versionFreshness = 'version_freshness';

  /// pub.dev quality score signal.
  static const String pubScore = 'pub_score';

  /// Null-safety migration signal.
  static const String nullSafety = 'null_safety';

  /// SDK-constraint compatibility signal.
  static const String sdkCompat = 'sdk_compat';

  /// Release cadence / frequency signal.
  static const String releaseFrequency = 'release_frequency';

  /// Repository HTTP reachability signal.
  static const String repoAvailability = 'repo_availability';

  /// Open issue count / resolution-rate signal.
  static const String openIssues = 'open_issues';

  /// Issue-close latency signal.
  static const String issueResponse = 'issue_response';

  /// pub.dev publisher-verification / Flutter Favourite signal.
  static const String verification = 'verification';
}
