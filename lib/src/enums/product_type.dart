/// What kind of thing a catalogue product sells.
///
/// A catalogue row in `BillingService.getPlans()` names its product by key and
/// by this type, and the type decides what a purchase of it leaves behind: a
/// subscription renews, a consumable tops up a balance, a non-consumable is
/// owned for good, and a physical product ships. Only a subscription has a
/// cycle, so only a subscription row's key carries one (`pro_monthly`).
///
/// Both directions match on LITERALS rather than on `.name`, and here it is not
/// a precaution: `nonConsumable` is spelled `non_consumable` on the wire, so a
/// `.name` encoder would send a word the producer rejects.
enum ProductType {
  /// A recurring charge that renews until cancelled.
  subscription,

  /// A one-off purchase that is used up, topping up a balance.
  consumable,

  /// A one-off purchase the customer owns for good.
  nonConsumable,

  /// A product that ships. The stores forbid in-app purchase of physical
  /// goods, so only the web rail can sell one.
  physical;

  /// The word to send on the wire.
  String toWire() {
    return switch (this) {
      ProductType.subscription => 'subscription',
      ProductType.consumable => 'consumable',
      ProductType.nonConsumable => 'non_consumable',
      ProductType.physical => 'physical',
    };
  }

  /// Decodes a `type` wire value, answering `null` for an absent or
  /// unrecognised one.
  ///
  /// **There is no fallback member, deliberately**, for the reason
  /// `BillingCycle` has none. Any member chosen for an unknown word is a claim
  /// about what the customer bought: reading a new type as `subscription` would
  /// render a renewal line for something that never renews. `null` lets a
  /// caller skip the row instead of mis-describing it.
  static ProductType? fromWire(String? raw) {
    return switch (raw) {
      'subscription' => ProductType.subscription,
      'consumable' => ProductType.consumable,
      'non_consumable' => ProductType.nonConsumable,
      'physical' => ProductType.physical,
      _ => null,
    };
  }
}
