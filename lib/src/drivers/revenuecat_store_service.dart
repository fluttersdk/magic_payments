import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart' show PlatformException;
import 'package:magic/magic.dart';
// A `show` list rather than a plain import: `purchases_flutter` declares its own
// `UnsupportedPlatformException`, and this file already imports the one in
// `../exceptions/billing_exception.dart`. Naming only what is used keeps that
// collision from becoming an ambiguous reference the next editor has to decode.
import 'package:purchases_flutter/purchases_flutter.dart'
    show
        CustomerInfo,
        IntroEligibility,
        IntroEligibilityStatus,
        Offering,
        Offerings,
        Package,
        PurchaseParams,
        Purchases,
        PurchasesConfiguration,
        PurchasesErrorCode,
        PurchasesErrorHelper,
        ProductCategory,
        StoreProduct,
        StoreProductChangeInfo,
        StoreReplacementMode;

import '../contracts/store_billing_service.dart';
import '../enums/billing_error_code.dart';
import '../enums/manage_via.dart';
import '../enums/store_change_timing.dart';
import '../exceptions/billing_exception.dart';
import '../models/purchase_context.dart';
import '../models/store_product_offer.dart';
import '../support/store_identity_sync.dart';

/// The STORE rail against RevenueCat: StoreKit on iOS, Play Billing on Android,
/// both through one SDK.
///
/// Resolved by `createStoreRail` and never constructed by a consumer, because
/// which build gets it is a capability question and the factory owns that
/// answer. It carries no platform branch of its own: the factory hands it
/// [store], and every store-specific rule below reads that.
///
/// ## Configuration
///
/// | Key | Required | What it is |
/// |---|---|---|
/// | `payments.revenuecat.public_sdk_key` | yes | the rail's PUBLIC SDK key for this platform (`appl_...` on iOS, `goog_...` on Android) |
/// | `payments.revenuecat.subject_label` | no | a word naming what the App User ID identifies, e.g. `team` |
///
/// The key is public by design: RevenueCat's SDK keys are shipped in every app
/// binary and grant nothing on their own, so this reads a config value rather
/// than a secret. It is read through magic's `Config` and never hardcoded, and
/// its absence refuses at CONFIGURE time (which is login, through [identify])
/// rather than at purchase time, so an operator who never published it learns
/// before a customer taps Upgrade.
///
/// ## The App User ID is the bare id
///
/// [identify] hands the vendor's own identifier to the rail UNPREFIXED. A
/// readable `team:<uuid>` would close a door: RevenueCat's server-to-server
/// purchase tracking requires a valid RFC 4122 v4 UUID in some configurations,
/// and a prefixed id is not one. The readability that prefix would have bought
/// is available for the cost of one call instead: set `subject_label` and the
/// driver records `<label>:<id>` as a subscriber attribute, where a dashboard
/// reader sees it and no integration parses it.
///
/// ## What a purchase refuses before the sheet opens
///
/// Every refusal below is a [BillingException] whose [BillingErrorCode] names
/// it, because each one is money moving to the wrong place if it were allowed:
///
/// - the rail is bound to another App User ID than the session's paying subject
///   (`identityMismatch`), or the session has none (`notIdentified`): the
///   webhook would credit somebody else;
/// - the customer holds a subscription another store sells
///   (`managedElsewhere`): a second purchase here charges them twice;
/// - on Play, the customer holds a product no tier or period can be read for
///   (`unmappedActiveProduct`): no replacement mode can be computed against it
///   safely.
///
/// A RevenueCat promotional grant (`rc_promo_...`) is no store's subscription,
/// so it takes part in neither check. On Play, a customer who already holds a
/// subscription is CHANGED in place with a replacement mode rather than sold a
/// second one; see [purchase].
///
/// ## What this driver does NOT decide
///
/// The vendor's backend is the authority on the entitlement, and this driver's
/// job ends at reporting that the store said something happened. Nothing here
/// grants, caches or infers an entitlement from what the SDK returns: `purchase`
/// answers `true` because the sheet completed, `restore` answers the rail's own
/// report about that one call, and a caller re-reads
/// `BillingService.currentEntitlement()` afterwards knowing it may not have
/// caught up yet. The active store product ids are read only to refuse or shape
/// a purchase, never to grant anything.
///
/// ## The seams, which are the only lines that reach a platform channel
///
/// Every SDK call sits in its own `@visibleForTesting` method and the error
/// translation stays ABOVE it, exactly as `BillingServiceWeb.launchHostedPage`
/// does for the in-app browser. A test then subclasses this driver, overrides
/// the seams, and exercises the shipped control flow: the config read, the
/// plan-to-package lookup, the await discipline and the catch clauses are the
/// real ones, and no part of `purchases_flutter` is ever mocked.
///
/// ```dart
/// final StoreBillingService? store = Payments.store;
/// if (store != null) {
///   await store.identify(team.id);
///   if (await store.purchase('pro_annual')) {
///     await Payments.billing.currentEntitlement();
///   }
/// }
/// ```
class RevenueCatStoreService implements StoreBillingService {
  /// Creates a [RevenueCatStoreService] selling through [store].
  ///
  /// [store] is [ManageVia.appStore] or [ManageVia.playStore], decided by the
  /// factory from the device it resolved the rail for.
  RevenueCatStoreService({required this.store});

