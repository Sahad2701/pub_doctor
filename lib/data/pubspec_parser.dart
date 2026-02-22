import 'dart:io';

import 'package:pub_semver/pub_semver.dart';
import 'package:yaml/yaml.dart';

/// The result of parsing a `pubspec.yaml` file.
///
/// Holds the resolved versions for both regular and dev dependencies as read
/// from the accompanying `pubspec.lock`. When no lock file exists, versions
/// are approximated from the version constraint strings in `pubspec.yaml`.
class PubspecInfo {
  /// Creates a [PubspecInfo].
  const PubspecInfo({
    required this.name,
    required this.dependencies,
    required this.devDependencies,
    required this.sdkConstraint,
    required this.path,
  });

  /// The package name declared in `pubspec.yaml`.
  final String name;

  /// Resolved versions for `dependencies`, keyed by package name.
  final Map<String, Version> dependencies;

  /// Resolved versions for `dev_dependencies`, keyed by package name.
  final Map<String, Version> devDependencies;

  /// The `environment.sdk` constraint, if declared.
  final VersionConstraint? sdkConstraint;

  /// Absolute or relative path to the `pubspec.yaml` file that was parsed.
  final String path;

  /// Combined map of [dependencies] and [devDependencies].
  Map<String, Version> get all => {...dependencies, ...devDependencies};
}

/// Parses a `pubspec.yaml` file and resolves dependency versions from the
/// adjacent `pubspec.lock`.
///
/// Lock-file resolution is preferred over raw constraint strings because it
/// captures the exact version that will be used in a `dart pub get`, making
/// risk scoring accurate for the installed dependency tree.
class PubspecParser {
  /// Parses the `pubspec.yaml` at [filePath] and returns a [PubspecInfo].
  ///
  /// Throws a [FileSystemException] when the file does not exist.
  Future<PubspecInfo> parse(String filePath) async {
    final file = File(filePath);
    if (!file.existsSync()) throw FileSystemException('not found', filePath);

    final yaml = loadYaml(await file.readAsString()) as YamlMap;
    final name = yaml['name'] as String? ?? 'unknown';

    final lockPath = filePath.replaceFirst('pubspec.yaml', 'pubspec.lock');
    final locked = await _readLock(lockPath);

    final deps = _block(yaml['dependencies'], locked);
    final devDeps = _block(yaml['dev_dependencies'], locked);

    VersionConstraint? sdk;
    final env = yaml['environment'];
    if (env is YamlMap) {
      try {
        sdk = VersionConstraint.parse(env['sdk'] as String? ?? '');
      } catch (_) {}
    }

    return PubspecInfo(
      name: name,
      dependencies: deps,
      devDependencies: devDeps,
      sdkConstraint: sdk,
      path: filePath,
    );
  }

  Map<String, Version> _block(dynamic raw, Map<String, Version> locked) {
    if (raw is! YamlMap) return {};
    final out = <String, Version>{};
    for (final entry in raw.entries) {
      final name = entry.key as String;
      if (name == 'flutter' || name == 'flutter_test') continue;
      if (locked.containsKey(name)) {
        out[name] = locked[name]!;
        continue;
      }
      final v = _versionFrom(entry.value);
      if (v != null) out[name] = v;
    }
    return out;
  }

  Version? _versionFrom(dynamic val) {
    if (val == null || val == 'any') return Version(0, 0, 0);
    if (val is String) {
      final cleaned =
          val.replaceAll(RegExp(r'[^0-9.]'), '').split(' ').first.trim();
      try {
        return Version.parse(cleaned);
      } catch (_) {}
    }
    return null;
  }

  Future<Map<String, Version>> _readLock(String path) async {
    final file = File(path);
    if (!file.existsSync()) return {};
    try {
      final yaml = loadYaml(await file.readAsString()) as YamlMap?;
      final pkgs = yaml?['packages'] as YamlMap?;
      if (pkgs == null) return {};
      final out = <String, Version>{};
      for (final e in pkgs.entries) {
        final vStr = (e.value as YamlMap?)?['version'] as String?;
        if (vStr != null) {
          try {
            out[e.key as String] = Version.parse(vStr);
          } catch (_) {}
        }
      }
      return out;
    } catch (_) {
      return {};
    }
  }
}
