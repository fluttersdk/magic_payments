# Rails

## Table of Contents

- <a name="toc-overview"></a>[Overview](#overview)
- <a name="toc-three-rails"></a>[The Three Rails](#three-rails)
- <a name="toc-reads"></a>[BillingService: Five Reads, Honourable Everywhere](#reads)
- <a name="toc-web"></a>[WebBillingService: the Stripe Rail](#web)
- <a name="toc-store"></a>[StoreBillingService: Declared, Not Implemented](#store)
  - [Product keys, on both rails](#product-keys)
  - [`products()`: the store's own prices](#store-prices)
  - [`PurchaseContext`](#purchase-context)
  - [What the store rail refuses](#store-refusals)
  - [Typed errors](#errors)
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
    required String productKey,
    required String successUrl,
    required String cancelUrl,
  });
  Future<void> swap({required String productKey});
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
    productKey: 'pro_annual',
    successUrl: 'https://example.com/billing?checkout=success',
    cancelUrl: 'https://example.com/billing?checkout=cancel',
  );
}
```

One product key names the tier AND the cycle together (see [Product keys](#product-keys)). A tier is
not a price: a vendor selling `pro` monthly and again at a discounted annual rate has two products,
and when tier and cycle travelled as two words a call that lost the second let the backend pick a
price while the screen showed the other. A single key cannot be half-sent. `checkout` and `swap`
send it as `product`; the producer resolves the price from the key and refuses with a 422 when it
has none mapped, which is how an adopter learns that rather than having a customer quietly charged
the wrong figure.

A cancellation on this rail is normally end-of-period, not immediate: the entitlement it leaves
behind still grants until `BillingEntitlement.currentPeriodEnd`. Re-read the entitlement rather than
assuming the call revoked anything.

---

## <a name="store"></a>StoreBillingService: Declared, Not Implemented

```dart
abstract class StoreBillingService {
  Future<void> identify(String appUserId);
  Future<bool> purchase(String productKey, {PurchaseContext? context});
  Future<Map<String, StoreProductOffer>> products(List<String> productKeys);
  Future<bool> restore();
  Future<void> openStoreManagement();
  ManageVia get store;
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
  final bool bought = await store.purchase('pro_annual');
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

### <a name="product-keys"></a>Product keys, on both rails

`purchase`, `checkout` and `swap` all take the same thing: the vendor's own catalogue key, such as
`'pro_annual'`, which is also the key a `getPlans()` row carries. It is never a store product id and
never a Stripe price id. Which store product or price a key maps to belongs to the rail's catalogue
(on the store rail the key is the RevenueCat package identifier, searched in the current offering
first and then the rest; on the web rail, the backend's price table), so adding or repricing a
product needs no client release. A product's `ProductType` (`subscription`, `consumable`,
`non_consumable`, `physical`) says what a purchase leaves behind; only a subscription key carries a
cycle.

### <a name="store-prices"></a>`products()`: the store's own prices

```dart
final Map<String, StoreProductOffer> offers = await store.products(<String>['pro_monthly', 'pro_annual']);
final StoreProductOffer? annual = offers['pro_annual'];
```

A store build renders the store's figures, not the catalogue's, because the store decides currency,
tax and rounding and its sheet will show them. A `StoreProductOffer` carries `priceString` (already
localized), `currencyCode`, `price`, an ISO `subscriptionPeriod` and the intro-price fields
(`introPrice`, `introPriceString`, `introPeriod`). A key the store has no product for is absent from
the map; render that product as unavailable rather than guessing a price. `products()` resolves
through the same offering packages `purchase` uses, so a key it prices is a key a purchase can buy.

### <a name="store-getter"></a>`store`: which store this is

`StoreBillingService.store` answers `ManageVia.appStore` or `ManageVia.playStore`. Compare it with
`BillingEntitlement.manageVia` to tell a subscription this store can change from one another rail
sold, without asking the running platform.

### <a name="purchase-context"></a>`PurchaseContext`: telling an upgrade from a downgrade

A store knows products, not tiers. When the customer already holds a subscription, pass the two facts
the rail needs, distilled from the catalogue you already read:

```dart
await store.purchase(
  'business_annual',
  context: const PurchaseContext(
    tierOrder: <String>['free', 'pro', 'business'],
    tierOfProduct: <String, String>{'pro_monthly': 'pro', 'business_annual': 'business'},
  ),
);
```

On Google Play the context decides the proration of a product change: a cycle change inside one tier
is charged at full price without proration, and a move across tiers is prorated and deferred.
Without a context the rail cannot tell the two apart.

### <a name="store-refusals"></a>What the store rail refuses

`purchase` and `restore` refuse, rather than guess, in these cases. Each throws a `BillingException`
with a typed code (see [Typed errors](#errors)):

- **Identity.** Nothing was identified (`notIdentified`), or the SDK's `appUserID` is not the id
  `identify()` bound (`identityMismatch`). A purchase attributed to another account is one the backend
  cannot give to the right customer.
- **Another store owns the subscription** (`managedElsewhere`). A subscription managed by Stripe, or
  by the other store, is not changed from here.
- **An active product this build cannot name** (`unmappedActiveProduct`). The account holds an active
  product of this store that is not in the offerings, so no change can be computed safely.

On Android a product change is passed to Play with the proration the context implies; the customer
sees Play's own sheet.

### <a name="errors"></a>Typed errors: `BillingException.code`

Switch on `BillingException.code`, never on `message`, which is prose that differs per rail and per
locale. The code is client-side only and never crosses the wire.

| `BillingErrorCode` | Meaning |
|--------------------|---------|
| `notConfigured` | no `public_sdk_key` in this build |
| `notIdentified` | no paying account identified before a purchase |
| `identityMismatch` | the SDK is bound to a different account than the one asking |
| `managedElsewhere` | another rail manages the subscription |
| `unmappedActiveProduct` | an active product is not in the offerings |
| `productUnavailable` | the rail has no product for the key |
| `pending` | the store has not settled it (parental approval, deferred payment); not a failure to retry |
| `receiptInUse` | the receipt belongs to another paying account |
| `alreadyOwned` | the customer already holds the product |
| `network` | the request or its answer never arrived |
| `store` | the store refused for a reason none of the above names |
| `unknown` | no cause named |

A customer dismissing the sheet is `false` from `purchase`, not an exception.

### <a name="store-identity"></a>Keeping the Store Identified

The id passed to `identify()` is what the rail's webhook attributes a purchase to, so the rail has
to be re-identified whenever the paying subject changes: on login, on a session restore, and on
every switch of the subject (a team switch, where teams pay). `StoreIdentitySync` owns the WHEN; you
supply the WHO:

```dart
// Who pays is your answer: a team here, a user elsewhere.
StoreIdentitySync.billableId = () => User.current.currentTeam?.id?.toString();
StoreIdentitySync.attach();

// A switch of the paying subject identifies explicitly once it succeeded,
// because the auth change it causes may still carry the previous subject.
if (await switchTeam(teamId)) {
  await StoreIdentitySync.syncNow();
}
```

- `attach()` listens to `Auth.stateNotifier` and syncs on every change; calling it twice listens once.
  `detach()` stops listening and forgets what was identified.
- A build without a store rail, and a session without a subject (`null` or an empty id), identify
  nothing. A signed-out session unbinds nothing either: the contract has no logout, and the next
  sign-in overwrites the binding.
- Syncs run one at a time in call order, and each reads the subject when its turn comes. A switch
  that lands while an identify is in flight identifies the newer subject after it, never alongside
  it, so the rail ends on the newer subject whatever order the vendor SDK finishes its calls in.
- The same id twice in a row identifies once, including two overlapping syncs. The guard resets when
  the id goes absent, so signing out and back in as the same subject identifies again.
- A `BillingException` from the rail is logged at error level and not thrown, since the login or
  switch that prompted the sync already succeeded; the next sync retries that id.
- `billableId` has no default. While it is unset nothing is identified, and one debug line says so.

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
