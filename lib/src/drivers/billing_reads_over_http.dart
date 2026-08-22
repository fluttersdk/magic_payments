import 'package:magic/magic.dart';

import '../contracts/billing_service.dart';
import '../exceptions/billing_exception.dart';
import '../models/billing_entitlement.dart';
import '../models/billing_invoices_page.dart';
import '../models/payment_method.dart';
import '../models/usage_stat.dart';

/// The five entitlement READS, over the vendor's own `api/v1`, shared by every
/// platform arm.
///
/// ## Why this is a mixin and not two implementations
///
/// The web and io drivers carried these five methods twice, byte for byte apart
/// from the class name inside each log prefix: 106 lines each, differing by one
/// line wrap. The duplication was invisible to every gate this package has,
/// because a conditional import compiles exactly ONE arm per target, so no
/// analyzer run and no test on any single platform could ever see the two copies
/// disagree. A fix applied to the web arm's envelope handling would simply leave
/// the same bug shipping on mobile, and nothing would report it.
///
/// It sits in a file with no platform import of its own, so both arms can take
/// it without either one dragging the other's libraries in.
///
/// ## Why the reads are shared at all
///
/// Reading an entitlement is honourable on every platform. The vendor's backend
/// is the authority on it no matter which rail sold the subscription, so a store
/// customer opening the web app reads the same truth as they do on the phone.
/// The only platform question left is which rails a build can SERVE, and that is
/// answered by which implementations the factory returns, never by a branch in
/// here.
///
/// The log prefix comes from `runtimeType`, so a line still names the concrete
/// driver that made the call (`[BillingServiceWeb.getUsage]`) rather than naming
/// this mixin and losing which arm was running.
mixin BillingReadsOverHttp implements BillingService {
  @override
  Future<BillingEntitlement> currentEntitlement() async {
    final MagicResponse response = await Http.get('/billing');
    if (!response.successful) {
      Log.error('[$runtimeType.currentEntitlement] ${response.errorMessage}');
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
      Log.error('[$runtimeType.getPlans] ${response.errorMessage}');
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
      Log.error('[$runtimeType.getUsage] ${response.errorMessage}');
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
      Log.error('[$runtimeType.getInvoices] ${response.errorMessage}');
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
      Log.error('[$runtimeType.getPaymentMethod] ${response.errorMessage}');
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
