/// Multi-rail billing for the Magic Framework.
///
/// One entitlement contract over more than one payment rail: Stripe on the web,
/// and store in-app purchase on iOS and Android. A consumer asks what a customer
/// is entitled to and where they manage it; which rail sold the subscription is
/// the package's problem, not the caller's.
///
/// `Payments` is the entry point. It forwards to `PaymentsManager`, which is
/// bound into magic's container under `'payments'` by
/// `PaymentsServiceProvider`.
///
/// ```dart
/// final BillingEntitlement entitlement =
///     await Payments.billing.currentEntitlement();
///
/// // A rail is CHECKED, never assumed: `null` is a build that cannot serve it.
/// final WebBillingService? web = Payments.web;
/// ```
library;

// The facade first: it is what a consumer imports this package for.
export 'src/facades/payments.dart';

// Contracts
export 'src/contracts/billing_service.dart';
export 'src/contracts/web_billing_service.dart';
export 'src/contracts/store_billing_service.dart';

// Models
export 'src/models/billing_entitlement.dart';
export 'src/models/billing_checkout_session.dart';
export 'src/models/billing_invoices_page.dart';
export 'src/models/invoice.dart';
export 'src/models/payment_method.dart';
export 'src/models/usage_stat.dart';

// Enums
export 'src/enums/billing_provider.dart';
export 'src/enums/plan_status.dart';
export 'src/enums/manage_via.dart';
export 'src/enums/invoice_status.dart';

// Drivers: the factory ONLY, and one line of it is load-bearing.
//
// All four driver files declare `createBillingService`,
// `createWebBillingService` and `createStoreBillingService`, because a
// conditional import resolves a whole FILE and every arm has to answer the same
// three questions. Exporting a second one collides on all three names. The
// factory is the copy meant to be public; the arms behind it are not, and
// `Payments` is the entry point that reads them.
export 'src/drivers/billing_service_factory.dart';

// The manager and the provider that binds it.
export 'src/payments_manager.dart';
export 'src/providers/payments_service_provider.dart';

// Exceptions
export 'src/exceptions/billing_exception.dart';
