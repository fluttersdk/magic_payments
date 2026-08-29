# Magic Payments

Multi-rail billing for the [Magic Framework](https://github.com/fluttersdk/magic). One entitlement
contract over Stripe on the web and store in-app purchase on iOS and Android.

> [!NOTE]
> The public API is still settling ahead of `0.1.0`. Pin an exact version
> (`magic_payments: 0.0.2`) if you depend on it before then.

## Why it exists

A subscription can be sold by more than one rail, and each rail has its own vocabulary, its own idea
of when a period ends, and its own opinion about who may cancel. An app that talks to them directly
ends up with that vocabulary spread across its widgets.

Magic Payments puts one contract in front of them. A consumer asks two questions, what is this
customer entitled to and where do they manage it, and the answers are rail-neutral:

```dart
final entitlement = await Payments.currentEntitlement();

if (entitlement.subscribed) {
  // `manageVia` says which surface owns the subscription: our own billing
  // portal, the App Store, or Play. The caller never checks the platform.
  showManageButton(entitlement.manageVia, entitlement.manageUrl);
}
```

The rail that sold the subscription is the package's problem. The platform the app happens to be
running on is a different axis entirely, and conflating the two is the mistake this package exists to
prevent: a subscription bought on a phone is still managed in its store when the customer opens the
web app.

## What you get

Three contracts, and the split is the API. `BillingService` carries the five entitlement reads and is
honourable on every platform, because the backend is the authority on what a customer is entitled to.
The two rails are nullable, and a `null` rail is a build that cannot serve it:

| Role | Access | Where it exists |
|------|--------|-----------------|
| Reads | `Payments.billing` | Everywhere. Entitlement, plans, usage, invoices, payment method. |
| Web rail | `Payments.web` | Web builds. Hosted Stripe checkout, plan swap, cancel, customer portal. |
| Store rail | `Payments.store` | iOS and Android, through RevenueCat. |

A rail is CHECKED, never assumed. Asking whether it exists is what decides whether a purchase button
renders at all, rather than rendering one that fails when tapped.

## Installation

```yaml
dependencies:
  magic_payments: ^0.0.2
```

```bash
# Register the plugin's artisan provider with the app dispatcher (once)
dart run magic:artisan plugin:install magic_payments

# Publish lib/config/payments.dart and register the config factory
dart run magic:artisan payments:install
```

Then register the service provider in your app's config, as with any Magic plugin:

```dart
'providers': [
  // ...existing providers...
  (app) => PaymentsServiceProvider(app),
],
```

`dart run magic:artisan payments:doctor` reports which rails the build resolved and whether the store
rail has the key it needs.

## Documentation

Full documentation lives at
[magic.fluttersdk.com/packages/payments](https://magic.fluttersdk.com/packages/payments/getting-started/installation).

## License

MIT. See [LICENSE](LICENSE).
