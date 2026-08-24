/// Where a paid plan stands in its lifecycle, in rail-neutral words.
///
/// Mirrors the server's own `PlanStatus` enum case for case. The eight cases are
/// the union of the FACTS the payment rails report, not of the words they use
/// for them: each rail's own status word maps into one of these server-side and
/// survives verbatim in `BillingEntitlement.providerStatus`, so no client has to
/// know which rail sold the plan in order to render its state.
///
/// [paused] is reachable from more than one rail: Google Play has an explicit
/// pause primitive, and Stripe reports `paused` too (`STATUS_PAUSED` on its
/// `Subscription`). A rail without the concept simply never sends the case,
/// whereas adding it later would be a wire break for every client already
/// decoding this vocabulary.
///
/// There is deliberately no client-side `grants()` mirror: the wire carries
/// `subscribed`, which the server derives from the tier plus its own
/// `PlanStatus::grants()`. A second definition here could disagree with the
/// first, and the server's is the one that gates.
enum PlanStatus {
  /// No plan lifecycle at all: a customer no rail has ever charged, and the
  /// landing place for a value this build does not know.
  none,

  /// Inside a trial: entitled, and not yet charged.
  trialing,

  /// Paid and current.
  active,

  /// The money has not arrived and the rail is still trying. [pastDue] and
  /// [grace] both mean the plan is still owed to the subscriber; they differ
  /// only in which side is holding the window open.
  pastDue,
  grace,

  /// Finished. [canceled] is a lifecycle the subscriber or the rail ended,
  /// [expired] is one that ran out; only one of them tends to come back.
  canceled,
  expired,

  /// Suspended by the subscriber with the intent of resuming. Not a
  /// cancellation, and not entitled while it lasts.
  paused;

  /// Decodes the `plan_status` wire value into a [PlanStatus], falling back to
  /// [PlanStatus.none] on an absent or unrecognised value.
  ///
  /// The fallback is what lets a newer backend ship a ninth status without
  /// crashing an older client, and it lands on a NON-entitling case on purpose:
  /// an unrecognised word must never read as an active plan.
  ///
  /// The values are matched EXPLICITLY rather than against `.name`, because the
  /// wire words are snake_case (`past_due`) where Dart is camelCase, so a
  /// `.name` comparison would silently drop that case into the fallback.
  static PlanStatus fromWire(String? raw) {
    return switch (raw) {
      'none' => PlanStatus.none,
      'trialing' => PlanStatus.trialing,
      'active' => PlanStatus.active,
      'past_due' => PlanStatus.pastDue,
      'grace' => PlanStatus.grace,
      'canceled' => PlanStatus.canceled,
      'expired' => PlanStatus.expired,
      'paused' => PlanStatus.paused,
      _ => PlanStatus.none,
    };
  }

  /// Whether a payment has failed and the rail is still retrying.
  ///
  /// This is NOT a `grants()` mirror, which this enum deliberately does not
  /// carry: whether a status entitles is the producer's answer and arrives as
  /// `BillingEntitlement.subscribed`. This asks a different question, and one no
  /// other field answers: is the customer's money late. Both dunning statuses
  /// still grant, so a screen reading `subscribed` alone cannot tell a paying
  /// customer from one whose card just bounced, and it showed both of them the
  /// same healthy renewal sentence.
  ///
  /// The two cases differ only in which side is holding the window open, which
  /// is a distinction for a support conversation and not for a warning banner,
  /// so they answer alike here.
  bool get isDunning => this == PlanStatus.pastDue || this == PlanStatus.grace;
}
