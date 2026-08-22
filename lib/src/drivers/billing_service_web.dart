import 'package:magic/magic.dart';

import '../contracts/billing_service.dart';
import '../contracts/store_billing_service.dart';
import '../contracts/web_billing_service.dart';
import '../exceptions/billing_exception.dart';
import '../models/billing_checkout_session.dart';
import '../models/billing_entitlement.dart';
import '../models/billing_invoices_page.dart';
import '../models/payment_method.dart';
import '../models/usage_stat.dart';

/// The web build's driver: the five reads, plus the WEB RAIL's four writes, over
/// the vendor's own `api/v1`.
///
/// One class serving two contracts rather than two classes serving one each. The
/// nine calls share a transport (magic's `Http` facade) and, more importantly,
/// share an envelope convention that is not uniform across the endpoints: two
/// bodies arrive wrapped in `data`, three arrive flat, and one is taken whole.
/// Splitting the reads from the writes would duplicate that convention in two
/// places, and a convention kept in two places is a convention that drifts.
///
/// The two calls that mint a hosted page open it with
/// `LaunchMode.inAppWebView` rather than the facade's default external browser.
/// That is not cosmetic: a hosted checkout returns the customer to
/// `successUrl` when they are done, and from an external browser that return
/// lands in the browser rather than back in the app.
///
/// It carries no platform branch. Which build gets this class is the factory's
/// answer, and it is also the whole availability answer for the web rail: this
/// file is the only one whose `createWebBillingService()` returns a rail rather
/// than `null`.
///
/// ```dart
/// final WebBillingService? web = createWebBillingService();
/// if (web != null) {
///   await web.checkout(
///     plan: 'pro',
///     successUrl: 'https://example.com/billing?checkout=success',
///     cancelUrl: 'https://example.com/billing?checkout=cancel',
///   );
/// }
/// ```
class BillingServiceWeb implements BillingService, WebBillingService {
  /// Creates a [BillingServiceWeb].
  const BillingServiceWeb();

  // ---------------------------------------------------------------------------
  // WebBillingService: the four writes
  // ---------------------------------------------------------------------------

  @override
  Future<BillingCheckoutSession> checkout({
    required String plan,
    required String successUrl,
    required String cancelUrl,
  }) async {
    final MagicResponse response = await Http.post(
      '/billing/checkout',
      data: {'plan': plan, 'success_url': successUrl, 'cancel_url': cancelUrl},
    );
    if (!response.successful) {
      Log.error('[BillingServiceWeb.checkout] ${response.errorMessage}');
      throw BillingException(
        response.errorMessage ?? 'Failed to start checkout.',
      );
    }

    // Flat: the producer unwraps its rail's session object into two keys of its
    // own, so there is no `data` envelope on this one.
    final Object? data = response.data;
    if (data is! Map<String, dynamic>) {
      throw const BillingException('Malformed checkout response.');
    }

    final BillingCheckoutSession session = BillingCheckoutSession.fromMap(data);
    await Launch.url(session.checkoutUrl, mode: LaunchMode.inAppWebView);
    return session;
  }

  @override
  Future<void> swap({required String plan}) async {
    final MagicResponse response = await Http.post(
      '/billing/swap',
      data: {'plan': plan},
    );
    if (!response.successful) {
      Log.error('[BillingServiceWeb.swap] ${response.errorMessage}');
      throw BillingException(response.errorMessage ?? 'Failed to change plan.');
    }
  }

  @override
  Future<void> cancel() async {
    final MagicResponse response = await Http.post('/billing/cancel');
    if (!response.successful) {
      Log.error('[BillingServiceWeb.cancel] ${response.errorMessage}');
      throw BillingException(
        response.errorMessage ?? 'Failed to cancel subscription.',
      );
    }
  }

  @override
  Future<String> openPortal({String? returnUrl}) async {
    final MagicResponse response = await Http.get(
      '/billing/portal',
      query: returnUrl == null ? null : {'return_url': returnUrl},
    );
    if (!response.successful) {
      Log.error('[BillingServiceWeb.openPortal] ${response.errorMessage}');
      throw BillingException(
        response.errorMessage ?? 'Failed to open the billing portal.',
      );
    }

    final Object? data = response.data;
    final String? portalUrl = data is Map<String, dynamic>
        ? data['portal_url'] as String?
        : null;
    // An empty string is refused alongside a missing key: it would launch
    // nothing and still report success, which reads to the customer as a portal
    // that opened and closed.
    if (portalUrl == null || portalUrl.isEmpty) {
      throw const BillingException('Malformed billing portal response.');
    }

    await Launch.url(portalUrl, mode: LaunchMode.inAppWebView);
    return portalUrl;
  }

