import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:magic/magic.dart';
import 'package:magic_payments/magic_payments.dart';
import 'package:magic_payments/src/contracts/store_billing_service.dart';
import 'package:magic_payments/src/drivers/billing_service_factory.dart';
import 'package:magic_payments/src/drivers/billing_service_io.dart' as io;
import 'package:magic_payments/src/drivers/billing_service_stub.dart' as stub;

const String _factoryPath = 'lib/src/drivers/billing_service_factory.dart';

/// The three arms the factory must carry, in the order a conditional import
/// evaluates them: the default first, then each guarded alternative.
///
/// Asserted as SOURCE TEXT and not as behaviour, because a test process can only
/// ever compile one arm. On the VM `dart.library.io` is the arm that resolves, so
/// a factory that had lost its web arm would pass every behavioural assertion in
/// this file and fail only in a browser.
const List<String> _arms = [
  "import 'billing_service_stub.dart'",
  "if (dart.library.html) 'billing_service_web.dart'",
  "if (dart.library.io) 'billing_service_io.dart'",
];

void main() {
  group('the factory carries all three arms', () {
    late String source;

    setUp(() {
      source = File(_factoryPath).readAsStringSync();
    });

    test('the conditional import declares the stub default and both guards', () {
      // Guard against a vacuous pass: an empty read would satisfy a `contains`
      // loop over nothing, so the file has to have been the right one first.
      expect(source, contains('createBillingService'));

      for (final String arm in _arms) {
        expect(
          source,
          contains(arm),
          reason:
              'A missing arm is a whole platform resolved to the wrong '
              'implementation, and the compiler cannot say so.',
        );
      }
    });

    test('each library guard appears exactly once in the whole file', () {
      // The count matters and not just the presence. Two io guards would be a
      // copy-paste that silently shadows one of them, and zero would send every
      // iOS and Android build to the stub, whose every method throws: the five
      // mobile READ paths that work today would break with no analyzer error
      // anywhere.
      //
      // Counted over the RAW source, comments included, because that is what
      // this package's own gate does. A docblock that spelled a guard out would
      // pass a presence check and fail the gate, which is the review-grep trap
      // in reverse.
      expect('dart.library.io'.allMatches(source).length, 1);
      expect('dart.library.html'.allMatches(source).length, 1);
    });

    test('the factory names no runtime platform check of its own', () {
      // The one place in the package that knows about platforms at all, and it
      // knows through the import graph. A runtime device check here would answer
      // "which rail" with "which device", which is the exact conflation this
      // package exists to prevent. Raw source again, so prose naming one of them
      // fails too: a docblock is where the next one would arrive.
      for (final String branch in <String>[
        'kIsWeb',
        'Platform.is',
        'defaultTargetPlatform',
      ]) {
        expect(source, isNot(contains(branch)));
      }
    });
  });

  group('the factory resolves the whole trio, not only the service', () {
    test('every arm answers the same three questions', () {
      // Typed on the left on purpose: a conditional import resolves a whole
      // FILE, so an arm missing one of the three functions is a compile error on
      // that platform only. The types are the contract each arm has to match.
      final BillingService service = createBillingService();
      final WebBillingService? web = createWebBillingService();
      final StoreBillingService? store = createStoreBillingService();

      expect(service, isNotNull);
      // On the VM the io arm resolves, so this is what a phone gets: five
      // honourable reads and neither rail yet.
      expect(service, isA<io.BillingServiceIo>());
      expect(web, isNull);
      expect(store, isNull);
    });

    test(
      'the io arm resolves a service whose reads are not refusals',
      () async {
        Log.fake();
        Http.fake({'/billing/usage': Http.response(_usageBody)});
        addTearDown(() {
          Http.unfake();
          Log.unfake();
        });

        // The point of the io arm existing at all. Drop it from the factory and
        // this same call resolves the stub and throws.
        final List<UsageStat> usage = await createBillingService().getUsage();

        expect(usage, hasLength(3));
      },
    );
  });

  group('each arm exposes the trio directly', () {
    test('the io arm resolves the mobile driver and neither rail', () {
      final BillingService service = io.createBillingService();
      final WebBillingService? web = io.createWebBillingService();
      final StoreBillingService? store = io.createStoreBillingService();

      expect(service, isA<io.BillingServiceIo>());
      // Both null, and both for the same reason: a build cannot serve a rail it
      // has no implementation for, and the honest answer is an absence a caller
      // can check rather than a method that throws when tapped.
      expect(web, isNull);
      expect(store, isNull);
    });

    test('the stub arm resolves the stub and neither rail', () {
      final BillingService service = stub.createBillingService();
      final WebBillingService? web = stub.createWebBillingService();
      final StoreBillingService? store = stub.createStoreBillingService();

      expect(service, isA<stub.BillingServiceStub>());
      expect(web, isNull);
      expect(store, isNull);
    });
  });

  group('the stub refuses rather than answering emptily', () {
    test('every read throws UnsupportedPlatformException', () async {
      const stub.BillingServiceStub service = stub.BillingServiceStub();

      // All five, in one test, because the claim is about the SET: an
      // unrecognised platform has no assumed network stack, so there is no read
      // here that can honourably resolve. A silent empty answer would render as
      // a customer with no subscription, which is a lie about a paying account.
      await expectLater(
        service.currentEntitlement(),
        throwsA(isA<UnsupportedPlatformException>()),
      );
      await expectLater(
        service.getPlans(),
        throwsA(isA<UnsupportedPlatformException>()),
      );
      await expectLater(
        service.getUsage(),
        throwsA(isA<UnsupportedPlatformException>()),
      );
      await expectLater(
        service.getInvoices(),
        throwsA(isA<UnsupportedPlatformException>()),
      );
      await expectLater(
        service.getPaymentMethod(),
        throwsA(isA<UnsupportedPlatformException>()),
      );
    });

    test(
      'a stub refusal is catchable as a plain BillingException too',
      () async {
        // The subtype relationship is the contract a caller relies on: a screen
        // that only wants "billing did not work" catches one type, and a screen
        // that wants to say something about the platform catches the other.
        await expectLater(
          const stub.BillingServiceStub().currentEntitlement(),
          throwsA(isA<BillingException>()),
        );
      },
    );

    test('the refusal names no other way to buy', () async {
      // Not a style preference. Pointing a customer at a purchase method
      // outside the app breaks App Review Guideline 3.1.3(a), and this message
      // is the one string in the package that a refused platform shows a human.
      try {
        await const stub.BillingServiceStub().currentEntitlement();
        fail('The stub resolved a read it cannot serve.');
      } on BillingException catch (error) {
        expect(error.message, 'Billing is not supported on this platform.');
        for (final String forbidden in <String>[
          'website',
          'browser',
          'web app',
          'our site',
          'App Store',
          'Play Store',
        ]) {
          expect(
            error.message.toLowerCase(),
            isNot(contains(forbidden.toLowerCase())),
          );
        }
      }
    });
  });
}

/// The `GET /billing/usage` body, FLAT, copied from the producer.
const Map<String, dynamic> _usageBody = {
  'monitors': {'used': 3, 'limit': 20},
  'responders': {'used': 2, 'limit': 10},
  'checks_this_month': {'used': 41234, 'limit': null},
};
