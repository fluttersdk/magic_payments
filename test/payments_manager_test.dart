import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:magic/magic.dart';
import 'package:magic_payments/magic_payments.dart';

void main() {
  setUp(() {
    // Two resets, because two singletons outlive a test. The container is reset
    // so a provider registration cannot leak into the next test, and the manager
    // is emptied because `PaymentsManager()` is a `static final` that survives
    // `MagicApp.reset()`: a fake rail registered here would otherwise still be
    // registered in the next file, which is how a leaked singleton once served
    // one tenant's data to the next.
    MagicApp.reset();
    MagicApp.instance.singleton('log', LogManager.new);
    PaymentsManager().forgetDrivers();
  });

  tearDown(() {
    PaymentsManager().forgetDrivers();
    MagicApp.reset();
  });

  group('the manager is one instance', () {
    test('two constructions are the same object', () {
      // The house shape: a `static final _instance` behind a `factory`. A second
      // instance would carry its own override registry, so a consumer's
      // `extend` would apply to a manager the billing screen never reads.
      expect(PaymentsManager(), same(PaymentsManager()));
    });
  });

  group('the roles come from the factory, not from a platform check', () {
    test('billing resolves the implementation this build compiled', () {
      final PaymentsManager manager = PaymentsManager();

      // Typed against the factory's own answer rather than against a named
      // class, so this assertion is true on every arm: it says "the manager
      // hands back what the conditional import resolved", which is the whole
      // claim. Naming `BillingServiceIo` here would make the test pass only on
      // the VM and read as a platform assumption inside the one package that
      // must not make any.
      expect(manager.billing.runtimeType, createBillingService().runtimeType);
    });

    test('an absent rail is null, and the absence is not a hardcoded null', () {
      final PaymentsManager manager = PaymentsManager();

      // Half a test on its own: a getter written as `=> null` would satisfy
      // these two lines forever. The second half is the override below, which
      // can only flip the answer if the getter actually reads a source.
      expect(manager.web, isNull);
      expect(manager.store, isNull);

      manager.extend(PaymentsManager.webRole, _FakeWebRail.new);
      manager.extend(PaymentsManager.storeRole, _FakeStoreRail.new);

      expect(manager.web, isA<_FakeWebRail>());
      expect(manager.store, isA<_FakeStoreRail>());
    });

    test('no file in the assembly asks the runtime which device it is on', () {
      // The package's one idea: the rail and the platform are different axes.
      // The conditional import in the factory is the only platform-aware line
      // in the whole package, so a second answer must not appear in the
      // manager, the facade or the provider. Asserted over the RAW source,
      // comments included, because a docblock naming one of these is where the
      // next one arrives, and a review grep that matches the prose warning
      // against a thing reads exactly like a match on the thing.
      for (final String path in _assemblyFiles) {
        final String source = File(path).readAsStringSync();
        expect(source, contains('///'), reason: '$path was not read.');

        for (final String branch in _platformBranches) {
          expect(
            source,
            isNot(contains(branch)),
            reason:
                '$path names $branch. A second way to ask which rail exists '
                'is a second answer that will disagree with the first.',
          );
        }
      }
    });

    test('the assembly reads no configuration outside its own root', () {
      // The Must NOT this package was extracted with: a plugin that read the
      // starter kit's config root would break the moment a consumer installed
      // it without the starter kit.
      //
      // Both halves are non-vacuous. The assembly reads exactly one key today,
      // and the count is asserted so this stays a measurement rather than a
      // loop over an empty set: a second key added without its own reasoning
      // fails here and has to be justified.
      final List<String> keys = [];
      for (final String path in _assemblyFiles) {
        final String source = File(path).readAsStringSync();
        expect(source, contains('///'), reason: '$path was not read.');
        expect(source, isNot(contains('magic_starter')));

        for (final Match match in _configReads.allMatches(source)) {
          expect(match.group(1), startsWith('payments.'));
          keys.add(match.group(1)!);
        }
      }

      expect(keys, ['payments.driver']);
    });
  });

  group('a resolved role is held, and extend replaces it', () {
    test('a role is created once and reused', () {
      // A counting factory rather than an identity check, because every driver
      // in this package has a `const` constructor and Dart canonicalises those:
      // `identical(createBillingService(), createBillingService())` is already
      // true, so an identity assertion would pass with no cache at all.
      int calls = 0;
      final PaymentsManager manager = PaymentsManager();
      manager.extend(PaymentsManager.billingRole, () {
        calls++;

        return _FakeBillingReads();
      });

      final BillingService first = manager.billing;
      final BillingService second = manager.billing;

      expect(calls, 1);
      expect(second, same(first));
    });

    test('extend after the first read replaces what is held', () {
      // The load-bearing half of `extend`, and the reason a test needs it:
      // without the eviction, a consumer (or a test) that overrides a role
      // AFTER anything has read it keeps getting the old driver, silently.
      final PaymentsManager manager = PaymentsManager();
      final BillingService resolved = manager.billing;
      expect(resolved, isNot(isA<_FakeBillingReads>()));

      manager.extend(PaymentsManager.billingRole, _FakeBillingReads.new);

      expect(manager.billing, isA<_FakeBillingReads>());
    });

    test('forgetDrivers restores the factory answers', () {
      final PaymentsManager manager = PaymentsManager();
      manager.extend(PaymentsManager.billingRole, _FakeBillingReads.new);
      manager.extend(PaymentsManager.webRole, _FakeWebRail.new);

      manager.forgetDrivers();

      // Both maps, not just the resolved one: a surviving factory would hand
      // the next test a fake rail it never registered, and a rail that claims
      // to exist is worse than one that does not.
      expect(manager.billing.runtimeType, createBillingService().runtimeType);
      expect(manager.web, isNull);
    });
  });

  group('an override that cannot serve its role fails loudly', () {
    test('a wrong-typed override names the role and both types', () {
      final PaymentsManager manager = PaymentsManager();
      // Reachable by construction: three roles carry three unrelated contracts
      // and one override registry, so the type can only be checked when the
      // role is read.
      manager.extend(PaymentsManager.webRole, _FakeBillingReads.new);

      expect(
        () => manager.web,
        throwsA(
          isA<BillingException>().having(
            (BillingException error) => error.message,
            'message',
            allOf(
              contains('web'),
              contains('_FakeBillingReads'),
              contains('WebBillingService'),
            ),
          ),
        ),
      );
    });

    test('an unknown role is refused at registration, not silently kept', () {
      final PaymentsManager manager = PaymentsManager();

      // A typo'd role that registered quietly would be an override nothing ever
      // reads: the consumer would see the built-in driver and have no way to
      // tell why their own was ignored.
      expect(
        () => manager.extend('portal', _FakeWebRail.new),
        throwsA(
          isA<BillingException>().having(
            (BillingException error) => error.message,
            'message',
            allOf(contains('portal'), contains('billing')),
          ),
        ),
      );
      expect(manager.web, isNull);
    });
  });

  group('the service provider binds the manager and wires it in boot', () {
    test('Magic.make resolves the manager after Magic.init', () async {
      await Magic.init(
        configFactories: const [],
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

/// The three files this step assembles, checked as source text.
const List<String> _assemblyFiles = [
  'lib/src/payments_manager.dart',
  'lib/src/facades/payments.dart',
  'lib/src/providers/payments_service_provider.dart',
];

/// The runtime device questions none of those three files may ask.
const List<String> _platformBranches = [
  'kIsWeb',
  'Platform.is',
  'defaultTargetPlatform',
  'get isWeb',
];

/// Container keys `register()` must not bind. Each is a plausible next
/// addition: a per-role binding would give the container a second opinion on
/// which driver serves a rail.
const List<String> _keysRegisterMustNotBind = [
  'billing',
  'web',
  'store',
  'payments.billing',
];

/// The literal key of a `Config.get<...>('...')` call.
final RegExp _configReads = RegExp(
  r"""Config\.get(?:<[^>]*>)?\(\s*['"]([^'"]+)""",
);

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

/// A fake WEB rail, used only to prove an absent rail is read rather than
/// hardcoded.
class _FakeWebRail implements WebBillingService {
  @override
  Future<BillingCheckoutSession> checkout({
    required String plan,
    required String successUrl,
    required String cancelUrl,
  }) => throw UnsupportedError('identity fake');

  @override
  Future<void> cancel() => throw UnsupportedError('identity fake');

  @override
  Future<String> openPortal({String? returnUrl}) =>
      throw UnsupportedError('identity fake');

  @override
  Future<void> swap({required String plan}) =>
      throw UnsupportedError('identity fake');
}

/// A fake STORE rail, for the same reason.
class _FakeStoreRail implements StoreBillingService {
  @override
  Future<void> identify(String appUserId) =>
      throw UnsupportedError('identity fake');

  @override
  Future<void> openStoreManagement() => throw UnsupportedError('identity fake');

  @override
  Future<bool> purchase({required String plan}) =>
      throw UnsupportedError('identity fake');

  @override
  Future<bool> restore() => throw UnsupportedError('identity fake');
}
