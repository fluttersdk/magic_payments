import 'package:flutter/foundation.dart';

/// The catalogue facts a store purchase needs to judge an upgrade or a
/// downgrade, handed in by the caller that already read the catalogue.
///
/// A store rail knows products, not tiers. Whether moving from `pro_monthly`
/// to `business_annual` is an upgrade decides how the store prorates it, and
/// that answer lives in the vendor's catalogue (`BillingService.getPlans()`),
/// which this package passes through undecoded. So the caller distils the two
/// facts the rail needs and nothing else.
@immutable
class PurchaseContext {
  /// Creates a [PurchaseContext].
  const PurchaseContext({required this.tierOrder, required this.tierOfProduct});

  /// The vendor's tiers from lowest to highest (`['free', 'pro', 'business']`).
  final List<String> tierOrder;

  /// The tier each catalogue product key belongs to
  /// (`{'pro_monthly': 'pro', 'pro_annual': 'pro'}`).
  final Map<String, String> tierOfProduct;
}
