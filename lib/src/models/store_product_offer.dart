import 'package:flutter/foundation.dart';

/// One store product as the STORE prices it for this customer.
///
/// A store build has to show the store's own localized price, not the vendor
/// catalogue's figure: the store decides the currency, the tax and the
/// rounding, and App Review rejects a screen whose price disagrees with the
/// purchase sheet. So this carries the store's answer verbatim.
///
/// Plain fields mirroring the store SDK's product, rather than the SDK type
/// itself, so the contract that returns it does not import a vendor package.
@immutable
class StoreProductOffer {
  /// Creates a [StoreProductOffer].
  const StoreProductOffer({
    required this.priceString,
    required this.currencyCode,
    required this.price,
    this.subscriptionPeriod,
    this.introPrice,
    this.introPriceString,
    this.introPeriod,
  });

  /// The price formatted by the store for the customer's locale and currency,
  /// ready to render (`'₺349,99'`). Render this, never a figure built from
  /// [price].
  final String priceString;

  /// The ISO 4217 code of the currency [price] is in (`'TRY'`).
  final String currencyCode;

  /// The price as a number in [currencyCode]'s major unit, for arithmetic such
  /// as a savings figure; not for display.
  final double price;

  /// The ISO 8601 billing period of a subscription (`'P1M'`, `'P1Y'`), or
  /// `null` for a product that does not renew.
  final String? subscriptionPeriod;

  /// The introductory price as a number, or `null` when the product has no
  /// introductory offer.
  final double? introPrice;

  /// The introductory price formatted by the store, or `null` when the product
  /// has no introductory offer.
  final String? introPriceString;

  /// The ISO 8601 period the introductory price lasts (`'P1W'`), or `null`
  /// when the product has no introductory offer.
  final String? introPeriod;
}
