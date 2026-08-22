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
        Offering,
        Offerings,
        Package,
        PurchaseParams,
        Purchases,
        PurchasesConfiguration,
        PurchasesErrorCode,
        PurchasesErrorHelper;

import '../contracts/store_billing_service.dart';
import '../exceptions/billing_exception.dart';

/// The STORE rail against RevenueCat: StoreKit on iOS, Play Billing on Android,
/// both through one SDK.
///
/// Resolved by `createStoreRail` and never constructed by a consumer, because
/// which build gets it is a capability question and the factory owns that
/// answer. It carries no platform branch of its own.
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
/// ## What this driver does NOT decide
///
/// The vendor's backend is the authority on the entitlement, and this driver's
/// job ends at reporting that the store said something happened. Nothing here
/// grants, caches or infers an entitlement from what the SDK returns: `purchase`
/// answers `true` because the sheet completed, `restore` answers the rail's own
/// report about that one call, and a caller re-reads
/// `BillingService.currentEntitlement()` afterwards knowing it may not have
/// caught up yet.
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
///   if (await store.purchase(plan: 'pro')) {
///     await Payments.billing.currentEntitlement();
///   }
/// }
/// ```
class RevenueCatStoreService implements StoreBillingService {
  /// Creates a [RevenueCatStoreService].
  RevenueCatStoreService();

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

  /// Whether [configureSdk] has already run for this process.
  bool _configured = false;

  // ---------------------------------------------------------------------------
  // StoreBillingService
  // ---------------------------------------------------------------------------

  @override
  Future<void> identify(String appUserId) async {
    await ensureConfigured();

    try {
      // `await`, not a bare call: the awaited future is what puts a rejection
      // inside this try. Drop it and the future escapes, the catch clauses never
      // run, and a device that failed to bind an identity goes on to offer a
      // purchase that will be attributed to whoever it was bound to before.
      await logInSdk(appUserId);

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
    } catch (error) {
      Log.error('[RevenueCatStoreService.identify] $error');
      throw BillingException('Failed to identify the paying account. $error');
    }
  }

  @override
  Future<bool> purchase({required String plan}) async {
    await ensureConfigured();

    try {
      final Offerings offerings = await fetchOfferings();
      final Package? package = packageFor(offerings, plan);
      if (package == null) {
        // Not a `false`. A dismissed sheet and a store with no product for this
        // plan are different events, and reporting the second as the first
        // hides a misconfigured catalogue behind a customer shrug.
        Log.error(
          '[RevenueCatStoreService.purchase] no package identified "$plan" in '
          '${offerings.all.length} offering(s)',
        );
        throw BillingException(
          'No store product is configured for the "$plan" plan.',
        );
      }

      await purchaseStorePackage(package);

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
      throw BillingException('The purchase could not be completed. $error');
    } catch (error) {
      Log.error('[RevenueCatStoreService.purchase] $error');
      throw BillingException('The purchase could not be completed. $error');
    }
  }

  @override
  Future<bool> restore() async {
    await ensureConfigured();

    try {
      // `await` inside the try for the same reason as everywhere else here, and
      // the bool is the seam's answer rather than this driver's opinion.
      return await restoreStorePurchases();
    } on BillingException {
      rethrow;
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
      );
    }

    await configureSdk(apiKey);
    _configured = true;
  }

  /// Finds the package [plan] names in [offerings], or null when none does.
  ///
  /// The CURRENT offering is searched first and the rest after it: an archived
  /// offering can carry a package under the same identifier pointing at last
  /// year's store product, and resolving that one charges last year's price.
  ///
  /// The identifier is the rail's catalogue key, so adding or repricing a plan
  /// is a dashboard change. A client that named a store SKU would need a
  /// re-release for the same thing.
  @visibleForTesting
  Package? packageFor(Offerings offerings, String plan) {
    for (final Offering offering in <Offering?>[
      offerings.current,
      ...offerings.all.values,
    ].nonNulls) {
      for (final Package package in offering.availablePackages) {
        if (package.identifier == plan) return package;
      }
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

  /// Records [values] against the identified subscriber. THE SEAM.
  @visibleForTesting
  Future<void> setSubscriberAttributes(Map<String, String> values) =>
      Purchases.setAttributes(values);

  /// Reads the rail's product catalogue. THE SEAM.
  @visibleForTesting
  Future<Offerings> fetchOfferings() => Purchases.getOfferings();

  /// Puts the store's purchase sheet up for [package]. THE SEAM.
  ///
  /// The `PurchaseResult` is discarded for the same reason [logInSdk]'s is: the
  /// sheet completing is this driver's whole answer, and the entitlement belongs
  /// to the backend the rail's webhook reaches.
  @visibleForTesting
  Future<void> purchaseStorePackage(Package package) =>
      Purchases.purchase(PurchaseParams.package(package));

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
  /// The one call in this driver that reaches `getCustomerInfo`, and it reads
  /// ONE string off the answer. The rail resolves the destination per store (the
  /// App Store screen on iOS, the Play Store one on Android), which is why no
  /// platform branch appears here; `null` means the account holds no store
  /// subscription to manage.
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
