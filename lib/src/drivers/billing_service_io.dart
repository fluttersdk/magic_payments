import '../contracts/billing_service.dart';
import '../contracts/store_billing_service.dart';
import '../contracts/web_billing_service.dart';
import 'billing_reads_over_http.dart';
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
/// The five reads themselves live in [BillingReadsOverHttp], shared with the web
/// arm. They were duplicated here byte for byte until the review that split
/// them out: a conditional import compiles one arm per target, so nothing this
/// package can run was able to see the two copies drift.
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
class BillingServiceIo with BillingReadsOverHttp implements BillingService {
  /// Creates a [BillingServiceIo].
  const BillingServiceIo();
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
