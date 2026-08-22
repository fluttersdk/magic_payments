import '../contracts/billing_service.dart';
import '../contracts/store_billing_service.dart';
import '../contracts/web_billing_service.dart';
import '../exceptions/billing_exception.dart';
import '../models/billing_entitlement.dart';
import '../models/billing_invoices_page.dart';
import '../models/payment_method.dart';
import '../models/usage_stat.dart';

/// The fallback [BillingService], resolved only where neither
/// `dart.library.html` nor `dart.library.io` applies.
///
/// Every read throws, and that is deliberate rather than left over. Elsewhere in
/// this package a read is honourable on every platform, because the vendor's
/// backend is the authority on an entitlement whatever rail sold it. Here there
/// is no assumed network stack to ask: this arm is reached on a platform the
/// package has never seen, so there is no transport to read the entitlement
/// over. A silent empty answer would render as a customer with no subscription,
/// which is a lie about a paying account, and it would be a lie a support ticket
/// could not distinguish from a genuine free tier.
///
/// Both rails resolve to `null` from this file, which is the correct answer for
/// the same reason: an absent rail is a button a caller does not render, not a
/// button that fails when tapped.
class BillingServiceStub implements BillingService {
  /// Creates a [BillingServiceStub].
  const BillingServiceStub();

  /// The one sentence a refused platform shows a human.
  ///
  /// It names no other way to buy, on purpose. Pointing a customer at a purchase
  /// method outside the app breaks App Review Guideline 3.1.3(a), and a message
  /// like "subscribe on our website" would do exactly that from inside a
  /// shipped binary.
  static const String _message = 'Billing is not supported on this platform.';

  @override
  Future<BillingEntitlement> currentEntitlement() async {
    throw const UnsupportedPlatformException(_message);
  }

  @override
  Future<List<Map<String, dynamic>>> getPlans() async {
    throw const UnsupportedPlatformException(_message);
  }

  @override
  Future<List<UsageStat>> getUsage() async {
    throw const UnsupportedPlatformException(_message);
  }

  @override
  Future<BillingInvoicesPage> getInvoices({String? cursor}) async {
    throw const UnsupportedPlatformException(_message);
  }

  @override
  Future<PaymentMethod> getPaymentMethod() async {
    throw const UnsupportedPlatformException(_message);
  }
}

/// Creates the fallback [BillingService] implementation.
///
/// The name and the return type are the conditional-import contract, shared with
/// both sibling arms. This is the DEFAULT arm, the one a platform lands on when
/// no guard matches, so a typo here is the failure that reaches an unexpected
/// platform rather than the one the compiler reports.
BillingService createBillingService() => const BillingServiceStub();

/// Resolves the WEB rail, which this arm never has.
///
/// A platform whose reads cannot be served has no business selling anything, and
/// `null` says so in the one way a caller can act on.
WebBillingService? createWebBillingService() => null;

/// Resolves the STORE rail, which this arm never has, for the same reason.
StoreBillingService? createStoreBillingService() => null;
