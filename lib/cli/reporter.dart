/// Renders [ProjectDiagnosis] results to stdout using ANSI colour when the
/// terminal supports it.
///
/// All output is written to [stdout] so it can be piped or captured. Use
/// `verbose: true` to include per-signal detail lines in the output.
library;

import 'dart:io';

import '../domain/models.dart';

bool get _color => stdout.supportsAnsiEscapes;

String _r(String s) => _color ? '\x1B[31m$s\x1B[0m' : s;
String _y(String s) => _color ? '\x1B[33m$s\x1B[0m' : s;
String _g(String s) => _color ? '\x1B[32m$s\x1B[0m' : s;
String _c(String s) => _color ? '\x1B[36m$s\x1B[0m' : s;
String _b(String s) => _color ? '\x1B[1m$s\x1B[0m' : s;
String _d(String s) => _color ? '\x1B[2m$s\x1B[0m' : s;

/// Formats and prints a [ProjectDiagnosis] to the terminal.
class CliReporter {
  /// Creates a [CliReporter].
  ///
  /// Set [verbose] to `true` to include extended signal details and zero-risk
  /// signals in the output.
  const CliReporter({this.verbose = false});

  /// Whether to include full signal details and zero-risk signals.
  final bool verbose;

  /// Prints the full project diagnosis: header, summary, per-package details,
  /// and a footer with the overall verdict.
  void printProject(ProjectDiagnosis d) {
    _header(d);
    _summary(d);
    stdout.writeln();
    for (final r in d.results) {
      _package(r);
    }
    _footer(d);
  }

  void _header(ProjectDiagnosis d) {
    stdout.writeln();
    stdout.writeln(_b(r'''
                 __         __           __           
     ____  __  __/ /_  ____/ /___  _____/ /_____  _____
    / __ \/ / / / __ \/ __  / __ \/ ___/ __/ __ \/ ___/
   / /_/ / /_/ / /_/ / /_/ / /_/ / /__/ /_/ /_/ / /    
  / .___/\__,_/_.___/\__,_/\____/\___/\__/\____/_/     
 /_/                                                   

    > Dependency Health Diagnostics for Dart & Flutter
    '''));
    stdout.writeln(_d('  ${d.pubspecPath}'));
    if (d.dartSdkVersion != null) {
      stdout.writeln(_d('  Dart SDK ${d.dartSdkVersion}'));
    }
    stdout.writeln(_d('  ${_ts(d.scannedAt)}'));
    stdout.writeln();
    stdout.writeln(_d('─' * 68));
  }

  void _summary(ProjectDiagnosis d) {
    final parts = <String>[];
    if (d.criticalCount > 0) parts.add(_r('${d.criticalCount} critical'));
    if (d.riskyCount > 0) parts.add(_r('${d.riskyCount} risky'));
    if (d.warningCount > 0) parts.add(_y('${d.warningCount} warning'));
    if (d.healthyCount > 0) parts.add(_g('${d.healthyCount} healthy'));
    stdout.writeln('  ${d.totalPackages} packages  ·  ${parts.join('  ·  ')}');
    if (d.abandonedPackages.isNotEmpty) {
      final names = d.abandonedPackages.map((r) => r.packageName).join(', ');
      stdout.writeln(_r('  ⚠  possibly abandoned: $names'));
    }
  }

  void _package(DiagnosisResult r) {
    stdout.writeln(_d('─' * 68));

    final badge = _badge(r.verification);
    final cache = r.isFromCache ? _d(' [cache]') : '';
    final versionLine =
        r.latestVersion != null && r.latestVersion != r.currentVersion
            ? _d(' ${r.currentVersion} → ${r.latestVersion}')
            : _d(' ${r.currentVersion}');

    stdout.writeln(
        '  ${_b(r.packageName)}$versionLine$badge$cache  ${_score(r.riskScore, r.riskLevel)}');

    final health = r.repoHealth;
    if (health != null) {
      final parts = <String>[];
      if (health.stars != null) parts.add('★ ${_fmt(health.stars!)}');
      if (health.openIssues != null) {
        final rate = health.issueResolutionRate;
        final pct = rate != null
            ? ' (${(rate * 100).toStringAsFixed(0)}% resolved)'
            : '';
        parts.add('${health.openIssues} open issues$pct');
      }
      if (health.avgIssueCloseTimeDays != null) {
        parts.add(
            '~${health.avgIssueCloseTimeDays!.toStringAsFixed(0)}d avg close time');
      }
      if (health.contributors != null) {
        parts.add('${health.contributors} contributors');
      }
      if (health.isArchived == true) parts.add(_r('ARCHIVED'));
      if (parts.isNotEmpty) stdout.writeln(_d('    ↳ ${parts.join('  ·  ')}'));
    }

    final interesting =
        verbose ? r.signals : r.signals.where((s) => s.risk > 0.0).toList();

    if (interesting.isEmpty) {
      stdout.writeln(_g('    ✓ all signals healthy'));
    } else {
      for (final s in interesting) {
        final icon = s.didFail ? '?' : (s.risk >= 0.7 ? '!' : '·');
        final color = s.risk >= 0.7 ? _r : (s.risk >= 0.4 ? _y : _g);
        stdout.writeln('    ${color(icon)}  ${s.reason}');
        if (verbose && s.detail != null) {
          stdout.writeln(_d('         ${s.detail}'));
        }
      }
    }

    if (r.recommendations.isNotEmpty) {
      stdout.writeln();
      for (final rec in r.recommendations) {
        stdout.writeln('    → $rec');
      }
    }

    stdout.writeln();
  }

  void _footer(ProjectDiagnosis d) {
    stdout.writeln(_d('─' * 68));
    stdout.writeln();
    if (d.criticalCount > 0 || d.riskyCount > 0) {
      stdout.writeln(
          _r('  Action required — review critical/risky packages above.'));
    } else if (d.warningCount > 0) {
      stdout.writeln(
          _y('  Some packages need attention. No immediate blockers.'));
    } else {
      stdout.writeln(_g('  All clear.'));
    }

    // Suggest `pub_doctor update` if any packages are severely outdated.
    final outdatedCount = d.results
        .where((r) =>
            r.latestVersion != null && r.currentVersion < r.latestVersion!)
        .length;
    if (outdatedCount > 0) {
      stdout.writeln();
      stdout.writeln(_b(
          '  💡 Tip: $outdatedCount dependencies are outdated. Run `pub_doctor update` to safely auto-resolve them.'));
    }
    stdout.writeln();
  }

  String _score(double score, RiskLevel level) {
    final s = '${score.toStringAsFixed(0)}/100 ${level.label}';
    return switch (level) {
      RiskLevel.critical || RiskLevel.risky => _r('[$s]'),
      RiskLevel.warning => _y('[$s]'),
      RiskLevel.low => _c('[$s]'),
      RiskLevel.healthy => _g('[$s]'),
    };
  }

  String _badge(PackageVerification v) => switch (v) {
        PackageVerification.verifiedPublisherAndFlutterFavourite =>
          _c(' [✓ verified] [★ ff]'),
        PackageVerification.verifiedPublisher => _c(' [✓ verified]'),
        PackageVerification.flutterFavourite => _c(' [★ ff]'),
        PackageVerification.none => '',
      };

  String _ts(DateTime d) =>
      '${d.year}-${_p(d.month)}-${_p(d.day)} ${_p(d.hour)}:${_p(d.minute)}';

  String _p(int n) => n.toString().padLeft(2, '0');

  String _fmt(int n) => n >= 1000 ? '${(n / 1000).toStringAsFixed(1)}k' : '$n';
}
