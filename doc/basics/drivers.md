# Drivers

## Table of Contents

- <a name="toc-concept"></a>[Driver Concept](#concept)
- <a name="toc-factory"></a>[The Conditional-Import Factory](#factory)
- <a name="toc-web-driver"></a>[BillingServiceWeb](#web-driver)
- <a name="toc-io-driver"></a>[BillingServiceIo](#io-driver)
- <a name="toc-stub-driver"></a>[BillingServiceStub](#stub-driver)
- <a name="toc-extend"></a>[Overriding a Driver](#extend)

---

## <a name="concept"></a>Driver Concept

A driver implements the contracts against one platform's own transport. `BillingServiceWeb` and
`BillingServiceIo` both talk to the vendor's `api/v1` over magic's `Http` facade; `BillingServiceStub`
talks to nothing, because it is reached on a platform this package has never seen. Which one a build
gets is decided once, at compile time, by the package's own conditional import, not by a runtime
check.

---

## <a name="factory"></a>The Conditional-Import Factory

`billing_service_factory.dart` is the one file in the package that knows about platforms at all, and
it knows through the import graph rather than through a branch:

```dart
import 'billing_service_stub.dart'
    if (dart.library.html) 'billing_service_web.dart'
    if (dart.library.io) 'billing_service_io.dart'
    as impl;

BillingService createBillingService() => impl.createBillingService();
WebBillingService? createWebBillingService() => impl.createWebBillingService();
StoreBillingService? createStoreBillingService() => impl.createStoreBillingService();
```

Three arms, and the third is not optional. Drop the `dart.library.io` guard and every iOS and Android
build resolves the stub instead, whose every read throws, with no analyzer error on any platform to
say so.

Every arm declares all three functions, because a conditional import resolves a whole FILE: each arm
has to answer for every rail, even when its own answer to two of them is `null`.

| Arm | `createBillingService()` | `createWebBillingService()` | `createStoreBillingService()` |
|-----|---------------------------|------------------------------|-------------------------------|
| Web (`dart.library.html`) | `BillingServiceWeb` | `BillingServiceWeb` | `null` |
| Io (`dart.library.io`) | `BillingServiceIo` | `null` | `RevenueCatStoreService` on iOS and Android, `null` elsewhere |
| Stub (default) | `BillingServiceStub` | `null` | `null` |

The io arm's answer is the only one that is not decided by the import alone. `dart.library.io` is also
satisfied on macOS, Windows and Linux, none of which has StoreKit or Play Billing, so that arm asks
the device question at runtime (`Platform.isIOS || Platform.isAndroid`) before handing back a rail.
The store rail needs configuration the other two do not: see
[Configuration](../getting-started/configuration.md).

### The five reads are shared, and a test keeps them that way

`BillingServiceWeb` and `BillingServiceIo` both take `BillingReadsOverHttp`, a mixin in a file with
no platform import of its own. The five reads are identical by nature rather than by coincidence:
they call the same `api/v1` endpoints and decode the same bodies, because the backend is the
authority on an entitlement whichever rail sold the subscription.

They were duplicated in both arms until a review measured them at 106 lines differing by a single
line wrap, and the duplication was invisible to every gate this package has. A conditional import
compiles exactly ONE arm per target, so no analyze run and no passing test on any platform could
observe the two copies disagreeing: a fix applied to the web arm's envelope handling would simply
leave the same bug shipping on mobile, silently.

`test/drivers/billing_reads_over_http_test.dart` therefore asserts the structure rather than the
behaviour: the mixin declares all five, NEITHER driver declares one of its own, and the mixin carries
no platform seam. If you add a read, add it there.

The log prefix comes from `runtimeType`, so a line still names the concrete driver that made the call
(`[BillingServiceWeb.getUsage]`) rather than naming the mixin.

`PaymentsServiceProvider.boot()` calls these three functions once and hands the results to
`PaymentsManager`, which is what makes `Payments.web` and `Payments.store` resolve to a real rail or
to `null` without a single `kIsWeb` check anywhere above the factory. See
[Payments Manager](../architecture/payments-manager.md).

---

## <a name="web-driver"></a>BillingServiceWeb

Implements both `BillingService` and `WebBillingService` in one class, because the nine web calls
share a transport and an envelope convention that is not uniform across the endpoints (some bodies
arrive wrapped in `data`, some flat). Splitting the reads from the writes into two classes would
duplicate that convention in two places.

The two calls that mint a hosted page (`checkout`, `openPortal`) open it with
`LaunchMode.inAppWebView` rather than the facade's default external browser, because a hosted
checkout returns the customer to `successUrl` when they are done, and an external browser return
lands in the browser rather than back in the app.

---

## <a name="io-driver"></a>BillingServiceIo

Implements `BillingService` only, the five reads, over the same `api/v1` endpoints as the web
driver. It carries no purchase-affecting method and no platform-specific throw: reading an
entitlement is honourable on every device, because the backend is the authority on it regardless of
which rail sold the subscription. This is a deliberate change from the shape it replaced, where a
single mobile class carried four purchase methods that always threw
`UnsupportedPlatformException`, producing an Upgrade button whose only behaviour was to fail.

---

## <a name="stub-driver"></a>BillingServiceStub

The fallback, reached only where neither `dart.library.html` nor `dart.library.io` applies. Every
read throws `UnsupportedPlatformException` here, and that is deliberate rather than an oversight:
there is no assumed network stack to ask on a platform this package has never seen, and a silent
empty answer would render as a customer with no subscription, which is a lie about a paying account
that a support ticket could not distinguish from a genuine free tier.

---

## <a name="extend"></a>Overriding a Driver

`PaymentsManager` follows the same override shape every manager in this ecosystem uses:
`SocialAuthManager.extend` in `magic_social_auth` is the sibling to read for the exact pattern. A
custom driver is registered by name and clears any cached instance for that name, so the next
resolution builds the new one:

```dart
Payments.manager.extend('sandbox', (config) => SandboxBillingDriver(config));
```

This is the seam a test uses to stand in for a driver without mocking a third-party SDK, and it is
how a consumer replaces the store rail: registering the store role puts your own
`StoreBillingService` in front of `RevenueCatStoreService`, which is the supported way to sell
through a mediator this package does not ship. See [Rails](./rails.md).

---

**Related**

- [Rails](https://magic.fluttersdk.com/packages/payments/basics/rails)
- [Payments Manager](https://magic.fluttersdk.com/packages/payments/architecture/payments-manager)
- [Service Provider](https://magic.fluttersdk.com/packages/payments/architecture/service-provider)
