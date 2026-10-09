/// Why a billing call failed, as a case a caller can switch on.
///
/// It exists so a screen never has to read `BillingException.message` to decide
/// what to show: a message is prose for a human, it differs per rail and per
/// locale, and a branch on its wording breaks the first time somebody rewords
/// it. The code is the stable half of the failure.
///
/// Client-side only: drivers assign it where they translate a rail's failure,
/// and it is never encoded to the wire. A driver may translate a producer's own
/// machine refusal code into one, matching that code as a literal at the throw
/// site (`product_not_sellable` is [productUnavailable]); the enum itself is
/// never decoded.
enum BillingErrorCode {
  /// The rail has no configuration in this build (a missing public SDK key).
  notConfigured,

  /// No paying account was identified to the rail before a purchase.
  notIdentified,

  /// The rail is bound to a different paying account than the one asking.
  identityMismatch,

  /// The subscription is managed on another rail, so this one must not touch
  /// it (a store subscription asked to change through the web, or the reverse).
  managedElsewhere,

  /// The account holds an active product the catalogue cannot name, so no
  /// change can be computed against it safely.
  unmappedActiveProduct,

  /// The rail has no product for the requested catalogue key, or the backend
  /// refuses to sell it.
  productUnavailable,

  /// The store accepted the purchase but has not settled it (parental approval,
  /// a deferred payment). Not a failure the customer has to retry.
  pending,

  /// The store receipt is already attributed to another paying account.
  receiptInUse,

  /// The customer already holds the product being bought.
  alreadyOwned,

  /// The request never reached the rail or its answer never came back.
  network,

  /// The store itself refused or failed, for a reason none of the cases above
  /// names.
  store,

  /// No cause was named: the default for a throw site that predates the codes.
  unknown,
}
