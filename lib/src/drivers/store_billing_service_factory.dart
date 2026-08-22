import 'dart:io' show Platform;

import '../contracts/store_billing_service.dart';
import 'revenuecat_store_service.dart';

/// Resolves the STORE rail for the device this build is running on, or `null`
/// where that device has no store.
///
/// ## Why a RUNTIME check lives here, of all places
///
/// The conditional import in `billing_service_factory.dart` cannot separate
/// these platforms. `dart.library.io` is true on iOS, Android, macOS, Windows
/// and Linux, and only the first two have StoreKit or Play Billing, so ONE
/// compiled artifact serves all five and the io arm cannot hand a RevenueCat
/// driver back unconditionally. A desktop build that did would offer a purchase
/// affordance whose only behaviour is to fail.
///
/// So this is the exception the package's own rule names rather than a break of
/// it: what a given build is CAPABLE of is answered by which implementation a
/// factory returns, and this file is that factory. The other axis, WHERE a
/// subscription is managed, is not asked here at all: that answer is the
/// entitlement's `manage_via`, because a subscription bought on an iPhone is
/// still managed in the App Store when the customer opens the web app.
///
/// `null` is the answer a caller acts on, and never a throwing stub: a build
/// with no store does not render an upgrade button rather than rendering one
/// that refuses when tapped.
///
/// ```dart
/// StoreBillingService? createStoreBillingService() => createStoreRail();
/// ```
///
/// [onStorePlatform] exists for tests, so BOTH answers are reachable from a host
/// that is neither a phone nor a browser: a `flutter test` run is always on a
/// desktop, so without it only the `null` branch could ever be exercised.
StoreBillingService? createStoreRail({bool? onStorePlatform}) {
  final bool hasStore =
      onStorePlatform ?? (Platform.isIOS || Platform.isAndroid);
  if (!hasStore) return null;

  return RevenueCatStoreService();
}
