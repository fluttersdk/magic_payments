import '../models/billing_entitlement.dart';
import '../models/billing_invoices_page.dart';
import '../models/payment_method.dart';
import '../models/usage_stat.dart';

/// What a customer is entitled to, and what they have spent, read from the
/// vendor's own backend.
///
/// FIVE methods, and all five are reads. That is the whole shape of this
/// contract: a read is honourable on every platform, because the backend is the
/// authority on an entitlement no matter which rail sold it, so no
/// implementation of this interface ever has to throw for want of a platform.
///
/// The purchase and management calls are deliberately absent. They belong to a
/// RAIL, and a rail is not available everywhere: they live on
/// `WebBillingService` and `StoreBillingService`, each resolved only in a build
/// that can serve it. A caller therefore checks for a rail (`!= null`) instead of
/// calling a method and catching the platform's refusal, which is the difference
/// between a button that is absent and a button that fails.
///
/// ```dart
/// final BillingEntitlement entitlement = await billing.currentEntitlement();
/// if (entitlement.manageVia == ManageVia.portal) {
///   // The web rail owns this surface; see WebBillingService.
/// }
/// ```
abstract class BillingService {
  /// Reads the customer's current entitlement.
  ///
  /// The one call every billing surface starts from, and the answer to "what am
  /// I paying for and where do I manage it" on every platform.
  Future<BillingEntitlement> currentEntitlement();

  /// Reads the plan catalogue, cheapest tier first (the order an
  /// upgrade/downgrade affordance depends on).
  ///
  /// Rows verbatim, undecoded, because a tier's own fields are the vendor's
  /// product: prices, feature bullets and in-product caps are what the vendor
  /// sells, not what a payment rail understands. A model here would either
  /// enumerate one vendor's catalogue in a shared package or discard the half of
  /// each row it does not know, and the consumer already owns the type it wants
  /// to decode these into.
  Future<List<Map<String, dynamic>>> getPlans();

  /// Reads the current cycle's metered usage against the plan's caps.
  ///
  /// Every resource the producer reports, keyed by its wire key; the display
  /// copy for each is the consumer's, paired up by [UsageStat.key].
  Future<List<UsageStat>> getUsage();

  /// Reads one cursor-paginated page of the customer's invoices.
  ///
  /// [cursor] is the [BillingInvoicesPage.nextCursor] of the previous page, and
  /// is omitted for the first.
  Future<BillingInvoicesPage> getInvoices({String? cursor});

  /// Reads the card on file and the next renewal date.
  ///
  /// The one read that dials a payment rail live, so it is the one read that
  /// deserves its own loading and error state rather than sharing the screen's:
  /// the producer soft-fails a rail outage to an all-null [PaymentMethod] with a
  /// 200, so a resolved value does not imply a card.
  Future<PaymentMethod> getPaymentMethod();
}
