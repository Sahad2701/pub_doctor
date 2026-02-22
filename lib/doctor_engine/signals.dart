/// Barrel file — re-exports every concrete [RiskSignal] implementation.
///
/// Import this file to access all signals in one go, typically only needed
/// inside `doctor_engine/scorer.dart`. External consumers should rely on the
/// top-level `package:pub_doctor/pub_doctor.dart` library instead.
library;

export 'signals/issue_response_signal.dart';
export 'signals/maintenance_signal.dart';
export 'signals/null_safety_signal.dart';
export 'signals/open_issues_signal.dart';
export 'signals/pub_score_signal.dart';
export 'signals/release_frequency_signal.dart';
export 'signals/repo_availability_signal.dart';
export 'signals/risk_signal.dart';
export 'signals/sdk_compat_signal.dart';
export 'signals/verification_signal.dart';
export 'signals/version_freshness_signal.dart';
