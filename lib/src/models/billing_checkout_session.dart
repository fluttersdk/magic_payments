import 'package:flutter/foundation.dart';

/// A newly created hosted checkout session, as returned by the checkout
/// endpoint.
///
/// The session id is worth carrying alongside the URL even though only the URL
/// is opened: it is the handle that reconciles what the customer did in the
/// hosted page with the webhook that reports it.
@immutable
class BillingCheckoutSession {
  /// Creates a [BillingCheckoutSession] for [checkoutUrl] and [sessionId].
  const BillingCheckoutSession({
    required this.checkoutUrl,
    required this.sessionId,
  });

  /// The rail-hosted checkout page URL to open in an in-app browser tab.
  final String checkoutUrl;

  /// The checkout session id, for reconciliation with the webhook.
  final String sessionId;

  /// Decodes a [BillingCheckoutSession] from the raw checkout response body.
  ///
  /// An absent field decodes to an empty string rather than throwing, so a
  /// malformed response is a session a caller can refuse to open instead of an
  /// exception out of a decode path.
  factory BillingCheckoutSession.fromMap(Map<String, dynamic> map) {
    return BillingCheckoutSession(
      checkoutUrl: (map['checkout_url'] as String?) ?? '',
      sessionId: (map['session_id'] as String?) ?? '',
    );
  }
}
