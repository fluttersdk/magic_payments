import 'package:flutter_test/flutter_test.dart';
import 'package:magic_payments/magic_payments.dart';

/// The complete `provider` vocabulary, copied from the producer's own
/// `BillingProvider` enum rather than written from memory.
const Map<String, BillingProvider> _providerWire = {
  'none': BillingProvider.none,
  'stripe': BillingProvider.stripe,
  'app_store': BillingProvider.appStore,
  'play_store': BillingProvider.playStore,
  'manual': BillingProvider.manual,
};

/// The complete `plan_status` vocabulary, copied from the producer's own
/// `PlanStatus` enum.
const Map<String, PlanStatus> _planStatusWire = {
  'none': PlanStatus.none,
  'trialing': PlanStatus.trialing,
  'active': PlanStatus.active,
  'past_due': PlanStatus.pastDue,
  'grace': PlanStatus.grace,
  'canceled': PlanStatus.canceled,
  'expired': PlanStatus.expired,
  'paused': PlanStatus.paused,
};

/// The complete `manage_via` vocabulary, copied from the four words
/// `SubscriptionResource::manageVia()`'s `match` can emit.
const Map<String, ManageVia> _manageViaWire = {
  'none': ManageVia.none,
  'portal': ManageVia.portal,
  'app_store': ManageVia.appStore,
  'play_store': ManageVia.playStore,
};

/// Stripe's own invoice statuses, copied from the five values Cashier passes
/// through, mapped onto this package's three settlement states.
const Map<String, InvoiceStatus> _invoiceStatusWire = {
  'paid': InvoiceStatus.paid,
  'open': InvoiceStatus.pending,
  'draft': InvoiceStatus.pending,
  'uncollectible': InvoiceStatus.failed,
  'void': InvoiceStatus.failed,
};

void main() {
  group('BillingProvider.fromWire', () {
    test('decodes every rail the producer can name', () {
      _providerWire.forEach((String wire, BillingProvider expected) {
        expect(BillingProvider.fromWire(wire), expected, reason: wire);
      });
    });

    test(
      'mirrors the wire completely, so no rail is mapped onto a neighbour',
      () {
        final List<BillingProvider> decoded = _providerWire.keys
            .map(BillingProvider.fromWire)
            .toList();

        expect(decoded.toSet().length, decoded.length);
        expect(decoded.toSet(), BillingProvider.values.toSet());
        expect(_providerWire.length, BillingProvider.values.length);
      },
    );

    test('lets only the word "none" read as none, so a forgotten rail cannot '
        'hide in the fallback', () {
      for (final String wire in _providerWire.keys.where((k) => k != 'none')) {
        expect(
          BillingProvider.fromWire(wire),
          isNot(BillingProvider.none),
          reason: wire,
        );
      }
    });

    test('attributes an absent or unknown rail to nobody', () {
      expect(BillingProvider.fromWire(null), BillingProvider.none);
      expect(BillingProvider.fromWire('paddle'), BillingProvider.none);
      expect(BillingProvider.fromWire('appStore'), BillingProvider.none);
    });
  });

  group('PlanStatus.fromWire', () {
    test('decodes every lifecycle the producer can report', () {
      _planStatusWire.forEach((String wire, PlanStatus expected) {
        expect(PlanStatus.fromWire(wire), expected, reason: wire);
      });
    });

    test('mirrors the wire completely, so no status is mapped onto a '
        'neighbour', () {
      final List<PlanStatus> decoded = _planStatusWire.keys
          .map(PlanStatus.fromWire)
          .toList();

      expect(decoded.toSet().length, decoded.length);
      expect(decoded.toSet(), PlanStatus.values.toSet());
      expect(_planStatusWire.length, PlanStatus.values.length);
    });

    test('lets only the word "none" read as none, so a forgotten status '
        'cannot hide in the fallback', () {
      for (final String wire in _planStatusWire.keys.where(
        (k) => k != 'none',
      )) {
        expect(PlanStatus.fromWire(wire), isNot(PlanStatus.none), reason: wire);
      }
    });

    test('reads an absent or unknown status as no entitlement at all', () {
      expect(PlanStatus.fromWire(null), PlanStatus.none);
      expect(PlanStatus.fromWire('incomplete_expired'), PlanStatus.none);
      // The snake_case trap: a `.name` comparison would decode this and drop
      // the wire's own `past_due` into the fallback.
      expect(PlanStatus.fromWire('pastDue'), PlanStatus.none);
    });
  });

  group('ManageVia.fromWire', () {
    test('decodes every surface the producer can name', () {
      _manageViaWire.forEach((String wire, ManageVia expected) {
        expect(ManageVia.fromWire(wire), expected, reason: wire);
      });
    });

    test('mirrors the wire completely, so no surface is mapped onto a '
        'neighbour', () {
      final List<ManageVia> decoded = _manageViaWire.keys
          .map(ManageVia.fromWire)
          .toList();

      expect(decoded.toSet().length, decoded.length);
      expect(decoded.toSet(), ManageVia.values.toSet());
      expect(_manageViaWire.length, ManageVia.values.length);
    });

    test('lets only the word "none" read as none, so a forgotten surface '
        'cannot hide in the fallback', () {
      for (final String wire in _manageViaWire.keys.where((k) => k != 'none')) {
        expect(ManageVia.fromWire(wire), isNot(ManageVia.none), reason: wire);
      }
    });

    test('steers the customer nowhere when it cannot name the surface', () {
      expect(ManageVia.fromWire(null), ManageVia.none);
      expect(ManageVia.fromWire('web_shop'), ManageVia.none);
      expect(ManageVia.fromWire('playStore'), ManageVia.none);
    });
  });

  group('InvoiceStatus.fromWire', () {
    test('folds each of Stripe\'s five statuses into its settlement state', () {
      _invoiceStatusWire.forEach((String wire, InvoiceStatus expected) {
        expect(InvoiceStatus.fromWire(wire), expected, reason: wire);
      });
    });

    test('reaches all three settlement states, so none is unreachable', () {
      final Set<InvoiceStatus> decoded = _invoiceStatusWire.keys
          .map(InvoiceStatus.fromWire)
          .toSet();

      expect(decoded, InvoiceStatus.values.toSet());
    });

    test('treats an absent or unknown status as unsettled, never as paid', () {
      expect(InvoiceStatus.fromWire(null), InvoiceStatus.pending);
      expect(InvoiceStatus.fromWire('deleted'), InvoiceStatus.pending);
    });
  });
}
