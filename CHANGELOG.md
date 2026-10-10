# Changelog

## [Unreleased]

### Added

- **`StoreProductOffer.introEligible`** (default `false`) is `true` only when the store says THIS customer may take the introductory offer, so a caller shows intro copy ("free for 14 days, then ...") only when it is `true`. On the App Store `products()` asks the SDK once for the store product ids that carry an intro price and only a definite `eligible` answer counts (unknown and ineligible stay `false`); on Play it skips the read and treats a present intro price as eligible, since Play only offers what the account may take (not verified against a real account). A failed eligibility read is logged and leaves every offer `false`. (`lib/src/models/store_product_offer.dart`, `lib/src/drivers/revenuecat_store_service.dart`, `doc/basics/rails.md`)

## 0.0.8

### Added

- **`payments:doctor --json` prints one object for an agent.** `{ok, checks: [{id, status, message, fix?}]}` with `status` one of `ok`, `warn` or `error`, the ids `dependency_declared`, `dependency_resolved`, `config_published`, `config_valid`, `provider_registered`, `config_factory_wired` and `store_rail_key`, and the same exit code as the human report. A key is only ever `present`, `absent` or `blank`, never its value. `payments_doctor` stays the only MCP tool. (`lib/src/cli/commands/doctor_command.dart`, `doc/basics/cli.md`)
- **`StoreBillingService.products(List<String>)` reads the store's own prices**, keyed by catalogue key: `StoreProductOffer` carries the localized `priceString`, `currencyCode`, `price`, an ISO `subscriptionPeriod` and the intro-price fields. A key the store has no product for is absent from the map.
- **`StoreBillingService.store` answers `ManageVia.appStore` or `ManageVia.playStore`**, and **`PurchaseContext`** hands a purchase the catalogue's tier order so the rail can tell an upgrade from a downgrade. On Play the replacement mode is: same subscription, longer period: `chargeFullPrice`; same subscription, same or shorter period: `withoutProration`; higher tier: `chargeProratedPrice` when the price per unit of time rises, else `chargeFullPrice`; same or lower tier: `deferred`. (`lib/src/drivers/revenuecat_store_service.dart`, `doc/basics/rails.md`)
- **`PurchaseContext.tierOfStoreProduct`** maps a store product id to its tier (default empty), built from the plan rows' `store_ids`, so a grandfathered product no offering sells any more can still be ranked. A Play id matches in full first, then by its bare subscription id. An upgrade from a grandfathered Play product is charged in full (its price is unknown); a base-plan switch from one is refused as `unmappedActiveProduct` (its period is unknown). The App Store rail no longer requires a held product to be in an offering. (`lib/src/models/purchase_context.dart`)
- **`StoreBillingService.lastChangeTiming` and `StoreChangeTiming` (`immediate`, `atRenewal`)** tell a caller whether the last purchase that changed a held subscription takes effect now or at renewal, without changing `purchase`'s `Future<bool>`. Play derives it from the replacement mode (`deferred` is `atRenewal`); the App Store from Apple's rules (a higher level now, a lower level or another duration of the same level at renewal). `null` when nothing changed or the timing cannot be ranked. (`lib/src/contracts/store_billing_service.dart`, `lib/src/enums/store_change_timing.dart`)
- **A one-off store product is bought beside a held subscription.** A package whose store product is not a subscription (the SDK's `productCategory`, or no billing period where it reports none) skips the cross-store refusal and the Play product change: credits or an unlock never replace or duplicate a subscription, on either store. (`lib/src/drivers/revenuecat_store_service.dart`)
- **A RevenueCat promotional grant (`rc_promo_...`) is ignored** by the cross-store and held-product checks: no store bills it, so it no longer refuses a purchase as `managedElsewhere` or `unmappedActiveProduct`.
- **The web rail maps the producer's `product_not_sellable` 422** from `checkout` and `swap` to `BillingErrorCode.productUnavailable`, keeping the producer's message. (`lib/src/drivers/billing_service_web.dart`)
- **`BillingException.code`, a typed `BillingErrorCode`**: `notConfigured`, `notIdentified`, `identityMismatch`, `managedElsewhere`, `unmappedActiveProduct`, `productUnavailable`, `pending`, `receiptInUse`, `alreadyOwned`, `network`, `store`, `unknown`. Branch on the code, never on `message`.
- **`ProductType`** (`subscription`, `consumable`, `non_consumable`, `physical`), and `BillingEntitlement.productKey` (wire `product`), `owned`, `balances` and `allowances`.
- **The store rail refuses instead of guessing.** `purchase` and `restore` refuse unless the SDK's `appUserID` equals the id `identify()` bound (`notIdentified`, `identityMismatch`); a subscription purchase is refused when the other store sells a subscription the customer holds (`managedElsewhere`; a Stripe subscription is not visible to the store rail, so the caller gates on `BillingEntitlement.manageVia`) or an active Play product cannot be ranked (`unmappedActiveProduct`). (`doc/basics/rails.md`, `doc/getting-started/configuration.md`)

### Changed

- **BREAKING: a purchase names a catalogue product key, not a tier and a cycle.** `StoreBillingService.purchase({required String plan})` is `purchase(String productKey, {PurchaseContext? context})`; `WebBillingService.checkout({plan, cycle, ...})` is `checkout({required String productKey, successUrl, cancelUrl})` and `swap({plan, cycle})` is `swap({required String productKey})`, which POSTs `{product: key}`. Migration: pass the key your catalogue uses for that tier and cycle (`'pro'` plus `BillingCycle.annual` becomes `'pro_annual'`); on the store rail the key must equal a RevenueCat package identifier.
- **BREAKING: `StoreBillingService` gained `products()` and the `store` and `lastChangeTiming` getters.** A class that implements it must add all three; a subclass of `RevenueCatStoreService` inherits them.
- **`StoreIdentitySync.recordBinding` is `@internal`.** The rail driver is its only caller; an app that recorded a binding by hand would make the sync skip the identify that fixes it.
- **`payments:doctor` builds its human and `--json` reports from one list of checks**, so a check cannot be added to one mode and missed by the other. Both outputs are unchanged. (`lib/src/cli/commands/doctor_command.dart`)
- **BREAKING: a failed billing call carries a typed `code`.** Code that matched on a `BillingException` message must switch on `BillingException.code`; a throw site that names no cause answers `BillingErrorCode.unknown`.
- **BREAKING: `BillingEntitlement.aiAnalysisTrialsRemaining` is removed.** It was one vendor's allowance on a shared model. Read it from `BillingEntitlement.allowances` or `balances`, which carry whatever the backend sends.
- **`purchases_flutter` is `^10.15.1`.** (`pubspec.yaml`)
- **Every sibling floor names this batch's release.** `magic` moves `^0.0.24` to `^0.0.27` and `fluttersdk_artisan` `^0.0.17` to `^0.0.19`. The old ranges already admitted the new versions, so a fresh `pub get` resolves nothing differently; what changes is that the floors name the releases this package is verified against. None of magic 0.0.25 to 0.0.27 or artisan 0.0.18 and 0.0.19 is breaking; artisan 0.0.19 widens its `xml` constraint to admit 7.x, which a consumer now inherits. (`pubspec.yaml`, `test/pubspec_floors_test.dart`)

### Fixed

- **The documentation describes the store rail that ships.** `doc/basics/rails.md` and the installation guide's platform table called the App Store and Play rails "Declared, not implemented"; `RevenueCatStoreService` implements both and `Payments.store` is non-null on iOS and Android. The rails guide also said the store rail refuses a subscription Stripe manages: `managedElsewhere` is raised only for an active product the OTHER store sells, and a Stripe subscription is not among the products RevenueCat reports, so the guide now says to gate the store's purchase affordance on `BillingEntitlement.manageVia`. The `BillingErrorCode.managedElsewhere` doc comment said the same wrong thing and is corrected. (`doc/basics/rails.md`, `doc/getting-started/installation.md`, `lib/src/enums/billing_error_code.dart`)
- **The bug report form's version placeholders name the right packages.** The Magic Payments field still read `0.0.1`, and the previous release had stamped its own version into the Magic Framework field. (`.github/ISSUE_TEMPLATE/bug_report.yml`)

## 0.0.7

### Changed

- **Every sibling floor names this batch's release.** `magic` moves `^0.0.22` to `^0.0.24` and `fluttersdk_artisan` `^0.0.16` to `^0.0.17`. The old ranges already admitted the new versions, so a fresh `pub get` resolves nothing differently; what changes is that the floors name the releases this package is verified against. magic 0.0.24 removes `MagicController.onRefreshUI` (BREAKING); this package calls it nowhere in `lib/` or `test/`, so nothing here moves with it. `test/pubspec_floors_test.dart` asserts the new floors. (`pubspec.yaml`, `test/pubspec_floors_test.dart`)

## 0.0.6

### Fixed

- **An idle `StoreIdentitySync.syncNow()` runs in the caller's zone instead of waiting on another zone's microtask queue.** 0.0.5 chained every sync onto a stored completed future, and a completed future runs its listeners in the zone it was created in: a sync started inside a widget test's fake-async zone (a team switch in `magic_starter`, which awaits the sync) never ran and the switch never returned, once an earlier test had created that future. An idle sync now starts in the caller's own turn; only a sync queued behind one in flight chains, and a `detach()` during an identify still keeps the next sync behind it. (`lib/src/support/store_identity_sync.dart`)

## 0.0.5

### Added

- **`StoreIdentitySync` keeps the store rail identified as the paying subject.** Set `StoreIdentitySync.billableId` to a resolver answering the subject's id (a team or a user; the consumer decides), call `attach()` once, and every `Auth.stateNotifier` change identifies `Payments.store` with it; `syncNow()` identifies on demand (after a switch of the paying subject) and `detach()` stops. It skips a build without a store rail and a session without a subject, runs syncs one at a time in call order, each reading the subject when its turn comes (so a switch during an identify leaves the rail on the newer subject whatever order the vendor SDK finishes in), identifies a repeated id once, identifies again after a sign-out, and logs a `BillingException` from the rail at error level instead of throwing, retrying that id on the next sync. An unset resolver identifies nothing and logs once at debug level. (`lib/src/support/store_identity_sync.dart`, `doc/basics/rails.md`)

### Changed

- **Every sibling floor names this batch's release.** `magic` moves `^0.0.16` to `^0.0.22`; `fluttersdk_artisan` stays at `^0.0.16`, still the newest. The old ranges already admitted the new versions, so a fresh `pub get` resolves nothing differently; what changes is that the floors name the release this package is verified against. `StoreIdentitySync` needs nothing newer than 0.0.16; of magic 0.0.22's BREAKING changes, only `Auth.fake()` dispatching through the real `Event` facade reaches it, from one test, and the suite passes unchanged. (`pubspec.yaml`, `test/pubspec_floors_test.dart`)

## 0.0.4

Dependency floors only; the package code is identical to 0.0.3.

### Changed

- **Every sibling floor names this batch's release.** `magic` moves `^0.0.15` to `^0.0.16`; `fluttersdk_artisan` stays at `^0.0.16`, still the newest. The old ranges already admitted the new versions, so a fresh `pub get` resolves nothing differently; what changes is that the floors name the releases this package is verified against. magic 0.0.16 widens `file_picker` to admit 13, where `PlatformFile.length()` answers null for an unreadable file; this package does not call `Pick`. `test/pubspec_floors_test.dart` pins the new magic floor. (`pubspec.yaml`, `test/pubspec_floors_test.dart`, `README.md`, `doc/getting-started/installation.md`)

## 0.0.3

Dependency floors only; the package code is identical to 0.0.2.

### Changed

- **Every sibling floor names this batch's release.** `magic` moves `^0.0.6` to `^0.0.15` and `fluttersdk_artisan` `^0.0.13` to `^0.0.16`. The old ranges already admitted the new versions, so a fresh `pub get` resolves nothing differently; what changes is that the floors name the releases this package is verified against. magic 0.0.15 is breaking in its database layer (a migration may no longer manage its own transaction, and `DB.transaction` refuses a callback that closes the transaction itself); nothing in this package calls either, so no code here changes, but an app below magic 0.0.15 no longer resolves this release. (`pubspec.yaml`, `test/pubspec_floors_test.dart`)

## 0.0.2

Documentation only; the package code is identical to 0.0.1.

### Changed

- **The README described a package that no longer existed.** It opened with a
  warning that `0.0.1` was a scaffold whose "public API is not implemented yet"
  and whose "exports are empty", which was true of the first commit and of
  nothing since: the barrels carry the three contracts, the drivers behind them,
  the entitlement model and the five enums, and 206 tests run against them. That
  warning was the first thing anyone read on pub.dev, so the package described
  itself as unusable while being usable. It now carries the ordinary pre-`0.1.0`
  caution instead.
- **The one code sample in the README called a method that does not exist.**
  `Payments.entitlement()` is `Payments.currentEntitlement()`. A reader copying
  the snippet did not compile.
- The README gained the three-role table (which rail exists where, and why a
  rail is checked rather than assumed) and the actual install commands, rather
  than a sentence pointing at "your app's config".

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

- **`PlanStatus.isDunning`, the question no field on the wire answered.** Both
  `pastDue` and `grace` still GRANT, so a screen reading `subscribed` alone
  cannot tell a paying customer from one whose card has just bounced, and it
  showed them the same healthy renewal sentence. Measured on a live Stripe test
  clock: a failed renewal put the subscription in `past_due` and the billing
  page still read "renews Nov 24, 2026" with no warning anywhere.

  Deliberately NOT a `grants()` mirror, which this enum does not carry: whether
  a status entitles is the producer's answer and arrives as
  `BillingEntitlement.subscribed`. This asks a different question, is the
  customer's money late, and a client that re-derived entitlement from the
  status word would be answering the first one twice.

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
