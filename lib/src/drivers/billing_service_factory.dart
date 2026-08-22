import '../contracts/billing_service.dart';
import '../contracts/store_billing_service.dart';
import '../contracts/web_billing_service.dart';
import 'billing_service_stub.dart'
    if (dart.library.html) 'billing_service_web.dart'
    if (dart.library.io) 'billing_service_io.dart'
    as impl;

/// Resolves the [BillingService] this build can actually serve.
///
/// The ONE place in the package that knows about platforms at all, and it knows
/// through the import graph rather than through a branch. Nothing here asks the
/// runtime which device it is on, because that question answers "which device"
/// and a billing surface needs "which rail": a subscription bought on an iPhone
/// is still managed in the App Store when the customer opens the web app, and
/// only the entitlement knows that.
///
/// THREE arms, and the third is not optional. The stub is the default, the web
/// library guard selects the web driver, and the `dart:io` guard selects the
/// mobile and desktop one. Drop that last guard and every iOS and Android build
/// resolves the stub, whose every method throws, which would break the five
/// mobile READ paths that work today, with no analyzer error on any platform to
/// say so.
///
/// The guard strings above are deliberately NOT spelled out in this prose. The
/// gate that keeps each of them to exactly one occurrence is a grep over this
/// raw file, and a docblock repeating the token is how a review grep once
/// matched the comment explaining the thing it was searching for.
///
/// ```dart
/// final BillingService billing = createBillingService();
/// final WebBillingService? web = createWebBillingService();
/// final StoreBillingService? store = createStoreBillingService();
/// ```
BillingService createBillingService() => impl.createBillingService();

/// Resolves the WEB rail, or `null` where this build cannot serve one.
///
/// A conditional import resolves a whole FILE, so every arm declares this
/// function and only the web one returns a rail. The `null` is the answer a
/// caller acts on: it asks whether the rail exists before it offers an upgrade
/// button, rather than offering one and catching the platform's refusal.
WebBillingService? createWebBillingService() => impl.createWebBillingService();

/// Resolves the STORE rail, or `null` where this build cannot serve one.
///
/// The web and stub arms answer `null`, because neither has a store to reach.
/// The io arm delegates to `createStoreRail()`, which hands back the RevenueCat
/// driver on iOS and Android and `null` on macOS, Windows and Linux: all three
/// desktops match the same import guard as mobile while having no StoreKit or
/// Play Billing, so which DEVICE is running is a question the import graph
/// cannot answer and that arm asks separately.
///
/// (Deliberately without naming the guard here. This file's own test counts each
/// guard string over the raw source, comments included, because two copies of one
/// would silently shadow each other; prose that spelled one out would fail that
/// count. See `test/drivers/billing_service_factory_test.dart`.)
///
/// A `null` here is therefore "this build cannot serve a store", and a caller
/// checks it instead of offering a purchase and catching a refusal.
StoreBillingService? createStoreBillingService() =>
    impl.createStoreBillingService();
