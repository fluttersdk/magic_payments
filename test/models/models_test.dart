import 'package:flutter_test/flutter_test.dart';
import 'package:magic_payments/magic_payments.dart';

/// The `GET /billing` payload with every one of the producer's THIRTEEN keys
/// populated, on the store rail (the only rail that carries `manage_url` and
/// `grace_period_ends_at`).
///
/// The keys are copied from `SubscriptionResource::toArray()`, in its order.
/// A fixture key the producer never emits proves nothing: this wire has never
/// carried a `status` key, only `plan_status`.
const Map<String, dynamic> _storeEntitlementWire = {
  'plan': 'business',
  'plan_status': 'past_due',
  'subscribed': true,
  'renews': true,
  'provider': 'app_store',
  'provider_status': 'in_billing_retry_period',
  'product_id': 'com.uptizm.business.monthly',
  'manage_via': 'app_store',
  'manage_url': 'https://apps.apple.com/account/subscriptions',
  'current_period_end': '2026-09-01T12:00:00.000Z',
  'trial_ends_at': null,
  'grace_period_ends_at': '2026-09-16T12:00:00.000Z',
  'ai_analysis_trials_remaining': 2,
};

/// The same payload on the Stripe rail, where FOUR of the eight nullable
/// fields are null by design rather than by accident.
const Map<String, dynamic> _stripeEntitlementWire = {
  'plan': 'pro',
  'plan_status': 'trialing',
  'subscribed': true,
  'renews': null,
  'provider': 'stripe',
  'provider_status': null,
  'product_id': null,
  'manage_via': 'portal',
  'manage_url': null,
  'current_period_end': '2026-09-01T12:00:00.000Z',
  'trial_ends_at': '2026-08-29T12:00:00.000Z',
  'grace_period_ends_at': null,
  'ai_analysis_trials_remaining': null,
};

/// One `data[]` entry of `GET /billing/invoices`, with all SIX keys
/// `InvoiceResource::toArray()` emits.
const Map<String, dynamic> _invoiceWire = {
  'id': 'in_1P2Qr3',
  'number': 'UPT-0007',
  'date': '2026-06-01T00:00:00.000Z',
  'amount': '\$348.00',
  'status': 'paid',
  'pdf_url': 'https://pay.stripe.com/invoice/in_1P2Qr3/pdf',
};

/// The `GET /billing/payment-method` payload, with all SIX keys the controller
/// emits on its success path, in its order.
const Map<String, dynamic> _paymentMethodWire = {
  'available': true,
  'renewal_date': '2026-06-01T00:00:00.000Z',
  'brand': 'visa',
  'last4': '4242',
  'exp_month': 8,
  'exp_year': 2027,
};

/// The same endpoint's answered-but-empty body: the rail WAS asked, it replied,
/// and the team has no card stored. The renewal date survives because a team
/// can be inside a trial with nothing on file.
const Map<String, dynamic> _paymentMethodNoCardWire = {
  'available': true,
  'renewal_date': '2026-06-01T00:00:00.000Z',
  'brand': null,
  'last4': null,
  'exp_month': null,
  'exp_year': null,
};

/// The same endpoint's Stripe-outage soft-fail: a 200 whose card fields are all
/// null and whose `available` says the rail could not be asked at all.
const Map<String, dynamic> _paymentMethodOutageWire = {
  'available': false,
  'renewal_date': null,
  'brand': null,
  'last4': null,
  'exp_month': null,
  'exp_year': null,
};

/// The five-key body a backend from before `available` existed still sends.
///
/// This is the shape that made the field necessary: without it the outage body
/// above and the no-card body above it were byte-identical, so a Stripe outage
/// read to the client as "no card on file". A consumer must read the absent key
/// as "not reported" rather than as `false`.
const Map<String, dynamic> _paymentMethodLegacyWire = {
  'renewal_date': '2026-06-01T00:00:00.000Z',
  'brand': 'visa',
  'last4': '4242',
  'exp_month': 8,
  'exp_year': 2027,
};

