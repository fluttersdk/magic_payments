/// The shared setup every billing test needs, and the seam convention every
/// future rail is tested through.
///
/// ## Why a helper at all
///
/// Nothing here decides anything. Each function does one binding a code path
/// under test resolves, and each is named after what it binds, because a test
/// whose setup is invisible is a test whose failure is hard to read: a
/// `setUpAll(harness)` that quietly bound four services turns "the container has
/// no [log]" into "something in the harness changed".
///
/// ## THE SEAM CONVENTION, which is the part worth copying
///
/// A driver method that touches a platform channel (an in-app browser, StoreKit,
/// Play Billing, a rail's SDK) is marked `@visibleForTesting` and left
/// overridable, and the translation that wraps it stays in the caller. A test
/// then subclasses the driver, overrides ONLY the channel-touching method, and
/// exercises the real control flow above it:
///
/// ```dart
/// class _FakeRailDriver extends BillingServiceWeb {
///   _FakeRailDriver(this.raising);
///
///   final Object? raising;
///
///   @override
///   Future<void> launchHostedPage(String url) async {
///     if (raising != null) throw raising!;
///   }
/// }
/// ```
///
/// `BillingServiceWeb.launchHostedPage` is the worked example: it is the only
/// line in that driver that reaches `url_launcher`, and
/// `BillingServiceWeb.openHostedPage`'s `try`/`catch` above it is what the tests
/// assert on. The rule the convention exists to keep is that a THIRD-PARTY SDK
/// is never mocked; what stands in is the package's own method.
///
/// [bindLaunchFacade] is the other half of the answer and not a competing one.
/// Override the seam when the assertion is about what the driver DOES with a
/// failure; bind the recording adapter when the assertion is about the launch
/// itself, because the mode (`inAppWebView` rather than an external browser) is
/// only observable underneath the facade.
library;

import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';
import 'package:magic_payments/magic_payments.dart';

/// Boots the framework the way a consumer app boots it, minus the app.
///
/// [providers] is registered and booted by `Magic.init` itself, so a test that
/// needs the provider's `register`/`boot` split gets it here rather than
/// hand-driving `MagicApp`.
Future<void> initMagicForTests({
  List<ServiceProvider> providers = const [],
}) async {
  WidgetsFlutterBinding.ensureInitialized();
  await Magic.init(configFactories: const [], providers: providers);
}

/// Empties both singletons that outlive a test.
///
/// Two resets, because two of them survive. The container is reset so a provider
/// registration cannot leak into the next test, and the manager is emptied
/// because `PaymentsManager()` is a `static final` that survives
/// `MagicApp.reset()`: a fake rail registered in one test would otherwise still
/// be registered in the next file, which is how a leaked singleton once served
/// one tenant's data to the next.
void resetPaymentsState() {
  MagicApp.reset();
  PaymentsManager().forgetDrivers();
}

/// Binds `log`, which every billing path resolves before it throws.
///
/// Load-bearing rather than tidy: a driver logs on its way out of a failure, and
/// `Log` resolves `Magic.make<LogManager>('log')`, so an unbound container fails
/// a failure-path test with a container error instead of the translation the test
/// is asserting on.
void bindLogFacade() {
  MagicApp.instance.singleton('log', LogManager.new);
}

/// Binds `launch` on a [RecordingLaunchAdapter] and hands the adapter back.
///
/// The write paths that mint a hosted page open it through magic's `Launch`
/// facade, which resolves a [LaunchService] out of the container, so this is the
/// binding a test needs when it asserts on the launch rather than on the
/// driver's own error handling.
RecordingLaunchAdapter bindLaunchFacade() {
  final RecordingLaunchAdapter adapter = RecordingLaunchAdapter();
  Magic.app.setInstance('launch', LaunchService(adapter: adapter));

  return adapter;
}

/// Removes the `launch` binding [bindLaunchFacade] installed.
void unbindLaunchFacade() {
  Magic.app.removeInstance('launch');
}

/// A [LaunchAdapter] that records instead of launching.
///
/// Recording the MODE as well as the URL is the point: `externalApplication`
/// would open a real browser, and a hosted checkout's return to `successUrl`
/// would land there instead of back in the app.
class RecordingLaunchAdapter implements LaunchAdapter {
  /// Every launch attempt, URL and mode both, in order.
  final List<(Uri, LaunchMode)> launched = [];

  @override
  Future<bool> launch(
    Uri url, {
    LaunchMode mode = LaunchMode.externalApplication,
  }) async {
    launched.add((url, mode));

    return true;
  }

  @override
  Future<bool> canLaunch(Uri url) async => true;
}
