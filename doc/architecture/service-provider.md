# Service Provider

## Table of Contents

- <a name="toc-overview"></a>[Overview](#overview)
- <a name="toc-two-phase"></a>[Two-Phase Bootstrap Pattern](#two-phase)
- <a name="toc-register"></a>[register(): IoC Binding](#register)
- <a name="toc-boot"></a>[boot(): Wiring the Platform Driver](#boot)
- <a name="toc-config"></a>[Config Root](#config)
- <a name="toc-registration"></a>[Registering the Provider](#registration)

---

## <a name="overview"></a>Overview

`PaymentsServiceProvider` is the bootstrap entry point for the plugin. It extends the Magic
Framework's `ServiceProvider`, the same base class every plugin in this ecosystem extends, and is
responsible for binding `PaymentsManager` into the IoC container and wiring the platform-appropriate
driver into it.

```dart
class PaymentsServiceProvider extends ServiceProvider {
  PaymentsServiceProvider(super.app);

  @override
  void register() { /* ... */ }

  @override
  Future<void> boot() async { /* ... */ }
}
```

---

## <a name="two-phase"></a>Two-Phase Bootstrap Pattern

| Phase | Method | Timing | Purpose |
|-------|--------|--------|---------|
| 1 | `register()` | Synchronous, early | Bind services into the IoC container |
| 2 | `boot()` | Async, after every provider has registered | Wire up anything that depends on another binding |

`register()` runs for every provider before `boot()` runs for any of them, so by the time this
provider's `boot()` runs, whatever `Config` and `Http` bindings the framework itself provides are
already in place.

---

## <a name="register"></a>register(): IoC Binding

`register()` does exactly one thing: bind the `PaymentsManager` singleton under the `'payments'`
key, and nothing else. No config read and no driver wiring happens here, both of which belong to
`boot()`.

```dart
app.singleton('payments', () => PaymentsManager());
```

After registration, any code in the app can resolve the manager by key:

```dart
final manager = app.make<PaymentsManager>('payments');
```

---

## <a name="boot"></a>boot(): Wiring the Platform Driver

`boot()` calls the package's conditional-import factory (`createBillingService()`,
`createWebBillingService()`, `createStoreBillingService()`) and hands the results to the manager, so
`Payments.web` and `Payments.store` resolve to a real rail or to `null` without either the provider
or the manager asking `kIsWeb` or `Platform.is`. See [Drivers](../basics/drivers.md) for what each
arm of that factory returns.

`boot()` also reads whatever this package's config root, `payments.*`, defines. As of this version
that is nothing (see [Configuration](../getting-started/configuration.md)), so no config read is
required for the platform driver to wire up correctly.

---

## <a name="config"></a>Config Root

The provider reads only under `payments.*`, never under `magic_starter.*` or any other plugin's
root. This is a hard boundary rather than a convention worth bending: a plugin reading another
plugin's config key would make the two impossible to reason about independently, and impossible to
ship separately.

---

## <a name="registration"></a>Registering the Provider

```dart
import 'package:magic_payments/magic_payments.dart';

final providers = [
  // ... other framework providers first
  (app) => PaymentsServiceProvider(app),
];
```

Register it after any provider it depends on, `ConfigServiceProvider` and `HttpServiceProvider` in
particular, since `boot()` needs both to be available.

---

**Related**

- [Payments Manager](https://magic.fluttersdk.com/packages/payments/architecture/payments-manager)
- [Configuration](https://magic.fluttersdk.com/packages/payments/getting-started/configuration)
- [Drivers](https://magic.fluttersdk.com/packages/payments/basics/drivers)
