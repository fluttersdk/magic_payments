import 'package:flutter_test/flutter_test.dart';
import 'package:magic/magic.dart';
// The barrel exports the FACTORY's copies of the three creator functions, and
// the group below is about the WEB ARM's copies, which it imports directly a
// line down. Both are deliberate, and every conditional-import arm declaring the
// same three names is the design rather than an accident, so the collision is
// resolved here at the one call site that wants the arm rather than by renaming
// anything.
import 'package:magic_payments/magic_payments.dart'
    hide
        createBillingService,
        createStoreBillingService,
        createWebBillingService;
import 'package:magic_payments/src/drivers/billing_service_web.dart';

import '../test_helper.dart';

/// The `GET /billing` body, envelope included.
///
/// Copied from the producer (`SubscriptionResource::toArray()` under the
/// controller's `['data' => ...]` wrapper), not written from memory: this
/// endpoint is one of the two the driver unwraps, so a fixture without the
/// envelope would assert the opposite of what ships.
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

/// The `GET /billing/plans` body: the vendor's catalogue under a `data`
/// envelope, served verbatim from the producer's plan config.
///
/// It carries `features` and `limits` deliberately. The web driver used to
/// decode this into a consumer-owned `Plan`; it now hands the row over whole,
/// and what matters is that nothing was dropped on the way through.
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

/// The `GET /billing/invoices` body: rows under `data`, the cursor alongside
/// it, so the whole body is what the page decoder takes.
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

/// The `GET /billing/payment-method` body, FLAT like the usage one, with all
/// six keys the producer emits.
const Map<String, dynamic> _paymentMethodBody = {
  'available': true,
  'renewal_date': '2026-09-01T12:00:00.000Z',
  'brand': 'visa',
  'last4': '4242',
  'exp_month': 8,
  'exp_year': 2027,
};

/// The `POST /billing/checkout` body: FLAT, and the two keys the producer
/// unwraps its rail's session object into.
const Map<String, dynamic> _checkoutBody = {
  'checkout_url': 'https://checkout.example.com/c/pay/cs_test_a1b2c3',
  'session_id': 'cs_test_a1b2c3',
};

/// The `GET /billing/portal` body: FLAT, one minted single-use URL.
const Map<String, dynamic> _portalBody = {
  'portal_url': 'https://billing.example.com/p/session/live_YWNjd',
};

/// The `POST /billing/swap` and `POST /billing/cancel` body.
///
/// Both actions answer with the whole re-read entitlement resource, envelope
/// included. The driver returns `void` from both, so the fixture is here to
/// prove exactly that: a body this shaped is not decoded into anything.
const Map<String, dynamic> _subscriptionBody = _entitlementBody;

/// The producer's 409 refusal, copied from `abortWithBillingConflict()`.
///
/// The store-owned case, which is the one refusal the web rail meets in
/// production: a customer who bought on a phone opens the web app and taps
/// Cancel. It is a real body and not a bare 500, so the message the customer
/// reads has to be the producer's own.
const Map<String, dynamic> _storeOwnedConflictBody = {
  'message':
      'This subscription is managed by the store that sold it and cannot be '
      'changed here.',
  'billing': {'reason': 'managed_by_store', 'provider': 'app_store'},
};

