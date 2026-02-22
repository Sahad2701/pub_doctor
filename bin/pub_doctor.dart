/// Entry point for the `pub_doctor` CLI.
///
/// Registers the `scan` and `cache` sub-commands and dispatches to them.
/// By default, bare flags (e.g. `pub_doctor --fresh`) are interpreted as
/// arguments to `scan`, so `pub_doctor` with no command still works.
library;

import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:pub_doctor/application/update_service.dart';
import 'package:pub_doctor/pub_doctor.dart';

void main(List<String> args) async {
  final runner = CommandRunner<void>(
      'pub_doctor', 'Dependency health diagnostics for Dart & Flutter.')
    ..addCommand(_ScanCommand())
    ..addCommand(_CacheCommand())
    ..addCommand(_UpdateCommand());

  // Allow `pub_doctor --fresh` as shorthand for `pub_doctor scan --fresh`.
  final effectiveArgs =
      (args.isEmpty || (args.isNotEmpty && args.first.startsWith('-')))
          ? ['scan', ...args]
          : args;

  try {
    await runner.run(effectiveArgs);
  } on UsageException catch (e) {
    stderr.writeln(e.message);
    exit(64);
  } catch (e, st) {
    stderr.writeln('pub_doctor: $e');
    if (Platform.environment['PUB_DOCTOR_DEBUG'] != null) stderr.writeln(st);
    exit(1);
  }
}

/// Scans a `pubspec.yaml` and prints a health report for each dependency.
class _ScanCommand extends Command<void> {
  _ScanCommand() {
    argParser
      ..addOption('pubspec',
          abbr: 'p', help: 'Path to pubspec.yaml', defaultsTo: 'pubspec.yaml')
      ..addFlag('dev',
          abbr: 'd', help: 'Include dev_dependencies', negatable: false)
      ..addFlag('fresh',
          abbr: 'f', help: 'Skip cache, fetch fresh data', negatable: false)
      ..addFlag('offline', help: 'Use cached data only', negatable: false)
      ..addFlag('verbose',
          abbr: 'v', help: 'Show full signal details', negatable: false)
      ..addOption('concurrency',
          abbr: 'c', help: 'Max concurrent requests', defaultsTo: '8');
  }

  @override
  String get name => 'scan';
  @override
  String get description => 'Scan pubspec.yaml and report dependency health.';

  @override
  Future<void> run() async {
    final args = argResults!;
    final opts = ScanOptions(
      includeDev: args['dev'] as bool,
      fresh: args['fresh'] as bool,
      offline: args['offline'] as bool,
      verbose: args['verbose'] as bool,
      concurrency: int.tryParse(args['concurrency'] as String) ?? 8,
    );

    final service = ScanService();
    try {
      final diagnosis = await service.scan(args['pubspec'] as String, opts);
      CliReporter(verbose: opts.verbose).printProject(diagnosis);
      if (diagnosis.criticalCount > 0 || diagnosis.riskyCount > 0) exit(1);
    } on FileSystemException catch (e) {
      stderr.writeln('error: ${e.message} (${e.path})');
      exit(1);
    } finally {
      service.dispose();
    }
  }
}

/// Parent command for local cache management sub-commands.
class _CacheCommand extends Command<void> {
  _CacheCommand() {
    addSubcommand(_CacheClearCmd());
    addSubcommand(_CacheStatsCmd());
  }

  @override
  String get name => 'cache';
  @override
  String get description =>
      'Manage the local metadata cache (~/.pub_doctor/cache/).';

  @override
  Future<void> run() async => printUsage();
}

/// Deletes all cached metadata entries.
class _CacheClearCmd extends Command<void> {
  @override
  String get name => 'clear';
  @override
  String get description => 'Delete all cached data.';

  @override
  Future<void> run() async {
    await DiskCache().clearAll();
    stdout.writeln('cache cleared.');
  }
}

/// Prints the number of cached entries and their total size on disk.
class _CacheStatsCmd extends Command<void> {
  @override
  String get name => 'stats';
  @override
  String get description => 'Show cache size.';

  @override
  Future<void> run() async {
    final s = await DiskCache().stats();
    stdout.writeln(
        '${s.entries} entries  ·  ${(s.bytes / 1024).toStringAsFixed(1)} KB');
  }
}

/// Automatically resolves and updates dependencies to their highest mutually compatible versions.
class _UpdateCommand extends Command<void> {
  _UpdateCommand() {
    argParser.addOption(
      'pubspec',
      abbr: 'p',
      help: 'Path to pubspec.yaml',
      defaultsTo: 'pubspec.yaml',
    );
  }

  @override
  String get name => 'update';
  @override
  String get description =>
      'Auto-resolve and update dependencies for maximum inter-compatibility.';

  @override
  Future<void> run() async {
    final args = argResults!;
    final pubspecPath = args['pubspec'] as String;

    final service = UpdateService();
    try {
      await service.update(pubspecPath);
    } on FileSystemException catch (e) {
      stderr.writeln('error: ${e.message} (${e.path})');
      exit(1);
    } catch (e) {
      stderr.writeln('pub_doctor update error: $e');
      exit(1);
    }
  }
}
