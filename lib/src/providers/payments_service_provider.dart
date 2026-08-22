import 'package:magic/magic.dart';

import '../contracts/billing_service.dart';
import '../payments_manager.dart';

/// Binds billing into magic's container and wires the platform driver.
///
/// Register it in the consumer's provider list:
///
/// ```dart
/// (app) => PaymentsServiceProvider(app),
/// ```
///
/// ## The register / boot split, and why it matters here
///
/// [register] binds ONE string-keyed singleton and does nothing else. It runs
/// the moment the provider is registered, which is before every other provider
/// has bound anything, so a driver resolved there would be resolved against a
/// half-built container. [boot] runs after all of them and is where the driver
/// is wired.
///
/// ## The configuration root, and the one key in it
///
/// This package reads `payments.*` and nothing else. It never reads a sibling
/// package's root: a plugin that read the starter kit's keys would break the
/// moment a consumer installed it without the starter kit.
///
/// `payments.driver` is the whole surface today, and it is a MODE rather than a
/// class name. `'platform'` is the only mode this package serves: it defers to
/// the conditional import in the billing service factory, which is the one place
/// that knows what a build can do. Absent or empty reads the same way, so an app
/// that never published a config still gets working entitlement reads.
///
/// Any other value is a misconfiguration, and [boot] says so at error level and
/// then wires the platform driver anyway. That degrade is deliberate: an
/// entitlement READ is honourable everywhere, and a paying customer must not
/// lose the billing screen over a typo in a key that cannot change what this
/// build is capable of. A driver of your own is installed in code, with
/// `Payments.extend(role, factory)`, not by naming it here: the container has no
/// reflection to turn a string into a constructor.
///
/// The rails are deliberately NOT configurable. A key that enabled or disabled a
/// rail would be a second answer to a question the import graph already settles,
/// and two answers eventually disagree.
class PaymentsServiceProvider extends ServiceProvider {
  /// Creates the provider against [app], magic's container.
  PaymentsServiceProvider(super.app);

  /// The container key billing is bound under.
  ///
  /// A string because magic's container has no reflection: `Magic.make` takes a
  /// name, so this is the word a consumer's own code resolves billing with.
  static const String _containerKey = 'payments';

  /// The only value `payments.driver` accepts: defer to the factory.
  static const String _platformMode = 'platform';

  @override
  void register() {
    app.singleton(_containerKey, () => PaymentsManager());
  }

  @override
  Future<void> boot() async {
    // 1. Through the container, not straight to the singleton: this is also the
    //    proof that `register()` bound what a consumer will resolve.
    final PaymentsManager payments = app.make<PaymentsManager>(_containerKey);

    // 2. The package's own config root, and the only key in it. A value this
    //    package cannot serve is reported and then ignored, because the mode
    //    cannot change what the build is capable of and a silent acceptance
    //    would leave the operator believing something was wired.
    final String? mode = Config.get<String>('payments.driver');
    if (mode != null && mode.isNotEmpty && mode != _platformMode) {
      Log.error(
        '[payments] config payments.driver is "$mode", and the only mode this '
        'package serves is "$_platformMode". Wiring the platform driver '
        'anyway. To supply a driver of your own, register it in code with '
        'Payments.extend(role, factory).',
      );
    }

    // 3. Wire the driver the factory's conditional import resolved for this
    //    build. Doing it here rather than lazily at the first billing screen
    //    means the resolution is recorded at boot, next to everything else that
    //    booted, which is where an operator looks first.
    final BillingService billing = payments.billing;

    // 4. Report which implementation answered and which rails came with it.
    //    Read from the same getters a caller reads, so the diagnostic cannot
    //    disagree with the behaviour: an absent rail here is exactly the absence
    //    that suppresses a purchase affordance.
    Log.debug(
      '[payments] driver ${billing.runtimeType}, '
      'web rail ${payments.web == null ? 'absent' : 'present'}, '
      'store rail ${payments.store == null ? 'absent' : 'present'}',
    );
  }
}