  // ---------------------------------------------------------------------------
  // BillingService: the five reads
  // ---------------------------------------------------------------------------

  @override
  Future<BillingEntitlement> currentEntitlement() async {
    final MagicResponse response = await Http.get('/billing');
    if (!response.successful) {
      Log.error(
        '[BillingServiceWeb.currentEntitlement] ${response.errorMessage}',
      );
      throw BillingException(
        response.errorMessage ?? 'Failed to load the billing entitlement.',
      );
    }

    final Object? raw = response.data is Map<String, dynamic>
        ? (response.data as Map<String, dynamic>)['data']
        : null;
    if (raw is! Map<String, dynamic>) {
      throw const BillingException('Malformed billing entitlement response.');
    }

    return BillingEntitlement.fromMap(raw);
  }

  @override
  Future<List<Map<String, dynamic>>> getPlans() async {
    final MagicResponse response = await Http.get('/billing/plans');
    if (!response.successful) {
      Log.error('[BillingServiceWeb.getPlans] ${response.errorMessage}');
      throw BillingException(
        response.errorMessage ?? 'Failed to load the plan catalog.',
      );
    }

    final Object? raw = response.data is Map<String, dynamic>
        ? (response.data as Map<String, dynamic>)['data']
        : null;
    if (raw is! List) {
      throw const BillingException('Malformed plan catalog response.');
    }

    // Rows verbatim: a tier's own fields are the vendor's product, and the
    // consumer already owns the type it decodes them into.
    return raw.whereType<Map<String, dynamic>>().toList();
  }

  @override
  Future<List<UsageStat>> getUsage() async {
    final MagicResponse response = await Http.get('/billing/usage');
    if (!response.successful) {
      Log.error('[BillingServiceWeb.getUsage] ${response.errorMessage}');
      throw BillingException(response.errorMessage ?? 'Failed to load usage.');
    }

    // The usage body is FLAT: the metered resources sit at the top level, with
    // no `data` envelope to unwrap. Unwrapping one here would read an empty map
    // and report zero usage against every cap.
    final Object? data = response.data;
    if (data is! Map<String, dynamic>) {
      throw const BillingException('Malformed usage response.');
    }

    return UsageStat.fromWireMap(data);
  }

  @override
  Future<BillingInvoicesPage> getInvoices({String? cursor}) async {
    final MagicResponse response = await Http.get(
      '/billing/invoices',
      query: cursor == null ? null : {'cursor': cursor},
    );
    if (!response.successful) {
      Log.error('[BillingServiceWeb.getInvoices] ${response.errorMessage}');
      throw BillingException(
        response.errorMessage ?? 'Failed to load invoices.',
      );
    }

    // The page decoder reads both `data` and `next_cursor`, so it takes the
    // whole body rather than the unwrapped rows.
    final Object? data = response.data;
    if (data is! Map<String, dynamic>) {
      throw const BillingException('Malformed invoices response.');
    }

    return BillingInvoicesPage.fromMap(data);
  }

  @override
  Future<PaymentMethod> getPaymentMethod() async {
    final MagicResponse response = await Http.get('/billing/payment-method');
    if (!response.successful) {
      Log.error(
        '[BillingServiceWeb.getPaymentMethod] ${response.errorMessage}',
      );
      throw BillingException(
        response.errorMessage ?? 'Failed to load the payment method.',
      );
    }

    // Flat like the usage body, and soft-failed by the producer: a rail outage
    // arrives as a 200 with every field null, so a resolved value does not imply
    // a card and must not be reported as an error.
    final Object? data = response.data;
    if (data is! Map<String, dynamic>) {
      throw const BillingException('Malformed payment method response.');
    }

    return PaymentMethod.fromMap(data);
  }
}

/// Creates the [BillingService] implementation for a web build.
///
/// The name and the return type are the conditional-import contract: every arm
/// declares the same three functions, and the factory imports exactly one file.
/// Renaming any of them would break the arms that are not being compiled, which
/// no analyzer run on one platform would show.
BillingService createBillingService() => const BillingServiceWeb();

/// Resolves the WEB rail for a web build, which is the one build that has one.
///
/// Non-null here and `null` in both sibling arms. That asymmetry is the whole
/// availability mechanism: a caller checks the rail rather than calling a method
/// and catching a refusal, so a build that cannot bill a card never renders an
/// upgrade button.
WebBillingService? createWebBillingService() => const BillingServiceWeb();

/// Resolves the STORE rail, which a web build never has.
///
/// The web has no App Store and no Play Store, so there is no implementation to
/// return and nothing to defer: `null` is the final answer on this arm, not a
/// placeholder for one.
StoreBillingService? createStoreBillingService() => null;
