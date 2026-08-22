import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:magic/magic.dart';
// `StoreBillingService` now reaches this file through the barrel, which the
// completed public surface exports; the direct import it used to need became
// redundant the moment the barrel was finished. The io driver is still imported
// directly, because this file is about that arm specifically.
import 'package:magic_payments/magic_payments.dart';
import 'package:magic_payments/src/drivers/billing_service_io.dart';

/// The `GET /billing` body, envelope included.
///
/// Copied from the producer (`SubscriptionResource::toArray()` under the
/// controller's `['data' => ...]` wrapper), not written from memory: the driver's
/// job on this endpoint is to unwrap `data`, so a fixture without the envelope
/// would assert the opposite of what ships.
const Map<String, dynamic> _entitlementBody = {
  'data': {
    'plan': 'pro',
    'plan_status': 'active',
    'subscribed': true,
    'renews': true,
    'provider': 'stripe',
    'provider_status': null,
    'product_id': null,
    'manage_via': 'portal',
    'manage_url': null,
    'current_period_end': '2026-09-01T12:00:00.000Z',
    'trial_ends_at': null,
    'grace_period_ends_at': null,
    'ai_analysis_trials_remaining': null,
  },
};

/// The `GET /billing/plans` body: the vendor's catalogue served verbatim under a
/// `data` envelope.
///
/// One real row, keys and nesting copied from the producer's plan catalogue
/// config. It carries `features` and `limits` deliberately: a row is handed over
/// undecoded, so the test that matters is that nothing was dropped on the way
/// through.
const Map<String, dynamic> _plansBody = {
  'data': [
    {
      'id': 'free',
      'name': 'Free',
      'tagline': 'Kick the tires, solo projects.',
      'monthly': 0,
      'annual': 0,
      'currency': 'usd',
      'features': ['1 monitor', '1 status page'],
      'recommended': false,
      'limits': {'monitors': 1, 'responders': 1, 'regions': 1},
    },
    {
      'id': 'pro',
      'name': 'Pro',
      'tagline': 'For teams on call.',
      'monthly': 29,
      'annual': 290,
      'currency': 'usd',
      'features': ['20 monitors', 'unlimited status pages'],
      'recommended': true,
      'limits': {'monitors': 20, 'responders': 10, 'regions': null},
    },
  ],
};

/// The `GET /billing/usage` body, FLAT and enveloped by nothing.
///
/// The producer returns the metered resources at the top level of this one
/// endpoint, so a driver that unwrapped `data` here would read an empty map and
/// report zero usage against every cap.
const Map<String, dynamic> _usageBody = {
  'monitors': {'used': 3, 'limit': 20},
  'responders': {'used': 2, 'limit': 10},
  'checks_this_month': {'used': 41234, 'limit': null},
};

/// The `GET /billing/invoices` body: rows under `data`, the cursor alongside it.
///
/// Row keys copied from the producer's invoice resource, whose `amount` is an
/// already-formatted currency string.
const Map<String, dynamic> _invoicesBody = {
  'data': [
    {
      'id': 'in_1P9xQ2',
      'number': 'A1B2C3-0001',
      'date': '2026-08-01T09:15:00.000Z',
      'amount': r'$29.00',
      'status': 'paid',
      'pdf_url': 'https://invoice.example.com/in_1P9xQ2.pdf',
    },
  ],
  'next_cursor': 'eyJpZCI6ImluXzFQOXhRMiJ9',
};

/// The `GET /billing/payment-method` body, FLAT like the usage one.
const Map<String, dynamic> _paymentMethodBody = {
  'renewal_date': '2026-09-01T12:00:00.000Z',
  'brand': 'visa',
  'last4': '4242',
  'exp_month': 8,
  'exp_year': 2027,
};

