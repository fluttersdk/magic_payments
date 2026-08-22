import '../models/billing_checkout_session.dart';

/// Buying and managing a subscription on the WEB rail, where the vendor bills
/// the card itself through a hosted checkout and a hosted portal.
///
/// FOUR methods, and all four change what the customer is paying for. They are
/// separate from `BillingService`'s reads because a rail is not available
/// everywhere: this contract is resolved only in a build that can serve it, and
/// resolves to `null` elsewhere. That absence is the point. A caller asks whether
/// the web rail exists before it offers an upgrade button, instead of offering
/// one and catching a refusal, so a store build never renders an affordance it
/// cannot honour.
///
/// The mobile counterpart is `StoreBillingService`. Neither contract extends the
/// other and neither extends `BillingService`: one implementation may serve
/// several of them, and which ones it serves is exactly what a caller needs to
/// be able to ask.
///
/// ```dart
/// if (web != null) {
///   await web.checkout(
///     plan: 'pro',
///     successUrl: 'https://example.com/billing?checkout=success',
///     cancelUrl: 'https://example.com/billing?checkout=cancel',
///   );
/// }
/// ```
abstract class WebBillingService {
  /// Starts a hosted checkout session for [plan] and returns it.
  ///
  /// [plan] is the vendor's own plan identifier (e.g. `'pro'`), never a rail's
  /// price id: the price a plan maps to is the backend's business, and a client
  /// that named it would have to be re-released to change a price.
  /// [successUrl] and [cancelUrl] are the pages the hosted checkout returns to
  /// on completion and on abort.
  Future<BillingCheckoutSession> checkout({
    required String plan,
    required String successUrl,
    required String cancelUrl,
  });

  /// Moves the subscription to [plan], up or down, on the existing card.
  ///
  /// The rail prorates; this call does not ask which direction the move is,
  /// because the answer changes nothing about the request.
  Future<void> swap({required String plan});

  /// Cancels the subscription.
  ///
  /// A cancellation on this rail is normally end-of-period rather than
  /// immediate, so the entitlement it leaves behind still grants until
  /// `BillingEntitlement.currentPeriodEnd`. Re-read the entitlement rather than
  /// assuming this call revoked anything.
  Future<void> cancel();

  /// Opens the hosted billing portal and returns the URL it minted.
  ///
  /// [returnUrl] is the page the portal sends the customer back to. The URL is
  /// returned as well as opened because it is single-use and short-lived: a
  /// caller that wants to reopen the portal calls this again rather than keeping
  /// the URL.
  Future<String> openPortal({String? returnUrl});
}