/// The `GET /billing/usage` payload, with the three metered resources the
/// controller emits and the `{used, limit}` shape each carries.
const Map<String, dynamic> _usageWire = {
  'monitors': {'used': 12, 'limit': 50},
  'responders': {'used': 3, 'limit': 10},
  'checks_this_month': {'used': 51840, 'limit': null},
};

void main() {
  group('BillingEntitlement.fromMap', () {
    test('decodes the store rail\'s thirteen fields', () {
      final BillingEntitlement entitlement = BillingEntitlement.fromMap(
        _storeEntitlementWire,
      );

      expect(entitlement.plan, 'business');
      expect(entitlement.planStatus, PlanStatus.pastDue);
      expect(entitlement.subscribed, isTrue);
      expect(entitlement.renews, isTrue);
      expect(entitlement.provider, BillingProvider.appStore);
      expect(entitlement.providerStatus, 'in_billing_retry_period');
      expect(entitlement.productId, 'com.uptizm.business.monthly');
      expect(entitlement.manageVia, ManageVia.appStore);
      expect(
        entitlement.manageUrl,
        'https://apps.apple.com/account/subscriptions',
      );
      expect(entitlement.currentPeriodEnd, DateTime.utc(2026, 9, 1, 12));
      expect(entitlement.trialEndsAt, isNull);
      expect(entitlement.gracePeriodEndsAt, DateTime.utc(2026, 9, 16, 12));
      expect(entitlement.aiAnalysisTrialsRemaining, 2);
    });

    test('keeps the Stripe rail\'s four by-design nulls as nulls', () {
      final BillingEntitlement entitlement = BillingEntitlement.fromMap(
        _stripeEntitlementWire,
      );

      expect(entitlement.planStatus, PlanStatus.trialing);
      expect(entitlement.provider, BillingProvider.stripe);
      expect(entitlement.manageVia, ManageVia.portal);
      // Null means no rail has said, which is not the claim `false` makes.
      expect(entitlement.renews, isNull);
      expect(entitlement.providerStatus, isNull);
      expect(entitlement.productId, isNull);
      expect(entitlement.manageUrl, isNull);
      expect(entitlement.gracePeriodEndsAt, isNull);
      expect(entitlement.aiAnalysisTrialsRemaining, isNull);
      expect(entitlement.trialEndsAt, DateTime.utc(2026, 8, 29, 12));
    });

    test('reads the status from plan_status only, so a payload carrying a '
        '"status" key decodes as unknown rather than as active', () {
      final BillingEntitlement entitlement = BillingEntitlement.fromMap({
        'plan': 'pro',
        'status': 'active',
        'subscribed': true,
      });

      expect(entitlement.planStatus, PlanStatus.none);
    });

    test('lands an undescribed entitlement on the non-entitling cases', () {
      final BillingEntitlement entitlement = BillingEntitlement.fromMap(
        const <String, dynamic>{},
      );

      expect(entitlement.plan, isNull);
      expect(entitlement.planStatus, PlanStatus.none);
      expect(entitlement.subscribed, isFalse);
      expect(entitlement.provider, BillingProvider.none);
      expect(entitlement.manageVia, ManageVia.none);
      expect(entitlement.aiAnalysisTrialsRemaining, isNull);
    });

    test('degrades a malformed or wrongly-typed instant to "not reported" '
        'rather than throwing, so the plan still renders', () {
      final BillingEntitlement entitlement = BillingEntitlement.fromMap({
        ..._stripeEntitlementWire,
        'current_period_end': 'the first of September',
        'trial_ends_at': 1756728000,
      });

      expect(entitlement.currentPeriodEnd, isNull);
      expect(entitlement.trialEndsAt, isNull);
      expect(entitlement.plan, 'pro');
    });

    test('keeps the whole payload, so a caller can read a key a newer backend '
        'added without waiting for a client release', () {
      final BillingEntitlement entitlement = BillingEntitlement.fromMap({
        ..._stripeEntitlementWire,
        'seats_included': 5,
      });

      expect(entitlement.raw['seats_included'], 5);
      expect(entitlement.raw.length, _stripeEntitlementWire.length + 1);
    });

    test('is const-constructible from decoded cases, so a fake needs no wire '
        'words', () {
      const BillingEntitlement entitlement = BillingEntitlement(
        plan: 'pro',
        planStatus: PlanStatus.active,
        subscribed: true,
        provider: BillingProvider.stripe,
        manageVia: ManageVia.portal,
        aiAnalysisTrialsRemaining: null,
        raw: <String, dynamic>{},
      );

      expect(entitlement.planStatus, PlanStatus.active);
      expect(entitlement.provider, BillingProvider.stripe);
      expect(entitlement.manageVia, ManageVia.portal);
      expect(entitlement.renews, isNull);
    });
  });

  group('BillingCheckoutSession.fromMap', () {
    test('decodes the checkout endpoint\'s two keys', () {
      final BillingCheckoutSession session =
          BillingCheckoutSession.fromMap(const {
            'checkout_url': 'https://checkout.stripe.com/c/pay/cs_test_1',
            'session_id': 'cs_test_1',
          });

      expect(
        session.checkoutUrl,
        'https://checkout.stripe.com/c/pay/cs_test_1',
      );
      expect(session.sessionId, 'cs_test_1');
    });

    test('degrades a malformed response to empty strings, which a caller can '
        'refuse to open', () {
      final BillingCheckoutSession session = BillingCheckoutSession.fromMap(
        const <String, dynamic>{},
      );

      expect(session.checkoutUrl, isEmpty);
      expect(session.sessionId, isEmpty);
    });
  });

  group('Invoice.fromMap', () {
    test('decodes the six keys the invoice resource emits', () {
      final Invoice invoice = Invoice.fromMap(_invoiceWire);

      expect(invoice.id, 'in_1P2Qr3');
      expect(invoice.number, 'UPT-0007');
      expect(invoice.date, DateTime.utc(2026, 6, 1));
      expect(invoice.amount, '\$348.00');
      expect(invoice.status, InvoiceStatus.paid);
      expect(invoice.pdfUrl, 'https://pay.stripe.com/invoice/in_1P2Qr3/pdf');
    });

    test('leaves an absent or malformed date null, so a caller can tell "no '
        'date" from a rendered one', () {
      expect(Invoice.fromMap(const <String, dynamic>{}).date, isNull);
      expect(Invoice.fromMap(const {'date': 'Jun 1, 2026'}).date, isNull);
    });

    test('reads an undescribed invoice as unsettled rather than as paid', () {
      final Invoice invoice = Invoice.fromMap(const <String, dynamic>{});

      expect(invoice.status, InvoiceStatus.pending);
      expect(invoice.id, isEmpty);
      expect(invoice.pdfUrl, isNull);
    });
  });

  group('BillingInvoicesPage.fromMap', () {
    test('decodes the page and its cursor', () {
      final BillingInvoicesPage page = BillingInvoicesPage.fromMap({
        'data': [_invoiceWire],
        'next_cursor': 'eyJpZCI6ImluXzFQMlFyMyJ9',
      });

      expect(page.invoices, hasLength(1));
      expect(page.invoices.single.number, 'UPT-0007');
      expect(page.nextCursor, 'eyJpZCI6ImluXzFQMlFyMyJ9');
    });

    test('reads a null cursor as the last page', () {
      final BillingInvoicesPage page = BillingInvoicesPage.fromMap({
        'data': [_invoiceWire],
        'next_cursor': null,
      });

      expect(page.nextCursor, isNull);
    });

    test('degrades a malformed data envelope to an empty page', () {
      final BillingInvoicesPage page = BillingInvoicesPage.fromMap(const {
        'data': 'nothing here',
      });

      expect(page.invoices, isEmpty);
      expect(page.nextCursor, isNull);
    });
  });

  group('PaymentMethod.fromMap', () {
    test('decodes the card the endpoint reported', () {
      final PaymentMethod method = PaymentMethod.fromMap(_paymentMethodWire);

      expect(method.available, isTrue);
      expect(method.brand, 'visa');
      expect(method.last4, '4242');
      expect(method.expMonth, 8);
      expect(method.expYear, 2027);
      expect(method.renewalDate, DateTime.utc(2026, 6, 1));
    });

    test('represents the Stripe-outage soft-fail as a rail that could not be '
        'asked, instead of throwing', () {
      final PaymentMethod method = PaymentMethod.fromMap(
        _paymentMethodOutageWire,
      );

      expect(method.available, isFalse);
      expect(method.brand, isNull);
      expect(method.last4, isNull);
      expect(method.expMonth, isNull);
      expect(method.expYear, isNull);
      expect(method.renewalDate, isNull);
    });

    test('leaves a malformed renewal date null rather than throwing out of a '
        'decode path', () {
      final PaymentMethod method = PaymentMethod.fromMap(const {
        'renewal_date': 'next month',
      });

      expect(method.renewalDate, isNull);
    });

    /// The pair the whole field exists to separate. Both bodies below carry no
    /// card, and only `available` says whether that is a fact or an unknown.
    test('tells the answered-but-empty body apart from the outage body', () {
      final PaymentMethod answered = PaymentMethod.fromMap(
        _paymentMethodNoCardWire,
      );
      final PaymentMethod outage = PaymentMethod.fromMap(
        _paymentMethodOutageWire,
      );

      expect(answered.last4, outage.last4);
      expect(answered.brand, outage.brand);

      expect(answered.available, isTrue);
      expect(outage.available, isFalse);
    });

    test('reads an absent available key as null, not as false, so an older '
        'backend is never told its rail is down', () {
      final PaymentMethod method = PaymentMethod.fromMap(
        _paymentMethodLegacyWire,
      );

      expect(method.available, isNull);
      expect(method.brand, 'visa');
      expect(method.last4, '4242');
      expect(method.expMonth, 8);
      expect(method.expYear, 2027);
      expect(method.renewalDate, DateTime.utc(2026, 6, 1));
    });

    /// `as bool?` would throw here, and a throw out of this factory blanks the
    /// billing screen's card rather than degrading one field of it.
    test('leaves a non-bool available null rather than throwing out of a '
        'decode path', () {
      final PaymentMethod method = PaymentMethod.fromMap(const {
        ..._paymentMethodLegacyWire,
        'available': 1,
      });

      expect(method.available, isNull);
      expect(method.last4, '4242');
    });
  });

  group('UsageStat', () {
    test('decodes every metered resource the payload carries, keyed by the '
        'wire key logic matches on', () {
      final List<UsageStat> stats = UsageStat.fromWireMap(_usageWire);

      expect(stats.map((UsageStat s) => s.key).toList(), [
        'monitors',
        'responders',
        'checks_this_month',
      ]);
      expect(stats.first.used, 12);
      expect(stats.first.limit, 50);
    });

    test('reads a null limit as unlimited rather than as zero', () {
      final List<UsageStat> stats = UsageStat.fromWireMap(_usageWire);

      expect(stats.last.used, 51840);
      expect(stats.last.limit, isNull);
    });

    test('carries no display copy of its own, so a consumer\'s catalogue owns '
        'the label in every language', () {
      final List<UsageStat> stats = UsageStat.fromWireMap(_usageWire);

      expect(stats.first.label, isNull);
      expect(stats.first.unit, isEmpty);
    });

    test('reads a resource whose entry is absent or malformed as zero used '
        'and unlimited, keeping the key it was asked for', () {
      final UsageStat stat = UsageStat.fromWire('monitors', 'not an object');

      expect(stat.key, 'monitors');
      expect(stat.used, 0);
      expect(stat.limit, isNull);
    });
  });
}
