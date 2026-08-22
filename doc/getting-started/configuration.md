# Configuration

## Table of Contents

- <a name="toc-overview"></a>[Overview](#overview)
- <a name="toc-current-state"></a>[Current State: No Required Keys](#current-state)
- <a name="toc-why"></a>[Why the Rail Resolves Without Config](#why)
- <a name="toc-runtime"></a>[Runtime Config Access](#runtime)
- <a name="toc-future"></a>[Where a Future Key Would Land](#future)

---

## <a name="overview"></a>Overview

Every Magic plugin owns its own config root, merged into the framework's `ConfigRepository` at boot
time and read back through `Config.get(key)`. This package's root is `payments.*`, and
`PaymentsServiceProvider.boot()` is the only code that is meant to read under it: never
`magic_starter.*`, and never a key another plugin owns.

---

## <a name="current-state"></a>Current State: One Key

`payments.*` carries exactly one key. `payments:install` publishes it to
`lib/config/payments.dart` and registers the config factory in `Magic.init`:

```dart
Map<String, dynamic> get paymentsConfig => {
  'payments': {
    'driver': 'platform',
  },
};
```

| Key | Type | Default | Read by |
|-----|------|---------|---------|
| `payments.driver` | `String` | `'platform'` | `PaymentsServiceProvider.boot()` |

`'platform'` is the only value the package serves, and it means "resolve the driver from the build",
which is what the conditional-import factory does. The key exists so that choice is recorded rather
than implicit.

Any other value is refused by the CLI (`payments:configure --driver=x` exits 1) and reported by
`payments:doctor`. If one reaches the runtime anyway, the provider logs an error and wires the
platform driver regardless, because a config typo must not take an entitlement read offline.

> [!NOTE]
> A driver of your own is registered in code, not named here:
> `Payments.extend(PaymentsManager.webRole, () => MyRail())`. A config string cannot resolve to a
> factory, and it cannot change which files a build compiled in. See [Drivers](../basics/drivers.md).

---

## <a name="why"></a>Why the Rail Resolves Without Config

A sibling plugin like `magic_notifications` reads `notifications.push.driver` to decide which push
SDK to wire up, because more than one driver could serve the same platform. Magic Payments has a
narrower question: which RAIL can this build serve at all, and that answer is structural rather than
a preference. A web build has `dart.library.html`, a mobile or desktop build has `dart.library.io`,
and neither a config flag nor a runtime check changes which files were compiled in. So the platform
driver is wired by the package's own conditional-import factory in `boot()`, not by a config
lookup. See [Drivers](../basics/drivers.md) for how that factory works.

---

## <a name="runtime"></a>Runtime Config Access

If you do add a key under `payments.*` yourself (for a custom driver registered through
`PaymentsManager.extend`, for instance), read it the same way any Magic config value is read:

```dart
final String? value = Config.get<String>('payments.your_key');
```

`Config.get` returns `null` for an absent key or one of the wrong type; supply your own fallback with
`??`.

---

## <a name="future"></a>Where a Future Key Would Land

The store rail is the most likely source of the next key, once a driver for it ships: a rail that
talks to an external service needs an identifier the build cannot infer. When one is added it will
appear in the table above with its type, its default and the code path that reads it, because a
documented key nothing reads is worse than an undocumented one. Nothing else needs to be set today.

---

**Related**

- [Installation](https://magic.fluttersdk.com/packages/payments/getting-started/installation)
- [Service Provider](https://magic.fluttersdk.com/packages/payments/architecture/service-provider)
- [Rails](https://magic.fluttersdk.com/packages/payments/basics/rails)