void main() {
  late FakeNetworkDriver network;
  late RecordingLaunchAdapter launcher;

  setUp(() {
    // Both bindings are load-bearing rather than tidy. Every method logs before
    // it throws, so an unbound `log` would fail a failure-path test for the
    // wrong reason, and the two write paths that open a hosted page resolve
    // `launch` on their success path, so an unbound one would fail the happy
    // path for the wrong reason too.
    Log.fake();
    launcher = bindLaunchFacade();
  });

  tearDown(() {
    Http.unfake();
    Log.unfake();
    unbindLaunchFacade();
  });

  group('BillingServiceWeb serves both the reads and the web rail', () {
    test('one class answers to the read contract and to the web rail', () {
      // The design claim of this driver: nine calls, one transport, one
      // envelope convention. A caller holding either contract is holding this
      // object, and the rail is checkable rather than throwable.
      const BillingServiceWeb driver = BillingServiceWeb();
      final BillingService reads = driver;
      final WebBillingService rail = driver;

      expect(reads, same(rail));
    });

    test('the web arm resolves a web rail and no store rail', () {
      // What the conditional import buys: on this arm the web rail is present,
      // and the store rail is absent as a null a caller can check rather than a
      // method that throws. The three are typed rather than inferred, because
      // the return TYPES are the conditional-import contract every other arm
      // has to match.
      final BillingService service = createBillingService();
      final WebBillingService? web = createWebBillingService();
      final StoreBillingService? store = createStoreBillingService();

      expect(service, isA<BillingServiceWeb>());
      expect(web, isA<BillingServiceWeb>());
      expect(store, isNull);
    });
  });

  group('BillingServiceWeb reads', () {
    test(
      'currentEntitlement reads GET /billing and unwraps its data envelope',
      () async {
        network = Http.fake({'/billing': Http.response(_entitlementBody)});

        final BillingEntitlement entitlement = await const BillingServiceWeb()
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

        final List<Map<String, dynamic>> plans = await const BillingServiceWeb()
            .getPlans();

        network.assertSent(
          (MagicRequest request) =>
              request.method == 'GET' && request.url == '/billing/plans',
        );
        expect(plans, hasLength(2));
        expect(plans.first['id'], 'free');
        // The row arrives whole, nested keys included. This is where the moved
        // driver changed shape: it used to decode a consumer-owned `Plan` and
        // drop everything that type had no field for.
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

        final List<UsageStat> usage = await const BillingServiceWeb()
            .getUsage();

        network.assertSent(
          (MagicRequest request) =>
              request.method == 'GET' && request.url == '/billing/usage',
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

        final BillingInvoicesPage page = await const BillingServiceWeb()
            .getInvoices();

        network.assertSent(
          (MagicRequest request) =>
              request.method == 'GET' && request.url == '/billing/invoices',
        );
        expect(page.invoices, hasLength(1));
        expect(page.invoices.first.number, 'A1B2C3-0001');
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

        await const BillingServiceWeb().getInvoices();
        await const BillingServiceWeb().getInvoices(cursor: 'page-two');

        // Two separate guards, so a fix to one cannot hide the other: an absent
        // cursor must not send an empty parameter, and a present one must ride
        // the query rather than the path.
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

        final PaymentMethod method = await const BillingServiceWeb()
            .getPaymentMethod();

        network.assertSent(
          (MagicRequest request) =>
              request.method == 'GET' &&
              request.url == '/billing/payment-method',
        );
        expect(method.brand, 'visa');
        expect(method.last4, '4242');
        expect(method.expMonth, 8);
        expect(method.expYear, 2027);
        expect(method.renewalDate, DateTime.utc(2026, 9, 1, 12));
        // The field a consumer gates its "we could not reach the payment
        // provider" copy on, asserted here and not only on the value object,
        // because this is the only place the flat-body read is exercised.
        expect(method.available, isTrue);
      },
    );

    test('no read opens a browser tab', () async {
      Http.fake({
        '/billing': Http.response(_entitlementBody),
        '/billing/plans': Http.response(_plansBody),
        '/billing/usage': Http.response(_usageBody),
        '/billing/invoices': Http.response(_invoicesBody),
        '/billing/payment-method': Http.response(_paymentMethodBody),
      });

      const BillingServiceWeb driver = BillingServiceWeb();
      await driver.currentEntitlement();
      await driver.getPlans();
      await driver.getUsage();
      await driver.getInvoices();
      await driver.getPaymentMethod();

      // A read that navigated away would take the customer off the billing
      // screen for looking at it. Only the two write paths that mint a hosted
      // page are allowed to launch anything.
      expect(launcher.launched, isEmpty);
    });
  });

  group('BillingServiceWeb checkout', () {
    test(
      'checkout posts the plan and both return URLs, then opens the hosted page in an in-app web view',
      () async {
        network = Http.fake({
          '/billing/checkout': Http.response(_checkoutBody),
        });

        final BillingCheckoutSession session = await const BillingServiceWeb()
            .checkout(
              plan: 'pro',
              successUrl: 'https://example.com/billing?checkout=success',
              cancelUrl: 'https://example.com/billing?checkout=cancel',
            );

        network.assertSent(
          (MagicRequest request) =>
              request.method == 'POST' &&
              request.url == '/billing/checkout' &&
              request.data is Map<String, dynamic> &&
              (request.data as Map<String, dynamic>)['plan'] == 'pro' &&
              (request.data as Map<String, dynamic>)['success_url'] ==
                  'https://example.com/billing?checkout=success' &&
              (request.data as Map<String, dynamic>)['cancel_url'] ==
                  'https://example.com/billing?checkout=cancel',
        );
        // The wire keys are snake_case because the producer validates them by
        // that name; a camelCase payload is a 422 the client cannot see.
        expect(
          (network.recorded.single.$1.data as Map<String, dynamic>).keys,
          containsAll(<String>['plan', 'success_url', 'cancel_url']),
        );
        expect(session.checkoutUrl, _checkoutBody['checkout_url']);
        expect(session.sessionId, 'cs_test_a1b2c3');
        // In-app, not external: an external browser leaves the app, and the
        // success URL that brings the customer back would land in Safari.
        expect(launcher.launched, hasLength(1));
        expect(
          launcher.launched.single.$1,
          Uri.parse(_checkoutBody['checkout_url'] as String),
        );
        expect(launcher.launched.single.$2, LaunchMode.inAppWebView);
      },
    );

    test(
      'a refused checkout throws the producer message and opens nothing',
      () async {
        network = Http.fake({
          '/billing/checkout': Http.response(_storeOwnedConflictBody, 409),
        });

        await expectLater(
          const BillingServiceWeb().checkout(
            plan: 'pro',
            successUrl: 'https://example.com/ok',
            cancelUrl: 'https://example.com/no',
          ),
          throwsA(
            isA<BillingException>().having(
              (BillingException error) => error.message,
              'message',
              _storeOwnedConflictBody['message'],
            ),
          ),
        );
        expect(launcher.launched, isEmpty);
      },
    );

    test(
      'a malformed checkout body throws instead of opening a blank tab',
      () async {
        // Its own test rather than an extra assertion on the refusal above: the
        // two guards sit on one outcome, and a single assertion would still pass
        // with either of them deleted.
        network = Http.fake({
          '/billing/checkout': Http.response('not an object'),
        });

        await expectLater(
          const BillingServiceWeb().checkout(
            plan: 'pro',
            successUrl: 'https://example.com/ok',
            cancelUrl: 'https://example.com/no',
          ),
          throwsA(isA<BillingException>()),
        );
        expect(launcher.launched, isEmpty);
      },
    );
  });

  group('BillingServiceWeb swap and cancel', () {
    test('swap posts the plan word, never a rail price id', () async {
      network = Http.fake({'/billing/swap': Http.response(_subscriptionBody)});

      await const BillingServiceWeb().swap(plan: 'business');

      network.assertSent(
        (MagicRequest request) =>
            request.method == 'POST' &&
            request.url == '/billing/swap' &&
            request.data is Map<String, dynamic> &&
            (request.data as Map<String, dynamic>)['plan'] == 'business',
      );
      expect((network.recorded.single.$1.data as Map<String, dynamic>), {
        'plan': 'business',
      });
      expect(launcher.launched, isEmpty);
    });

    test('cancel posts to /billing/cancel with no payload at all', () async {
      network = Http.fake({
        '/billing/cancel': Http.response(_subscriptionBody),
      });

      await const BillingServiceWeb().cancel();

      network.assertSent(
        (MagicRequest request) =>
            request.method == 'POST' && request.url == '/billing/cancel',
      );
      // An empty map would be a body the producer does not validate and does
      // not want; the endpoint takes nothing.
      expect(network.recorded.single.$1.data, isNull);
    });

    test(
      'a store-owned subscription refuses a cancel with the producer message',
      () async {
        network = Http.fake({
          '/billing/cancel': Http.response(_storeOwnedConflictBody, 409),
        });

        await expectLater(
          const BillingServiceWeb().cancel(),
          throwsA(
            isA<BillingException>().having(
              (BillingException error) => error.message,
              'message',
              _storeOwnedConflictBody['message'],
            ),
          ),
        );
      },
    );

    test(
      'a swap the producer refuses throws rather than resolving quietly',
      () async {
        // `swap` returns void, so a swallowed failure would look exactly like a
        // completed plan change to the screen that called it.
        network = Http.fake({
          '/billing/swap': Http.response({
            'message': 'No active subscription to swap.',
          }, 404),
        });

        await expectLater(
          const BillingServiceWeb().swap(plan: 'pro'),
          throwsA(
            isA<BillingException>().having(
              (BillingException error) => error.message,
              'message',
              'No active subscription to swap.',
            ),
          ),
        );
      },
    );
  });

  group('BillingServiceWeb openPortal', () {
    test(
      'openPortal sends the return URL as a query parameter and opens the minted URL',
      () async {
        network = Http.fake({'/billing/portal': Http.response(_portalBody)});

        final String url = await const BillingServiceWeb().openPortal(
          returnUrl: 'https://example.com/billing',
        );

        network.assertSent(
          (MagicRequest request) =>
              request.method == 'GET' && request.url == '/billing/portal',
        );
        expect(network.recorded.single.$1.queryParameters, {
          'return_url': 'https://example.com/billing',
        });
        // Returned as well as opened, because the URL is single-use: a caller
        // that wants the portal again asks for a new one.
        expect(url, _portalBody['portal_url']);
        expect(launcher.launched.single.$1, Uri.parse(url));
        expect(launcher.launched.single.$2, LaunchMode.inAppWebView);
      },
    );

    test(
      'openPortal omits the query parameter entirely when no return URL is given',
      () async {
        network = Http.fake({'/billing/portal': Http.response(_portalBody)});

        await const BillingServiceWeb().openPortal();

        expect(network.recorded.single.$1.queryParameters, isNull);
      },
    );

    test(
      'an empty portal URL throws instead of opening nothing successfully',
      () async {
        // The producer soft-fails nothing on this endpoint, but Cashier answers a
        // customer-less team with a 409 and a malformed body is what a proxy in
        // front of it produces. An empty string would launch nothing and return
        // success.
        network = Http.fake({
          '/billing/portal': Http.response({'portal_url': ''}),
        });

        await expectLater(
          const BillingServiceWeb().openPortal(),
          throwsA(isA<BillingException>()),
        );
        expect(launcher.launched, isEmpty);
      },
    );

    test('a portal body with no portal_url key at all throws', () async {
      network = Http.fake({
        '/billing/portal': Http.response({'message': 'Nope.'}),
      });

      await expectLater(
        const BillingServiceWeb().openPortal(),
        throwsA(isA<BillingException>()),
      );
      expect(launcher.launched, isEmpty);
    });

    test(
      'a team with no billing account is refused with the producer reason',
      () async {
        network = Http.fake({
          '/billing/portal': Http.response({
            'message': 'This team has no billing account to manage yet.',
            'billing': {'reason': 'no_billing_account', 'provider': 'none'},
          }, 409),
        });

        await expectLater(
          const BillingServiceWeb().openPortal(),
          throwsA(
            isA<BillingException>().having(
              (BillingException error) => error.message,
              'message',
              'This team has no billing account to manage yet.',
            ),
          ),
        );
      },
    );
  });

  // ---------------------------------------------------------------------------
  // The hosted-page seam, and the error translation above it
  //
  // `launchHostedPage` is the only line in this driver that reaches
  // `url_launcher`, so it is the marked seam, and `openHostedPage`'s try/catch
  // is the contract these tests assert: anything the platform raises becomes a
  // BillingException the billing screen can show, and something already ours
  // reaches the caller unchanged rather than being wrapped twice.
  //
  // The seam is what a future rail's driver copies. The fake below overrides ONE
  // method of the real driver; it does not mock `url_launcher`, and the control
  // flow under test is the shipped one.
  // ---------------------------------------------------------------------------

  group('BillingServiceWeb translates what the hosted-page seam raises', () {
    test('a raw platform failure becomes a BillingException', () async {
      // The reachable production case: `Launch` resolves a `LaunchService` out
      // of the container, so a consumer that never registered
      // LaunchServiceProvider gets a raw container error out of `checkout()`,
      // and a screen catching BillingException would not catch it.
      //
      // Regression guard for a bare `launchHostedPage(url);`: an unawaited
      // future completes after the try has exited, so the catch clause never
      // sees the error at all and the write reports success.
      Http.fake({'/billing/checkout': Http.response(_checkoutBody)});
      final _FakeHostedPageDriver driver = _FakeHostedPageDriver(
        raising: StateError('no in-app browser on this device'),
      );

      await expectLater(
        driver.checkout(
          plan: 'pro',
          successUrl: 'https://example.com/ok',
          cancelUrl: 'https://example.com/no',
        ),
        throwsA(isA<BillingException>()),
      );
    });

    test('a BillingException from below is rethrown unchanged', () async {
      // The same instance, not merely the same type: wrapping it again would
      // replace the producer's own refusal with this driver's generic message,
      // and the producer's is the one the customer needs to read.
      Http.fake({'/billing/portal': Http.response(_portalBody)});
      const BillingException original = BillingException(
        'This subscription is managed by the store that sold it.',
      );
      final _FakeHostedPageDriver driver = _FakeHostedPageDriver(
        raising: original,
      );

      await expectLater(driver.openPortal(), throwsA(same(original)));
    });

    test('a launcher that declines is a failure, not a silent success', () async {
      // The failure a `catch` can never see. `LaunchService.url` answers `false`
      // for a malformed URL or any platform refusal and never throws
      // (`magic/lib/src/launch/launch_service.dart:29-43`), so before the seam
      // returned a bool this path resolved normally: the customer tapped
      // Upgrade, nothing opened, and checkout reported a session.
      Http.fake({'/billing/checkout': Http.response(_checkoutBody)});
      final _FakeHostedPageDriver driver = _FakeHostedPageDriver(opens: false);

      await expectLater(
        driver.checkout(
          plan: 'pro',
          successUrl: 'https://example.com/ok',
          cancelUrl: 'https://example.com/no',
        ),
        throwsA(isA<BillingException>()),
      );

      // The URL really was handed to the seam: this is a refusal to open, not a
      // failure to try, which is what makes the guard the right place for it.
      expect(driver.opened, hasLength(1));
    });

    test('both hosted pages open through the seam and nothing else', () async {
      // The `launch` binding is removed first, so this cannot pass by falling
      // through to the facade: the seam is the driver's only route to the
      // platform channel, which is what makes overriding it enough.
      Http.fake({
        '/billing/checkout': Http.response(_checkoutBody),
        '/billing/portal': Http.response(_portalBody),
      });
      unbindLaunchFacade();
      final _FakeHostedPageDriver driver = _FakeHostedPageDriver();

      await driver.checkout(
        plan: 'pro',
        successUrl: 'https://example.com/ok',
        cancelUrl: 'https://example.com/no',
      );
      await driver.openPortal();

      expect(driver.opened, [
        _checkoutBody['checkout_url'],
        _portalBody['portal_url'],
      ]);
      expect(launcher.launched, isEmpty);
    });
  });
}

/// A [BillingServiceWeb] with the in-app browser stood in for.
///
/// Only the seam is replaced. The envelope handling, the guards and the
/// try/catch under test are the driver's own.
class _FakeHostedPageDriver extends BillingServiceWeb {
  _FakeHostedPageDriver({this.raising, this.opens = true});

  /// Raised from the seam, or null to record the URL and answer [opens].
  final Object? raising;

  /// What the seam answers when it does not raise.
  ///
  /// Separate from [raising] because the two are genuinely different failures:
  /// a platform channel that throws, and a launcher that declines and says so
  /// with a `false`. Only the first would ever reach a `catch`.
  final bool opens;

  /// Every URL the driver asked the seam to open, in order.
  final List<String> opened = [];

  @override
  Future<bool> launchHostedPage(String url) async {
    if (raising != null) throw raising!;
    opened.add(url);

    return opens;
  }
}
