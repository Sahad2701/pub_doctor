# Architecture

This document covers the internals of pub_doctor for anyone working on the codebase or building on top of it.

---

## Layers

```
┌───────────────────────────────────────┐
│  CLI  (bin/, lib/cli/)                │  argument parsing, terminal output
├───────────────────────────────────────┤
│  Application  (lib/application/)      │  orchestration, no business rules
├───────────────────────────────────────┤
│  Doctor Engine  (lib/doctor_engine/)  │  scoring, signal evaluation
├───────────────────────────────────────┤
│  Domain  (lib/domain/)                │  data classes only, no I/O
├───────────────────────────────────────┤
│  Data  (lib/data/)                    │  pub.dev API, GitHub API, cache, parser
└───────────────────────────────────────┘
```

Dependencies flow downward only. `doctor_engine` never touches `data`. `data` never touches `doctor_engine`. The `application` layer is the only place that imports from both sides.

---

## Scan pipeline

```
CLI args
  └─ ScanService.scan()
       ├─ PubspecParser.parse()          reads pubspec.yaml + pubspec.lock
       ├─ PubApiClient.fetchAll()        concurrent pub.dev fetches (gate: 8)
       ├─ GitHubClient.fetchRepoHealth() concurrent GitHub fetches (gate: 5)
       │     ├─ /repos/:owner/:repo          stars, forks, open_issues, archived
       │     ├─ /repos/:owner/:repo/commits  last commit date
       │     └─ /repos/:owner/:repo/issues   avg close time (last 100 closed)
       ├─ PubApiClient.probe()           HEAD check for packages with no GH data
       └─ DoctorEngine.diagnose()        per-package, synchronous
            └─ [Signal × 10].evaluate()
```

Everything up to `DoctorEngine.diagnose()` is async and I/O-bound. The engine itself is synchronous — it receives a fully-populated `PackageMetadata` and doesn't touch the network.

---

## Scoring formula

```
score = (Σ weight_i × risk_i) / (Σ weight_i of non-failed signals) × 100
```

`risk_i` ∈ [0, 1] for each signal.  
`score` ∈ [0, 100].  

Failed signals (network error, missing data) are excluded from both numerator and denominator. This means a flaky GitHub connection degrades signal coverage but doesn't inflate the score.

### Weight table (sums to 100)

| Signal | Weight |
|---|---|
| maintenance | 25 |
| version_freshness | 20 |
| pub_score | 10 |
| null_safety | 8 |
| release_frequency | 8 |
| sdk_compat | 7 |
| open_issues | 7 |
| issue_response | 5 |
| verification | 5 |
| repo_availability | 5 |

---

## Signal contract

Every signal is a class that extends `RiskSignal`:

```dart
abstract class RiskSignal {
  String get id;
  double get weight;
  SignalResult evaluate(PackageMetadata meta);
}
```

Rules signals must follow:
- Never throw. Catch internally, return `didFail: true`.
- Return `risk` strictly in [0, 1]. The engine asserts this.
- Be stateless. The same `PackageMetadata` should always produce the same `SignalResult`.
- No I/O. All data must be in `PackageMetadata` before `evaluate()` is called.

---

## Cache

Layout: `~/.pub_doctor/cache/<sha256(key)>.json`

Each entry:
```json
{
  "_exp": 1718000000000,
  "_v": 1,
  "_data": { ... }
}
```

`_v` is the schema version. On mismatch (e.g. after a pub_doctor upgrade that changes the blob shape), the entry is deleted and re-fetched. This prevents stale shape bugs without needing a migration.

TTLs:
- pub.dev data: 24h
- GitHub repo health: 12h
- Repository HEAD probe: 6h

Each entry is a separate file. A partial write (power loss mid-write) cannot corrupt other entries.

---

## Concurrency and rate limiting

### pub.dev
- Concurrency gate: 8 simultaneous requests (configurable via `--concurrency`)
- Retry: 3 attempts with exponential backoff (base 500ms, factor 1.5) + ±20% jitter
- 429 responses: backoff factor bumped to 4.0

### GitHub
- Concurrency gate: 5 simultaneous per-package fetches (hard-coded, not configurable)
- Three endpoints fetched concurrently per package within the gate
- Unauthenticated: 60 req/hr. `GITHUB_TOKEN` raises this to 5000 req/hr
- Total GitHub timeout: 30s. Partial results (packages that completed) are used.

### Repository probe (HEAD check)
- Only runs when a package has a repo URL but GitHub data couldn't be fetched
- Total timeout: 15s per scan. Partial results accepted.

---

## Open issues signal detail

The `open_issues` signal blends two sub-scores:

```
countRisk  = f(open issue count)   — absolute number, more = worse
rateRisk   = 1 - resolutionRate    — closed/(open+closed), lower = worse

risk = countRisk × 0.5 + rateRisk × 0.5
```

`countRisk` buckets:

| Open issues | countRisk |
|---|---|
| 0 | 0.0 |
| 1–10 | 0.1 |
| 11–30 | 0.3 |
| 31–100 | 0.5 |
| 101–300 | 0.7 |
| > 300 | 0.9 |

The blend means a package with 500 open issues but 97% resolution scores much better than one with 20 open issues and 10% resolution.

---

## Issue response time

We fetch the last 100 closed issues from `/repos/:owner/:repo/issues?state=closed&per_page=100` and compute the mean of `(closed_at - created_at)` in days. Pull requests are filtered out (they appear in the issues endpoint but have a `pull_request` key).

Risk curve:

| Avg close days | Risk |
|---|---|
| ≤ 7 | 0.0 |
| 8–30 | 0.2 |
| 31–90 | 0.5 |
| 91–180 | 0.75 |
| > 180 | 1.0 |

---

## Error handling policy

- No user-visible unhandled exceptions. All errors are caught, logged to stderr at debug level, and converted to partial results.
- Network errors during signal data collection → signal marked `didFail: true`, excluded from score.
- Network errors during pub.dev fetch → package excluded from results (can't score without base metadata).
- YAML parse errors → `FileSystemException` propagates to CLI layer, printed cleanly, `exit(1)`.
- Unexpected errors in signals → caught in `DoctorEngine._runAll()`, marked as failed.

---

## Exit codes

| Code | Meaning |
|---|---|
| 0 | All packages Healthy or Warning |
| 1 | One or more Critical or Risky packages |
| 1 | Scan failed (missing pubspec.yaml, malformed YAML) |
| 64 | Bad CLI arguments (EX_USAGE) |

---

## Roadmap

### v0.2.0
- GitLab support (`gitlab.com` host detection in `GitHubClient` → refactored to `VcsClient`)
- `.pub_doctor.yaml` config file: weight overrides, package ignore list, custom abandonment threshold
- Open PR count signal (separate `/pulls` endpoint)
- Accurate contributor count via `Link` header pagination

### v0.3.0
- OSV vulnerability feed integration (https://osv.dev/docs/)
- License risk signal (GPL/AGPL flag for commercial projects)
- `--format=json` output for tooling integration

### Future
- Transitive dependency graph analysis
- Flutter breaking change detection (cross-ref flutter/flutter)
- `pub_doctor fix` — auto-bump safe upgrades and open a PR
