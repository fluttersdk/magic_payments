/// When a store purchase that CHANGED a held subscription takes effect, as
/// `StoreBillingService.lastChangeTiming` reports it.
///
/// Client-side only, like `BillingErrorCode`: the store rail derives it from
/// the change it asked the store for, and it never crosses the wire. It exists
/// so a screen can tell the customer "your plan changes now" from "your plan
/// changes at renewal" without knowing either store's rules.
enum StoreChangeTiming {
  /// The new product is in force as soon as the store confirms the purchase
  /// (an upgrade, or a Play base-plan switch).
  immediate,

  /// The held product runs to the end of its period and the new one starts at
  /// the renewal (a downgrade, or an App Store move to another duration of the
  /// same level).
  atRenewal,
}
