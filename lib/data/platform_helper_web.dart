String? getEnv(String name) => null;
void writeStderr(String message) {
  // no-op on web or print
  // ignore: avoid_print
  print(message);
}
