# Changelog

## 0.0.1

First release of the package. Everything below is new, so this entry describes
the shape rather than a diff.

### Added

- **Billing for a Magic app over more than one rail, behind three contracts
  instead of one.** `BillingService` carries the five entitlement READS, which
  are honourable on every platform because the backend is the authority on an
  entitlement no matter which rail sold the subscription. `WebBillingService`
  carries the four web writes (checkout, swap, cancel, portal).
  `StoreBillingService` carries the four store methods (identify, purchase,
  restore, openStoreManagement). Nine methods in, nine out, none dropped.

  The split is the point. A single interface forces a build that cannot serve a
  method to declare it anyway, so the shape it replaces threw
  `UnsupportedPlatformException` from four methods on mobile and a billing screen
  rendered an Upgrade button whose only behaviour was to fail. A caller now asks
  whether a rail EXISTS (`Payments.store != null`) and does not render the
  affordance, instead of rendering one and catching a refusal.

- **One compile-time platform seam, and exactly one runtime device check.** The
  drivers resolve through a three-arm conditional import (a stub default, a web
  arm, an io arm), each arm exposing the same three factory functions because a
  conditional import resolves a whole FILE. The io arm asks one runtime question
  of its own, and it is not a smell: its guard is also satisfied on macOS,
  Windows and Linux, none of which has StoreKit or Play Billing, so "which rails
  can this BUILD serve" and "does this DEVICE have a store" are two different
  questions with one mechanism each. Nothing above the factory branches on a
  platform.

- **A RevenueCat store driver**, `RevenueCatStoreService`, on `purchases_flutter`.
  It reads one config key, `payments.revenuecat.public_sdk_key`, and refuses a
  blank one at purchase time by logging and throwing rather than letting the
  SDK's own failure surface far from its cause. RevenueCat issues a separate
  public key per store, and `lib/config/payments.dart` is Dart rather than JSON,
  so the published stub resolves it with a `switch (defaultTargetPlatform)`.

- **`PaymentsManager`, the `Payments` facade and a service provider.** The
  manager holds one resolved instance per role and `extend()` swaps any of them,
  which is how a consumer replaces the store rail with a mediator this package
  does not ship, and how a test stands in for a driver without mocking a
  third-party SDK.

- **A CLI on `fluttersdk_artisan`**: `payments:install`, `payments:configure` and
  `payments:doctor`, in a `lib/cli.dart` entry point separate from the runtime
  library so an app that never runs a command does not carry the command tree.
  Only `doctor` is exposed as an MCP tool, because the other two mutate a
  consumer's files.

  `doctor` reports the store rail's key as `absent`, `blank` or `declared`
  WITHOUT failing on it. A web-only or desktop-only app is correct without the
  key, so failing would turn a sound project red; but the driver throws under a
  customer's finger when it is missing, and passing in silence was measured on a
  real consumer and was worse. It reports, with the consequence attached.

- **`PaymentMethod.available`, so a consumer stops guessing why a card is
  missing.** Reading a card is the one billing call that dials the rail live, so
  the producer soft-fails a rail outage into a 200 with every field null, which
  is byte-identical to a customer who genuinely has no card. The field is the
  producer's own answer to which of the two it was: `false` means the rail could
  not be asked, `true` with a null `last4` means there is genuinely no card.
  It decodes as `bool?` and an ABSENT key is null, never false, because a
  backend too old to send it must not be reported as a rail that is down.

- **`BillingCycle`, because a tier is not a price.** A vendor selling `pro` at a
  monthly rate and again at a discounted annual rate has one tier and two
  prices, and three places have to agree which is in play: the catalogue shows a
  figure, the checkout charges one, the renewal line names one. With no cycle on
  the wire those answers come from three sources and disagree. Measured on a
  consumer app against a live Stripe test account: the screen offered "Annual,
  save ~15%" at $29/mo and Stripe charged $34.00 monthly, with the invoice and
  the renewal date siding with Stripe.

  So `WebBillingService.checkout` and `swap` both take a REQUIRED `cycle`, with
  no default. A default would be the same defect wearing a type: the caller
  showing an annual figure has to say annual, and the compiler is what makes
  every call site say which. `BillingEntitlement.cycle` reports what the
  customer actually bought, resolved server-side from the price their
  subscription sits on, which is a different fact from whichever column a
  catalogue toggle happens to be displaying.

  It is the ONE vocabulary in this package with no fallback member:
  `BillingCycle.fromWire` answers `null` rather than picking a side. Every other
  enum here degrades to a `none` case because "no rail has said" is a state it
  can express; monthly and annual are the only two cycles there are, so a
  default is a claim about what somebody is being charged. Null means unknown
  and a caller has to render it as unknown.

- **Seven documentation pages** under `doc/`, covering installation,
  configuration, the rails, the drivers, the manager, the service provider and
  the CLI.

### Notes for anyone reading the source

- The five reads live in one place, `BillingReadsOverHttp`, mixed into both the
  web and io arms. They were duplicated byte for byte until a review found them,
  and the duplication was invisible to every gate this package has: only ONE arm
  compiles per target, so no analyze run and no passing test could ever observe
  the two copies disagreeing. `test/drivers/billing_reads_over_http_test.dart`
  asserts that neither arm declares a read of its own, which is the part that
  survives a future refactor.

- Neither store rail has processed a transaction. No RevenueCat project or store
  product exists yet, so the store path is exercised by tests and by nothing
  else. Treat it as code-complete and unproven.
