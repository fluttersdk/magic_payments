import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic/magic.dart';
// The barrel supplies `BillingException` and the `StoreBillingService` contract;
// the driver and its factory are internal, so both are imported directly. The
// SDK is imported with a `show` list because it is only ever used to BUILD the
// value objects the seams hand over, never to reach a channel: nothing in this
// file talks to RevenueCat.
import 'package:magic_payments/magic_payments.dart';
import 'package:magic_payments/src/drivers/revenuecat_store_service.dart';
import 'package:magic_payments/src/drivers/store_billing_service_factory.dart';
import 'package:purchases_flutter/purchases_flutter.dart'
    show Offering, Offerings, Package, PurchasesErrorCode;

import '../test_helper.dart';

/// The paying subject's id, in the shape the plan requires: a bare RFC 4122 v4
/// UUID with no `team:` prefix, because RevenueCat's server-to-server purchase
/// tracking refuses a non-UUID App User ID in some configurations.
const String _appUserId = '9f8c1d2e-4b3a-4c1d-8e7f-0a1b2c3d4e5f';

/// A `Package` payload in the SDK's own wire shape.
///
/// Copied from the producer, which for this seam is the SDK itself
/// (`purchases_flutter-10.9.1/test/offering_test.dart`'s `generateOfferingJSON`,
/// read by `Package.fromJson`). Written from memory it would decode into a
/// package whose identifier the lookup under test could never match.
Map<String, dynamic> _packageJson(String identifier, String productId) => {
  'identifier': identifier,
  'packageType': 'MONTHLY',
  'product': {
    'identifier': productId,
    'description': 'Everything a team on call needs.',
    'title': 'Pro',
    'price': 29.0,
    'priceString': r'$29.00',
    'currencyCode': 'USD',
    'introPrice': null,
    'discounts': null,
    'productCategory': null,
    'defaultOption': null,
    'subscriptionOptions': null,
    'presentedOfferingIdentifier': null,
    'subscriptionPeriod': 'P1M',
  },
  'presentedOfferingContext': {'offeringIdentifier': 'default'},
};

/// An [Offering] carrying one package per (plan, product) pair given.
Offering _offering(String identifier, Map<String, String> packages) =>
    Offering.fromJson({
      'identifier': identifier,
      'serverDescription': '',
      'metadata': <String, Object>{},
      'availablePackages': packages.entries
          .map(
            (MapEntry<String, String> entry) =>
                _packageJson(entry.key, entry.value),
          )
          .toList(),
      'lifetime': null,
      'annual': null,
      'sixMonth': null,
      'threeMonth': null,
      'twoMonth': null,
      'monthly': null,
      'weekly': null,
    });

/// The catalogue a configured rail answers with: one current offering holding
/// the `pro` plan.
Offerings _catalogue() {
  final Offering current = _offering('default', const {'pro': 'pro_monthly'});

  return Offerings(<String, Offering>{'default': current}, current: current);
}