  @override
  final ManageVia store;

  /// The config key holding the rail's public SDK key for this platform.
  static const String apiKeyConfigKey = 'payments.revenuecat.public_sdk_key';

  /// The config key naming what the App User ID identifies, e.g. `team`.
  ///
  /// Optional, and absent means no attribute is written at all: an attribute
  /// repeating the App User ID would add a field and no information.
  static const String subjectLabelConfigKey =
      'payments.revenuecat.subject_label';

  /// The subscriber attribute the label is recorded under.
  ///
  /// A custom attribute rather than one of the rail's reserved ones (`$email`,
  /// `$displayName`): those carry meanings the rail acts on, and this is a note
  /// for whoever reads the dashboard.
  static const String subjectAttribute = 'magic_subject';

  /// An ISO 8601 billing period as the store reports it (`P1M`, `P1Y`).
  static final RegExp _isoPeriod = RegExp(r'^P(\d+)([DWMY])$');

  /// The prefix RevenueCat gives the id of a promotional entitlement granted
  /// from its dashboard, which no store bills.
  static const String _promotionalPrefix = 'rc_promo_';

  /// Whether [configureSdk] has already run for this process.
  bool _configured = false;

  @override
  StoreChangeTiming? get lastChangeTiming => _lastChangeTiming;

  /// What [lastChangeTiming] answers: cleared when a purchase starts, set only
  /// once the store confirmed it.
  StoreChangeTiming? _lastChangeTiming;

  // ---------------------------------------------------------------------------
  // StoreBillingService
  // ---------------------------------------------------------------------------

  @override
  Future<void> identify(String appUserId) async {
    await ensureConfigured();

    try {
      // The rail's binding is unknown from the moment the login starts until it
      // succeeds, so the sync's repeat guard forgets it now and learns the new
      // one only below. A failed login then leaves the next sync free to bind
      // the paying subject again rather than skipping it as a repeat.
      StoreIdentitySync.recordBinding(null);

      // `await`, not a bare call: the awaited future is what puts a rejection
      // inside this try. Drop it and the future escapes, the catch clauses never
      // run, and a device that failed to bind an identity goes on to offer a
      // purchase that will be attributed to whoever it was bound to before.
      await logInSdk(appUserId);
      StoreIdentitySync.recordBinding(appUserId);

      // The bare id above, the readable form here, and only when an operator
      // supplied the word: the driver knows the paying subject's id and not what
      // kind of thing it is.
      final String? label = Config.get<String>(subjectLabelConfigKey)?.trim();
      if (label != null && label.isNotEmpty) {
        try {
          await setSubscriberAttributes({
            subjectAttribute: '$label:$appUserId',
          });
        } catch (error) {
          // Handled here rather than shared with the identity failure below,
          // and not swallowed either. The identity WAS bound, which is all this
          // method promises; reporting a dashboard nicety as a failed identify
          // would tell a caller the paying subject is unbound and stop it
          // offering a purchase that would have worked.
          Log.warning(
            '[RevenueCatStoreService.identify] subscriber attribute not '
            'recorded: $error',
          );
        }
      }
    } on BillingException {
      rethrow;
    } on PlatformException catch (error) {
      Log.error('[RevenueCatStoreService.identify] ${error.code} $error');
      throw BillingException(
        'Failed to identify the paying account. $error',
        code: billingCodeFor(error),
      );
    } catch (error) {
      Log.error('[RevenueCatStoreService.identify] $error');
      throw BillingException('Failed to identify the paying account. $error');
    }
  }

