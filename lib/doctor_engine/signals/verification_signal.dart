import '../../constants.dart';
import '../../domain/models.dart';
import 'risk_signal.dart';

/// Checks whether the package comes from a verified publisher or has
/// Flutter Favourite status.
///
/// Unverified community packages carry inherent supply-chain risk: anyone can
/// publish under any name, and there is no vetting of the publisher's identity.
/// Verified publishers and Flutter Favourites have gone through additional
/// review processes on pub.dev.
///
/// Weight: 5.
class VerificationSignal extends RiskSignal {
  /// Creates a [VerificationSignal].
  const VerificationSignal();

  @override
  String get id => SignalIds.verification;

  @override
  double get weight => 5;

  @override
  SignalResult evaluate(PackageMetadata meta) {
    return switch (meta.verification) {
      PackageVerification.verifiedPublisherAndFlutterFavourite => SignalResult(
          signalId: id,
          risk: 0.0,
          reason:
              'Verified publisher (${meta.publisherDomain}) + Flutter Favourite',
        ),
      PackageVerification.verifiedPublisher => SignalResult(
          signalId: id,
          risk: 0.05,
          reason: 'Verified publisher: ${meta.publisherDomain}',
        ),
      PackageVerification.flutterFavourite => const SignalResult(
          signalId: SignalIds.verification,
          risk: 0.05,
          reason: 'Flutter Favourite',
        ),
      PackageVerification.none => const SignalResult(
          signalId: SignalIds.verification,
          risk: 0.5,
          reason: 'Unverified community package',
          detail:
              'No verified publisher badge. Review the source before trusting in production.',
        ),
    };
  }
}
