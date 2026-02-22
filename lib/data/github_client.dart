/// HTTP client for the GitHub REST API (v3 / 2022-11-28).
///
/// Fetches repository health metrics such as open issue count, recent commits,
/// and contributor data. Responses are cached with a 12-hour TTL to respect
/// GitHub's unauthenticated rate limit of 60 requests per hour.
///
/// Set the `GITHUB_TOKEN` environment variable to raise the rate limit to
/// 5 000 requests per hour.
library;

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../constants.dart';
import '../domain/models.dart';
import 'cache.dart';

/// Wraps the GitHub API and converts raw JSON into [RepoHealth] objects.
class GitHubClient {
  /// Creates a [GitHubClient].
  ///
  /// - [client]: optional injectable HTTP client for testing.
  /// - [cache]: optional [DiskCache] for caching responses.
  /// - [timeout]: per-request timeout.
  GitHubClient(
      {http.Client? client,
      DiskCache? cache,
      Duration timeout = const Duration(seconds: 10)})
      : _http = client ?? http.Client(),
        _cache = cache,
        _timeout = timeout;

  final http.Client _http;
  final DiskCache? _cache;
  final Duration _timeout;

  /// Fetches [RepoHealth] for the GitHub repository at [repoUrl].
  ///
  /// Returns `null` when [repoUrl] is not a GitHub URL, when the request
  /// fails, or when the response cannot be parsed.
  Future<RepoHealth?> fetchRepoHealth(Uri repoUrl) async {
    final owner = _owner(repoUrl);
    final repo = _repo(repoUrl);
    if (owner == null || repo == null) return null;

    final cacheKey = 'gh:health:$owner/$repo';
    final hit = await _cache?.get(cacheKey);
    if (hit != null) return _parseHealth(hit);

    final results = await Future.wait([
      _get('/repos/$owner/$repo'),
      _get('/repos/$owner/$repo/commits?per_page=1'),
      _get('/repos/$owner/$repo/issues?state=closed&per_page=100&sort=updated'),
      _get('/repos/$owner/$repo/contributors?per_page=1&anon=false'),
    ]);

    final repoData = results[0];
    if (repoData == null) return null;

    final blob = {
      'repo': repoData,
      'commits': results[1],
      'closed_issues': results[2],
      'contributors': results[3],
    };

    await _cache?.set(cacheKey, blob, ttl: const Duration(hours: 12));
    return _parseHealth(blob);
  }

  /// Closes the underlying HTTP client.
  void dispose() => _http.close();

  Future<dynamic> _get(String path) async {
    final headers = <String, String>{
      'Accept': 'application/vnd.github+json',
      'X-GitHub-Api-Version': '2022-11-28',
    };
    final token = Platform.environment['GITHUB_TOKEN'];
    if (token != null) headers['Authorization'] = 'Bearer $token';

    try {
      final res = await _http
          .get(Uri.parse('${Urls.githubApi}$path'), headers: headers)
          .timeout(_timeout);

      if (res.statusCode == 200) return json.decode(res.body);
      if (res.statusCode == 403 || res.statusCode == 429) {
        stderr.writeln(
            '  [pub_doctor] GitHub rate limit hit. Set GITHUB_TOKEN for 5000 req/hr.');
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  RepoHealth? _parseHealth(Map<String, dynamic> blob) {
    try {
      final repo = blob['repo'] as Map<String, dynamic>?;
      if (repo == null) return null;

      DateTime? lastCommit;
      final commits = blob['commits'];
      if (commits is List && commits.isNotEmpty) {
        final dateStr =
            commits.first['commit']?['committer']?['date'] as String?;
        if (dateStr != null) lastCommit = DateTime.tryParse(dateStr);
      }

      double? avgCloseDays;
      final closed = blob['closed_issues'];
      if (closed is List && closed.isNotEmpty) {
        var totalDays = 0.0;
        var counted = 0;
        for (final issue in closed) {
          if (issue is! Map) continue;
          if (issue.containsKey('pull_request')) continue;
          final createdStr = issue['created_at'] as String?;
          final closedStr = issue['closed_at'] as String?;
          if (createdStr == null || closedStr == null) continue;
          final created = DateTime.tryParse(createdStr);
          final closedAt = DateTime.tryParse(closedStr);
          if (created == null || closedAt == null) continue;
          totalDays += closedAt.difference(created).inHours / 24.0;
          counted++;
        }
        if (counted > 0) avgCloseDays = totalDays / counted;
      }

      final contributors = blob['contributors'];
      final contributorCount =
          contributors is List ? contributors.length : null;

      final openIssues = repo['open_issues_count'] as int?;
      final closedCount = closed is List
          ? closed
              .where((i) => i is Map && !i.containsKey('pull_request'))
              .length
          : null;

      return RepoHealth(
        openIssues: openIssues,
        closedIssues: closedCount,
        stars: repo['stargazers_count'] as int?,
        forks: repo['forks_count'] as int?,
        contributors: contributorCount,
        avgIssueCloseTimeDays: avgCloseDays,
        lastCommitDate: lastCommit,
        isArchived: repo['archived'] as bool?,
        hasIssuesEnabled: repo['has_issues'] as bool?,
        defaultBranch: repo['default_branch'] as String?,
      );
    } catch (_) {
      return null;
    }
  }

  String? _owner(Uri url) {
    if (!url.host.contains('github.com')) return null;
    final segs = url.pathSegments.where((s) => s.isNotEmpty).toList();
    return segs.isNotEmpty ? segs[0] : null;
  }

  String? _repo(Uri url) {
    if (!url.host.contains('github.com')) return null;
    final segs = url.pathSegments.where((s) => s.isNotEmpty).toList();
    if (segs.length < 2) return null;
    return segs[1].replaceAll('.git', '');
  }
}