/// Every write a rail contract declares, plus the four the moved driver used to
/// throw from. A declaration of any of them inside `lib/src/drivers/` is a
/// purchase path a build can reach.
const List<String> _writeMethodNames = [
  'purchase',
  'restore',
  'openStoreManagement',
  'checkout',
  'swap',
  'cancel',
  'openPortal',
];

/// Matches a Dart METHOD DECLARATION of one of [_writeMethodNames], and not a
/// call to one.
///
/// Anchored to the start of a line and preceded by a return type, so
/// `subscription.cancel()` and a docblock naming `cancel` do not match. The
/// distinction is the whole point: this package's defect history includes a
/// review grep that matched the comment warning against the thing it searched
/// for.
final RegExp _writeMethodDeclaration = RegExp(
  '^\\s*(?:Future<[^>]*>|void|Never)\\s+(${_writeMethodNames.join('|')})\\s*\\(',
  multiLine: true,
);

/// Matches a class taking on the store rail's contract, however it takes it on.
final RegExp _storeRailImplementation = RegExp(
  r'(?:implements|extends|with)\s+[^{]*\bStoreBillingService\b',
);

const String _ioDriverPath = 'lib/src/drivers/billing_service_io.dart';

void main() {
  group('BillingServiceIo reads', () {
    late FakeNetworkDriver network;

    setUp(() {
      // The reads log before they throw, and a log call with no bound manager
      // would fail the failure path for the wrong reason.
      Log.fake();
    });

    tearDown(() {
      Http.unfake();
      Log.unfake();
    });

    test(
      'currentEntitlement reads GET /billing and unwraps its data envelope',
      () async {
        network = Http.fake({'/billing': Http.response(_entitlementBody)});

        final BillingEntitlement entitlement = await const BillingServiceIo()
            .currentEntitlement();

        network.assertSent(
          (MagicRequest request) =>
              request.method == 'GET' && request.url == '/billing',
        );
        expect(entitlement.plan, 'pro');
        expect(entitlement.planStatus, PlanStatus.active);
        expect(entitlement.manageVia, ManageVia.portal);
        expect(entitlement.subscribed, isTrue);
      },
    );

    test(
      'getPlans reads GET /billing/plans and hands every row over undecoded',
      () async {
        network = Http.fake({'/billing/plans': Http.response(_plansBody)});

        final List<Map<String, dynamic>> plans = await const BillingServiceIo()
            .getPlans();

        network.assertSent(
          (MagicRequest request) => request.url == '/billing/plans',
        );
        expect(plans, hasLength(2));
        expect(plans.first['id'], 'free');
        // The row arrives whole, nested keys included: dropping the half of a row
        // this package has no model for is exactly what returning raw maps avoids.
        expect(plans.first['limits'], {
          'monitors': 1,
          'responders': 1,
          'regions': 1,
        });
        expect(plans.last['features'], [
          '20 monitors',
          'unlimited status pages',
        ]);
      },
    );

    test(
      'getUsage reads GET /billing/usage from the FLAT body, keeping an unlimited cap null',
      () async {
        network = Http.fake({'/billing/usage': Http.response(_usageBody)});

        final List<UsageStat> usage = await const BillingServiceIo().getUsage();

        network.assertSent(
          (MagicRequest request) => request.url == '/billing/usage',
        );
        expect(usage.map((UsageStat stat) => stat.key), [
          'monitors',
          'responders',
          'checks_this_month',
        ]);
        expect(usage.first.used, 3);
        expect(usage.first.limit, 20);
        // Unlimited must stay null: read as zero it would gate a paying customer
        // out of what they bought.
        expect(usage.last.limit, isNull);
      },
    );

    test(
      'getInvoices reads GET /billing/invoices and keeps the next cursor',
      () async {
        network = Http.fake({
          '/billing/invoices': Http.response(_invoicesBody),
        });

        final BillingInvoicesPage page = await const BillingServiceIo()
            .getInvoices();

        network.assertSent(
          (MagicRequest request) => request.url == '/billing/invoices',
        );
        expect(page.invoices, hasLength(1));
        expect(page.invoices.first.number, 'A1B2C3-0001');
        expect(page.invoices.first.amount, r'$29.00');
        expect(page.invoices.first.status, InvoiceStatus.paid);
        expect(page.nextCursor, 'eyJpZCI6ImluXzFQOXhRMiJ9');
      },
    );

    test(
      'getInvoices sends the cursor as a query parameter, and omits it on the first page',
      () async {
        network = Http.fake({
          '/billing/invoices': Http.response(_invoicesBody),
        });

        await const BillingServiceIo().getInvoices();
        await const BillingServiceIo().getInvoices(cursor: 'page-two');

        // Two separate guards, so a fix to one cannot hide the other: an absent
        // cursor must not send an empty parameter, and a present one must ride the
        // query rather than the path.
        expect(network.recorded.first.$1.queryParameters, isNull);
        expect(network.recorded.last.$1.queryParameters, {
          'cursor': 'page-two',
        });
      },
    );

    test(
      'getPaymentMethod reads GET /billing/payment-method from the FLAT body',
      () async {
        network = Http.fake({
          '/billing/payment-method': Http.response(_paymentMethodBody),
        });

        final PaymentMethod method = await const BillingServiceIo()
            .getPaymentMethod();

        network.assertSent(
          (MagicRequest request) => request.url == '/billing/payment-method',
        );
        expect(method.brand, 'visa');
        expect(method.last4, '4242');
        expect(method.expMonth, 8);
        expect(method.expYear, 2027);
        expect(method.renewalDate, DateTime.utc(2026, 9, 1, 12));
      },
    );

    test(
      'a soft-failed payment method resolves all-null instead of throwing',
      () async {
        // The producer answers 200 with every field null when the rail is down, so
        // a resolved value does not imply a card and must not imply an error.
        network = Http.fake({
          '/billing/payment-method': Http.response({
            'renewal_date': null,
            'brand': null,
            'last4': null,
            'exp_month': null,
            'exp_year': null,
          }),
        });

        final PaymentMethod method = await const BillingServiceIo()
            .getPaymentMethod();

        expect(method.brand, isNull);
        expect(method.renewalDate, isNull);
      },
    );

    test(
      'a non-2xx entitlement response throws BillingException carrying the producer message',
      () async {
        network = Http.fake({
          '/billing': Http.response({'message': 'Team not found.'}, 404),
        });

        await expectLater(
          const BillingServiceIo().currentEntitlement(),
          throwsA(
            isA<BillingException>().having(
              (BillingException error) => error.message,
              'message',
              'Team not found.',
            ),
          ),
        );
        network.assertSentCount(1);
      },
    );

    test(
      'a malformed entitlement payload throws BillingException rather than a cast error',
      () async {
        network = Http.fake({
          '/billing': Http.response({'data': 'nonsense'}),
        });

        await expectLater(
          const BillingServiceIo().currentEntitlement(),
          throwsA(isA<BillingException>()),
        );
      },
    );

    test('no read throws for want of a platform', () async {
      Http.fake({
        '/billing': Http.response(_entitlementBody),
        '/billing/plans': Http.response(_plansBody),
        '/billing/usage': Http.response(_usageBody),
        '/billing/invoices': Http.response(_invoicesBody),
        '/billing/payment-method': Http.response(_paymentMethodBody),
      });

      const BillingServiceIo driver = BillingServiceIo();

      // All five, in one test, because the claim under test is about the SET:
      // after the contract narrowed to reads, nothing this driver declares is
      // allowed to refuse the device it runs on.
      await expectLater(driver.currentEntitlement(), completes);
      await expectLater(driver.getPlans(), completes);
      await expectLater(driver.getUsage(), completes);
      await expectLater(driver.getInvoices(), completes);
      await expectLater(driver.getPaymentMethod(), completes);
    });
  });

  group('the store rail is absent, not broken', () {
    test('the mobile driver declares no purchase-affecting method at all', () {
      final String source = _strippedSource(File(_ioDriverPath));

      // Guard against a vacuous pass: the stripper must have left the code it
      // was pointed at, or an empty string would satisfy every assertion below.
      expect(source, contains('class BillingServiceIo'));
      expect(source, contains('currentEntitlement('));

      expect(
        _writeMethodDeclaration
            .allMatches(source)
            .map((RegExpMatch match) => match.group(1))
            .toList(),
        isEmpty,
        reason:
            'A write declared here is a purchase path a store build can reach, '
            'and the four that used to live here are what shipped a broken CTA.',
      );
    });

    test('the mobile driver names UnsupportedPlatformException nowhere', () {
      final String source = _strippedSource(File(_ioDriverPath));

      expect(source, contains('class BillingServiceIo'));
      expect(
        source,
        isNot(contains('UnsupportedPlatformException')),
        reason:
            'An unavailable rail is a null a caller can check, never a throw a '
            'caller has to catch.',
      );
    });

    test('exactly one class in lib implements StoreBillingService', () {
      // The successor to a dated assertion. Until the RevenueCat driver landed
      // this counted ZERO implementations; it counts ONE now, and the count is
      // what still bites: a second class taking on the contract is a second
      // purchase path, and the two would disagree about which account a purchase
      // was attributed to.
      final List<File> dartFiles = Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((File file) => file.path.endsWith('.dart'))
          .toList();

      // The sweep has to have swept something; an empty set satisfies a length
      // assertion for the wrong reason.
      expect(dartFiles.length, greaterThan(5));

      final List<String> implementations = dartFiles
          .where(
            (File file) =>
                _storeRailImplementation.hasMatch(_strippedSource(file)),
          )
          .map((File file) => file.path)
          .toList();

      expect(implementations, [
        'lib/src/drivers/revenuecat_store_service.dart',
      ]);
    });

    test(
      'identify is reachable through the contract, not only on an implementation',
      () async {
        // Step 30 binds a team switch to the store rail through this interface. A
        // member that existed only on the RevenueCat class would be a member that
        // binding cannot reach, which is why the test types the variable as the
        // contract.
        final _RecordingStoreRail rail = _RecordingStoreRail();
        final StoreBillingService contract = rail;

        await contract.identify('team_7');

        expect(rail.identified, ['team_7']);
      },
    );

    test(
      'the contract answers a purchase with whether the entitlement changed',
      () async {
        final StoreBillingService contract = _RecordingStoreRail();

        expect(await contract.purchase(plan: 'pro'), isTrue);
        expect(await contract.restore(), isFalse);
        await expectLater(contract.openStoreManagement(), completes);
      },
    );
  });
}

/// Reads [file] with its comments removed.
///
/// A grep over raw source hits the docblock that explains why the thing it
/// searches for is absent, which is how a review grep once certified the
/// opposite of what it measured.
String _strippedSource(File file) {
  return file
      .readAsStringSync()
      .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '')
      .replaceAll(RegExp(r'^\s*///.*$', multiLine: true), '')
      .replaceAll(RegExp(r'^\s*//.*$', multiLine: true), '');
}

/// A test double for the store rail, and the only implementation of
/// [StoreBillingService] that exists anywhere.
///
/// It lives in the test tree on purpose: the assertion above sweeps `lib/`, so a
/// double here proves the contract is implementable without making the package
/// claim a purchase path it cannot serve.
class _RecordingStoreRail implements StoreBillingService {
  final List<String> identified = [];

  @override
  Future<void> identify(String appUserId) async {
    identified.add(appUserId);
  }

  @override
  Future<bool> purchase({required String plan}) async => true;

  @override
  Future<bool> restore() async => false;

  @override
  Future<void> openStoreManagement() async {}
}
