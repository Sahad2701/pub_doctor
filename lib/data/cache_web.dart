class DiskCache {
  DiskCache({String? dir});
  Future<void> set(String key, Map<String, dynamic> data,
      {Duration ttl = const Duration(hours: 24)}) async {}
  Future<Map<String, dynamic>?> get(String key) async => null;
  Future<void> clearAll() async {}
  Future<({int entries, int bytes})> stats() async => (entries: 0, bytes: 0);
}
