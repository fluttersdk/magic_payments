# Payments Manager

## Table of Contents

- <a name="toc-singleton"></a>[Singleton Lifecycle](#singleton)
- <a name="toc-reads"></a>[The Five Reads](#reads)
- <a name="toc-rails"></a>[Rail Resolution: web and store](#rails)
- <a name="toc-extend"></a>[extend(): Overriding a Driver](#extend)
- <a name="toc-facade"></a>[Facade Delegation](#facade)

---

## <a name="singleton"></a>Singleton Lifecycle

`PaymentsManager` is a process-level singleton, the same shape as every other manager in this
ecosystem (`NotificationManager`, `SocialAuthManager`): a private constructor behind a `factory`
that always returns the same instance.

```dart
class PaymentsManager {
  static final PaymentsManager _instance = PaymentsManager._internal();

  factory PaymentsManager() => _instance;

  PaymentsManager._internal();
}
```

`Payments`, the facade, resolves the same instance, so state set through one is visible through the
other.

---

## <a name="reads"></a>The Five Reads

The manager holds the `BillingService` this build resolved (through the conditional-import factory,
see [Drivers](../basics/drivers.md)) and answers the five reads on it. `Payments` forwards each one
as an explicit static method of the same name:

```dart
final entitlement = await Payments.currentEntitlement();
final plans = await Payments.getPlans();
final usage = await Payments.getUsage();
final invoices = await Payments.getInvoices();
final method = await Payments.getPaymentMethod();
```

None of the five ever throws for want of a platform: the manager always has SOME `BillingService`,
because every arm of the factory returns a real one (never `null`) for the reads.

---

## <a name="rails"></a>Rail Resolution: web and store

The manager also exposes the two RAILS, reading them from the same factory rather than from a
platform check:

```dart
WebBillingService? get web;
StoreBillingService? get store;
```

`Payments.web` and `Payments.store` forward these directly. Either can be `null`, and that is the
whole availability mechanism: a caller checks the rail before it renders an affordance, instead of
rendering one and catching a refusal.

```dart
final web = Payments.web;
if (web != null) {
  await web.checkout(
    plan: 'pro',
    cycle: BillingCycle.annual,
    successUrl: '...',
    cancelUrl: '...',
  );
}
```

There is no second way to ask the same question anywhere in the package: no `isWeb` getter, no
`kIsWeb` check inside the manager. A second way to ask would eventually disagree with the first, and
the contract's own absence is already the answer. See [Rails](../basics/rails.md) for what each
rail's contract promises and, for the store rail, what it does not.

---

## <a name="extend"></a>extend(): Overriding a Driver

The manager resolves drivers through an explicit registry plus a factory map, because there is no
reflection here to autowire one, and exposes an `extend(name, factory)` hook that registers a custom
driver and clears any cached instance under that name so the next resolution builds the new one.
This mirrors `SocialAuthManager.extend` in `magic_social_auth`, the sibling to read for the exact
pattern.

```dart
Payments.manager.extend('sandbox', (config) => SandboxBillingDriver(config));
```

This is the seam a test uses to stand in for a driver's behaviour without mocking a third-party SDK,
and the one a future store implementation would let a consumer swap.

---

## <a name="facade"></a>Facade Delegation

`Payments` carries no logic of its own; every member is a forwarder to the manager, the same
convention `Notify` and `SocialAuth` follow:

```dart
class Payments {
  Payments._();

  static PaymentsManager get manager => PaymentsManager();

  static Future<BillingEntitlement> currentEntitlement() =>
      manager.currentEntitlement();

  // ... the remaining reads, `web`, `store` and `extend` follow the same shape.
}
```

Reaching for `Payments.manager` directly is how a caller gets at anything the facade has not (yet)
forwarded.

---

**Related**

- [Service Provider](https://magic.fluttersdk.com/packages/payments/architecture/service-provider)
- [Rails](https://magic.fluttersdk.com/packages/payments/basics/rails)
- [Drivers](https://magic.fluttersdk.com/packages/payments/basics/drivers)
