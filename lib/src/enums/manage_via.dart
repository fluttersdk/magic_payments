/// Where the customer manages the subscription, as the server computed it.
///
/// It is a function of the RAIL rather than of the running platform: the two are
/// independent axes, and a subscription bought on an iPhone is still managed in
/// the App Store when the customer opens the web app. So a client branches its
/// management affordances on this, never on `kIsWeb` or `Platform.is`.
///
/// Deliberately dumb: it carries no pairing helper for
/// `BillingEntitlement.manageUrl`, because the pairing is a rendering decision.
/// A null `manageUrl` on a store rail must render a statement WITHOUT a link
/// rather than a dead button, and only the view knows how to say that.
///
/// [portal] is a surface rather than a URL because a Stripe portal session is
/// short-lived, single-use and carries a baked-in return URL; the client calls
/// the portal endpoint for it.
enum ManageVia {
  /// Nowhere to send the customer: no rail, an operator grant, an unknown rail,
  /// or Stripe without a customer record (whose portal endpoint cannot answer).
  /// Also the landing place for a value this build does not know.
  none,

  /// The vendor's own Stripe billing portal, reached through the portal
  /// endpoint.
  portal,

  /// The store's own account surface, whose destination arrives as
  /// `BillingEntitlement.manageUrl`.
  appStore,
  playStore;

  /// Decodes the `manage_via` wire value into a [ManageVia], falling back to
  /// [ManageVia.none] on an absent or unrecognised value.
  ///
  /// The fallback is what lets a newer backend name a fifth surface without
  /// crashing an older client, and [ManageVia.none] is the honest landing
  /// place: a client that cannot name the surface must not steer the customer at
  /// a guessed one, least of all past a store that forbids the steering.
  ///
  /// The values are matched EXPLICITLY rather than against `.name`, because the
  /// wire words are snake_case (`play_store`) where Dart is camelCase, so a
  /// `.name` comparison would silently drop both store surfaces into the
  /// fallback.
  static ManageVia fromWire(String? raw) {
    return switch (raw) {
      'none' => ManageVia.none,
      'portal' => ManageVia.portal,
      'app_store' => ManageVia.appStore,
      'play_store' => ManageVia.playStore,
      _ => ManageVia.none,
    };
  }
}
