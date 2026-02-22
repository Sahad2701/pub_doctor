import 'dart:io';

String? getEnv(String name) => Platform.environment[name];
void writeStderr(String message) => stderr.writeln(message);
