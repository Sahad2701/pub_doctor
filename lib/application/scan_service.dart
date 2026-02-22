import 'dart:io';

import 'package:pub_semver/pub_semver.dart';

import '../data/cache.dart';
import '../data/github_client.dart';
import '../data/pub_api_client.dart';
import '../data/pubspec_parser.dart';
import '../doctor_engine/scorer.dart';
import '../domain/models.dart';

/// Configuration for a [ScanService.scan] run.
class ScanOptions {
  /// Creates a [ScanOptions] with sensible defaults.
  const ScanOptions({
    this.includeDev = false,
    this.fresh = false,
    this.offline = false,
    this.verbose = false,
    this.concurrency = 8,
  });

  /// Whether to include `dev_dependencies` in the scan.
  final bool includeDev;

  /// When `true`, bypasses the disk cache and fetches fresh data from the
  /// network even if a valid cached entry exists.
  final bool fresh;

  /// Restricts the scan to cached data only — no network calls are made.
  final bool offline;

  /// Enables verbose signal output in the CLI reporter.
  final bool verbose;

  /// Maximum number of concurrent HTTP requests.
  final int concurrency;
}

/// Orchestrates a full dependency-health scan.
///
/// Parses the target `pubspec.yaml`, fetches package metadata from pub.dev
/// and GitHub, then delegates scoring to [RiskScorer].
class ScanService {
  /// Creates a [ScanService], optionally injecting a custom [DiskCache].
  ScanService({DiskCache? cache}) : _cache = cache ?? DiskCache();

  final DiskCache _cache;
  PubApiClient? _pub;
  GitHubClient? _gh;

  Future<ProjectDiagnosis> scan(String pubspecPath, ScanOptions opts) async {
    final info = await PubspecParser().parse(pubspecPath);
    final sdk = _detectSdk();
    final packages = opts.includeDev ? info.all : info.dependencies;

    if (packages.isEmpty) {
      return ProjectDiagnosis(
        results: [],
        scannedAt: DateTime.now(),
        pubspecPath: pubspecPath,
        dartSdkVersion: sdk?.toString(),
      );
    }

    Map<String, PackageMetadata> meta;

    if (opts.offline) {
      meta = await _fromCacheOnly(packages);
    } else {
      _pub ??= PubApiClient(cache: _cache, concurrency: opts.concurrency);
      _gh ??= GitHubClient(cache: _cache);

      meta = await _pub!.fetchAll(packages, fresh: opts.fresh);
      await _augmentGitHub(meta);
      await _probeRepos(meta);
    }

    final repoReachability = {
      for (final m in meta.values)
        if (m.repositoryUrl != null && m.repoHealth != null)
          m.repositoryUrl.toString(): true,
    };

    final scorer =
        RiskScorer(dartSdkVersion: sdk, repoReachability: repoReachability);
    final results = meta.values.map(scorer.diagnose).toList()
      ..sort((a, b) => b.riskScore.compareTo(a.riskScore));

    return ProjectDiagnosis(
      results: results,
      scannedAt: DateTime.now(),
      pubspecPath: pubspecPath,
      dartSdkVersion: sdk?.toString(),
    );
  }

  void dispose() {
    _pub?.dispose();
    _gh?.dispose();
  }

  Future<void> _augmentGitHub(Map<String, PackageMetadata> meta) async {
    const maxConcurrent = 5;
    var inFlight = 0;

    final futures = <Future<void>>[];
    for (final entry in meta.entries) {
      final url = entry.value.repositoryUrl;
      if (url == null) continue;

      while (inFlight >= maxConcurrent) {
        await Future<void>.delayed(const Duration(milliseconds: 30));
      }
      inFlight++;

      futures.add(
        _gh!.fetchRepoHealth(url).then((health) {
          if (health != null) {
            meta[entry.key] = entry.value.copyWith(repoHealth: health);
          }
        }).whenComplete(() => inFlight--),
      );
    }

    await Future.wait(futures)
        .timeout(const Duration(seconds: 30), onTimeout: () => []);
  }

  Future<void> _probeRepos(Map<String, PackageMetadata> meta) async {
    final futures = <Future<void>>[];
    for (final m in meta.values) {
      final url = m.repositoryUrl;
      if (url == null || m.repoHealth != null) continue;
      futures.add(_pub!.probe(url).then((_) {}));
    }
    await Future.wait(futures)
        .timeout(const Duration(seconds: 15), onTimeout: () => []);
  }

  Future<Map<String, PackageMetadata>> _fromCacheOnly(
      Map<String, Version> packages) async {
    final out = <String, PackageMetadata>{};
    for (final e in packages.entries) {
      final hit = await _cache.get('pub:${e.key}');
      if (hit != null) {
        out[e.key] = PackageMetadata(
          name: e.key,
          currentVersion: e.value,
          isFromCache: true,
        );
      }
    }
    return out;
  }

  Version? _detectSdk() {
    try {
      final r = Process.runSync('dart', ['--version']);
      final out = (r.stdout as String).isNotEmpty
          ? r.stdout as String
          : r.stderr as String;
      final m = RegExp(r'(\d+\.\d+\.\d+)').firstMatch(out);
      if (m != null) return Version.parse(m.group(1)!);
    } catch (_) {}
    return null;
  }
}
