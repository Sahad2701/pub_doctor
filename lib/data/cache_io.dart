import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

/// A simple key-value disk cache backed by individual JSON files.
///
/// Each entry occupies its own file, so a partial write or corruption can
/// never affect other cached values. File names are derived from the SHA-256
/// hash of the entry key, which keeps arbitrary key strings safe for the
/// filesystem.
///
/// Layout: `~/.pub_doctor/cache/<sha256>.json`
///
/// File content format:
/// ```json
/// { "_exp": <epoch_ms>, "_v": 1, "_data": { ... } }
/// ```
class DiskCache {
  /// Creates a [DiskCache] rooted at [dir].
  ///
  /// Defaults to `~/.pub_doctor/cache/` when [dir] is not specified.
  DiskCache({String? dir}) : _dir = dir ?? _defaultDir();

  final String _dir;

  // Increment this when the on-disk format changes in a breaking way.
  static const _schemaVersion = 1;

  static String _defaultDir() {
    final home = Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        Directory.current.path;
    return p.join(home, '.pub_doctor', 'cache');
  }

  /// Writes [data] under [key] with the given [ttl].
  ///
  /// Silently ignores I/O errors (e.g. disk full, permission denied) so that
  /// cache failures are never fatal to a scan.
  Future<void> set(String key, Map<String, dynamic> data,
      {Duration ttl = const Duration(hours: 24)}) async {
    final file = _file(key);
    try {
      await file.parent.create(recursive: true);
      await file.writeAsString(
        json.encode({
          '_exp': DateTime.now().add(ttl).millisecondsSinceEpoch,
          '_v': _schemaVersion,
          '_data': data,
        }),
        flush: true,
      );
    } catch (_) {
      // disk full, permissions — not fatal
    }
  }

  /// Retrieves the cached value for [key], or `null` if it is missing,
  /// expired, or written by an incompatible schema version.
  Future<Map<String, dynamic>?> get(String key) async {
    final file = _file(key);
    try {
      if (!await file.exists()) return null;
      final obj =
          json.decode(await file.readAsString()) as Map<String, dynamic>;
      if ((obj['_v'] as int?) != _schemaVersion) {
        await file.delete();
        return null;
      }
      final exp = obj['_exp'] as int?;
      if (exp == null || DateTime.now().millisecondsSinceEpoch > exp) {
        await file.delete();
        return null;
      }
      return obj['_data'] as Map<String, dynamic>?;
    } catch (_) {
      return null;
    }
  }

  /// Deletes all cached entries by removing the cache directory entirely.
  Future<void> clearAll() async {
    final dir = Directory(_dir);
    if (await dir.exists()) await dir.delete(recursive: true);
  }

  /// Returns the number of cached entries and their total size in bytes.
  Future<({int entries, int bytes})> stats() async {
    final dir = Directory(_dir);
    if (!await dir.exists()) return (entries: 0, bytes: 0);
    var count = 0;
    var bytes = 0;
    await for (final f in dir.list()) {
      if (f is File && f.path.endsWith('.json')) {
        count++;
        bytes += await f.length();
      }
    }
    return (entries: count, bytes: bytes);
  }

  File _file(String key) {
    final hash = sha256.convert(utf8.encode(key)).toString();
    return File(p.join(_dir, '$hash.json'));
  }
}
