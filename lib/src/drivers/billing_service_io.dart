import 'package:magic/magic.dart';

import '../contracts/billing_service.dart';
import '../contracts/store_billing_service.dart';
import '../contracts/web_billing_service.dart';
import '../exceptions/billing_exception.dart';
import '../models/billing_entitlement.dart';
import '../models/billing_invoices_page.dart';
import '../models/payment_method.dart';
import '../models/usage_stat.dart';
import 'store_billing_service_factory.dart';

/// The [BillingService] every build with `dart:io` resolves to: iOS, Android and
/// desktop.
///
/// FIVE methods, five reads over the vendor's own `api/v1`, and not one of them
/// refuses the device it runs on. That is the whole difference from the shape
/// this replaces: the same class used to carry four purchase-affecting methods
/// that threw `UnsupportedPlatformException`, because the interface it satisfied
/// declared them, so a mobile billing screen rendered an Upgrade button whose
/// only behaviour was to fail. The writes now live on their own rail contracts
/// (`WebBillingService`, `StoreBillingService`), which a build that cannot serve
/// them simply does not resolve, and a caller checks for a rail instead of
/// catching a refusal.
///
/// It carries no platform branch of its own. Reading an entitlement is
/// honourable everywhere, because the vendor's backend is the authority on it no
/// matter which rail sold the subscription, and the only platform question left,
/// which rails this build can serve, is answered by which implementations the
/// factory returns.
///
/// ```dart
/// final BillingService billing = createBillingService();
/// final BillingEntitlement entitlement = await billing.currentEntitlement();
/// ```
class BillingServiceIo implements BillingService {
  /// Creates a [BillingServiceIo].
  const BillingServiceIo();

  @override
  Future<BillingEntitlement> currentEntitlement() async {
    final MagicResponse response = await Http.get('/billing');
    if (!response.successful) {
      Log.error(
        '[BillingServiceIo.currentEntitlement] ${response.errorMessage}',
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
      Log.error('[BillingServiceIo.getPlans] ${response.errorMessage}');
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
      Log.error('[BillingServiceIo.getUsage] ${response.errorMessage}');
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
      Log.error('[BillingServiceIo.getInvoices] ${response.errorMessage}');
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
      Log.error('[BillingServiceIo.getPaymentMethod] ${response.errorMessage}');
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

/// Creates the [BillingService] implementation for a `dart:io` build.
///
/// The name and the return type are the conditional-import contract: the web arm
/// declares the same function, and the factory that picks between them imports
/// one of the two files. Renaming either would break the arm that is not being
/// compiled, which no analyzer run on this platform would show.
BillingService createBillingService() => const BillingServiceIo();

/// Resolves the WEB rail for a `dart:io` build, which never has one.
///
/// A phone does not bill a card through a hosted web checkout, and a desktop
/// build of this arm has no such surface either. `null` rather than a throwing
/// implementation is the whole point of the rail split: the caller asks whether
/// the rail exists and does not render the button, instead of rendering one that
/// fails when tapped, which is the shape this driver used to ship.
WebBillingService? createWebBillingService() => null;

/// Resolves the STORE rail for a `dart:io` build.
///
/// Delegated rather than answered here, and that delegation is the whole point:
/// `dart.library.io` is true on macOS, Windows and Linux too, none of which has
/// StoreKit or Play Billing, so this arm cannot hand a store driver back
/// unconditionally. `createStoreRail` is where the device question is asked, and
/// it still answers `null` on every platform without a store.
StoreBillingService? createStoreBillingService() => createStoreRail();
