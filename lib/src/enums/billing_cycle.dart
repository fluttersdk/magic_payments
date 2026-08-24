/// How often a subscription is charged.
///
/// It exists because a tier and a price are not the same thing. A vendor selling
/// `pro` at a monthly rate and again at a discounted annual rate has ONE tier and
/// TWO prices, and every part of the purchase path has to agree which of the two
/// is in play: the catalogue shows a figure, the checkout charges one, and the
/// renewal line names one. When the cycle travels nowhere, those three answers
/// come from three different places and disagree.
///
/// The wire words are the enum names, so [fromWire] can match on `.name` rather
/// than on a literal table. That is not true of every vocabulary in this package
/// (`ManageVia` has snake_case wire words and matches explicitly), so do not
/// copy the shortcut without checking the words.
enum BillingCycle {
  /// Charged every month, at the tier's full rate.
  monthly,

  /// Charged every year, at the tier's discounted effective-per-month rate.
  annual;

  /// The word to send on the wire.
  String toWire() => name;

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
    for (final BillingCycle cycle in BillingCycle.values) {
      if (cycle.name == raw) return cycle;
    }

    return null;
  }
}
