import '../enums/manage_via.dart';
import '../models/purchase_context.dart';
import '../models/store_product_offer.dart';

/// Buying and managing a subscription on the STORE rail, where the platform's
/// own in-app purchase system takes the money: StoreKit on iOS, Google Play
/// Billing on Android.
///
/// FIVE methods and one getter. Four of the methods hand the customer to a
/// surface this package does not own, and [products] reads the store's own
/// prices, which only the store can answer. They are separate from `BillingService`'s reads because
/// a rail is not available everywhere: this contract is resolved only in a build
/// that can serve it, and resolves to `null` elsewhere. There is deliberately no
/// `isAvailable` here, because the contract's own absence IS the availability
/// answer, and a second way to ask the same question is a second answer that can
/// disagree with the first.
///
/// The web counterpart is `WebBillingService`. Neither contract extends the other
/// and neither extends `BillingService`: which rails a build serves is exactly
/// what a caller needs to be able to ask.
///
/// ## What none of these methods promise
///
/// A store purchase is asynchronous, and the RAIL'S WEBHOOK is the authority on
/// the entitlement, not the device that tapped Buy. So a `true` from [purchase]
/// or [restore] says the store reported a completed transaction, and says nothing
/// about what `BillingService.currentEntitlement()` will answer one millisecond
/// later: the vendor's backend may not have been told yet. A caller re-reads the
/// entitlement, and treats a stale answer as "not yet" rather than as a failure.
///
/// ```dart
/// // The store rail is absent on the web, and a checkable absence is the point.
/// if (store != null) {
///   final bool bought = await store.purchase('pro_annual');
///   if (bought) {
///     // The store is done. The entitlement may not have caught up yet.
///     await billing.currentEntitlement();
///   }
/// }
/// ```
abstract class StoreBillingService {
  /// Tells the rail which of the vendor's accounts this device is buying for.
  ///
  /// [appUserId] is the vendor's own stable identifier for the paying subject,
  /// the same one its webhook will be attributed to (a team id where teams pay,
  /// a user id where users do). Never a device id or an anonymous rail-minted
  /// one: a purchase attributed to a device is a purchase the backend cannot
  /// give to anybody.
  ///
  /// It sits on this contract, and not only inside the rail's own driver, because
  /// a team switch has to be able to re-identify through the interface. A member
  /// that exists only on an implementation is a member the binding that needs it
  /// cannot reach.
  ///
  /// Call it on login and on every switch of the paying subject, before offering
  /// a purchase. It does NOT promise that the rail has finished aliasing the
  /// identity, and it grants nothing on its own.
  Future<void> identify(String appUserId);

  /// Puts the store's purchase sheet in front of the customer for
  /// [productKey], and answers whether the store reported a completed
  /// transaction.
  ///
  /// [productKey] is the vendor's own catalogue key (e.g. `'pro_annual'`), the
  /// same key `WebBillingService.checkout` takes and the same key a product in a
  /// `BillingService.getPlans()` row carries, never a store product id. The
  /// store product a key maps to belongs to the rail's catalogue, and a client
  /// that named a store SKU would need a re-release to add or reprice one.
  ///
  /// [context] carries the catalogue's tier order, so the rail can tell an
  /// upgrade from a downgrade when the customer already holds a subscription.
  /// The rail knows products, not tiers.
  ///
  /// `false` is the ordinary outcome of a customer who dismissed the sheet, so it
  /// is not an error and must not be reported as one; a rail that genuinely
  /// failed throws `BillingException` with a typed code instead. `true` is the
  /// rail's word and not the vendor's: see the class doc on what it does not
  /// promise.
  Future<bool> purchase(String productKey, {PurchaseContext? context});

  /// Reads the store's own localized price for each of [productKeys], keyed by
  /// catalogue key.
  ///
  /// A store build renders these figures rather than the catalogue's, because
  /// the store decides currency, tax and rounding, and the sheet will show its
  /// own. A key the store has no product for is absent from the answer rather
  /// than mapped to a guessed price; a caller renders that product as
  /// unavailable.
  Future<Map<String, StoreProductOffer>> products(List<String> productKeys);

  /// Asks the store for purchases this account already owns, and answers whether
  /// it handed one back.
  ///
  /// Required on iOS by App Review, and the customer's only route back to a
  /// subscription they bought on another device or before a reinstall. `false`
  /// means the store had nothing for the identified account, which is an answer
  /// to show the customer and not a failure to log; it also carries the same
  /// non-promise as [purchase] about when the entitlement catches up.
  Future<bool> restore();

  /// Opens the platform's own subscription management surface (the App Store or
  /// Play Store subscription screen).
  ///
  /// No URL in and none out, unlike `WebBillingService.openPortal`: the
  /// destination belongs to the operating system rather than to a session this
  /// package mints, so there is nothing to hand back or reuse.
  ///
  /// It promises only that the surface was opened. What the customer does there,
  /// including cancelling, reaches the vendor through the rail's webhook, so a
  /// caller re-reads the entitlement on return rather than assuming anything
  /// changed.
  Future<void> openStoreManagement();

  /// Which store this rail sells through: [ManageVia.appStore] or
  /// [ManageVia.playStore].
  ///
  /// The rail's own answer, so a caller comparing it with
  /// `BillingEntitlement.manageVia` can tell a subscription this store can
  /// change from one another rail sold, without asking the running platform.
  ManageVia get store;
}
