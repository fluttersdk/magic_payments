/// Base exception for billing failures.
///
/// Thrown when a request against a billing endpoint fails (a non-2xx response)
/// or returns a malformed payload. Callers decide how to surface it, and the two
/// answers differ: a write action reports the failure and stays on the form,
/// while a read degrades to its last known state rather than blanking a screen
/// the customer is paying for.
class BillingException implements Exception {
  /// Creates a [BillingException] describing [message].
  const BillingException(this.message);

  /// A human-readable description of the failure.
  final String message;

  @override
  String toString() => 'BillingException: $message';
}

/// Thrown when the rail a call needs is not part of this build.
///
/// A [BillingException] subtype rather than a sibling, so a caller that only
/// wants "billing did not work" catches it for free and a caller that wants to
/// say something specific about the platform can catch it on its own.
///
/// It exists for a genuine absence, not for a missing implementation: reading an
/// entitlement is honourable on every platform, and the purchase and management
/// calls live on their own rail contracts precisely so that an unavailable rail
/// is a resolved `null` a caller can check rather than a method that throws.
/// What remains for this exception is a rail that is present but cannot serve
/// the running device: a store rail on a device with in-app purchase disabled,
/// or a build wired for one rail being asked for the other.
class UnsupportedPlatformException extends BillingException {
  /// Creates an [UnsupportedPlatformException] describing [message].
  const UnsupportedPlatformException(super.message);

  @override
  String toString() => 'UnsupportedPlatformException: $message';
}
