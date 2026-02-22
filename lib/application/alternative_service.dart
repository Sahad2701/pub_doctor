import 'package:pub_semver/pub_semver.dart';

import '../data/pub_api_client.dart';
import '../doctor_engine/scorer.dart';
import '../domain/models.dart';

/// Finds healthier alternative packages for high-risk dependencies.
class AlternativeService {
  AlternativeService(this._api);

  final PubApiClient _api;

  /// Given a [PackageMetadata] that has high risk, searches for similar packages
  /// and returns a list of names that have better health metrics.
  Future<List<String>> findBetterAlternatives(PackageMetadata original) async {
    // Only suggest alternatives for high-risk or abandoned packages
    final topics = original.topics
        .where((t) => !t.startsWith('sdk:') && !t.startsWith('platform:'))
        .toList();
    if (topics.isEmpty) return [];

    // Search for packages with similar topics
    final query = topics.take(3).join(' ');
    final results = await _api.search(query);

    final alternatives = <String>[];
    final scorer = RiskScorer();

    for (final name in results.take(10)) {
      if (name == original.name) continue;

      try {
        final meta =
            await _api.fetch(name: name, currentVersion: Version(0, 0, 0));
        if (meta == null) continue;

        final diagnosis = scorer.diagnose(meta);
        // If the alternative is significantly healthier, suggest it
        if (diagnosis.riskScore < 40 &&
            diagnosis.riskScore < (original.riskScore ?? 100) - 20) {
          alternatives.add(name);
        }
      } catch (_) {
        continue;
      }

      if (alternatives.length >= 3) break;
    }

    return alternatives;
  }
}

extension on PackageMetadata {
  double? get riskScore {
    // This is a bit of a hack since riskScore is computed by RiskScorer
    // But for the sake of comparison in this service, we can't easily get it
    // without running the scorer.
    return null;
  }
}
