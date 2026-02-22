# pub_doctor

[![pub version](https://img.shields.io/pub/v/pub_doctor.svg)](https://pub.dev/packages/pub_doctor)
[![CI](https://github.com/Sahad2701/pub_doctor/actions/workflows/ci.yml/badge.svg)](https://github.com/Sahad2701/pub_doctor/actions)
[![license: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

A fast dependency health analyzer for Dart and Flutter projects.

**pub_doctor** scans your `pubspec.yaml`, analyzes dependency metadata, and detects risky or poorly maintained packages before they cause build failures or compatibility issues.

It helps you maintain stable builds, enforce dependency health, and make safer upgrade decisions locally and in CI.

---

# Overview

Managing dependencies in Dart and Flutter projects becomes difficult over time:

* packages stop being maintained
* versions become outdated
* updates introduce breaking changes
* security or stability risks go unnoticed

pub_doctor analyzes dependency ecosystem signals and generates a **risk score** for each package so you can detect problems early.

No project source code is analyzed only public package metadata.

---

# Features

* Dependency risk scoring
* Maintenance activity analysis
* Version freshness detection
* Update availability detection
* CI automation support
* Fast and lightweight execution
* Offline support with caching
* Machine-readable JSON output
* No code analysis

---

# What pub_doctor Checks

* Package maintenance activity
* Version freshness
* Ecosystem risk signals
* Update availability
* Overall dependency risk score

pub_doctor evaluates dependency health using public package and repository signals.

---

# Installation

## Global installation (recommended)

```bash
dart pub global activate pub_doctor
```

Then run:

```bash
pub_doctor
```

---

## Add to project (dev dependency)

```yaml
dev_dependencies:
  pub_doctor: ^0.0.1
```

Run with:

```bash
dart run pub_doctor
```

---

## Run without installing

```bash
dart run pub_doctor
```

---

# Quick Start

Run pub_doctor inside any Dart or Flutter project:

```bash
pub_doctor
```

This scans the `pubspec.yaml` in the current directory and analyzes all dependencies.

---

# Usage

## Basic commands

### Analyze dependencies

```bash
pub_doctor
```

Scans project dependencies and prints health results.

---

### Analyze including dev dependencies

```bash
pub_doctor --dev
```

---

### Output machine-readable JSON

```bash
pub_doctor --json
```

Useful for CI or automation.

---

### Enable CI mode

```bash
pub_doctor --ci
```

Fails with a non-zero exit code when high-risk dependencies are detected.

---

### Auto-update safe dependencies (New)

```bash
pub_doctor update
```

Automatically resolves and upgrades all your packages in `pubspec.yaml` to their highest mutually compatible versions to fix inter-compatibility conflicts.

---

### Run using cached data only

```bash
pub_doctor --offline
```

No network requests.

---

### Show detailed output

```bash
pub_doctor --verbose
```

Shows all scoring signals.

---

### Show help

```bash
pub_doctor --help
```

---

# Example Output

```
$ pub_doctor

Analyzing dependencies...

✓ http
Risk Score: 2.1 (Healthy)
Latest: 1.2.0
Status: Actively maintained

⚠ some_old_package
Risk Score: 8.4 (High Risk)
Latest: 0.9.0
No commits for 412 days — maintenance appears inactive

Overall Project Risk Score: 5.3 (Moderate)
```

---

# Risk Scoring

Each dependency receives a risk score from **0 → 10**.

| Score | Level         |
| ----- | ------------- |
| 0–3   | Healthy       |
| 4–6   | Moderate Risk |
| 7–10  | High Risk     |

## Signals used

* Time since last release
* Repository commit activity
* Version lag from latest
* Ecosystem maintenance indicators
* Update frequency

The score is heuristic and explainable.
It helps guide decisions not replace engineering judgment.

---

# CI Integration (Recommended)

pub_doctor can run automatically in CI pipelines and fail builds when risky dependencies are detected.

This ensures dependency health enforcement across teams.

---

## GitHub Actions Example

```yaml
name: Dependency Health Check

on: [push, pull_request]

jobs:
  pub_doctor:
    runs-on: ubuntu-latest

    steps:
      - uses: actions/checkout@v4
      - uses: dart-lang/setup-dart@v1

      - run: dart pub global activate pub_doctor
      - run: pub_doctor --ci
```

---

## CI Exit Codes

| Exit Code | Meaning                         |
| --------- | ------------------------------- |
| 0         | All dependencies healthy        |
| 1         | High risk dependencies detected |
| 2         | Analysis error                  |

---

# Typical Workflow

## During local development

```bash
pub_doctor
```

Check dependency health before committing.

---

## Before upgrading dependencies

```bash
flutter pub upgrade
pub_doctor
```

Detect risks introduced by upgrades.

---

## Continuous Integration

Run pub_doctor automatically to prevent risky dependencies from reaching production.

---

# Performance

* Fast analysis (usually < 2 seconds)
* Cached results for repeated runs
* Minimal network usage
* Parallel dependency checks
* Works locally and in CI environments

---

# Caching

To improve performance:

* Dependency metadata is cached locally
* Cache expires automatically
* `--offline` uses cached results only

---

# Privacy & Security

* No source code is uploaded
* Only public dependency metadata is analyzed
* No tracking or telemetry
* Safe for private projects

---

# Limitations

* Only public package metadata is analyzed
* Transitive dependency scanning is limited
* Private repositories may provide limited signals
* Risk score is heuristic and not a guarantee of quality

---

# When Should You Use pub_doctor?

Use pub_doctor if you want:

* Stable builds
* Early dependency risk detection
* Safer upgrades
* Automated dependency health checks
* CI dependency enforcement
* Better long-term project stability


