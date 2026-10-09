import 'package:flutter/foundation.dart';

/// The catalogue facts a store purchase needs to judge an upgrade or a
/// downgrade, handed in by the caller that already read the catalogue.
///
/// A store rail knows products, not tiers. Whether moving from `pro_monthly`
/// to `business_annual` is an upgrade decides how the store prorates it, and
/// that answer lives in the vendor's catalogue (`BillingService.getPlans()`),
/// which this package passes through undecoded. So the caller distils the
/// facts the rail needs and nothing else.
@immutable
class PurchaseContext {
  /// Creates a [PurchaseContext].
  const PurchaseContext({
    required this.tierOrder,
    required this.tierOfProduct,
    this.tierOfStoreProduct = const <String, String>{},
  });

  /// The vendor's tiers from lowest to highest (`['free', 'pro', 'business']`).
  final List<String> tierOrder;

  /// The tier each catalogue product key belongs to
  /// (`{'pro_monthly': 'pro', 'pro_annual': 'pro'}`).
  final Map<String, String> tierOfProduct;

  /// The tier each STORE product id belongs to, including products no longer
  /// sold (`{'pro_sub:monthly': 'pro', 'com.app.pro.monthly': 'pro'}`).
  ///
  /// The only way the rail can rank a grandfathered product: one no offering
  /// carries has no catalogue key to look up in [tierOfProduct]. Built from
  /// every plan row's `store_ids`, the non-sellable products included. A Play
  /// id is `subscriptionId:basePlanId`; the rail matches the full id first and
  /// then the bare subscription id, so a base plan the rows never listed still
  /// ranks by its subscription. Empty by default, which refuses a change from
  /// a product nothing names rather than guessing its tier.
  final Map<String, String> tierOfStoreProduct;
}
