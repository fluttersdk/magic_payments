import 'package:flutter_test/flutter_test.dart';
import 'package:magic/magic.dart';
import 'package:magic_payments/magic_payments.dart';

import '../test_helper.dart';

void main() {
  setUp(() {
    resetPaymentsState();
    bindLogFacade();
  });

  tearDown(resetPaymentsState);

  group('the service provider binds the manager and wires it in boot', () {
    test('Magic.make resolves the manager after Magic.init', () async {
      await initMagicForTests(
        providers: [PaymentsServiceProvider(MagicApp.instance)],
      );

      // The container key is a string because magic has no reflection: this is
      // the exact call a consumer's own provider makes to reach billing.
      expect(Magic.make<PaymentsManager>('payments'), same(PaymentsManager()));
    });

    test('register binds one key and boot is what wires the driver', () async {
      // One test for both halves of the register/boot split, because the two
      // are the same mistake seen from two sides: config reads and driver
      // wiring in `register()` run before other providers have bound anything
      // they might need.
      int calls = 0;
      PaymentsManager().extend(PaymentsManager.billingRole, () {
        calls++;

        return _FakeBillingReads();
      });

      final MagicApp app = MagicApp.instance;
      app.register(PaymentsServiceProvider(app));

      expect(app.bound('payments'), isTrue);
      expect(
        calls,
        0,
        reason:
            'register() must bind only; wiring a driver there is boot()s job.',
      );
      for (final String key in _keysRegisterMustNotBind) {
        expect(app.bound(key), isFalse, reason: 'register() bound [$key] too.');
      }

      await app.boot();

      expect(
        calls,
        1,
        reason: 'boot() must wire the platform driver through the factory.',
      );
    });

    test('an absent config root still wires the driver, quietly', () async {
      // The state an app is in before it publishes a config, and the state a
      // test is in. Entitlement reads are honourable on every platform, so
      // there is nothing here worth complaining about.
      final FakeLogManager log = Log.fake();
      final MagicApp app = MagicApp.instance;
      app.register(PaymentsServiceProvider(app));

      await app.boot();

      expect(Config.get<String>('payments.driver'), isNull);
      log.assertNothingLogged('error');
    });

    test('the platform mode is the shipped value and is accepted', () async {
      Config.set('payments.driver', 'platform');
      final FakeLogManager log = Log.fake();
      final MagicApp app = MagicApp.instance;
      app.register(PaymentsServiceProvider(app));

      await app.boot();

      log.assertNothingLogged('error');
    });

    test('a mode this package cannot serve is reported, not obeyed', () async {
      // The key is a MODE, and the only thing that can answer "what can this
      // build do" is the conditional import. So a value naming something else
      // is a misconfiguration that has to be said out loud: accepting it
      // silently would leave the operator believing a rail was wired.
      Config.set('payments.driver', 'revenuecat');
      final FakeLogManager log = Log.fake();
      final MagicApp app = MagicApp.instance;
      app.register(PaymentsServiceProvider(app));

      await app.boot();

      final Iterable<String> errors = log.entries
          .where((FakeLogEntry entry) => entry.level == 'error')
          .map((FakeLogEntry entry) => entry.message);
      expect(errors, hasLength(1));
      expect(errors.single, contains('revenuecat'));
      expect(errors.single, contains('platform'));

      // Reported and then ignored, deliberately: the reads must survive a typo
      // in a key that cannot change what this build is capable of.
      expect(Payments.billing.runtimeType, createBillingService().runtimeType);
    });

    test(
      'boot reports which driver and which rails this build resolved',
      () async {
        final FakeLogManager log = Log.fake();
        final MagicApp app = MagicApp.instance;
        app.register(PaymentsServiceProvider(app));

        await app.boot();

        // The single most useful line in a support ticket that says "billing says
        // it is unsupported": it names the resolved implementation and whether
        // each rail is present, read from the same source the getters read.
        final String message = log.entries
            .map((FakeLogEntry entry) => entry.message)
            .join('\n');
        expect(
          message,
          contains(createBillingService().runtimeType.toString()),
        );
        expect(message, contains('web'));
        expect(message, contains('store'));
      },
    );
  });
}

/// Container keys `register()` must not bind. Each is a plausible next
/// addition: a per-role binding would give the container a second opinion on
/// which driver serves a rail.
const List<String> _keysRegisterMustNotBind = [
  'billing',
  'web',
  'store',
  'payments.billing',
];

/// A fake serving the five READS and neither rail.
///
/// Its methods throw rather than answering: nothing in these tests calls one,
/// and a fake that returned a plausible entitlement would invite a test to
/// assert on data no producer ever sent.
class _FakeBillingReads implements BillingService {
  @override
  Future<BillingEntitlement> currentEntitlement() =>
      throw UnsupportedError('identity fake');

  @override
  Future<List<Map<String, dynamic>>> getPlans() =>
      throw UnsupportedError('identity fake');

  @override
  Future<BillingInvoicesPage> getInvoices({String? cursor}) =>
      throw UnsupportedError('identity fake');

  @override
  Future<PaymentMethod> getPaymentMethod() =>
      throw UnsupportedError('identity fake');

  @override
  Future<List<UsageStat>> getUsage() => throw UnsupportedError('identity fake');
}
