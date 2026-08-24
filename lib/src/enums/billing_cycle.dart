/// How often a subscription is charged.
///
/// It exists because a tier and a price are not the same thing. A vendor selling
/// `pro` at a monthly rate and again at a discounted annual rate has ONE tier and
/// TWO prices, and every part of the purchase path has to agree which of the two
/// is in play: the catalogue shows a figure, the checkout charges one, and the
/// renewal line names one. When the cycle travels nowhere, those three answers
/// come from three different places and disagree.
///
/// Both directions match on LITERALS rather than on `.name`, the same way
/// `ManageVia` and `BillingProvider` do. The two words happen to be identical to
/// the member names today, so `.name` would work and read shorter; it would also
/// be the only place in this package where adding a member silently changes the
/// wire. A future `semiAnnual` would encode as `semiAnnual` to a producer that
/// spells it `semi_annual`, `fromWire` would round-trip it happily, and the enum
/// test would stay green while the request 422s. The literals cost four lines
/// and cannot do that.
enum BillingCycle {
  /// Charged every month, at the tier's full rate.
  monthly,

  /// Charged every year, at the tier's discounted effective-per-month rate.
  annual;

  /// The word to send on the wire.
  String toWire() {
    return switch (this) {
      BillingCycle.monthly => 'monthly',
      BillingCycle.annual => 'annual',
    };
  }

  /// Decodes a `cycle` wire value, answering `null` for an absent or
  /// unrecognised one.
  ///
  /// **There is no fallback member, deliberately.** Every other vocabulary here
  /// degrades to a `none` case, because "no rail has said" is a state those
  /// vocabularies can express. A cycle cannot: monthly and annual are the only
  /// two answers, and picking either one for an unknown value is a claim about
  /// what a customer is being charged. That claim is the defect this type was
  /// added to fix, where a screen said "billed annually" to every paying
  /// customer because the cycle was a hardcoded literal. `null` means the cycle
  /// is unknown and a caller has to say so, or say nothing.
  static BillingCycle? fromWire(String? raw) {
    return switch (raw) {
      'monthly' => BillingCycle.monthly,
      'annual' => BillingCycle.annual,
      _ => null,
    };
  }
}
