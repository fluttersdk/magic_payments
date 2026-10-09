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
    show
        Offering,
        Offerings,
        Package,
        PurchasesErrorCode,
        StoreProductChangeInfo,
        StoreReplacementMode;

import '../test_helper.dart';

/// The paying subject's id, in the shape the plan requires: a bare RFC 4122 v4
/// UUID with no `team:` prefix, because RevenueCat's server-to-server purchase
/// tracking refuses a non-UUID App User ID in some configurations.
const String _appUserId = '9f8c1d2e-4b3a-4c1d-8e7f-0a1b2c3d4e5f';

/// Another paying subject, the one a device left bound elsewhere is bound to.
const String _otherUserId = '1a2b3c4d-5e6f-4a7b-8c9d-0e1f2a3b4c5d';

/// An introductory price in the SDK's own wire shape, copied from the producer
/// (`purchases_flutter-10.15.2/test/introductory_price_test.dart`'s
/// `mockIntroductoryPriceJson`, read by `IntroductoryPrice.fromJson`).
const Map<String, Object> _introPriceJson = {
  'price': 0.0,
  'priceString': r'$0.00',
  'period': 'P2W',
  'cycles': 1,
  'periodUnit': 'DAY',
  'periodNumberOfUnits': 14,
};

/// A `Package` payload in the SDK's own wire shape.
///
/// Copied from the producer, which for this seam is the SDK itself
/// (`purchases_flutter-10.9.1/test/offering_test.dart`'s `generateOfferingJSON`,
/// read by `Package.fromJson`). Written from memory it would decode into a
/// package whose identifier the lookup under test could never match.
Map<String, dynamic> _packageJson(
  String identifier,
  String productId, {
  String period = 'P1M',
  double price = 29.0,
  String priceString = r'$29.00',
  Map<String, Object>? introPrice,
}) => {
  'identifier': identifier,
  'packageType': 'MONTHLY',
  'product': {
    'identifier': productId,
    'description': 'Everything a team on call needs.',
    'title': 'Pro',
    'price': price,
    'priceString': priceString,
    'currencyCode': 'USD',
    'introPrice': introPrice,
    'discounts': null,
    'productCategory': null,
    'defaultOption': null,
    'subscriptionOptions': null,
    'presentedOfferingIdentifier': null,
    'subscriptionPeriod': period,
  },
  'presentedOfferingContext': {'offeringIdentifier': 'default'},
};

/// An [Offering] carrying one package per (plan, product) pair given.
///
/// [periods] names the billing period of a plan whose period is not monthly,
/// and [prices] the price of a plan that does not cost the default 29.
Offering _offering(
  String identifier,
  Map<String, String> packages, {
  Map<String, String> periods = const {},
  Map<String, double> prices = const {},
}) => _offeringOf(
  identifier,
  packages.entries
      .map(
        (MapEntry<String, String> entry) => _packageJson(
          entry.key,
          entry.value,
          period: periods[entry.key] ?? 'P1M',
          price: prices[entry.key] ?? 29.0,
        ),
      )
      .toList(),
);

