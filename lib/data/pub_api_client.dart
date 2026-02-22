// ignore_for_file: avoid_redundant_argument_values

/// HTTP client for the pub.dev API.
///
/// Handles concurrency limiting, exponential back-off on rate limits or
/// transient errors, response parsing, and optional disk caching (24-hour TTL
/// by default). All fetch operations are safe to run concurrently up to the
/// configured [concurrency] limit.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;
import 'package:pub_semver/pub_semver.dart';

import '../constants.dart';
import '../domain/models.dart';
import 'cache.dart';

// A simple semaphore that limits the number of in-flight HTTP requests.
class _Gate {
  _Gate(int limit) : _available = limit;
  int _available;
  final _q = <Completer<void>>[];

  Future<void> acquire() async {
    if (_available > 0) {
      _available--;
      return;
    }
    final c = Completer<void>();
    _q.add(c);
    await c.future;
  }

  void release() {
    if (_q.isNotEmpty) {
      _q.removeAt(0).complete();
    } else {
      _available++;
    }
  }
}

/// Fetches and parses pub.dev package metadata.
///
/// Combining data from the `/packages/<name>` and `/packages/<name>/score`
/// endpoints it builds [PackageMetadata] objects suitable for risk scoring.
class PubApiClient {
  /// Creates a [PubApiClient].
  ///
  /// - [client]: optional injectable HTTP client for testing.
  /// - [cache]: optional [DiskCache] to read/write cached responses.
  /// - [concurrency]: maximum number of simultaneous in-flight requests.
  /// - [timeout]: per-request timeout.
  /// - [retries]: number of retry attempts on failure or rate-limit.
  PubApiClient({
    http.Client? client,
    DiskCache? cache,
    int concurrency = 8,
    Duration timeout = const Duration(seconds: 15),
    int retries = 3,
  })  : _http = client ?? http.Client(),
        _cache = cache,
        _gate = _Gate(concurrency),
        _timeout = timeout,
        _retries = retries;

  final http.Client _http;
  final DiskCache? _cache;
  final _Gate _gate;
  final Duration _timeout;
  final int _retries;

  static final _rng = math.Random();

  /// Fetches metadata for a single [name]/[currentVersion] pair.
  ///
  /// Returns `null` when the package cannot be found on pub.dev.
  /// Serves from [DiskCache] when [fresh] is `false` and a valid entry exists.
  Future<PackageMetadata?> fetch({
    required String name,
    required Version currentVersion,
    bool fresh = false,
  }) async {
    if (!fresh && _cache != null) {
      final hit = await _cache!.get('pub:$name');
      if (hit != null) return _parse(hit, currentVersion, fromCache: true);
    }

    final info = await _get('${Urls.pubDevApi}/packages/$name');
    if (info == null) return null;

    final score = await _get('${Urls.pubDevApi}/packages/$name/score');
    final blob = {'info': info, 'score': score};
    await _cache?.set('pub:$name', blob, ttl: const Duration(hours: 24));

    return _parse(blob, currentVersion, fromCache: false);
  }

  /// Fetches metadata for all [packages] concurrently.
  ///
  /// Entries that cannot be resolved (404, parse error) are silently excluded
  /// from the result map.
  Future<Map<String, PackageMetadata>> fetchAll(
    Map<String, Version> packages, {
    bool fresh = false,
  }) async {
    final entries = await Future.wait(
      packages.entries.map((e) async {
        final m =
            await fetch(name: e.key, currentVersion: e.value, fresh: fresh);
        return MapEntry(e.key, m);
      }),
    );
    return {
      for (final e in entries)
        if (e.value != null) e.key: e.value!
    };
  }

  /// Sends a HEAD request to [url] to check reachability.
  ///
  /// Returns `true` when the server responds with a 2xx/3xx status,
  /// `false` on a 4xx/5xx, and `null` on connection failure.
  Future<bool?> probe(Uri url) async {
    try {
      await _gate.acquire();
      final res = await _http.head(url).timeout(const Duration(seconds: 8));
      return res.statusCode < 400;
    } catch (_) {
      return null;
    } finally {
      _gate.release();
    }
  }

  /// Closes the underlying HTTP client. Call this when done with the instance.
  void dispose() => _http.close();

