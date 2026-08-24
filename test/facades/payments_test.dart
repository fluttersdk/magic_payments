import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:magic_payments/magic_payments.dart';

import '../test_helper.dart';

void main() {
  setUp(() {
    resetPaymentsState();
    bindLogFacade();
  });

  tearDown(resetPaymentsState);

  group('every member reaches the manager', () {
    test('the facade and the manager answer with the same objects', () {
      final PaymentsManager manager = PaymentsManager();

      expect(Payments.manager, same(manager));
      expect(Payments.billing, same(manager.billing));
      expect(Payments.web, same(manager.web));
      expect(Payments.store, same(manager.store));
    });

    test('extend through the facade is visible on the manager', () {
      // The claim is that there is ONE registry. A facade holding its own would
      // let a consumer override a rail the billing screen never reads.
      Payments.extend(PaymentsManager.webRole, _FakeWebRail.new);

      expect(PaymentsManager().web, isA<_FakeWebRail>());
      expect(Payments.web, same(PaymentsManager().web));
    });

    test('forgetDrivers through the facade clears the manager', () {
      Payments.extend(PaymentsManager.webRole, _FakeWebRail.new);

      Payments.forgetDrivers();

      expect(PaymentsManager().web, isNull);
      expect(Payments.web, isNull);
    });
  });

  group('the facade carries no logic of its own', () {
    test('it forwards and does nothing else', () {
      final String source = File(_facade).readAsStringSync();
      // Vacuity guard: an unreadable path would satisfy every `isNot` below.
      expect(source, contains('class Payments'));

      // A private constructor, so the facade is a namespace rather than a type
      // a consumer can hold an instance of.
      expect(source, contains('Payments._()'));

      for (final String forbidden in _logic) {
        expect(
          source,
          isNot(contains(forbidden)),
          reason:
              'The facade names $forbidden. A forwarder that decides anything '
              'is a second implementation of what the manager already does.',
        );
      }
    });
  });
}

/// The facade's own source, read as text because "it forwards and nothing else"
/// is a claim about the file rather than about a return value.
const String _facade = 'lib/src/facades/payments.dart';

/// Constructs that would mean the facade decided something. `Config.` and
/// `Http.` cover the two the manager and the drivers own; `try` covers the
/// error translation that belongs to a driver.
const List<String> _logic = [
  'if (',
  'switch',
  'Config.',
  'Http.',
  'try {',
  'await ',
];

/// A fake WEB rail. Identity only: nothing here calls a rail method.
class _FakeWebRail implements WebBillingService {
  @override
  Future<BillingCheckoutSession> checkout({
    required String plan,
    required BillingCycle cycle,
    required String successUrl,
    required String cancelUrl,
  }) => throw UnsupportedError('identity fake');

  @override
  Future<void> cancel() => throw UnsupportedError('identity fake');

  @override
  Future<String> openPortal({String? returnUrl}) =>
      throw UnsupportedError('identity fake');

  @override
  Future<void> swap({required String plan, required BillingCycle cycle}) =>
      throw UnsupportedError('identity fake');
}