  /// Puts the store's sheet up for [productKey], after refusing every purchase
  /// that would move money to the wrong place (see the class doc).
  ///
  /// On Play, a customer already holding a subscription of this store is
  /// changed in place, with the old subscription id and a replacement mode:
  ///
  /// | Change | Mode | [lastChangeTiming] |
  /// |---|---|---|
  /// | same subscription, longer period | `chargeFullPrice` | `immediate` |
  /// | same subscription, same or shorter period | `withoutProration` | `immediate` |
  /// | other subscription, higher tier, price per day rises | `chargeProratedPrice` | `immediate` |
  /// | other subscription, higher tier, otherwise | `chargeFullPrice` | `immediate` |
  /// | other subscription, same or lower tier | `deferred` | `atRenewal` |
  ///
  /// Play allows only the first two for a base-plan switch on one subscription,
  /// and accepts a prorated charge only when the price per unit of time rises,
  /// which is why both the tier order and the held product's price matter. A
  /// held product no offering sells any more (grandfathered) is ranked through
  /// [PurchaseContext.tierOfStoreProduct]; its price and period are unknown, so
  /// an upgrade from it is charged in full and a base-plan switch from it is
  /// refused. With no [context] a change between subscriptions is refused
  /// rather than guessed.
  ///
  /// A one-off product (consumable or non-consumable) skips all of this: it is
  /// bought beside a held subscription, on either store, with no change and no
  /// timing, since it neither replaces nor duplicates a subscription.
  ///
  /// The App Store rail never passes a change, because StoreKit moves a
  /// subscription inside its group on its own, so a held product it cannot name
  /// does not block the purchase. It still reports Apple's timing: a higher
  /// level now, a lower level or another duration of the same level at renewal.
  @override
  Future<bool> purchase(String productKey, {PurchaseContext? context}) async {
    await ensureConfigured();
    _lastChangeTiming = null;

    try {
      // 1. The webhook credits whoever the rail is bound to, so that must be
      //    the session's paying subject before anything else is asked.
      await _requirePayingSubject('purchase');

      // 2. The package the key names, which is also the one `products` priced.
      final Offerings offerings = await fetchOfferings();
      final Package? package = packageFor(offerings, productKey);
      if (package == null) {
        // Not a `false`. A dismissed sheet and a store with no product for this
        // plan are different events, and reporting the second as the first
        // hides a misconfigured catalogue behind a customer shrug.
        Log.error(
          '[RevenueCatStoreService.purchase] no package identified '
          '"$productKey" in ${offerings.all.length} offering(s)',
        );
        throw BillingException(
          'No store product is configured for "$productKey".',
          code: BillingErrorCode.productUnavailable,
        );
      }

      // 3. A one-off product (credits, an unlock) is bought beside whatever
      //    the customer subscribes to: it changes no subscription, so neither
      //    the cross-store refusal nor a replacement applies to it.
      if (!_isSubscription(package.storeProduct)) {
        await purchaseStorePackage(package);

        return true;
      }

      // 4. What the customer already holds decides whether this is a refusal,
      //    a fresh purchase or a change, and when that change lands.
      final List<String> held = _heldStoreProducts(
        await activeStoreProductIds(),
      );
      final StoreProductChangeInfo? change = store == ManageVia.playStore
          ? _playChange(offerings, held, package, productKey, context)
          : null;
      final StoreChangeTiming? timing = store == ManageVia.playStore
          ? _playTiming(change)
          : _appStoreTiming(offerings, held, package, productKey, context);

      await purchaseStorePackage(package, productChangeInfo: change);

      // 5. Only now: a dismissed or failed sheet changed nothing, and its
      //    timing would announce a change that never happened.
      _lastChangeTiming = timing;

      // The store's word, and nothing about the entitlement: the rail's webhook
      // is what tells the vendor's backend, and it may not have yet.
      return true;
    } on BillingException {
      rethrow;
    } on PlatformException catch (error) {
      if (isCancellation(error)) {
        // The ordinary outcome of a customer changing their mind, so it is not
        // logged as an error and not reported as one.
        Log.debug(
          '[RevenueCatStoreService.purchase] dismissed by the customer',
        );

        return false;
      }
      Log.error('[RevenueCatStoreService.purchase] ${error.code} $error');
      throw BillingException(
        'The purchase could not be completed. $error',
        code: billingCodeFor(error),
      );
    } catch (error) {
      Log.error('[RevenueCatStoreService.purchase] $error');
      throw BillingException('The purchase could not be completed. $error');
    }
  }

  @override
  Future<Map<String, StoreProductOffer>> products(
    List<String> productKeys,
  ) async {
    await ensureConfigured();

    try {
      final Offerings offerings = await fetchOfferings();

      // 1. Resolved through the same lookup `purchase` uses, so the price on the
      //    screen is the price of the product the sheet will sell.
      final Map<String, Package> packages = <String, Package>{
        for (final String key in productKeys)
          if (packageFor(offerings, key) case final Package package)
            key: package,
      };

      // 2. Eligibility is the store's answer about the customer, read per store
      //    product id, which is not the catalogue key the map is keyed by.
      final Set<String> eligible = await _introEligibleStoreProducts([
        for (final Package package in packages.values) package.storeProduct,
      ]);

      return <String, StoreProductOffer>{
        for (final MapEntry<String, Package> entry in packages.entries)
          entry.key: _offerFor(
            entry.value.storeProduct,
            introEligible: eligible.contains(
              entry.value.storeProduct.identifier,
            ),
          ),
      };
    } on BillingException {
      rethrow;
    } on PlatformException catch (error) {
      Log.error('[RevenueCatStoreService.products] ${error.code} $error');
      throw BillingException(
        'Store prices could not be read. $error',
        code: billingCodeFor(error),
      );
    } catch (error) {
      Log.error('[RevenueCatStoreService.products] $error');
      throw BillingException('Store prices could not be read. $error');
    }
  }

