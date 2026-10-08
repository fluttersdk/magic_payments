import 'package:flutter/foundation.dart';

import '../enums/billing_cycle.dart';
import '../enums/billing_provider.dart';
import '../enums/manage_via.dart';
import '../enums/plan_status.dart';

/// What the customer is entitled to, and where they manage it.
///
/// The seventeen fields mirror the entitlement wire one for one, in its
/// rail-neutral vocabulary: nothing here names a payment rail's own dialect
/// except [providerStatus], which is debug text and must never reach a gate or
/// a computed field.
///
/// SEVEN of the seventeen are never null: [planStatus], [subscribed],
/// [provider] and [manageVia], which degrade to their non-entitling case, and
/// the three holdings [owned], [balances] and [allowances], which degrade to
/// empty. An empty holding is the same claim as an absent one (the customer
/// holds nothing of that kind), which is why only those may default.
///
/// The other ten are nullable, and a decoder that defaulted any of them would
/// claim a state no rail has reported, which is a different sentence from "not
/// reported". Four are null on the Stripe rail BY DESIGN rather than by
/// accident: [manageUrl] and [gracePeriodEndsAt] have no Stripe source at all,
/// and [providerStatus] and [productId] stay null until a rail writes them.
///
/// [raw] keeps the full decoded payload, so a caller can read a field this value
/// object has not enumerated (a key a newer backend added) without waiting for a
/// client release.
@immutable
class BillingEntitlement {
  /// Builds an entitlement from ALREADY-DECODED cases rather than from raw wire
  /// words, which is what makes the constructor `const`.
  ///
  /// Decoding belongs to [BillingEntitlement.fromMap], the one place a wire
  /// word ever arrives. Keeping it out of here means a hand-built entitlement (a
  /// test fake, a fixture, an offline default) states its cases in the type
  /// system instead of in strings the compiler cannot check.
  ///
  /// The optional fields are the ones a caller building an entitlement by hand
  /// can honestly leave unsaid. [subscribed] defaults to `false` and the three
  /// vocabularies to their `none` case, which is the same non-entitling landing
  /// place their `fromWire` fallbacks use: an entitlement nobody described must
  /// never read as a paid one.
  const BillingEntitlement({
    required this.plan,
    this.planStatus = PlanStatus.none,
    this.subscribed = false,
    this.renews,
    this.cycle,
    this.provider = BillingProvider.none,
    this.providerStatus,
    this.productId,
    this.manageVia = ManageVia.none,
    this.manageUrl,
    this.currentPeriodEnd,
    this.trialEndsAt,
    this.gracePeriodEndsAt,
    this.productKey,
    this.owned = const [],
    this.balances = const {},
    this.allowances = const {},
    required this.raw,
  });

  /// The active tier identifier (e.g. `'pro'`), or `null` when the producer
  /// sent none.
  ///
  /// Required in the constructor although nullable, so a hand-built
  /// entitlement says which tier it is, or says `null` out loud.
  final String? plan;

  /// Where the paid plan stands in its lifecycle, in the neutral vocabulary.
  final PlanStatus planStatus;

  /// Whether the customer currently holds a paid plan.
  ///
  /// Trusted from the wire, never recomputed here: the server derives it from
  /// the entitlement tier plus its own `PlanStatus::grants()`, and a second
  /// client-side definition could disagree with the one that actually gates. A
  /// customer with a failed charge stays subscribed while their rail retries.
  final bool subscribed;

  /// Whether the subscription rolls over at [currentPeriodEnd].
  ///
  /// Nullable on purpose: `null` means no rail has said, which is not the claim
  /// `false` makes.
  final bool? renews;

  /// How often the customer is charged, or `null` when no rail has said.
  ///
  /// This is what the customer BOUGHT, resolved server-side from the price their
  /// subscription is on. It is not the cycle a screen happens to be displaying,
  /// and the two are easy to conflate: a catalogue toggle changes which figure a
  /// card shows and changes nothing about the charge.
  ///
  /// Null is a real state and has to be rendered as one. It covers a customer on
  /// no rail, a tier the vendor prices only one way and never mapped, and a
  /// producer too old to report the field. Defaulting it to either member would
  /// put a billing claim on screen that nothing verified, which is exactly the
  /// defect [BillingCycle] exists to close.
  final BillingCycle? cycle;

  /// Which rail granted the entitlement.
  final BillingProvider provider;

  /// The rail's OWN status word, verbatim, including words the neutral
  /// vocabulary has none for. Debug and support text only: never a gate, never
  /// an input to a computed field.
  final String? providerStatus;

  /// The rail's product identifier (a Stripe price id, a store product id), or
  /// `null` until a rail writes one.
  final String? productId;

  /// Where the customer manages this subscription, computed server-side from the
  /// rail so no client has to learn the rail-to-surface mapping.
  final ManageVia manageVia;

  /// The destination that pairs with a store [manageVia], or `null`.
  ///
  /// Null on the Stripe rail by design (a portal session is minted live by the
  /// portal endpoint), and also possible on a store rail whose management URL
  /// has not arrived. A null on a store rail renders a statement WITHOUT a link
  /// rather than a dead button.
  final String? manageUrl;