void main() {
  setUp(() {
    resetPaymentsState();
    // The driver logs on its way out of every failure, and `Log` resolves a
    // manager out of the container: without this the failure paths would fail
    // for a container error instead of the translation under test.
    Log.fake();
    Config.set(RevenueCatStoreService.apiKeyConfigKey, 'appl_public_test_key');
  });

  tearDown(() {
    Log.unfake();
    resetPaymentsState();
  });

  group('the public SDK key comes from config', () {
    test('a missing key refuses loudly before any store call is made', () async {
      // Configure time, not purchase time: `identify` runs at login, so an
      // operator who never published the key learns at login rather than from a
      // customer who tapped Upgrade.
      Config.set(RevenueCatStoreService.apiKeyConfigKey, null);
      final _FakeStoreRail rail = _FakeStoreRail();

      await expectLater(
        rail.identify(_appUserId),
        throwsA(
          isA<BillingException>().having(
            (BillingException error) => error.message,
            'message',
            contains(RevenueCatStoreService.apiKeyConfigKey),
          ),
        ),
      );
      expect(rail.configured, isEmpty);
      expect(rail.loggedIn, isEmpty);
    });

    test('an empty key is refused exactly like an absent one', () async {
      // The `??` right side of a config read is unvisited code, and a published
      // config with the key left blank is the state a real app ships in first.
      Config.set(RevenueCatStoreService.apiKeyConfigKey, '   ');
      final _FakeStoreRail rail = _FakeStoreRail();

      await expectLater(
        rail.identify(_appUserId),
        throwsA(isA<BillingException>()),
      );
      expect(rail.configured, isEmpty);
    });

    test('the key is read once and the SDK configured once', () async {
      final _FakeStoreRail rail = _FakeStoreRail(offerings: _catalogue());

      await rail.identify(_appUserId);
      await rail.purchase(plan: 'pro');
      await rail.restore();

      expect(rail.configured, ['appl_public_test_key']);
    });
  });

  group('identify binds the paying subject to the rail', () {
    test('the App User ID reaches the rail bare, with no prefix', () async {
      final _FakeStoreRail rail = _FakeStoreRail();

      await rail.identify(_appUserId);

      // Both halves matter and each has its own failure: the value has to be
      // the id, and it has to still be a UUID. A `team:` prefix closes
      // RevenueCat's server-to-server purchase tracking on a configuration
      // that requires an RFC 4122 v4 id.
      expect(rail.loggedIn, [_appUserId]);
      expect(rail.loggedIn.single, isNot(contains(':')));
    });

    test(
      'no subscriber attribute is set when no label is configured',
      () async {
        // No fabricated data: the readable label is the operator's word, and
        // duplicating the App User ID into an attribute says nothing new.
        final _FakeStoreRail rail = _FakeStoreRail();

        await rail.identify(_appUserId);

        expect(rail.attributes, isEmpty);
      },
    );

    test('a configured label rides an attribute, never the id', () async {
      // The trade the plan makes explicitly: the readability a `team:` prefix
      // would have given the id is provided by a subscriber attribute instead.
      Config.set(RevenueCatStoreService.subjectLabelConfigKey, 'team');
      final _FakeStoreRail rail = _FakeStoreRail();

      await rail.identify(_appUserId);

      expect(rail.attributes, [
        {RevenueCatStoreService.subjectAttribute: 'team:$_appUserId'},
      ]);
      expect(rail.loggedIn, [_appUserId]);
    });

    test('a raw rail failure becomes a BillingException', () async {
      final _FakeStoreRail rail = _FakeStoreRail(
        raisingOnLogIn: StateError('the receipt refresh blew up'),
      );

      await expectLater(
        rail.identify(_appUserId),
        throwsA(isA<BillingException>()),
      );
    });

    test(
      'a failed attribute write is a warning, not a failed identity',
      () async {
        // The identity WAS bound, which is all this method promises. Reporting a
        // cosmetic dashboard write as a failure would tell a caller the paying
        // subject is unbound and stop it offering a purchase that would work.
        Config.set(RevenueCatStoreService.subjectLabelConfigKey, 'team');
        final FakeLogManager log = Log.fake();
        final _FakeStoreRail rail = _FakeStoreRail(
          raisingOnAttributes: StateError('attribute queue full'),
        );

        await expectLater(rail.identify(_appUserId), completes);

        expect(rail.loggedIn, [_appUserId]);
        // Deliberately handled rather than swallowed: nothing silent here.
        expect(
          log.entries
              .where((FakeLogEntry entry) => entry.level == 'warning')
              .map((FakeLogEntry entry) => entry.message),
          hasLength(1),
        );
        log.assertNothingLogged('error');
      },
    );

    test('a BillingException from below is rethrown unchanged', () async {
      const BillingException original = BillingException('already ours');
      final _FakeStoreRail rail = _FakeStoreRail(raisingOnLogIn: original);

      await expectLater(rail.identify(_appUserId), throwsA(same(original)));
    });
  });

  group('purchase maps a plan to a package in the rail catalogue', () {
    test('a plan with a package is purchased and reported true', () async {
      final _FakeStoreRail rail = _FakeStoreRail(offerings: _catalogue());

      expect(await rail.purchase(plan: 'pro'), isTrue);
      expect(rail.purchased, ['pro']);
    });

    test('the current offering wins over an archived one', () async {
      // Both offerings carry a `pro` package and they point at different store
      // products. Resolving the archived one would charge last year's price.
      final Offering current = _offering('2026', const {'pro': 'pro_monthly'});
      final _FakeStoreRail rail = _FakeStoreRail(
        offerings: Offerings(<String, Offering>{
          'archived': _offering('2024', const {'pro': 'pro_monthly_legacy'}),
          '2026': current,
        }, current: current),
      );

      await rail.purchase(plan: 'pro');

      expect(rail.purchasedProducts, ['pro_monthly']);
    });

    test('a plan with no package refuses by name, never answers false', () async {
      // `false` is a customer dismissing a sheet. Reporting a misconfigured
      // store the same way hides it behind a shrug for the life of the release.
      final _FakeStoreRail rail = _FakeStoreRail(offerings: _catalogue());

      await expectLater(
        rail.purchase(plan: 'enterprise'),
        throwsA(
          isA<BillingException>().having(
            (BillingException error) => error.message,
            'message',
            contains('enterprise'),
          ),
        ),
      );
      expect(rail.purchased, isEmpty);
    });

    test('a customer who dismisses the sheet is a false, not a failure', () async {
      // The rail reports a cancellation as a PlatformException whose code is the
      // ORDINAL of its error enum, which is how `PurchasesErrorHelper` reads it.
      // Derived from the enum rather than written as `'1'`, so a reordering
      // upstream cannot leave this fixture quietly pointing at another code.
      final _FakeStoreRail rail = _FakeStoreRail(
        offerings: _catalogue(),
        raisingOnPurchase: PlatformException(
          code: PurchasesErrorCode.purchaseCancelledError.index.toString(),
          message: 'Purchase was cancelled.',
        ),
      );

      expect(await rail.purchase(plan: 'pro'), isFalse);
    });

    test('a store problem is a failure, not a dismissal', () async {
      // The other side of the same guard: every code that is not the
      // cancellation one has to reach the customer as a failure.
      final _FakeStoreRail rail = _FakeStoreRail(
        offerings: _catalogue(),
        raisingOnPurchase: PlatformException(
          code: PurchasesErrorCode.storeProblemError.index.toString(),
          message: 'There was a problem with the store.',
        ),
      );

      await expectLater(
        rail.purchase(plan: 'pro'),
        throwsA(isA<BillingException>()),
      );
    });

    test('a platform error with a non-numeric code is still ours', () async {
      // `PurchasesErrorHelper.getErrorCode` parses the code as a number and
      // throws a FormatException on anything else, and `channel-error` is
      // exactly such a code: the translation must not blow up inside its own
      // catch clause.
      final _FakeStoreRail rail = _FakeStoreRail(
        offerings: _catalogue(),
        raisingOnPurchase: PlatformException(code: 'channel-error'),
      );

      await expectLater(
        rail.purchase(plan: 'pro'),
        throwsA(isA<BillingException>()),
      );
    });

    test('a raw failure from the sheet becomes a BillingException', () async {
      // Regression guard for a bare `purchaseStorePackage(package);`: an
      // unawaited future completes after the try has exited, so the catch never
      // sees the rejection and a purchase that never happened reports `true`.
      final _FakeStoreRail rail = _FakeStoreRail(
        offerings: _catalogue(),
        raisingOnPurchase: StateError('no StoreKit on this device'),
      );

      await expectLater(
        rail.purchase(plan: 'pro'),
        throwsA(isA<BillingException>()),
      );
    });

    test('a failure to fetch the catalogue is a BillingException', () async {
      // The same await discipline one call earlier: the offerings fetch is a
      // network call and it fails on a plane.
      final _FakeStoreRail rail = _FakeStoreRail(
        raisingOnOfferings: StateError('offerings request timed out'),
      );

      await expectLater(
        rail.purchase(plan: 'pro'),
        throwsA(isA<BillingException>()),
      );
    });

    test('a BillingException from below is rethrown unchanged', () async {
      const BillingException original = BillingException('already ours');
      final _FakeStoreRail rail = _FakeStoreRail(
        offerings: _catalogue(),
        raisingOnPurchase: original,
      );

      await expectLater(rail.purchase(plan: 'pro'), throwsA(same(original)));
    });
  });

  group('restore reports what the store handed back', () {
    test('a restore that hands something back answers true', () async {
      final _FakeStoreRail rail = _FakeStoreRail(restores: true);

      expect(await rail.restore(), isTrue);
    });

    test('nothing to restore is an answer, not a failure', () async {
      // An answer to show the customer. Reported as an error it would send them
      // to support over an account that simply never bought anything.
      final _FakeStoreRail rail = _FakeStoreRail();

      expect(await rail.restore(), isFalse);
    });

    test('a raw rail failure becomes a BillingException', () async {
      final _FakeStoreRail rail = _FakeStoreRail(
        raisingOnRestore: StateError('receipt refresh failed'),
      );

      await expectLater(rail.restore(), throwsA(isA<BillingException>()));
    });
  });

  group('openStoreManagement opens the surface the rail names', () {
    test('the management URL is handed to the launch seam', () async {
      final _FakeStoreRail rail = _FakeStoreRail(
        managementUrl: 'https://apps.apple.com/account/subscriptions',
      );

      await rail.openStoreManagement();

      expect(rail.launched, ['https://apps.apple.com/account/subscriptions']);
    });

    test('no management URL is a refusal, not a silent success', () async {
      // The rail answers null when the account has no store subscription to
      // manage, and a resolved future would read to the customer as a screen
      // that opened and closed.
      final _FakeStoreRail rail = _FakeStoreRail();

      await expectLater(
        rail.openStoreManagement(),
        throwsA(isA<BillingException>()),
      );
      expect(rail.launched, isEmpty);
    });

    test('a launcher that declines is a failure, not a success', () async {
      // The half no `catch` can see: `LaunchService.url` never throws, it
      // answers `false` (`magic/lib/src/launch/launch_service.dart:29-43`).
      final _FakeStoreRail rail = _FakeStoreRail(
        managementUrl: 'https://play.google.com/store/account/subscriptions',
        opens: false,
      );

      await expectLater(
        rail.openStoreManagement(),
        throwsA(isA<BillingException>()),
      );
      expect(rail.launched, hasLength(1));
    });

    test('a raw failure reading the URL becomes a BillingException', () async {
      final _FakeStoreRail rail = _FakeStoreRail(
        raisingOnManagementUrl: StateError('customer info request failed'),
      );

      await expectLater(
        rail.openStoreManagement(),
        throwsA(isA<BillingException>()),
      );
    });
  });

  group('the rail resolves only where a store exists', () {
    test('a store platform resolves the RevenueCat driver', () {
      expect(
        createStoreRail(onStorePlatform: true),
        isA<RevenueCatStoreService>(),
      );
    });

    test('a dart:io platform without a store resolves null', () {
      // macOS, Windows and Linux all carry `dart:library.io` and none of them
      // has StoreKit or Play Billing, so the io ARM cannot hand the driver back
      // unconditionally: one compiled artifact serves all five platforms.
      expect(createStoreRail(onStorePlatform: false), isNull);
    });

    test('the desktop test host itself has no store rail', () {
      // The real platform read, not the injected one. A `flutter test` host is
      // always a desktop, so this is the unoverridden branch answering.
      expect(createStoreRail(), isNull);
    });
  });
}

