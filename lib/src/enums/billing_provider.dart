/// Which rail granted the entitlement the customer currently holds.
///
/// Mirrors the server's own `BillingProvider` enum case for case. The
/// vocabulary is deliberately neutral: several rails carry the same facts in
/// their own dialects, and a wire leaking one rail's words would force every
/// client to learn that dialect and relearn it when a second rail arrives. The
/// rail's own word survives in `BillingEntitlement.providerStatus`, which is
/// debug text and never a gate.
///
/// This enum answers "who is billing this customer", and nothing more. It says
/// nothing about WHEN a period ends or whether it renews (those are their own
/// fields), and nothing about where the subscription is managed: that is
/// `ManageVia`, which the server computes from this plus one existence check.
enum BillingProvider {
  /// Nobody is billing: a customer no rail has ever charged, and the landing
  /// place for a value this build does not know.
  none,

  /// The card rail, billed by the vendor directly.
  stripe,

  /// The two mobile stores, which bill on the vendor's behalf and keep
  /// management of the purchase inside their own account surface.
  appStore,
  playStore,

  /// Granted by an operator rather than sold: a comp, a migration, a support
  /// gesture. It entitles exactly like a paid rail and has no receipt.
  manual;

  /// Decodes the `provider` wire value into a [BillingProvider], falling back
  /// to [BillingProvider.none] on an absent or unrecognised value.
  ///
  /// The fallback is what lets a newer backend ship a sixth rail without
  /// crashing an older client. It lands on [BillingProvider.none] rather than
  /// on a real rail on purpose: reading an unknown provider as an existing one
  /// would have the client attribute a grant to a rail that never made it.
  ///
  /// The values are matched EXPLICITLY rather than against `.name`, because the
  /// wire words are snake_case (`app_store`) where Dart is camelCase, so a
  /// `.name` comparison would silently drop both store rails into the fallback.
  static BillingProvider fromWire(String? raw) {
    return switch (raw) {
      'none' => BillingProvider.none,
      'stripe' => BillingProvider.stripe,
      'app_store' => BillingProvider.appStore,
      'play_store' => BillingProvider.playStore,
      'manual' => BillingProvider.manual,
      _ => BillingProvider.none,
    };
  }
}