  Future<Map<String, dynamic>?> _get(String url) async {
    for (var attempt = 0; attempt <= _retries; attempt++) {
      try {
        await _gate.acquire();
        final res = await _http.get(Uri.parse(url),
            headers: {'Accept': 'application/json'}).timeout(_timeout);

        if (res.statusCode == 200) {
          return json.decode(res.body) as Map<String, dynamic>;
        }
        if (res.statusCode == 404) return null;
        if (res.statusCode == 429 && attempt < _retries) {
          await _backoff(attempt, factor: 4.0);
          continue;
        }
        if (attempt < _retries) await _backoff(attempt);
      } catch (_) {
        if (attempt < _retries) await _backoff(attempt);
      } finally {
        _gate.release();
      }
    }
    return null;
  }

  static Future<void> _backoff(int attempt, {double factor = 1.5}) {
    final ms = (500 * math.pow(factor, attempt)).round();
    final jitter = (_rng.nextDouble() * 0.4 - 0.2) * ms;
    return Future<void>.delayed(
        Duration(milliseconds: (ms + jitter).round().clamp(100, 30000)));
  }

  PackageMetadata? _parse(Map<String, dynamic> blob, Version current,
      {required bool fromCache}) {
    try {
      final info = blob['info'] as Map<String, dynamic>?;
      if (info == null) return null;
      final score = blob['score'] as Map<String, dynamic>?;
      final latest = info['latest'] as Map<String, dynamic>?;
      final pubspec = latest?['pubspec'] as Map<String, dynamic>?;

      final versionsRaw = info['versions'] as List<dynamic>? ?? [];
      final releases = <Release>[];
      for (final v in versionsRaw) {
        final m = v as Map<String, dynamic>;
        final vs = m['version'] as String?;
        final pub = m['published'] as String?;
        if (vs != null && pub != null) {
          try {
            releases.add(Release(
                version: Version.parse(vs), publishedAt: DateTime.parse(pub)));
          } catch (_) {}
        }
      }
      releases.sort((a, b) => b.publishedAt.compareTo(a.publishedAt));

      Version? latestStable;
      Version? latestAny;
      for (final r in releases) {
        latestAny ??= r.version;
        if (!r.version.isPreRelease) {
          latestStable ??= r.version;
          break;
        }
      }

      final granted = score?['grantedPoints'] as int?;
      final maxPts = score?['maxPoints'] as int?;
      final pubScore = (granted != null && maxPts != null && maxPts > 0)
          ? granted / maxPts * 100.0
          : null;
      final popularity = (score?['popularityScore'] as num?)?.toDouble();

      final env = pubspec?['environment'] as Map<String, dynamic>?;
      VersionConstraint? sdkConstraint;
      try {
        final s = env?['sdk'] as String?;
        if (s != null) sdkConstraint = VersionConstraint.parse(s);
      } catch (_) {}

      bool? isNullSafe;
      if (sdkConstraint is VersionRange) {
        final min = sdkConstraint.min;
        isNullSafe = min != null && min >= Version(2, 12, 0);
      }

      Uri? repoUrl;
      try {
        final s = pubspec?['repository'] as String? ??
            pubspec?['homepage'] as String?;
        if (s != null) repoUrl = Uri.parse(s);
      } catch (_) {}

      final publisher = info['publisher']?['publisherId'] as String?;
      final tags = (latest?['tags'] as List<dynamic>?)?.cast<String>() ?? [];
      final isFF = tags.contains('flutter-favourite');
      final verification = switch ((publisher != null, isFF)) {
        (true, true) =>
          PackageVerification.verifiedPublisherAndFlutterFavourite,
        (false, true) => PackageVerification.flutterFavourite,
        (true, false) => PackageVerification.verifiedPublisher,
        _ => PackageVerification.none,
      };

      Uri? issueUrl;
      try {
        final s = pubspec?['issue_tracker'] as String?;
        if (s != null) issueUrl = Uri.parse(s);
      } catch (_) {}

      return PackageMetadata(
        name: info['name'] as String? ?? '',
        currentVersion: current,
        latestVersion: latestAny,
        latestStableVersion: latestStable,
        repositoryUrl: repoUrl,
        issueTrackerUrl: issueUrl,
        publisherDomain: publisher,
        pubScore: pubScore,
        pubPopularity: popularity != null ? popularity * 100 : null,
        sdkConstraint: sdkConstraint,
        isNullSafe: isNullSafe,
        isDiscontinued: info['isDiscontinued'] as bool?,
        isUnlisted: info['isUnlisted'] as bool?,
        releases: releases,
        verification: verification,
        fetchedAt: DateTime.now(),
        isFromCache: fromCache,
      );
    } catch (_) {
      return null;
    }
  }
}
