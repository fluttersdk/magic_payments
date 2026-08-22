# Installation

## Table of Contents

- <a name="toc-overview"></a>[Overview](#overview)
- <a name="toc-pubdev"></a>[pub.dev Dependency Setup](#pubdev)
- <a name="toc-service-provider"></a>[Service Provider Registration](#service-provider)
- <a name="toc-main-dart"></a>[main.dart](#main-dart)
- <a name="toc-platforms"></a>[Which Platform Gets Which Rail](#platforms)
- <a name="toc-cli"></a>[CLI Setup](#cli)
- <a name="toc-next-steps"></a>[Next Steps](#next-steps)

---

## <a name="overview"></a>Overview

Magic Payments is a multi-rail billing plugin for the Magic Framework. It puts one entitlement
contract in front of two payment rails: Stripe on the web, and the platform's own in-app purchase
system on iOS and Android. A consuming app asks two questions, what is this customer entitled to and
where do they manage it, and the answers are rail-neutral.

> [!WARNING]
> The store rail (`StoreBillingService`) is declared in this package but has no implementation yet.
> `createStoreBillingService()` returns `null` on every build, so no app built against this version
> can offer a mobile purchase. The five reads (`BillingService`) and the web rail
> (`WebBillingService`) are real and work today. See [Rails](../basics/rails.md).

---

## <a name="pubdev"></a>pub.dev Dependency Setup

Add the package to your `pubspec.yaml`:

```yaml
dependencies:
  magic_payments: ^0.0.1
```

Then fetch dependencies:

```bash
flutter pub get
```

> [!NOTE]
> The public API is still settling ahead of a `0.1.0` release. Pin an exact version
> (`magic_payments: 0.0.1`) if you depend on it before then, the same caution the package's own
> README carries.

---

## <a name="service-provider"></a>Service Provider Registration

Register `PaymentsServiceProvider` in your app's provider list, the same way as any other Magic
plugin:

```dart
import 'package:magic_payments/magic_payments.dart';

final providers = [
  // ... other providers
  (app) => PaymentsServiceProvider(app),
];
```

`PaymentsServiceProvider` runs the usual two-phase boot: `register()` binds one string-keyed
singleton under `'payments'`, and `boot()` wires the platform driver through the package's
conditional-import factory. Neither phase requires a config file to exist for the five reads or the
web rail to work. See [Service Provider](../architecture/service-provider.md) for the full sequence.

---

## <a name="main-dart"></a>main.dart

Register the published config the same way every other plugin config is registered. `payments:install`
does this for you; the shape is here so you can check its work:

```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Magic.init(
    configFactories: [
      () => appConfig,
      () => paymentsConfig,
    ],
  );

  runApp(MyApp());
}
```

The five READS and the web rail boot without a single key, so a web-only app whose factory is missing
still works and `payments:doctor` is the only thing that notices. The STORE rail is different: it
reads `payments.revenuecat.public_sdk_key` the first time it needs the SDK, so on iOS and Android an
unregistered factory turns into a `BillingException` under the customer's finger on the purchase
sheet.

See [Configuration](./configuration.md) for every key and for why the store rail's key is resolved
per platform.

---

## <a name="platforms"></a>Which Platform Gets Which Rail

| Contract | Web | iOS / Android | Reason |
|----------|-----|----------------|--------|
| `BillingService` (5 reads) | Yes | Yes | The backend is the authority on an entitlement whatever rail sold it, so a read never has to refuse a platform. |
| `WebBillingService` (checkout, swap, cancel, openPortal) | Yes | No (`null`) | The web rail bills a card directly through a hosted checkout and portal. |
| `StoreBillingService` (identify, purchase, restore, openStoreManagement) | No (`null`) | Declared, not implemented (`null`) | StoreKit and Play Billing take the money; the driver behind this contract has not shipped yet. |

Which rail is present is decided by the package's own conditional-import factory, not by
`kIsWeb` or `Platform.is`. See [Rails](../basics/rails.md) and [Drivers](../basics/drivers.md).

---

## <a name="cli"></a>CLI Setup

Magic Payments ships three CLI commands on `fluttersdk_artisan`: `install`, `configure` and
`doctor`.

```bash
dart run magic_payments doctor
```

The exact flags each command accepts are still settling alongside the rest of the public API in
this version; run a command with `--help` for the authoritative set, and see
[CLI Reference](../basics/cli.md) for what each command is for.

---

## <a name="next-steps"></a>Next Steps

1. Read [Configuration](./configuration.md) for the `payments.*` namespace.
2. Read [Rails](../basics/rails.md), especially the section on entitlement authority, before wiring
   a purchase button.
3. Read [Drivers](../basics/drivers.md) to see how a build resolves the driver it can serve.

---

**Related**

- [Configuration](https://magic.fluttersdk.com/packages/payments/getting-started/configuration)
- [Rails](https://magic.fluttersdk.com/packages/payments/basics/rails)
- [CLI Reference](https://magic.fluttersdk.com/packages/payments/basics/cli)
