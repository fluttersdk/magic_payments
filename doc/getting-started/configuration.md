# Configuration

## Table of Contents

- <a name="toc-overview"></a>[Overview](#overview)
- <a name="toc-keys"></a>[The Keys](#keys)
- <a name="toc-store"></a>[The Store Rail's Key, Per Platform](#store)
- <a name="toc-why"></a>[Why the Rail Itself Is Not Configured](#why)
- <a name="toc-runtime"></a>[Runtime Config Access](#runtime)

---

## <a name="overview"></a>Overview

Every Magic plugin owns its own config root, merged into the framework's `ConfigRepository` at boot
time and read back through `Config.get(key)`. This package's root is `payments.*`, and
`PaymentsServiceProvider.boot()` plus the store driver are the only code meant to read under it:
never `magic_starter.*`, and never a key another plugin owns.

---

## <a name="keys"></a>The Keys

`payments:install` publishes them to `lib/config/payments.dart` and registers the config factory in
`Magic.init`:

```dart
import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform;

Map<String, dynamic> get paymentsConfig => {
  'payments': {
    'driver': 'platform',
    'revenuecat': {
      'public_sdk_key': switch (defaultTargetPlatform) {
        TargetPlatform.iOS => 'appl_your_ios_key',
        TargetPlatform.android => 'goog_your_android_key',
        _ => '',
      },
      'subject_label': 'team',
    },
  },
};
```

| Key | Type | Default | Read by |
|-----|------|---------|---------|
| `payments.driver` | `String` | `'platform'` | `PaymentsServiceProvider.boot()` |
| `payments.revenuecat.public_sdk_key` | `String` | none, REQUIRED on iOS and Android | `RevenueCatStoreService.ensureConfigured()` |
| `payments.revenuecat.subject_label` | `String` | `'team'` | `RevenueCatStoreService`, in log lines only |

`payments.driver` is `'platform'`, the only value the package serves, and it means "resolve the
driver from the build", which is what the conditional-import factory does. The key exists so that
choice is recorded rather than implicit. Any other value is refused by the CLI
(`payments:configure --driver=x` exits 1) and reported by `payments:doctor`. If one reaches the
runtime anyway, the provider logs an error and wires the platform driver regardless, because a config
typo must not take an entitlement read offline.

`payments.revenuecat.*` is read only by the store rail, so a web-only or desktop-only app needs
none of it. `payments:doctor` reports what it finds under `public_sdk_key` without failing on it, for
exactly that reason: it runs on your laptop and cannot know which build you will ship.

> [!WARNING]
> `public_sdk_key` is the PUBLIC key. It ships inside the app bundle by design. Your project's
> SECRET key authenticates your SERVER to the RevenueCat API and must never appear in this file or
> anywhere else in a client build.

> [!NOTE]
> A driver of your own is registered in code, not named here:
> `Payments.extend(PaymentsManager.webRole, () => MyRail())`. A config string cannot resolve to a
> factory, and it cannot change which files a build compiled in. See [Drivers](../basics/drivers.md).

---

## <a name="store"></a>The Store Rail's Key, Per Platform

RevenueCat issues a **separate public SDK key for each store**: `appl_...` for the App Store app and
`goog_...` for the Play app. One shared string cannot serve both, and this is the reason the stub
resolves the value instead of stating it: `lib/config/payments.dart` is Dart, not JSON, so an
expression is as valid there as a literal.

`defaultTargetPlatform` rather than `Platform.isIOS`, because `dart:io` is unavailable on web and
this config is compiled into every build, web included. The `_` arm covers every platform that has no
store, and an empty string there is correct rather than lazy: nothing outside iOS and Android reads
the key.

A blank or absent value is refused at purchase time rather than silently. `ensureConfigured()` logs
and throws a `BillingException` naming the missing key, so the failure points at the config instead
of surfacing as an SDK error far from its cause. Note that `Payments.store` is still non-null on those
platforms, because whether a device HAS a store and whether you have configured it are two different
questions; the first is what the null check answers.

---

## <a name="why"></a>Why the Rail Itself Is Not Configured

A sibling plugin like `magic_notifications` reads `notifications.push.driver` to decide which push
SDK to wire up, because more than one driver could serve the same platform. Which RAIL a build can
serve is a narrower question, and structural rather than a preference: a web build has
`dart.library.html`, a mobile or desktop build has `dart.library.io`, and neither a config flag nor a
runtime check changes which files were compiled in. So the platform driver is wired by the package's
own conditional-import factory in `boot()`, not by a config lookup.

A key claiming to enable or disable Stripe or a store would be a second answer to a question the
import graph already settles, and two answers eventually disagree. Credentials are the opposite case:
no import can supply them, which is why they do live here. See [Drivers](../basics/drivers.md) for
how the factory decides, including why the io arm asks one runtime question of its own.

---

## <a name="runtime"></a>Runtime Config Access

If you add a key under `payments.*` yourself (for a custom driver registered through
`PaymentsManager.extend`, for instance), read it the same way any Magic config value is read:

```dart
final String? value = Config.get<String>('payments.your_key');
```

`Config.get` returns `null` for an absent key or one of the wrong type; supply your own fallback with
`??`. The store driver reads its key exactly this way, then trims it and refuses an empty result.

---

**Related**

- [Installation](https://magic.fluttersdk.com/packages/payments/getting-started/installation)
- [Service Provider](https://magic.fluttersdk.com/packages/payments/architecture/service-provider)
- [Rails](https://magic.fluttersdk.com/packages/payments/basics/rails)
