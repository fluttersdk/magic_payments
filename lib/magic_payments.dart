/// Multi-rail billing for the Magic Framework.
///
/// One entitlement contract over more than one payment rail: Stripe on the web,
/// and store in-app purchase on iOS and Android. A consumer asks what a customer
/// is entitled to and where they manage it; which rail sold the subscription is
/// the package's problem, not the caller's.
///
/// This barrel is partial. It exports the contracts, the value objects, the
/// vocabularies and the exceptions; the facade, the drivers and the service
/// provider arrive with their own code, because a barrel cannot export a symbol
/// that does not exist yet.
library;

// Contracts
export 'src/contracts/billing_service.dart';
export 'src/contracts/web_billing_service.dart';

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

// Exceptions
export 'src/exceptions/billing_exception.dart';
