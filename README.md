# Magic Payments

Multi-rail billing for the [Magic Framework](https://github.com/fluttersdk/magic). One entitlement
contract over Stripe on the web and store in-app purchase on iOS and Android.

> [!WARNING]
> `0.0.1` is a scaffold. The public API is not implemented yet and the exports are empty. Pin an
> exact version if you depend on this before `0.1.0`.

## Why it exists

A subscription can be sold by more than one rail, and each rail has its own vocabulary, its own idea
of when a period ends, and its own opinion about who may cancel. An app that talks to them directly
ends up with that vocabulary spread across its widgets.

Magic Payments puts one contract in front of them. A consumer asks two questions, what is this
customer entitled to and where do they manage it, and the answers are rail-neutral:

```dart
final entitlement = await Payments.entitlement();

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

## Installation

```yaml
dependencies:
  magic_payments: ^0.0.1
```

Then register the service provider in your app's config, as with any Magic plugin.

## Documentation

Full documentation lives at
[magic.fluttersdk.com/packages/payments](https://magic.fluttersdk.com/packages/payments/getting-started/installation).

## License

MIT. See [LICENSE](LICENSE).