/// An [Offering] carrying the package payloads given, verbatim.
Offering _offeringOf(String identifier, List<Map<String, dynamic>> packages) =>
    Offering.fromJson({
      'identifier': identifier,
      'serverDescription': '',
      'metadata': <String, Object>{},
      'availablePackages': packages,
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

/// The Play catalogue: two subscriptions, each with a monthly and an annual
/// base plan, in RevenueCat's `subscriptionId:basePlanId` product id shape.
///
/// Priced like a real catalogue, because the replacement mode of an upgrade
/// now turns on the price per day: business costs twice pro at either period.
Offerings _playCatalogue({
  Map<String, String> packages = const {
    'pro_monthly': 'pro_sub:monthly',
    'pro_annual': 'pro_sub:annual',
    'business_monthly': 'business_sub:monthly',
    'business_annual': 'business_sub:annual',
  },
  Map<String, double> prices = const {
    'pro_monthly': 30.0,
    'pro_annual': 300.0,
    'business_monthly': 60.0,
    'business_annual': 600.0,
  },
}) {
  final Offering current = _offering(
    'default',
    packages,
    periods: const {'pro_annual': 'P1Y', 'business_annual': 'P1Y'},
    prices: prices,
  );

  return Offerings(<String, Offering>{'default': current}, current: current);
}

/// The App Store catalogue: bare product ids, which never carry a `:`.
Offerings _appStoreCatalogue() {
  final Offering current = _offering(
    'default',
    const {
      'pro_monthly': 'com.app.pro.monthly',
      'pro_annual': 'com.app.pro.annual',
      'business_monthly': 'com.app.business.monthly',
    },
    periods: const {'pro_annual': 'P1Y'},
  );

  return Offerings(<String, Offering>{'default': current}, current: current);
}

/// The catalogue's tier facts for the Play catalogue above.
const PurchaseContext _tiers = PurchaseContext(
  tierOrder: ['free', 'pro', 'business'],
  tierOfProduct: {
    'pro_monthly': 'pro',
    'pro_annual': 'pro',
    'business_monthly': 'business',
    'business_annual': 'business',
  },
);

/// The refusal a purchase or restore must end in, by its code.
Matcher _refusedWith(BillingErrorCode code) => throwsA(
  isA<BillingException>().having(
    (BillingException error) => error.code,
    'code',
    code,
  ),
);

void main() {
  setUp(() {
    resetPaymentsState();
    // The driver logs on its way out of every failure, and `Log` resolves a
    // manager out of the container: without this the failure paths would fail
    // for a container error instead of the translation under test.
    Log.fake();
    Config.set(RevenueCatStoreService.apiKeyConfigKey, 'appl_public_test_key');
    // The session pays as the subject every fake rail starts bound to, so the
    // identity guard passes unless a test says otherwise.
    StoreIdentitySync.billableId = () => _appUserId;
  });

  tearDown(() {
    StoreIdentitySync.detach();
    StoreIdentitySync.billableId = null;
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

    test('a missing key is refused as notConfigured', () async {
      // A caller switches on the code, and this one tells an operator rather
      // than a customer what to fix.
      Config.set(RevenueCatStoreService.apiKeyConfigKey, null);

      await expectLater(
        _FakeStoreRail().purchase('pro'),
        _refusedWith(BillingErrorCode.notConfigured),
      );
    });

    test('the key is read once and the SDK configured once', () async {
      final _FakeStoreRail rail = _FakeStoreRail(offerings: _catalogue());

      await rail.identify(_appUserId);
      await rail.purchase('pro');
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

      expect(await rail.purchase('pro'), isTrue);
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

      await rail.purchase('pro');

      expect(rail.purchasedProducts, ['pro_monthly']);
    });

    test('a plan with no package refuses by name, never answers false', () async {
      // `false` is a customer dismissing a sheet. Reporting a misconfigured
      // store the same way hides it behind a shrug for the life of the release.
      final _FakeStoreRail rail = _FakeStoreRail(offerings: _catalogue());

      await expectLater(
        rail.purchase('enterprise'),
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

      expect(await rail.purchase('pro'), isFalse);
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

      await expectLater(rail.purchase('pro'), throwsA(isA<BillingException>()));
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

      await expectLater(rail.purchase('pro'), throwsA(isA<BillingException>()));
    });

    test('a raw failure from the sheet becomes a BillingException', () async {
      // Regression guard for a bare `purchaseStorePackage(package);`: an
      // unawaited future completes after the try has exited, so the catch never
      // sees the rejection and a purchase that never happened reports `true`.
      final _FakeStoreRail rail = _FakeStoreRail(
        offerings: _catalogue(),
        raisingOnPurchase: StateError('no StoreKit on this device'),
      );

      await expectLater(rail.purchase('pro'), throwsA(isA<BillingException>()));
    });

    test('a failure to fetch the catalogue is a BillingException', () async {
      // The same await discipline one call earlier: the offerings fetch is a
      // network call and it fails on a plane.
      final _FakeStoreRail rail = _FakeStoreRail(
        raisingOnOfferings: StateError('offerings request timed out'),
      );

      await expectLater(rail.purchase('pro'), throwsA(isA<BillingException>()));
    });

    test('a BillingException from below is rethrown unchanged', () async {
      const BillingException original = BillingException('already ours');
      final _FakeStoreRail rail = _FakeStoreRail(
        offerings: _catalogue(),
        raisingOnPurchase: original,
      );

      await expectLater(rail.purchase('pro'), throwsA(same(original)));
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

  group('purchase and restore refuse a rail bound to another subject', () {
    test('no paying subject in the session refuses as notIdentified', () async {
      StoreIdentitySync.billableId = () => null;
      final _FakeStoreRail rail = _FakeStoreRail(offerings: _catalogue());

      await expectLater(
        rail.purchase('pro'),
        _refusedWith(BillingErrorCode.notIdentified),
      );
      expect(rail.purchased, isEmpty);
    });

    test('an empty paying subject is refused like an absent one', () async {
      StoreIdentitySync.billableId = () => '';
      final _FakeStoreRail rail = _FakeStoreRail(offerings: _catalogue());

      await expectLater(
        rail.purchase('pro'),
        _refusedWith(BillingErrorCode.notIdentified),
      );
    });

    test(
      'a rail bound to another subject refuses before the sheet opens',
      () async {
        // The webhook attributes a purchase to the App User ID the rail holds,
        // so buying here would hand team B's money to team A's account.
        StoreIdentitySync.billableId = () => _otherUserId;
        final _FakeStoreRail rail = _FakeStoreRail(offerings: _catalogue());

        await expectLater(
          rail.purchase('pro'),
          _refusedWith(BillingErrorCode.identityMismatch),
        );
        expect(rail.purchased, isEmpty);
      },
    );

    test('an anonymous rail identity is a mismatch, not a pass', () async {
      final _FakeStoreRail rail = _FakeStoreRail(
        offerings: _catalogue(),
        appUserId: r'$RCAnonymousID:8c0f2a',
      );

      await expectLater(
        rail.purchase('pro'),
        _refusedWith(BillingErrorCode.identityMismatch),
      );
      expect(rail.purchased, isEmpty);
    });

    test('restore refuses a rail bound to another subject', () async {
      // A restore aliases the store receipt onto whoever the rail holds, so it
      // moves a subscription between paying subjects exactly like a purchase.
      StoreIdentitySync.billableId = () => _otherUserId;
      final _FakeStoreRail rail = _FakeStoreRail(restores: true);

      await expectLater(
        rail.restore(),
        _refusedWith(BillingErrorCode.identityMismatch),
      );
      expect(rail.restoreCalls, 0);
    });

    test('restore refuses with no paying subject', () async {
      StoreIdentitySync.billableId = () => null;
      final _FakeStoreRail rail = _FakeStoreRail(restores: true);

      await expectLater(
        rail.restore(),
        _refusedWith(BillingErrorCode.notIdentified),
      );
      expect(rail.restoreCalls, 0);
    });

    test('purchase identifies the rail first, then buys', () async {
      // A rail still on the anonymous id it booted with is re-bound by the sync
      // the purchase awaits, so the comparison after it passes.
      final _FakeStoreRail rail = _FakeStoreRail(
        offerings: _catalogue(),
        appUserId: r'$RCAnonymousID:8c0f2a',
      );
      Payments.extend(PaymentsManager.storeRole, () => rail);

      expect(await rail.purchase('pro'), isTrue);
      expect(rail.loggedIn, [_appUserId]);
      expect(rail.purchased, ['pro']);
    });

    test('restore identifies the rail first, then restores', () async {
      final _FakeStoreRail rail = _FakeStoreRail(
        restores: true,
        appUserId: r'$RCAnonymousID:8c0f2a',
      );
      Payments.extend(PaymentsManager.storeRole, () => rail);

      expect(await rail.restore(), isTrue);
      expect(rail.loggedIn, [_appUserId]);
    });

    test(
      'an identify outside the sync is not skipped as a repeat later',
      () async {
        // The sync's repeat guard has to describe the rail's real binding. A
        // direct identify moved the rail, so the next sync must move it back.
        final _FakeStoreRail rail = _FakeStoreRail();
        Payments.extend(PaymentsManager.storeRole, () => rail);

        await StoreIdentitySync.syncNow();
        await rail.identify(_otherUserId);
        await StoreIdentitySync.syncNow();

        expect(rail.loggedIn, [_appUserId, _otherUserId, _appUserId]);
      },
    );

    test('a direct identify of the subject spares the sync a repeat', () async {
      // The other half of the recorded binding: a login that succeeded is
      // recorded, so the sync does not log the same subject in twice.
      final _FakeStoreRail rail = _FakeStoreRail();
      Payments.extend(PaymentsManager.storeRole, () => rail);

      await rail.identify(_appUserId);
      await StoreIdentitySync.syncNow();

      expect(rail.loggedIn, [_appUserId]);
    });

    test('a failed identify leaves the next sync free to retry', () async {
      // The rail's binding after a failed login is unknown, so the recorded id
      // is cleared before the login rather than trusted across it.
      final _FakeStoreRail rail = _FakeStoreRail();
      Payments.extend(PaymentsManager.storeRole, () => rail);

      await StoreIdentitySync.syncNow();
      rail.raisingOnLogIn = StateError('login request dropped');
      await expectLater(
        rail.identify(_appUserId),
        throwsA(isA<BillingException>()),
      );
      rail.raisingOnLogIn = null;
      await StoreIdentitySync.syncNow();

      expect(rail.loggedIn, [_appUserId, _appUserId]);
    });
  });

  group('products prices the package purchase would buy', () {
    test('each key carries the store product of its package', () async {
      final Offering current = _offeringOf('2026', [
        _packageJson(
          'pro_annual',
          'pro_sub:annual',
          period: 'P1Y',
          price: 349.99,
          priceString: '₺349,99',
          introPrice: _introPriceJson,
        ),
      ]);
      final _FakeStoreRail rail = _FakeStoreRail(
        offerings: Offerings(<String, Offering>{
          'archived': _offeringOf('2024', [
            _packageJson('pro_annual', 'pro_sub:legacy', price: 199.0),
          ]),
          '2026': current,
        }, current: current),
      );

      final Map<String, StoreProductOffer> offers = await rail.products([
        'pro_annual',
      ]);

      final StoreProductOffer offer = offers['pro_annual']!;
      expect(offer.price, 349.99);
      expect(offer.priceString, '₺349,99');
      expect(offer.currencyCode, 'USD');
      expect(offer.subscriptionPeriod, 'P1Y');
      expect(offer.introPrice, 0.0);
      expect(offer.introPriceString, r'$0.00');
      expect(offer.introPeriod, 'P2W');
    });

    test('a product with no introductory offer carries none', () async {
      final _FakeStoreRail rail = _FakeStoreRail(offerings: _catalogue());

      final StoreProductOffer offer = (await rail.products(['pro']))['pro']!;

      expect(offer.introPrice, isNull);
      expect(offer.introPriceString, isNull);
      expect(offer.introPeriod, isNull);
    });

    test('a key the store has no package for is absent', () async {
      final _FakeStoreRail rail = _FakeStoreRail(offerings: _catalogue());

      final Map<String, StoreProductOffer> offers = await rail.products([
        'pro',
        'enterprise',
      ]);

      expect(offers.keys, ['pro']);
    });

    test('a failure to fetch the catalogue is a BillingException', () async {
      final _FakeStoreRail rail = _FakeStoreRail(
        raisingOnOfferings: StateError('offerings request timed out'),
      );

      await expectLater(
        rail.products(['pro']),
        throwsA(isA<BillingException>()),
      );
    });
  });

  group('a subscription another store manages is never bought over', () {
    test('an App Store product on the Play rail is managedElsewhere', () async {
      // Buying here would charge the customer twice, once per store, for one
      // subscription.
      final _FakeStoreRail rail = _FakeStoreRail(
        store: ManageVia.playStore,
        offerings: _playCatalogue(),
        activeProducts: const ['com.app.pro.monthly'],
      );

      await expectLater(
        rail.purchase('pro_annual', context: _tiers),
        _refusedWith(BillingErrorCode.managedElsewhere),
      );
      expect(rail.purchased, isEmpty);
    });

    test('a Play product on the App Store rail is managedElsewhere', () async {
      final _FakeStoreRail rail = _FakeStoreRail(
        offerings: _appStoreCatalogue(),
        activeProducts: const ['pro_sub:monthly'],
      );

      await expectLater(
        rail.purchase('pro_annual'),
        _refusedWith(BillingErrorCode.managedElsewhere),
      );
      expect(rail.purchased, isEmpty);
    });

    test(
      'a Play product the catalogue cannot name is unmappedActiveProduct',
      () async {
        final _FakeStoreRail rail = _FakeStoreRail(
          store: ManageVia.playStore,
          offerings: _playCatalogue(),
          activeProducts: const ['legacy_sub:monthly'],
        );

        await expectLater(
          rail.purchase('pro_annual', context: _tiers),
          _refusedWith(BillingErrorCode.unmappedActiveProduct),
        );
        expect(rail.purchased, isEmpty);
      },
    );

    test(
      'a grandfathered App Store product does not block the new purchase',
      () async {
        // The held product is no longer sold, so no offering names it. StoreKit
        // moves the customer inside the group on its own, so nothing here has
        // to compute against it; refusing would strand a paying customer on a
        // plan they can never leave from the app.
        final _FakeStoreRail rail = _FakeStoreRail(
          offerings: _appStoreCatalogue(),
          activeProducts: const ['com.app.legacy.monthly'],
        );

        expect(
          await rail.purchase(
            'business_monthly',
            context: const PurchaseContext(
              tierOrder: ['free', 'pro', 'business'],
              tierOfProduct: {
                'pro_monthly': 'pro',
                'business_monthly': 'business',
              },
              tierOfStoreProduct: {'com.app.legacy.monthly': 'pro'},
            ),
          ),
          isTrue,
        );
        expect(rail.purchasedProducts, ['com.app.business.monthly']);
        expect(rail.productChanges, [isNull]);
        // A higher level in the group, which Apple applies at once.
        expect(rail.lastChangeTiming, StoreChangeTiming.immediate);
      },
    );

    test('a RevenueCat promotional grant is neither store', () async {
      // `rc_promo_` ids are granted from the RevenueCat dashboard. Read by
      // shape, one has no `:` and would look like an App Store product to the
      // Play rail, refusing a customer whom no store bills at all.
      final _FakeStoreRail rail = _FakeStoreRail(
        store: ManageVia.playStore,
        offerings: _playCatalogue(),
        activeProducts: const ['rc_promo_pro_lifetime'],
      );

      expect(await rail.purchase('pro_annual', context: _tiers), isTrue);
      expect(rail.productChanges, [isNull]);
      expect(rail.lastChangeTiming, isNull);
    });

    test(
      'a promotional grant beside a Play product is not a second one',
      () async {
        // Two active ids would be refused as ambiguous; the grant is not one of
        // the subscriptions Play could replace.
        final _FakeStoreRail rail = _FakeStoreRail(
          store: ManageVia.playStore,
          offerings: _playCatalogue(),
          activeProducts: const ['rc_promo_pro_lifetime', 'pro_sub:monthly'],
        );

        expect(await rail.purchase('pro_annual', context: _tiers), isTrue);
        expect(rail.productChanges.single?.oldProductIdentifier, 'pro_sub');
      },
    );

    test('a promotional grant on the App Store rail is ignored too', () async {
      final _FakeStoreRail rail = _FakeStoreRail(
        offerings: _appStoreCatalogue(),
        activeProducts: const ['rc_promo_pro_lifetime'],
      );

      expect(await rail.purchase('pro_annual', context: _tiers), isTrue);
      expect(rail.lastChangeTiming, isNull);
    });

    test('the App Store rail never passes a product change', () async {
      // StoreKit moves a subscription inside its group on its own; a change
      // record is a Play concept.
      final _FakeStoreRail rail = _FakeStoreRail(
        offerings: _appStoreCatalogue(),
        activeProducts: const ['com.app.pro.monthly'],
      );

      expect(await rail.purchase('pro_annual', context: _tiers), isTrue);
      expect(rail.purchasedProducts, ['com.app.pro.annual']);
      expect(rail.productChanges, [isNull]);
    });
  });

  group('a one-off product is bought beside a held subscription', () {
    /// An offering holding the subscription packages [subscriptions] (key to
    /// store product id) plus one consumable, `credits_10`, sold as store
    /// product [creditsId] in the SDK's own wire shape for an in-app product:
    /// `NON_SUBSCRIPTION` and no period.
    Offerings withCredits(Map<String, String> subscriptions, String creditsId) {
      final Map<String, dynamic> credits = _packageJson(
        'credits_10',
        creditsId,
      );
      final Map<String, dynamic> product =
          Map<String, dynamic>.of(credits['product'] as Map<String, dynamic>)
            ..addAll(<String, dynamic>{
              'productCategory': 'NON_SUBSCRIPTION',
              'subscriptionPeriod': null,
            });
      final Offering current = _offeringOf('default', <Map<String, dynamic>>[
        for (final MapEntry<String, String> entry in subscriptions.entries)
          _packageJson(
            entry.key,
            entry.value,
            period: entry.key.endsWith('_annual') ? 'P1Y' : 'P1M',
          ),
        <String, dynamic>{
          ...credits,
          'packageType': 'CUSTOM',
          'product': product,
        },
      ]);

      return Offerings(<String, Offering>{
        'default': current,
      }, current: current);
    }

    test('on Play, a subscriber buys credits with no product change', () async {
      // Routing it through the subscription change refused it as
      // `unmappedActiveProduct` (a consumable has no tier), or would have
      // attached a replacement to an in-app product.
      final _FakeStoreRail rail = _FakeStoreRail(
        store: ManageVia.playStore,
        offerings: withCredits(const {
          'pro_monthly': 'pro_sub:monthly',
          'pro_annual': 'pro_sub:annual',
        }, 'credits_10'),
        activeProducts: const ['pro_sub:monthly'],
      );

      expect(await rail.purchase('credits_10', context: _tiers), isTrue);
      expect(rail.purchasedProducts, ['credits_10']);
      expect(rail.productChanges, [isNull]);
      expect(rail.lastChangeTiming, isNull);
    });

    test('a subscription on the other store does not refuse credits', () async {
      // Two charges for one subscription is what `managedElsewhere` prevents;
      // a consumable is not a second subscription.
      final _FakeStoreRail rail = _FakeStoreRail(
        offerings: withCredits(const {
          'pro_annual': 'com.app.pro.annual',
        }, 'com.app.credits.10'),
        activeProducts: const ['pro_sub:monthly'],
      );

      expect(await rail.purchase('credits_10'), isTrue);
      expect(rail.purchasedProducts, ['com.app.credits.10']);
      expect(rail.lastChangeTiming, isNull);
    });

    test('a subscription purchase still refuses the other store', () async {
      final _FakeStoreRail rail = _FakeStoreRail(
        offerings: withCredits(const {
          'pro_annual': 'com.app.pro.annual',
        }, 'com.app.credits.10'),
        activeProducts: const ['pro_sub:monthly'],
      );

      await expectLater(
        rail.purchase('pro_annual'),
        _refusedWith(BillingErrorCode.managedElsewhere),
      );
    });
  });

  group('a Play subscription is changed in place, never bought twice', () {
    /// The rail the last [changeFor] bought through.
    _FakeStoreRail? lastRail;

    Future<StoreProductChangeInfo?> changeFor(
      String active,
      String productKey, {
      PurchaseContext? context = _tiers,
    }) async {
      final _FakeStoreRail rail = _FakeStoreRail(
        store: ManageVia.playStore,
        offerings: _playCatalogue(),
        activeProducts: [active],
      );
      lastRail = rail;

      expect(await rail.purchase(productKey, context: context), isTrue);

      return rail.productChanges.single;
    }

    Matcher change(String oldProduct, StoreReplacementMode mode) =>
        isA<StoreProductChangeInfo>()
            .having(
              (StoreProductChangeInfo info) => info.oldProductIdentifier,
              'oldProductIdentifier',
              oldProduct,
            )
            .having(
              (StoreProductChangeInfo info) => info.replacementMode,
              'replacementMode',
              mode,
            );

    test('no active subscription buys without a product change', () async {
      final _FakeStoreRail rail = _FakeStoreRail(
        store: ManageVia.playStore,
        offerings: _playCatalogue(),
      );

      expect(await rail.purchase('pro_annual', context: _tiers), isTrue);
      expect(rail.productChanges, [isNull]);
    });

    test('monthly to annual on one subscription charges full price', () async {
      // Play allows only CHARGE_FULL_PRICE or WITHOUT_PRORATION for a base
      // plan switch, and a longer period starts a fresh, longer cycle now.
      expect(
        await changeFor('pro_sub:monthly', 'pro_annual'),
        change('pro_sub', StoreReplacementMode.chargeFullPrice),
      );
    });

    test('annual to monthly on one subscription waits for renewal', () async {
      expect(
        await changeFor('pro_sub:annual', 'pro_monthly'),
        change('pro_sub', StoreReplacementMode.withoutProration),
      );
    });

    test('a higher tier is prorated now', () async {
      expect(
        await changeFor('pro_sub:annual', 'business_annual'),
        change('pro_sub', StoreReplacementMode.chargeProratedPrice),
      );
    });

    test('a lower tier is deferred to renewal', () async {
      expect(
        await changeFor('business_sub:monthly', 'pro_monthly'),
        change('business_sub', StoreReplacementMode.deferred),
      );
    });

    test('a tier change with no catalogue context is refused', () async {
      // Without the tier order an upgrade and a downgrade look the same, and
      // guessing either one charges somebody the wrong amount.
      final _FakeStoreRail rail = _FakeStoreRail(
        store: ManageVia.playStore,
        offerings: _playCatalogue(),
        activeProducts: const ['pro_sub:annual'],
      );

      await expectLater(
        rail.purchase('business_annual'),
        _refusedWith(BillingErrorCode.unmappedActiveProduct),
      );
      expect(rail.purchased, isEmpty);
    });

    test('an active product with no tier in the context is refused', () async {
      final _FakeStoreRail rail = _FakeStoreRail(
        store: ManageVia.playStore,
        offerings: _playCatalogue(),
        activeProducts: const ['pro_sub:annual'],
      );

      await expectLater(
        rail.purchase(
          'business_annual',
          context: const PurchaseContext(
            tierOrder: ['pro', 'business'],
            tierOfProduct: {'business_annual': 'business'},
          ),
        ),
        _refusedWith(BillingErrorCode.unmappedActiveProduct),
      );
    });

    test('a target tier missing from the tier order is refused', () async {
      final _FakeStoreRail rail = _FakeStoreRail(
        store: ManageVia.playStore,
        offerings: _playCatalogue(),
        activeProducts: const ['pro_sub:annual'],
      );

      await expectLater(
        rail.purchase(
          'business_annual',
          context: const PurchaseContext(
            tierOrder: ['pro'],
            tierOfProduct: {'pro_annual': 'pro', 'business_annual': 'business'},
          ),
        ),
        _refusedWith(BillingErrorCode.unmappedActiveProduct),
      );
    });

    test('two active Play subscriptions are refused as ambiguous', () async {
      final _FakeStoreRail rail = _FakeStoreRail(
        store: ManageVia.playStore,
        offerings: _playCatalogue(),
        activeProducts: const ['pro_sub:monthly', 'business_sub:monthly'],
      );

      await expectLater(
        rail.purchase('business_annual', context: _tiers),
        _refusedWith(BillingErrorCode.unmappedActiveProduct),
      );
      expect(rail.purchased, isEmpty);
    });

    test('buying the product already held is alreadyOwned', () async {
      final _FakeStoreRail rail = _FakeStoreRail(
        store: ManageVia.playStore,
        offerings: _playCatalogue(),
        activeProducts: const ['pro_sub:monthly'],
      );

      await expectLater(
        rail.purchase('pro_monthly', context: _tiers),
        _refusedWith(BillingErrorCode.alreadyOwned),
      );
      expect(rail.purchased, isEmpty);
    });

    test(
      'a higher tier cheaper per day is charged in full, not prorated',
      () async {
        // Pro monthly at 30 is 1.00 a day; business annual at 300 is 0.82 a day.
        // Play accepts CHARGE_PRORATED_PRICE only when the price per unit of
        // time rises, and rejects this purchase with it.
        final _FakeStoreRail rail = _FakeStoreRail(
          store: ManageVia.playStore,
          offerings: _playCatalogue(
            prices: const {'pro_monthly': 30.0, 'business_annual': 300.0},
          ),
          activeProducts: const ['pro_sub:monthly'],
        );

        expect(await rail.purchase('business_annual', context: _tiers), isTrue);
        expect(
          rail.productChanges.single,
          change('pro_sub', StoreReplacementMode.chargeFullPrice),
        );
        expect(rail.lastChangeTiming, StoreChangeTiming.immediate);
      },
    );

    test(
      'a higher tier at the same price per day is charged in full',
      () async {
        // Equal is not a rise, and Play's rule is a strict one.
        final _FakeStoreRail rail = _FakeStoreRail(
          store: ManageVia.playStore,
          offerings: _playCatalogue(
            prices: const {'pro_annual': 300.0, 'business_annual': 300.0},
          ),
          activeProducts: const ['pro_sub:annual'],
        );

        expect(await rail.purchase('business_annual', context: _tiers), isTrue);
        expect(
          rail.productChanges.single,
          change('pro_sub', StoreReplacementMode.chargeFullPrice),
        );
      },
    );

    test('a downgrade reports that it takes effect at renewal', () async {
      expect(
        await changeFor('business_sub:monthly', 'pro_monthly'),
        change('business_sub', StoreReplacementMode.deferred),
      );
      expect(lastRail!.lastChangeTiming, StoreChangeTiming.atRenewal);
    });

    test('a shorter base plan reports that it takes effect now', () async {
      // WITHOUT_PRORATION swaps the plan at once and bills the new price at
      // the next recurrence, so the customer holds the new plan immediately.
      expect(
        await changeFor('pro_sub:annual', 'pro_monthly'),
        change('pro_sub', StoreReplacementMode.withoutProration),
      );
      expect(lastRail!.lastChangeTiming, StoreChangeTiming.immediate);
    });

    test('a fresh purchase reports no change timing', () async {
      final _FakeStoreRail rail = _FakeStoreRail(
        store: ManageVia.playStore,
        offerings: _playCatalogue(),
      );

      expect(rail.lastChangeTiming, isNull);
      await rail.purchase('pro_annual', context: _tiers);
      expect(rail.lastChangeTiming, isNull);
    });

    test('a dismissed change leaves no timing behind', () async {
      // The timing of a change that never happened would tell the screen a
      // plan moves at renewal when nothing moves at all.
      final _FakeStoreRail rail = _FakeStoreRail(
        store: ManageVia.playStore,
        offerings: _playCatalogue(),
        activeProducts: const ['business_sub:monthly'],
      );
      await rail.purchase('pro_monthly', context: _tiers);
      expect(rail.lastChangeTiming, StoreChangeTiming.atRenewal);

      rail.raisingOnPurchase = PlatformException(
        code: PurchasesErrorCode.purchaseCancelledError.index.toString(),
      );
      expect(await rail.purchase('pro_annual', context: _tiers), isFalse);
      expect(rail.lastChangeTiming, isNull);
    });
  });

  group('a grandfathered Play product is changed by its store id', () {
    /// Tier facts carrying the store id of a product no offering sells any
    /// more, the way an app builds them from the plan rows' `store_ids`.
    PurchaseContext grandfathered(Map<String, String> tierOfStoreProduct) =>
        PurchaseContext(
          tierOrder: _tiers.tierOrder,
          tierOfProduct: _tiers.tierOfProduct,
          tierOfStoreProduct: tierOfStoreProduct,
        );

    Matcher change(String oldProduct, StoreReplacementMode mode) =>
        isA<StoreProductChangeInfo>()
            .having(
              (StoreProductChangeInfo info) => info.oldProductIdentifier,
              'oldProductIdentifier',
              oldProduct,
            )
            .having(
              (StoreProductChangeInfo info) => info.replacementMode,
              'replacementMode',
              mode,
            );

    _FakeStoreRail holding(String active) => _FakeStoreRail(
      store: ManageVia.playStore,
      offerings: _playCatalogue(),
      activeProducts: [active],
    );

    test('an upgrade from it is charged in full, its price unknown', () async {
      // No package, so no price: whether the price per day rises cannot be
      // known, and only CHARGE_FULL_PRICE is valid either way.
      final _FakeStoreRail rail = holding('old_sub:monthly');

      expect(
        await rail.purchase(
          'business_monthly',
          context: grandfathered(const {'old_sub:monthly': 'pro'}),
        ),
        isTrue,
      );
      expect(
        rail.productChanges.single,
        change('old_sub', StoreReplacementMode.chargeFullPrice),
      );
      expect(rail.lastChangeTiming, StoreChangeTiming.immediate);
    });

    test('a downgrade from it is deferred', () async {
      final _FakeStoreRail rail = holding('old_sub:monthly');

      await rail.purchase(
        'pro_monthly',
        context: grandfathered(const {'old_sub:monthly': 'business'}),
      );

      expect(
        rail.productChanges.single,
        change('old_sub', StoreReplacementMode.deferred),
      );
      expect(rail.lastChangeTiming, StoreChangeTiming.atRenewal);
    });

    test('its tier is found by the bare subscription id', () async {
      // RevenueCat may report a base plan the catalogue rows never listed;
      // the subscription is still the one the rows name.
      final _FakeStoreRail rail = holding('old_sub:p1m-legacy');

      await rail.purchase(
        'business_monthly',
        context: grandfathered(const {'old_sub:monthly': 'pro'}),
      );

      expect(
        rail.productChanges.single,
        change('old_sub', StoreReplacementMode.chargeFullPrice),
      );
    });

    test('the full store id wins over the bare subscription id', () async {
      final _FakeStoreRail rail = holding('old_sub:monthly');

      await rail.purchase(
        'pro_monthly',
        context: grandfathered(const {
          'old_sub:annual': 'free',
          'old_sub:monthly': 'business',
        }),
      );

      expect(
        rail.productChanges.single,
        change('old_sub', StoreReplacementMode.deferred),
      );
    });

    test('a subscription id naming two tiers is refused', () async {
      final _FakeStoreRail rail = holding('old_sub:p1m-legacy');

      await expectLater(
        rail.purchase(
          'business_monthly',
          context: grandfathered(const {
            'old_sub:annual': 'free',
            'old_sub:monthly': 'business',
          }),
        ),
        _refusedWith(BillingErrorCode.unmappedActiveProduct),
      );
      expect(rail.purchased, isEmpty);
    });

    test('a base-plan switch from it is refused, its period unknown', () async {
      // Same subscription, so Play allows only a full charge (longer period)
      // or no proration (shorter), and which one is a guess without the
      // current period.
      final _FakeStoreRail rail = holding('pro_sub:legacy');

      await expectLater(
        rail.purchase(
          'pro_annual',
          context: grandfathered(const {'pro_sub:legacy': 'pro'}),
        ),
        _refusedWith(BillingErrorCode.unmappedActiveProduct),
      );
      expect(rail.purchased, isEmpty);
    });
  });

  group('the App Store rail reports when Apple applies a change', () {
    const PurchaseContext tiers = PurchaseContext(
      tierOrder: ['free', 'pro', 'business'],
      tierOfProduct: {
        'pro_monthly': 'pro',
        'pro_annual': 'pro',
        'business_monthly': 'business',
      },
    );

    Future<StoreChangeTiming?> timingFor(
      String active,
      String productKey, {
      PurchaseContext? context = tiers,
    }) async {
      final _FakeStoreRail rail = _FakeStoreRail(
        offerings: _appStoreCatalogue(),
        activeProducts: [active],
      );

      expect(await rail.purchase(productKey, context: context), isTrue);
      expect(rail.productChanges, [isNull]);

      return rail.lastChangeTiming;
    }

    test('a higher level in the group applies at once', () async {
      expect(
        await timingFor('com.app.pro.monthly', 'business_monthly'),
        StoreChangeTiming.immediate,
      );
    });

    test('a lower level applies at the next renewal', () async {
      expect(
        await timingFor('com.app.business.monthly', 'pro_monthly'),
        StoreChangeTiming.atRenewal,
      );
    });

    test('the same level at another duration applies at renewal', () async {
      expect(
        await timingFor('com.app.pro.monthly', 'pro_annual'),
        StoreChangeTiming.atRenewal,
      );
    });

    test('without the tier order the timing is not claimed', () async {
      expect(
        await timingFor(
          'com.app.pro.monthly',
          'business_monthly',
          context: null,
        ),
        isNull,
      );
    });

    test('a held product no tier names claims no timing', () async {
      expect(
        await timingFor('com.app.legacy.monthly', 'business_monthly'),
        isNull,
      );
    });
  });

  group('a store failure reaches the caller as a typed code', () {
    const Map<PurchasesErrorCode, BillingErrorCode> mapping = {
      PurchasesErrorCode.paymentPendingError: BillingErrorCode.pending,
      PurchasesErrorCode.receiptAlreadyInUseError:
          BillingErrorCode.receiptInUse,
      PurchasesErrorCode.receiptInUseByOtherSubscriberError:
          BillingErrorCode.receiptInUse,
      PurchasesErrorCode.productAlreadyPurchasedError:
          BillingErrorCode.alreadyOwned,
      PurchasesErrorCode.networkError: BillingErrorCode.network,
      PurchasesErrorCode.offlineConnectionError: BillingErrorCode.network,
      PurchasesErrorCode.storeProblemError: BillingErrorCode.store,
      PurchasesErrorCode.configurationError: BillingErrorCode.notConfigured,
      PurchasesErrorCode.productNotAvailableForPurchaseError:
          BillingErrorCode.productUnavailable,
      PurchasesErrorCode.invalidReceiptError: BillingErrorCode.unknown,
    };

    PlatformException raised(PurchasesErrorCode code) =>
        PlatformException(code: code.index.toString(), message: code.name);

    for (final MapEntry<PurchasesErrorCode, BillingErrorCode> entry
        in mapping.entries) {
      test('${entry.key.name} from the sheet is ${entry.value.name}', () async {
        final _FakeStoreRail rail = _FakeStoreRail(
          offerings: _catalogue(),
          raisingOnPurchase: raised(entry.key),
        );

        await expectLater(rail.purchase('pro'), _refusedWith(entry.value));
      });
    }

    test('a paymentPending from restore is pending too', () async {
      final _FakeStoreRail rail = _FakeStoreRail(
        raisingOnRestore: raised(PurchasesErrorCode.paymentPendingError),
      );

      await expectLater(rail.restore(), _refusedWith(BillingErrorCode.pending));
    });

    test('a network failure reading products is network', () async {
      final _FakeStoreRail rail = _FakeStoreRail(
        raisingOnOfferings: raised(PurchasesErrorCode.networkError),
      );

      await expectLater(
        rail.products(['pro']),
        _refusedWith(BillingErrorCode.network),
      );
    });

    test('a non-numeric platform code is unknown, not a crash', () async {
      final _FakeStoreRail rail = _FakeStoreRail(
        offerings: _catalogue(),
        raisingOnPurchase: PlatformException(code: 'channel-error'),
      );

      await expectLater(
        rail.purchase('pro'),
        _refusedWith(BillingErrorCode.unknown),
      );
    });

    test('a plan with no package is productUnavailable', () async {
      final _FakeStoreRail rail = _FakeStoreRail(offerings: _catalogue());

      await expectLater(
        rail.purchase('enterprise'),
        _refusedWith(BillingErrorCode.productUnavailable),
      );
    });
  });

  group('the rail resolves only where a store exists', () {
    test(
      'iOS resolves the RevenueCat driver selling through the App Store',
      () {
        final StoreBillingService? rail = createStoreRail(isIOS: true);

        expect(rail, isA<RevenueCatStoreService>());
        expect(rail!.store, ManageVia.appStore);
      },
    );

    test('Android resolves the RevenueCat driver selling through Play', () {
      final StoreBillingService? rail = createStoreRail(
        isIOS: false,
        isAndroid: true,
      );

      expect(rail, isA<RevenueCatStoreService>());
      expect(rail!.store, ManageVia.playStore);
    });

    test('a dart:io platform without a store resolves null', () {
      // macOS, Windows and Linux all carry `dart:library.io` and none of them
      // has StoreKit or Play Billing, so the io ARM cannot hand the driver back
      // unconditionally: one compiled artifact serves all five platforms.
      expect(createStoreRail(isIOS: false, isAndroid: false), isNull);
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
    super.store = ManageVia.appStore,
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
    String appUserId = _appUserId,
    this.activeProducts = const [],
  }) : boundUserId = appUserId;

  /// The catalogue the offerings seam answers with.
  final Offerings? offerings;

  /// The App User ID the rail is bound to: the one it started with, then the
  /// last one logged in, which is what the SDK itself would answer.
  String boundUserId;

  /// The store product ids the customer-info seam reports active.
  final List<String> activeProducts;

  /// Raised from the seam each one is named for, or null to answer normally.
  ///
  /// The login one is mutable so a test can fail one identify among several.
  Object? raisingOnLogIn;
  final Object? raisingOnAttributes;
  final Object? raisingOnOfferings;
  final Object? raisingOnRestore;

  /// Raised from the purchase sheet, mutable so a test can dismiss one
  /// purchase among several.
  Object? raisingOnPurchase;
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

  /// The product change each of those purchases carried, null for none.
  final List<StoreProductChangeInfo?> productChanges = [];

  /// How many times the restore seam was reached.
  int restoreCalls = 0;

  /// Every URL the driver asked the launch seam to open, in order.
  final List<String> launched = [];

  @override
  Future<void> configureSdk(String apiKey) async => configured.add(apiKey);

  @override
  Future<void> logInSdk(String appUserId) async {
    if (raisingOnLogIn != null) throw raisingOnLogIn!;
    loggedIn.add(appUserId);
    boundUserId = appUserId;
  }

  @override
  Future<String> currentAppUserId() async => boundUserId;

  @override
  Future<List<String>> activeStoreProductIds() async => activeProducts;

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
  Future<void> purchaseStorePackage(
    Package package, {
    StoreProductChangeInfo? productChangeInfo,
  }) async {
    if (raisingOnPurchase != null) throw raisingOnPurchase!;
    purchased.add(package.identifier);
    purchasedProducts.add(package.storeProduct.identifier);
    productChanges.add(productChangeInfo);
  }

  @override
  Future<bool> restoreStorePurchases() async {
    restoreCalls++;
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
