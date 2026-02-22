import 'package:pub_doctor/pub_doctor.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:test/test.dart';

PackageMetadata pkg({
  String name = 'test_pkg',
  String current = '1.0.0',
  String? latest,
  String? latestStable,
  double? pubScore,
  bool? isNullSafe,
  bool? isDiscontinued,
  RepoHealth? repoHealth,
  List<Release> releases = const [],
  PackageVerification verification = PackageVerification.none,
  Uri? repoUrl,
}) =>
    PackageMetadata(
      name: name,
      currentVersion: Version.parse(current),
      latestVersion: latest != null ? Version.parse(latest) : null,
      latestStableVersion:
          latestStable != null ? Version.parse(latestStable) : null,
      pubScore: pubScore,
      isNullSafe: isNullSafe,
      isDiscontinued: isDiscontinued,
      repoHealth: repoHealth,
      releases: releases,
      verification: verification,
      repositoryUrl: repoUrl,
    );

void main() {
  group('MaintenanceSignal', () {
    const s = MaintenanceSignal();

    test('0.0 for commit within 90 days', () {
      final r = s.evaluate(pkg(
          repoHealth: RepoHealth(
              lastCommitDate:
                  DateTime.now().subtract(const Duration(days: 45)))));
      expect(r.risk, 0.0);
    });

    test('0.3 for 91–180 days', () {
      final r = s.evaluate(pkg(
          repoHealth: RepoHealth(
              lastCommitDate:
                  DateTime.now().subtract(const Duration(days: 130)))));
      expect(r.risk, 0.3);
    });

    test('0.6 for 181–365 days', () {
      final r = s.evaluate(pkg(
          repoHealth: RepoHealth(
              lastCommitDate:
                  DateTime.now().subtract(const Duration(days: 280)))));
      expect(r.risk, 0.6);
    });

    test('1.0 for > 365 days', () {
      final r = s.evaluate(pkg(
          repoHealth: RepoHealth(
              lastCommitDate:
                  DateTime.now().subtract(const Duration(days: 400)))));
      expect(r.risk, 1.0);
    });

    test('1.0 for discontinued regardless of commit date', () {
      final r = s.evaluate(pkg(
        isDiscontinued: true,
        repoHealth: RepoHealth(lastCommitDate: DateTime.now()),
      ));
      expect(r.risk, 1.0);
    });

    test('0.6 when repo url is null', () {
      final r = s.evaluate(pkg());
      expect(r.risk, 0.6);
    });
  });

  group('VersionFreshnessSignal', () {
    const s = VersionFreshnessSignal();

    test('0.0 when current == latest', () {
      expect(
          s.evaluate(pkg(current: '2.0.0', latestStable: '2.0.0')).risk, 0.0);
    });

    test('0.2 for patch behind', () {
      expect(
          s.evaluate(pkg(current: '2.0.0', latestStable: '2.0.5')).risk, 0.2);
    });

    test('0.5 for minor behind', () {
      expect(
          s.evaluate(pkg(current: '2.0.0', latestStable: '2.3.0')).risk, 0.5);
    });

    test('1.0 for major behind', () {
      expect(s.evaluate(pkg(latestStable: '3.0.0')).risk, 1.0);
    });

    test('didFail when no latest', () {
      expect(s.evaluate(pkg()).didFail, true);
    });
  });

  group('NullSafetySignal', () {
    const s = NullSafetySignal();

    test('0.0 for null safe', () {
      expect(s.evaluate(pkg(isNullSafe: true)).risk, 0.0);
    });

    test('1.0 for non-null-safe', () {
      expect(s.evaluate(pkg(isNullSafe: false)).risk, 1.0);
    });
  });

  group('OpenIssuesSignal', () {
    const s = OpenIssuesSignal();

    test('low risk with few open issues and high resolution', () {
      final r = s.evaluate(
          pkg(repoHealth: const RepoHealth(openIssues: 5, closedIssues: 200)));
      expect(r.risk, lessThan(0.3));
    });

    test('high risk with many open issues and low resolution', () {
      final r = s.evaluate(
          pkg(repoHealth: const RepoHealth(openIssues: 400, closedIssues: 10)));
      expect(r.risk, greaterThan(0.6));
    });

    test('didFail when no repo health', () {
      expect(s.evaluate(pkg()).didFail, true);
    });
  });

  group('IssueResponseSignal', () {
    const s = IssueResponseSignal();

    test('0.0 for fast response ≤7d', () {
      expect(
          s
              .evaluate(
                  pkg(repoHealth: const RepoHealth(avgIssueCloseTimeDays: 4)))
              .risk,
          0.0);
    });

    test('1.0 for > 180d avg', () {
      expect(
          s
              .evaluate(
                  pkg(repoHealth: const RepoHealth(avgIssueCloseTimeDays: 200)))
              .risk,
          1.0);
    });

    test('didFail when no data', () {
      expect(s.evaluate(pkg()).didFail, true);
    });
  });

  group('ReleaseFrequencySignal', () {
    const s = ReleaseFrequencySignal();
    final now = DateTime.now();

    test('0.0 for frequent releases', () {
      final releases = List.generate(
          6,
          (i) => Release(
              version: Version.parse('1.0.$i'),
              publishedAt: now.subtract(Duration(days: i * 20))));
      expect(s.evaluate(pkg(releases: releases)).risk, 0.0);
    });

    test('1.0 for very sparse releases', () {
      final releases = [
        Release(
            version: Version.parse('1.0.0'),
            publishedAt: now.subtract(const Duration(days: 900))),
        Release(version: Version.parse('1.1.0'), publishedAt: now),
      ];
      expect(s.evaluate(pkg(releases: releases)).risk, 1.0);
    });
  });

  group('VerificationSignal', () {
    const s = VerificationSignal();

    test('0.0 for verified + ff', () {
      expect(
          s
              .evaluate(pkg(
                  verification:
                      PackageVerification.verifiedPublisherAndFlutterFavourite))
              .risk,
          0.0);
    });

    test('0.5 for unverified', () {
      expect(s.evaluate(pkg()).risk, 0.5);
    });
  });

  group('RiskScorer', () {
    test('discontinued → high risk', () {
      // Discontinued + null-unsafe + low pub score pushes aggregate to Critical
      final result = RiskScorer().diagnose(pkg(
        isDiscontinued: true,
        isNullSafe: false,
        pubScore: 30,
      ));
      expect(result.riskLevel, anyOf(RiskLevel.critical, RiskLevel.risky));
    });

    test('fully healthy package scores ≤ 40', () {
      final now = DateTime.now();
      final releases = List.generate(
          5,
          (i) => Release(
              version: Version.parse('2.0.$i'),
              publishedAt: now.subtract(Duration(days: i * 25))));
      final meta = PackageMetadata(
        name: 'great_pkg',
        currentVersion: Version.parse('2.0.4'),
        latestVersion: Version.parse('2.0.4'),
        latestStableVersion: Version.parse('2.0.4'),
        pubScore: 100,
        pubPopularity: 95,
        isNullSafe: true,
        isDiscontinued: false,
        releases: releases,
        verification: PackageVerification.verifiedPublisher,
        publisherDomain: 'example.dev',
        repositoryUrl: Uri.parse('https://github.com/example/great_pkg'),
        repoHealth: RepoHealth(
          openIssues: 3,
          closedIssues: 150,
          avgIssueCloseTimeDays: 5,
          lastCommitDate: now.subtract(const Duration(days: 14)),
          stars: 2000,
          isArchived: false,
        ),
      );
      final result =
          RiskScorer(dartSdkVersion: Version.parse('3.3.0')).diagnose(meta);
      expect(result.riskScore, lessThanOrEqualTo(40));
    });

    test('score is always 0–100', () {
      final meta = pkg(isDiscontinued: true, isNullSafe: false, pubScore: 0);
      final result = RiskScorer().diagnose(meta);
      expect(result.riskScore, inInclusiveRange(0.0, 100.0));
    });
  });
}