/// A [RevenueCatStoreService] with every platform call stood in for.
///
/// Only the seams are replaced. The config read, the plan-to-package lookup, the
/// await discipline and the catch clauses under test are the driver's own, and no
/// part of `purchases_flutter` is mocked: what stands in is this package's own
/// method, which is the convention in `test/test_helper.dart`.
class _FakeStoreRail extends RevenueCatStoreService {
  _FakeStoreRail({
    this.offerings,
    this.raisingOnLogIn,
    this.raisingOnAttributes,
    this.raisingOnOfferings,
    this.raisingOnPurchase,
    this.raisingOnRestore,
    this.raisingOnManagementUrl,
    this.restores = false,
    this.managementUrl,
    this.opens = true,
  });

  /// The catalogue the offerings seam answers with.
  final Offerings? offerings;

  /// Raised from the seam each one is named for, or null to answer normally.
  final Object? raisingOnLogIn;
  final Object? raisingOnAttributes;
  final Object? raisingOnOfferings;
  final Object? raisingOnPurchase;
  final Object? raisingOnRestore;
  final Object? raisingOnManagementUrl;

  /// What the restore seam reports the store handed back.
  final bool restores;

  /// The URL the rail names for managing the subscription, or null for none.
  final String? managementUrl;

  /// Whether the launch seam reports the page opened.
  ///
  /// Separate from a raised error because the two are genuinely different
  /// failures, and only one of them would ever reach a `catch`.
  final bool opens;

