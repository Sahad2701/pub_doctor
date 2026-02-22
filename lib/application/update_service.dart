import 'dart:convert';
import 'dart:io';

/// Automated service to update `pubspec.yaml` to the highest mutually compatible versions.
class UpdateService {
  /// Resolves the latest highest compatible versions and rewrites `pubspec.yaml`.
  Future<void> update(String pubspecPath) async {
    final pubspecFile = File(pubspecPath);
    if (!await pubspecFile.exists()) {
      throw FileSystemException('pubspec.yaml not found', pubspecPath);
    }

    stdout.writeln('🔍 Resolving maximum mutually compatible versions...');
    final result = await Process.run(
      'dart',
      [
        'pub',
        'outdated',
        '--json',
        '--no-dev-dependencies',
        '--no-dependency-overrides'
      ],
      runInShell: true,
    );

    if (result.exitCode != 0 && result.exitCode != 1) {
      throw Exception('Failed to resolve dependencies: ${result.stderr}');
    }

    final data = jsonDecode(result.stdout as String) as Map<String, dynamic>;
    final packages = data['packages'] as List<dynamic>? ?? [];

    if (packages.isEmpty) {
      stdout.writeln(
          '✅ All dependencies are already mutually compatible and up-to-date!');
      return;
    }

    String pubspecContent = await pubspecFile.readAsString();
    int updatedCount = 0;

    stdout.writeln('\n📦 Upgrading dependencies:');
    for (final pkg in packages) {
      final name = pkg['package'] as String;
      final currentDetails = pkg['current'] as Map<String, dynamic>?;
      final resolvableDetails = pkg['resolvable'] as Map<String, dynamic>?;

      if (currentDetails == null || resolvableDetails == null) continue;

      final currentVersion = currentDetails['version'] as String?;
      final resolvableVersion = resolvableDetails['version'] as String?;

      if (currentVersion != null &&
          resolvableVersion != null &&
          currentVersion != resolvableVersion) {
        // Find the specific dependency constraint in pubspec.yaml and replace it.
        // This regex looks for `package_name: ^currentVersion` or `package_name: currentVersion`
        // We capture any preceding spaces and the colon structure to preserve formatting.
        final regex = RegExp('(^\\s*$name:\\s*)[\\^>=<]*$currentVersion\\s*\$',
            multiLine: true);

        if (regex.hasMatch(pubspecContent)) {
          pubspecContent = pubspecContent.replaceFirstMapped(
            regex,
            (match) => '${match.group(1)}^$resolvableVersion',
          );
          stdout.writeln('   ↑ $name: $currentVersion -> $resolvableVersion');
          updatedCount++;
        }
      }
    }

    if (updatedCount > 0) {
      await pubspecFile.writeAsString(pubspecContent);
      stdout.writeln('\n💾 Writing updates to $pubspecPath...');

      stdout.writeln('🔄 Running dart pub get...');
      final pubGetResult =
          await Process.run('dart', ['pub', 'get'], runInShell: true);

      if (pubGetResult.exitCode == 0) {
        stdout.writeln('✅ Successfully updated $updatedCount packages!');
      } else {
        stdout.writeln('❌ Failed to resolve package tree during dart pub get.');
        stdout.writeln(pubGetResult.stderr);
      }
    } else {
      stdout.writeln(
          '✅ All dependencies are already mutually compatible and up-to-date!');
    }
  }
}