  @override
  Future<bool> restore() async {
    await ensureConfigured();

    try {
      // A restore aliases the store receipt onto whoever the rail holds, so it
      // moves a subscription between paying subjects exactly like a purchase.
      await _requirePayingSubject('restore');

      // `await` inside the try for the same reason as everywhere else here, and
      // the bool is the seam's answer rather than this driver's opinion.
      return await restoreStorePurchases();
    } on BillingException {
      rethrow;
    } on PlatformException catch (error) {
      Log.error('[RevenueCatStoreService.restore] ${error.code} $error');
      throw BillingException(
        'Purchases could not be restored. $error',
        code: billingCodeFor(error),
      );
    } catch (error) {
      Log.error('[RevenueCatStoreService.restore] $error');
      throw BillingException('Purchases could not be restored. $error');
    }
  }

  @override
  Future<void> openStoreManagement() async {
    await ensureConfigured();

    try {
      final String? url = await fetchManagementUrl();
      if (url == null || url.isEmpty) {
        // The rail names no surface when the account holds no store
        // subscription. Resolving anyway would read to the customer as a screen
        // that opened and closed.
        Log.error(
          '[RevenueCatStoreService.openStoreManagement] the rail named no '
          'management surface for this account',
        );
        throw const BillingException(
          'This account has no store subscription to manage.',
        );
      }

      final bool opened = await launchManagementPage(url);
      if (!opened) {
        // The other half of the same failure, and the half no `catch` can see:
        // the launcher answers `false` instead of throwing.
        Log.error(
          '[RevenueCatStoreService.openStoreManagement] launcher refused $url',
        );
        throw const BillingException(
          'Failed to open the store subscription screen.',
        );
      }
    } on BillingException {
      rethrow;
    } catch (error) {
      Log.error('[RevenueCatStoreService.openStoreManagement] $error');
      throw BillingException(
        'Failed to open the store subscription screen. $error',
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Configuration, and the lookup the seams are wrapped around
  // ---------------------------------------------------------------------------

  /// Configures the SDK once, refusing loudly when no key was published.
  ///
  /// Every method calls it, and [identify] is the first of them in an app's life
  /// (it runs on login), so a missing key surfaces there rather than under a
  /// customer's finger on the purchase sheet.
  @visibleForTesting
  Future<void> ensureConfigured() async {
    if (_configured) return;

    final String? apiKey = Config.get<String>(apiKeyConfigKey)?.trim();
    // An empty string is refused alongside a missing key: a published config
    // with the value left blank is the state a real app ships in first, and the
    // SDK's own failure for it arrives far from the cause.
    if (apiKey == null || apiKey.isEmpty) {
      Log.error(
        '[RevenueCatStoreService] no store rail key. Publish '
        '$apiKeyConfigKey with this platform\'s PUBLIC RevenueCat SDK key.',
      );
      throw const BillingException(
        'The store rail is not configured. Set '
        '$apiKeyConfigKey to this platform\'s public RevenueCat SDK key.',
        code: BillingErrorCode.notConfigured,
      );
    }

    await configureSdk(apiKey);
    _configured = true;
  }

  /// Finds the package [productKey] names in [offerings], or null when none
  /// does. [productKey] is the catalogue key `purchase` was given, which is the
  /// package identifier on the rail's dashboard.
  ///
  /// The CURRENT offering is searched first and the rest after it: an archived
  /// offering can carry a package under the same identifier pointing at last
  /// year's store product, and resolving that one charges last year's price.
  ///
  /// The identifier is the rail's catalogue key, so adding or repricing a plan
  /// is a dashboard change. A client that named a store SKU would need a
  /// re-release for the same thing.
  @visibleForTesting
  Package? packageFor(Offerings offerings, String productKey) {
    for (final Package package in _packagesOf(offerings)) {
      if (package.identifier == productKey) return package;
    }

    return null;
  }

  /// Whether [error] is the rail reporting a customer who dismissed the sheet.
  ///
  /// The numeric guard is load-bearing rather than defensive:
  /// `PurchasesErrorHelper.getErrorCode` parses the code as a number and throws
  /// a `FormatException` on anything else, and a `PlatformException` carrying
  /// `channel-error` is exactly such a code. Without it the translation blows up
  /// inside its own catch clause and the caller sees neither answer.
  @visibleForTesting
  bool isCancellation(PlatformException error) {
    if (int.tryParse(error.code) == null) return false;

    return PurchasesErrorHelper.getErrorCode(error) ==
        PurchasesErrorCode.purchaseCancelledError;
  }

  /// The [BillingErrorCode] a caller switches on for the rail's [error].
  ///
  /// Behind the same numeric guard as [isCancellation], and negative codes
  /// included, because `getErrorCode` indexes the enum with the parsed number.
  /// A code with no case of its own is [BillingErrorCode.unknown] rather than
  /// the nearest neighbour, which would be a claim about the failure.
  @visibleForTesting
  BillingErrorCode billingCodeFor(PlatformException error) {
    final int? raw = int.tryParse(error.code);
    if (raw == null || raw < 0) return BillingErrorCode.unknown;

    return switch (PurchasesErrorHelper.getErrorCode(error)) {
      PurchasesErrorCode.paymentPendingError => BillingErrorCode.pending,
      PurchasesErrorCode.receiptAlreadyInUseError ||
      PurchasesErrorCode.receiptInUseByOtherSubscriberError =>
        BillingErrorCode.receiptInUse,
      PurchasesErrorCode.productAlreadyPurchasedError =>
        BillingErrorCode.alreadyOwned,
      PurchasesErrorCode.networkError ||
      PurchasesErrorCode.offlineConnectionError => BillingErrorCode.network,
      PurchasesErrorCode.storeProblemError => BillingErrorCode.store,
      PurchasesErrorCode.configurationError => BillingErrorCode.notConfigured,
      PurchasesErrorCode.productNotAvailableForPurchaseError =>
        BillingErrorCode.productUnavailable,
      _ => BillingErrorCode.unknown,
    };
  }

  /// Refuses unless the rail is bound to the session's paying subject.
  ///
  /// The sync runs first so a rail still on a previous or anonymous id is
  /// re-bound when it can be; what is compared afterwards is the rail's OWN
  /// answer, not what the sync believes it did. An anonymous id never equals a
  /// paying subject's id, so it refuses as a mismatch.
  Future<void> _requirePayingSubject(String method) async {
    await StoreIdentitySync.syncNow();

    final String? billable = StoreIdentitySync.billableId?.call();
    if (billable == null || billable.isEmpty) {
      Log.error(
        '[RevenueCatStoreService.$method] no paying subject is identified',
      );
      throw const BillingException(
        'No paying account is identified for the store.',
        code: BillingErrorCode.notIdentified,
      );
    }

    final String bound = await currentAppUserId();
    if (bound != billable) {
      Log.error(
        '[RevenueCatStoreService.$method] the rail is bound to "$bound", '
        'not the paying subject "$billable"',
      );
      throw const BillingException(
        'The store is signed in for a different paying account.',
        code: BillingErrorCode.identityMismatch,
      );
    }
  }

  /// Whether [product] is a subscription, which is the only kind a purchase
  /// can collide with: one a customer already holds may need replacing, and
  /// one another store bills must not be bought twice.
  ///
  /// The SDK's category decides. Where it reports none, a billing period does,
  /// since an in-app product never carries one.
  bool _isSubscription(StoreProduct product) =>
      switch (product.productCategory) {
        ProductCategory.subscription => true,
        ProductCategory.nonSubscription => false,
        null => product.subscriptionPeriod != null,
      };

  /// The store product ids the customer holds that a purchase here has to
  /// account for, refusing any id another store sells.
  ///
  /// A promotional grant (`rc_promo_...`) is dropped first: RevenueCat issues it
  /// from its dashboard, no store bills it, and read by shape it would look like
  /// an App Store product to the Play rail. Which store an id belongs to is read
  /// off its shape: Play subscription ids are `subscriptionId:basePlanId`, App
  /// Store ids never carry a `:`.
  List<String> _heldStoreProducts(List<String> activeIds) {
    final List<String> held = <String>[
      for (final String id in activeIds)
        if (!id.startsWith(_promotionalPrefix)) id,
    ];

    for (final String id in held) {
      if (!_soldHere(id)) {
        Log.error(
          '[RevenueCatStoreService.purchase] "$id" is managed by another store',
        );
        throw const BillingException(
          'This subscription is managed by another store.',
          code: BillingErrorCode.managedElsewhere,
        );
      }
    }

    return held;
  }

  /// The replacement a Play purchase carries, or null for a fresh purchase.
  /// The rules are tabled on [purchase].
  StoreProductChangeInfo? _playChange(
    Offerings offerings,
    List<String> held,
    Package target,
    String productKey,
    PurchaseContext? context,
  ) {
    if (held.isEmpty) return null;

    // Play replaces ONE subscription per purchase, and with two there is no
    // answer to which one the customer means to give up.
    if (held.length > 1) {
      throw _unmapped(
        '${held.length} active Play subscriptions, so the one to replace is '
        'ambiguous',
      );
    }

    final String currentId = held.single;
    if (currentId == target.storeProduct.identifier) {
      throw const BillingException(
        'This subscription is already active.',
        code: BillingErrorCode.alreadyOwned,
      );
    }

    // Null for a grandfathered product: no offering sells it any more.
    final Package? current = _packageSelling(offerings, currentId);

    // The bare subscription id: Play Billing ignores anything after the `:`.
    final String oldSubscription = _subscriptionOf(currentId);
    final StoreReplacementMode mode =
        oldSubscription == _subscriptionOf(target.storeProduct.identifier)
        ? _basePlanSwitch(currentId, current, target)
        : _tierChange(currentId, current, target, productKey, context);

    return StoreProductChangeInfo(oldSubscription, replacementMode: mode);
  }

  /// When [change] lands: a deferred replacement at renewal, every other one
  /// now, and nothing for a fresh purchase.
  StoreChangeTiming? _playTiming(StoreProductChangeInfo? change) {
    if (change == null) return null;

    return change.replacementMode == StoreReplacementMode.deferred
        ? StoreChangeTiming.atRenewal
        : StoreChangeTiming.immediate;
  }

  /// A base-plan switch on one subscription, where Play allows only
  /// `chargeFullPrice` and `withoutProration`.
  ///
  /// Which one turns on the current period, and a held product with no package
  /// has none to read: picking either would be a guess about a charge.
  StoreReplacementMode _basePlanSwitch(
    String currentId,
    Package? current,
    Package target,
  ) {
    if (current == null) {
      throw _unmapped(
        '"$currentId" is in no offering, so its period is unknown',
      );
    }

    final int from = _periodDays(current);
    final int to = _periodDays(target);

    return to > from
        ? StoreReplacementMode.chargeFullPrice
        : StoreReplacementMode.withoutProration;
  }

  /// A move between subscriptions, judged by the catalogue's tier order and,
  /// for an upgrade, by the price per day.
  ///
  /// Play accepts `chargeProratedPrice` only when the price per unit of time
  /// rises, so an upgrade to a longer, cheaper-per-day period (or from a held
  /// product whose price is unknown) is charged in full instead.
  StoreReplacementMode _tierChange(
    String currentId,
    Package? current,
    Package target,
    String productKey,
    PurchaseContext? context,
  ) {
    if (context == null) {
      throw _unmapped('no tier order to judge a change between subscriptions');
    }

    final int from = _rank(context, _tierOfHeld(currentId, current, context));
    final int to = _rank(context, context.tierOfProduct[productKey]);
    if (from < 0 || to < 0) {
      throw _unmapped('no tier ranks "$currentId" against "$productKey"');
    }

    if (to <= from) return StoreReplacementMode.deferred;
    if (current == null) return StoreReplacementMode.chargeFullPrice;

    return _pricePerDay(target) > _pricePerDay(current)
        ? StoreReplacementMode.chargeProratedPrice
        : StoreReplacementMode.chargeFullPrice;
  }

  /// When Apple applies a move from the held product to [target], or null when
  /// nothing is being changed or the move cannot be ranked.
  ///
  /// Inside one subscription group a higher level applies at once, and a lower
  /// level or the same level at another duration at the next renewal. More than
  /// one held product means more than one group, where a purchase is not a
  /// change of the one the customer meant, so no timing is claimed.
  StoreChangeTiming? _appStoreTiming(
    Offerings offerings,
    List<String> held,
    Package target,
    String productKey,
    PurchaseContext? context,
  ) {
    if (context == null || held.length != 1) return null;

    final String currentId = held.single;
    if (currentId == target.storeProduct.identifier) return null;

    final Package? current = _packageSelling(offerings, currentId);
    final int from = _rank(context, _tierOfHeld(currentId, current, context));
    final int to = _rank(context, context.tierOfProduct[productKey]);
    if (from < 0 || to < 0) return null;

    return to > from
        ? StoreChangeTiming.immediate
        : StoreChangeTiming.atRenewal;
  }

  /// The tier of the held store product [storeProductId], or null when nothing
  /// names it.
  ///
  /// Its package's catalogue key first. A product no offering sells any more
  /// has none, so [PurchaseContext.tierOfStoreProduct] answers: the full id,
  /// then the bare subscription id of a Play product, the latter only when
  /// every id under that subscription names one tier.
  String? _tierOfHeld(
    String storeProductId,
    Package? current,
    PurchaseContext context,
  ) {
    final String? byKey = current == null
        ? null
        : context.tierOfProduct[current.identifier];
    if (byKey != null) return byKey;

    final Map<String, String> byStoreId = context.tierOfStoreProduct;
    final String? exact = byStoreId[storeProductId];
    if (exact != null) return exact;

    final String subscription = _subscriptionOf(storeProductId);
    final Set<String> tiers = <String>{
      for (final MapEntry<String, String> entry in byStoreId.entries)
        if (_subscriptionOf(entry.key) == subscription) entry.value,
    };

    return tiers.length == 1 ? tiers.single : null;
  }

  /// The position of [tier] in the context's tier order, -1 when absent.
  int _rank(PurchaseContext context, String? tier) =>
      tier == null ? -1 : context.tierOrder.indexOf(tier);

  /// The package selling the store product [storeProductId], current offering
  /// first, or null when no offering carries it (a grandfathered product).
  Package? _packageSelling(Offerings offerings, String storeProductId) {
    for (final Package package in _packagesOf(offerings)) {
      if (package.storeProduct.identifier == storeProductId) return package;
    }

    return null;
  }

  /// Every package in [offerings], the current offering's first.
  Iterable<Package> _packagesOf(Offerings offerings) sync* {
    for (final Offering offering in <Offering?>[
      offerings.current,
      ...offerings.all.values,
    ].nonNulls) {
      yield* offering.availablePackages;
    }
  }

  /// Whether [storeProductId] is a product of [store] rather than another's.
  bool _soldHere(String storeProductId) =>
      storeProductId.contains(':') == (store == ManageVia.playStore);

  /// The subscription id of a Play product id `subscriptionId:basePlanId`.
  String _subscriptionOf(String storeProductId) =>
      storeProductId.split(':').first;

  /// The billing period of [package] in days, close enough to order periods.
  ///
  /// A product with no readable period cannot be ordered against another, and
  /// picking a mode for it anyway would be a guess about a charge.
  int _periodDays(Package package) {
    final String? period = package.storeProduct.subscriptionPeriod;
    final RegExpMatch? match = period == null
        ? null
        : _isoPeriod.firstMatch(period);
    if (match == null) {
      throw _unmapped(
        '"${package.storeProduct.identifier}" has no readable period',
      );
    }

    final int count = int.parse(match.group(1)!);

    return count *
        switch (match.group(2)!) {
          'D' => 1,
          'W' => 7,
          'M' => 30,
          _ => 365,
        };
  }

  /// What [package] costs per day of its billing period, in the store's
  /// currency. Two packages of one storefront share a currency, which is all
  /// the comparison in [_tierChange] needs.
  double _pricePerDay(Package package) =>
      package.storeProduct.price / _periodDays(package);

  /// The refusal for an active product no change can be computed against.
  BillingException _unmapped(String reason) {
    Log.error('[RevenueCatStoreService.purchase] $reason');

    return const BillingException(
      'The active subscription cannot be changed from here.',
      code: BillingErrorCode.unmappedActiveProduct,
    );
  }

  /// The store product ids among [products] whose introductory offer THIS
  /// customer may take.
  ///
  /// Only products that carry an introductory price are considered, since the
  /// store has nothing to say about the others. The App Store is asked: its
  /// answer is the customer's own history with the subscription group, and only
  /// a definite `eligible` counts, so unknown and ineligible both stay out. Play
  /// is not asked, because its SDK answers unknown for everything and so would
  /// withhold every real trial; a present intro price is taken as eligible there
  /// since Play only offers what the account may take. That Play half is
  /// unverified against a real account.
  ///
  /// A failed read logs and answers nothing eligible: prices still render, and
  /// an offer is never promised on a read that did not happen.
  Future<Set<String>> _introEligibleStoreProducts(
    Iterable<StoreProduct> products,
  ) async {
    final Set<String> withIntro = <String>{
      for (final StoreProduct product in products)
        if (product.introductoryPrice != null) product.identifier,
    };
    if (withIntro.isEmpty) return <String>{};

    if (store == ManageVia.playStore) return withIntro;

    try {
      final Map<String, IntroEligibilityStatus> answers =
          await checkIntroEligibilitySdk(withIntro.toList());

      return <String>{
        for (final MapEntry<String, IntroEligibilityStatus> answer
            in answers.entries)
          if (withIntro.contains(answer.key) &&
              answer.value ==
                  IntroEligibilityStatus.introEligibilityStatusEligible)
            answer.key,
      };
    } catch (error) {
      Log.warning(
        '[RevenueCatStoreService.products] intro eligibility not read, so no '
        'intro offer is claimed: $error',
      );

      return <String>{};
    }
  }

  /// The store's own figures for [product], verbatim, with [introEligible] as
  /// the store answered it for this customer.
  StoreProductOffer _offerFor(
    StoreProduct product, {
    required bool introEligible,
  }) => StoreProductOffer(
    priceString: product.priceString,
    currencyCode: product.currencyCode,
    price: product.price,
    subscriptionPeriod: product.subscriptionPeriod,
    introPrice: product.introductoryPrice?.price,
    introPriceString: product.introductoryPrice?.priceString,
    introPeriod: product.introductoryPrice?.period,
    introEligible: introEligible,
  );

  // ---------------------------------------------------------------------------
  // The seams: one SDK call each, nothing else
  // ---------------------------------------------------------------------------

  /// Configures the RevenueCat SDK with [apiKey]. THE SEAM.
  @visibleForTesting
  Future<void> configureSdk(String apiKey) =>
      Purchases.configure(PurchasesConfiguration(apiKey));

  /// Binds the rail's current identity to [appUserId]. THE SEAM.
  ///
  /// The `LogInResult` is discarded deliberately: it carries a `CustomerInfo`,
  /// and reading an entitlement off it here would make the device the authority
  /// on what a customer may use.
  @visibleForTesting
  Future<void> logInSdk(String appUserId) => Purchases.logIn(appUserId);

  /// Reads the App User ID the rail is bound to right now. THE SEAM.
  ///
  /// An anonymous rail answers its own `$RCAnonymousID:` id.
  @visibleForTesting
  Future<String> currentAppUserId() => Purchases.appUserID;

  /// Records [values] against the identified subscriber. THE SEAM.
  @visibleForTesting
  Future<void> setSubscriberAttributes(Map<String, String> values) =>
      Purchases.setAttributes(values);

  /// Reads the rail's product catalogue. THE SEAM.
  @visibleForTesting
  Future<Offerings> fetchOfferings() => Purchases.getOfferings();

  /// Asks the store which of [storeProductIds] this customer may take the
  /// introductory offer on. THE SEAM.
  ///
  /// Keyed by store product id, with the SDK's status verbatim: deciding that
  /// only `eligible` counts belongs to the driver, not to the line that reaches
  /// the channel. iOS only; Android answers unknown for everything, which is why
  /// the Play rail never calls this.
  @visibleForTesting
  Future<Map<String, IntroEligibilityStatus>> checkIntroEligibilitySdk(
    List<String> storeProductIds,
  ) async {
    final Map<String, IntroEligibility> answers =
        await Purchases.checkTrialOrIntroductoryPriceEligibility(
          storeProductIds,
        );

    return <String, IntroEligibilityStatus>{
      for (final MapEntry<String, IntroEligibility> answer in answers.entries)
        answer.key: answer.value.status,
    };
  }

  /// Reads the store product ids the identified account holds active. THE
  /// SEAM.
  ///
  /// The ids and nothing else off the `CustomerInfo`: they decide whether a
  /// purchase is refused or shaped into a change, never what anybody is
  /// entitled to. On Android, App Store ids may appear beside the Play ones.
  @visibleForTesting
  Future<List<String>> activeStoreProductIds() async {
    final CustomerInfo info = await Purchases.getCustomerInfo();

    return info.activeSubscriptions;
  }

  /// Puts the store's purchase sheet up for [package]. THE SEAM.
  ///
  /// [productChangeInfo] is the Play subscription the purchase replaces, or
  /// null for a fresh purchase.
  ///
  /// The `PurchaseResult` is discarded for the same reason [logInSdk]'s is: the
  /// sheet completing is this driver's whole answer, and the entitlement belongs
  /// to the backend the rail's webhook reaches.
  @visibleForTesting
  Future<void> purchaseStorePackage(
    Package package, {
    StoreProductChangeInfo? productChangeInfo,
  }) => Purchases.purchase(
    PurchaseParams.package(package, productChangeInfo: productChangeInfo),
  );

  /// Asks the store for what the identified account already owns. THE SEAM.
  ///
  /// Answers whether the store handed a purchase BACK, which is the question
  /// `restore` documents. It reads two fields of the returned info, the
  /// subscriptions the store reports active and the one-off purchases it reports
  /// at all (a lifetime plan is not a subscription), and no entitlement: nothing
  /// is granted here, and the caller re-reads the backend either way.
  @visibleForTesting
  Future<bool> restoreStorePurchases() async {
    final CustomerInfo info = await Purchases.restorePurchases();

    return info.activeSubscriptions.isNotEmpty ||
        info.nonSubscriptionTransactions.isNotEmpty;
  }

  /// Reads the URL the rail names for managing this subscription. THE SEAM.
  ///
  /// It reads ONE string off the customer info. The rail resolves the
  /// destination per store (the App Store screen on iOS, the Play Store one on
  /// Android), which is why no platform branch appears here; `null` means the
  /// account holds no store subscription to manage.
  @visibleForTesting
  Future<String?> fetchManagementUrl() async {
    final CustomerInfo info = await Purchases.getCustomerInfo();

    return info.managementURL;
  }

  /// Hands [url] to the operating system. THE SEAM.
  ///
  /// `LaunchMode.externalApplication`, which is `Launch.url`'s default, and NOT
  /// the `inAppWebView` the hosted web pages use: the destination is the store's
  /// own app, and an in-app web view would render a page that cannot manage a
  /// subscription. Returns whether it opened, because `LaunchService.url`
  /// answers `false` rather than throwing.
  @visibleForTesting
  Future<bool> launchManagementPage(String url) => Launch.url(url);
}
