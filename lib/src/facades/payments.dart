import '../contracts/billing_service.dart';
import '../contracts/store_billing_service.dart';
import '../contracts/web_billing_service.dart';
import '../models/billing_entitlement.dart';
import '../models/billing_invoices_page.dart';
import '../models/payment_method.dart';
import '../models/usage_stat.dart';
import '../payments_manager.dart';

/// The static entry point to billing, in magic's facade style.
///
/// Every member forwards to [PaymentsManager] and decides nothing. There is no
/// state here and no logic: magic's facades are explicit static stubs over a
/// resolved singleton, because Dart has no `__callStatic` to generate them and a
/// facade that computed anything would be a second implementation of what the
/// manager already does.
///
/// The three accessors mirror the manager's three roles, and the two rails keep
/// their nullability: a `null` rail is a build that cannot serve it, which is an
/// answer to check before rendering a purchase affordance rather than an error
/// to report.
///
/// ```dart
/// final BillingService billing = Payments.billing;
/// final WebBillingService? web = Payments.web;
///
/// // Swap a role for a fake, or for a rail a consumer implements itself.
/// Payments.extend(PaymentsManager.storeRole, () => MyStoreRail());
/// ```
class Payments {
  /// Not instantiable. The facade is a namespace, not a type to hold.
  Payments._();

  /// The manager every member below forwards to.
  ///
  /// Public because the manager is where a consumer reaches for the members a
  /// facade should not mirror, and because a test asserting the two agree needs
  /// to be able to name it.
  static PaymentsManager get manager => PaymentsManager();

  /// The five entitlement reads. See [PaymentsManager.billing].
  static BillingService get billing => manager.billing;

  /// The WEB rail, or `null` where this build cannot serve one.
  /// See [PaymentsManager.web].
  static WebBillingService? get web => manager.web;

  /// The STORE rail, or `null` where this build cannot serve one.
  /// See [PaymentsManager.store].
  static StoreBillingService? get store => manager.store;

  /// Reads the customer's current entitlement.
  /// See [BillingService.currentEntitlement].
  static Future<BillingEntitlement> currentEntitlement() =>
      billing.currentEntitlement();

  /// Reads the plan catalogue, cheapest tier first.
  /// See [BillingService.getPlans].
  static Future<List<Map<String, dynamic>>> getPlans() => billing.getPlans();

  /// Reads the current cycle's metered usage.
  /// See [BillingService.getUsage].
  static Future<List<UsageStat>> getUsage() => billing.getUsage();

  /// Reads one cursor-paginated page of invoices.
  /// See [BillingService.getInvoices].
  static Future<BillingInvoicesPage> getInvoices({String? cursor}) =>
      billing.getInvoices(cursor: cursor);

  /// Reads the card on file and the next renewal date.
  /// See [BillingService.getPaymentMethod].
  static Future<PaymentMethod> getPaymentMethod() => billing.getPaymentMethod();

  /// Registers [factory] as the implementation of [role].
  /// See [PaymentsManager.extend].
  static void extend(String role, Object Function() factory) =>
      manager.extend(role, factory);

  /// Drops every override and every resolved instance.
  /// See [PaymentsManager.forgetDrivers].
  static void forgetDrivers() => manager.forgetDrivers();
}
