# Rails

## Table of Contents

- <a name="toc-overview"></a>[Overview](#overview)
- <a name="toc-three-rails"></a>[The Three Rails](#three-rails)
- <a name="toc-reads"></a>[BillingService: Five Reads, Honourable Everywhere](#reads)
- <a name="toc-web"></a>[WebBillingService: the Stripe Rail](#web)
- <a name="toc-store"></a>[StoreBillingService: Declared, Not Implemented](#store)
- <a name="toc-authority"></a>[Entitlement Authority Belongs to the Backend](#authority)
- <a name="toc-axis"></a>[The Rail and the Platform Are Different Axes](#axis)

---

## <a name="overview"></a>Overview

A subscription can be sold by more than one rail: Stripe on the web, StoreKit on iOS, Google Play
Billing on Android. Each has its own vocabulary, its own idea of when a period ends and its own
opinion about who may cancel. Magic Payments puts one contract in front of them so a consuming app
never has to learn a rail's dialect to render a billing screen.

---

## <a name="three-rails"></a>The Three Rails

| Rail | Contract | Platform | Status |
|------|----------|----------|--------|
| Stripe | `WebBillingService` | Web | Implemented |
| App Store | `StoreBillingService` | iOS | Declared, not implemented |
| Play Store | `StoreBillingService` | Android | Declared, not implemented |

`BillingService`, the five reads, sits above all three: it answers on every platform because the
backend is the authority on an entitlement regardless of which rail sold it.

---

## <a name="reads"></a>BillingService: Five Reads, Honourable Everywhere

```dart
abstract class BillingService {
  Future<BillingEntitlement> currentEntitlement();
  Future<List<Map<String, dynamic>>> getPlans();
  Future<List<UsageStat>> getUsage();
  Future<BillingInvoicesPage> getInvoices({String? cursor});
  Future<PaymentMethod> getPaymentMethod();
}
```

None of these five throws for want of a platform. `currentEntitlement()` is the call every billing
surface starts from:

```dart
final BillingEntitlement entitlement = await Payments.currentEntitlement();

if (entitlement.subscribed) {
  showManageButton(entitlement.manageVia, entitlement.manageUrl);
}
```

`Payments` forwards each of the five reads directly as a static method of the same name, the same
explicit-forwarder shape every facade in this ecosystem uses (`Notify.markAsRead`, `SocialAuth.driver`).

`getPlans()` returns each tier's row verbatim rather than decoded into a shared type: a plan's
prices and feature bullets are the vendor's product, not a payment concept, and the consumer already
owns the type it wants to decode them into.

---

## <a name="web"></a>WebBillingService: the Stripe Rail

```dart
abstract class WebBillingService {
  Future<BillingCheckoutSession> checkout({
    required String plan,
    required String successUrl,
    required String cancelUrl,
  });
  Future<void> swap({required String plan});
  Future<void> cancel();
  Future<String> openPortal({String? returnUrl});
}
```

These four methods change what the customer is paying for, so they live off the read contract
entirely. `Payments.web` resolves to `null` off a web build; a caller checks for the rail before it
renders an upgrade button, rather than rendering one and catching the platform's refusal:

```dart
final WebBillingService? web = Payments.web;
if (web != null) {
  await web.checkout(
    plan: 'pro',
    successUrl: 'https://example.com/billing?checkout=success',
    cancelUrl: 'https://example.com/billing?checkout=cancel',
  );
}
```

A cancellation on this rail is normally end-of-period, not immediate: the entitlement it leaves
behind still grants until `BillingEntitlement.currentPeriodEnd`. Re-read the entitlement rather than
assuming the call revoked anything.

---

## <a name="store"></a>StoreBillingService: Declared, Not Implemented

```dart
abstract class StoreBillingService {
  Future<void> identify(String appUserId);
  Future<bool> purchase({required String plan});
  Future<bool> restore();
  Future<void> openStoreManagement();
}
```

`RevenueCatStoreService` implements it, and `Payments.store` is non-null on iOS and Android. It stays
`null` on web, on desktop and on the fallback arm, so a purchase affordance must be gated on
`Payments.store != null` and not on a platform check of your own.

> [!WARNING]
> Non-null does NOT mean configured. The driver reads
> `payments.revenuecat.public_sdk_key` the first time it needs the SDK and throws a
> `BillingException` when that key is blank or absent, because whether a device HAS a store and
> whether you have supplied credentials for it are two different questions. See
> [Configuration](../getting-started/configuration.md).

The contract makes one non-promise, and it is the whole reason the store rail is separate:

**A `true` from `purchase()` or `restore()` says the store reported a completed transaction. It says
nothing about what `currentEntitlement()` will answer immediately afterwards.** A store purchase is
asynchronous, and the rail's own webhook is the authority on the entitlement, not the device that
tapped Buy. The vendor's backend may not have been told yet by the time the purchase call returns.

```dart
final StoreBillingService? store = Payments.store;
if (store != null) {
  final bool bought = await store.purchase(plan: 'pro');
  if (bought) {
    // The store is done. The entitlement may not have caught up yet.
    // Treat a stale answer as "not yet", never as a failure.
    await Payments.currentEntitlement();
  }
}
```

Building a UI that reads `purchase()`'s `true` as an entitlement grant is the bug this package
exists to prevent on the store rail specifically. It is safe on every OTHER call in this package
because every other write either confirms synchronously (the web rail's `checkout`, `swap`,
`cancel`) or is itself a read; only a store purchase carries this asynchronous gap.

---

## <a name="authority"></a>Entitlement Authority Belongs to the Backend

**The consuming backend, not this package, decides who is entitled to what.** Every method on every
contract here is a client of that decision, never a maker of it:

- `WebBillingService.checkout`, `.swap` and `.cancel` all ask Stripe to change something and let the
  backend's own webhook project the result into the entitlement the backend serves back.
- `StoreBillingService.purchase` and `.restore`, once implemented, hand the customer to the App
  Store or Play Store and report only what the STORE said, not what the backend has recorded.
- `BillingService.currentEntitlement` is the one call that reads the backend's own answer, and it is
  the only source of truth this package recognises.

A client that grants a feature locally on a `true` from a purchase or a checkout call has built an
entitlement of its own that can disagree with the backend's. Always re-read
`currentEntitlement()` after a write, and treat the write's own boolean or session id as a hint that
something happened, never as the grant itself.

---

## <a name="axis"></a>The Rail and the Platform Are Different Axes

A subscription bought on an iPhone is still managed in the App Store when the customer opens the web
app. The rail that sold a subscription and the platform the app happens to be running on are
independent facts, and conflating them is the mistake this package exists to prevent.

So a consumer branches its management affordances on `BillingEntitlement.manageVia`
(`ManageVia.portal`, `.appStore`, `.playStore` or `.none`), never on `kIsWeb` or `Platform.is`:

```dart
switch (entitlement.manageVia) {
  case ManageVia.portal:
    await Payments.web?.openPortal();
  case ManageVia.appStore:
  case ManageVia.playStore:
    await Payments.store?.openStoreManagement();
  case ManageVia.none:
    // Nowhere to send the customer: no rail, an operator grant, or an unknown rail.
    break;
}
```

On a non-web platform, never render a link, URL or CTA pointing at web checkout or the Stripe
portal. Apple's App Review Guideline 3.1.3 preamble bans steering a customer outside the app to
another purchase method, and `manageVia` being the same value on every platform for the same rail is
what makes that easy to honour: there is nothing to override per platform, only per rail.

---

**Related**

- [Drivers](https://magic.fluttersdk.com/packages/payments/basics/drivers)
- [Payments Manager](https://magic.fluttersdk.com/packages/payments/architecture/payments-manager)
- [Installation](https://magic.fluttersdk.com/packages/payments/getting-started/installation)