  /// Every API key the driver configured the SDK with, in order.
  final List<String> configured = [];

  /// Every App User ID the driver logged in, in order.
  final List<String> loggedIn = [];

  /// Every subscriber-attribute map the driver set, in order.
  final List<Map<String, String>> attributes = [];

  /// The package identifier of every purchase the driver started.
  final List<String> purchased = [];

  /// The store product identifier behind each of those packages.
  final List<String> purchasedProducts = [];

  /// Every URL the driver asked the launch seam to open, in order.
  final List<String> launched = [];

  @override
  Future<void> configureSdk(String apiKey) async => configured.add(apiKey);

  @override
  Future<void> logInSdk(String appUserId) async {
    if (raisingOnLogIn != null) throw raisingOnLogIn!;
    loggedIn.add(appUserId);
  }

  @override
  Future<void> setSubscriberAttributes(Map<String, String> values) async {
    if (raisingOnAttributes != null) throw raisingOnAttributes!;
    attributes.add(values);
  }

  @override
  Future<Offerings> fetchOfferings() async {
    if (raisingOnOfferings != null) throw raisingOnOfferings!;

    return offerings ?? const Offerings(<String, Offering>{});
  }

  @override
  Future<void> purchaseStorePackage(Package package) async {
    if (raisingOnPurchase != null) throw raisingOnPurchase!;
    purchased.add(package.identifier);
    purchasedProducts.add(package.storeProduct.identifier);
  }

  @override
  Future<bool> restoreStorePurchases() async {
    if (raisingOnRestore != null) throw raisingOnRestore!;

    return restores;
  }

  @override
  Future<String?> fetchManagementUrl() async {
    if (raisingOnManagementUrl != null) throw raisingOnManagementUrl!;

    return managementUrl;
  }

  @override
  Future<bool> launchManagementPage(String url) async {
    launched.add(url);

    return opens;
  }
}
