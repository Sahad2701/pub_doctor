/// Web-safe and WASM-safe exports — no `dart:io` imports.
///
/// Use this library when targeting the browser or compiling with `dart2wasm`.
/// For the full CLI experience (scanning, caching, network), import
/// `package:pub_doctor/pub_doctor.dart` instead.
library;

export 'constants.dart';
export 'doctor_engine/scorer.dart';
export 'doctor_engine/signals.dart';
export 'domain/models.dart';