  /// When the paid period ends, whether or not it renews, or `null` when no rail
  /// has reported one.
  final DateTime? currentPeriodEnd;

  /// When the trial ends. Stripe-only by construction: the producer reads it
  /// from its own local subscription row, and a store trial arrives as
  /// [planStatus] `trialing` plus [currentPeriodEnd] instead.
  final DateTime? trialEndsAt;

  /// When the dunning grace period ends, or `null` when the customer is not in
  /// one. Non-null is itself the answer to "is this customer in a grace
  /// period"; there is no separate boolean on this wire.
  final DateTime? gracePeriodEndsAt;

  /// The catalogue key of the product the subscription is on (e.g.
  /// `'pro_annual'`), read from the `product` wire key, or `null` when no rail
  /// has said.
  ///
  /// The vendor's own key, the same one `purchase` and `checkout` take, and not
  /// [productId], which is a rail's SKU or price id. A caller compares this
  /// against a catalogue row's `key` to mark the current product.
  final String? productKey;

  /// The catalogue keys of one-off products the customer owns for good (e.g.
  /// `['lifetime']`). Empty when they own none or the producer predates it.
  final List<String> owned;

  /// Remaining units per consumable balance (e.g. `{'credits': 5}`). Empty
  /// when there are none or the producer predates it.
  final Map<String, int> balances;

  /// The vendor's in-product allowances for the current tier, passed through
  /// undecoded for the same reason catalogue rows are: their shape is the
  /// vendor's product. Empty when the producer sends none.
  final Map<String, dynamic> allowances;

  /// The full decoded entitlement payload.
  final Map<String, dynamic> raw;

  /// Decodes a [BillingEntitlement] from the unwrapped `data` object of the
  /// entitlement response.
  ///
  /// The status is read from `plan_status`, which is the only status key this
  /// wire has ever emitted; a `status` key does not exist on it, and a fixture
  /// that says otherwise decodes to [PlanStatus.none] here rather than quietly
  /// agreeing with itself.
  ///
  /// The three holdings accept a JSON `[]` as empty: PHP encodes an empty
  /// associative array as a list, so `[]` is the producer saying "none", not a
  /// malformed payload.
  factory BillingEntitlement.fromMap(Map<String, dynamic> map) {
    return BillingEntitlement(
      plan: map['plan'] as String?,
      planStatus: PlanStatus.fromWire(map['plan_status'] as String?),
      subscribed: (map['subscribed'] as bool?) ?? false,
      renews: map['renews'] as bool?,
      cycle: BillingCycle.fromWire(map['cycle'] as String?),
      provider: BillingProvider.fromWire(map['provider'] as String?),
      providerStatus: map['provider_status'] as String?,
      productId: map['product_id'] as String?,
      manageVia: ManageVia.fromWire(map['manage_via'] as String?),
      manageUrl: map['manage_url'] as String?,
      currentPeriodEnd: _instantFromWire(map['current_period_end']),
      trialEndsAt: _instantFromWire(map['trial_ends_at']),
      gracePeriodEndsAt: _instantFromWire(map['grace_period_ends_at']),
      productKey: map['product'] as String?,
      owned: _keysFromWire(map['owned']),
      balances: _balancesFromWire(map['balances']),
      allowances: _objectFromWire(map['allowances']),
      raw: map,
    );
  }
}

/// Decodes one of the entitlement's three ISO 8601 instants.
///
/// `DateTime.tryParse` rather than `parse`, and an `Object?` rather than a
/// `String?` in: a malformed or wrongly-typed instant degrades to "not
/// reported" exactly as an unrecognised enum value degrades to its `none` case.
/// A billing screen that cannot render a date must still render the plan.
///
/// Private rather than shared with the other two decoders that want it: a
/// package's barrel exports every public name in the files it exports, and
/// `instantFromWire` is far too generic a word to claim in a consumer's
/// namespace for three lines of saved duplication.
DateTime? _instantFromWire(Object? raw) {
  return raw is String ? DateTime.tryParse(raw) : null;
}

/// Decodes the `owned` list, keeping only its string entries.
List<String> _keysFromWire(Object? raw) {
  return raw is List ? raw.whereType<String>().toList() : const [];
}

/// Decodes the `balances` object, keeping only its numeric entries.
///
/// A list (PHP's empty object) or any other shape decodes to empty rather than
/// throwing, the same way a malformed instant degrades to "not reported".
Map<String, int> _balancesFromWire(Object? raw) {
  if (raw is! Map) return const {};

  return {
    for (final MapEntry<Object?, Object?> entry in raw.entries)
      if (entry.key is String && entry.value is num)
        entry.key! as String: (entry.value! as num).toInt(),
  };
}

/// Decodes the `allowances` object verbatim, or empty for any other shape.
Map<String, dynamic> _objectFromWire(Object? raw) {
  return raw is Map<String, dynamic> ? raw : const {};
}
