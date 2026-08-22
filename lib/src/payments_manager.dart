import 'contracts/billing_service.dart';
import 'contracts/store_billing_service.dart';
import 'contracts/web_billing_service.dart';
import 'drivers/billing_service_factory.dart';
import 'exceptions/billing_exception.dart';

/// The one object a consumer asks for billing, and the only assembly point
/// between the entitlement reads and the two purchase rails.
///
/// A singleton in the house shape (a `static final` instance behind a `factory`
/// constructor), because the override registry has to be the SAME registry the
/// billing screen reads: a second manager would accept a consumer's [extend] and
/// then hand the screen the built-in driver anyway.
///
/// ## Three roles, three contracts, and why they are not one
///
/// - [billing] serves the five entitlement READS, which are honourable on every
///   platform: the vendor's backend is the authority on an entitlement no matter
///   which rail sold the subscription.
/// - [web] and [store] serve the WRITES, and each is `null` in a build that
///   cannot serve that rail. The absence is the availability answer. A caller
///   checks the rail before it renders an upgrade button instead of rendering
///   one and catching a refusal, which is the difference between a button that
///   is absent and a button that fails.
///
/// All three come from `createBillingService()`, `createWebBillingService()` and
/// `createStoreBillingService()`, so the conditional import inside
/// `billing_service_factory.dart` stays the only line in this package that knows
/// anything about platforms. Nothing here asks the runtime which device it is
/// on, and nothing here offers a second way to ask whether a rail exists: the
/// contract's own absence already answers it, and a second answer would
/// eventually disagree with the first.
///
/// ```dart
/// final BillingEntitlement entitlement =
///     await Payments.billing.currentEntitlement();
///
/// // A rail is checked, never assumed.
/// final WebBillingService? web = Payments.web;
/// if (web != null) {
///   await web.openPortal(returnUrl: 'https://example.com/billing');
/// }
/// ```
class PaymentsManager {
  /// The single instance every entry point resolves to.
  static final PaymentsManager _instance = PaymentsManager._internal();

  /// Returns the singleton.
  factory PaymentsManager() => _instance;

  PaymentsManager._internal();

  /// The role serving the five entitlement reads.
  static const String billingRole = 'billing';

  /// The role serving the WEB rail: a hosted checkout and a hosted portal.
  static const String webRole = 'web';

  /// The role serving the STORE rail: StoreKit and Google Play Billing.
  static const String storeRole = 'store';

  /// Every role [extend] accepts.
  ///
  /// Closed, and closed on purpose: a role is a contract this package declares,
  /// so a name outside this set is a typo rather than an extension point.
  static const Set<String> roles = {billingRole, webRole, storeRole};

  /// Consumer-registered factories, keyed by ROLE rather than by class name.
  ///
  /// A consumer overriding the web rail is replacing a role and should not have
  /// to know which class currently fills it. There is no reflection in Dart
  /// here, so the built-in half of the resolution is an explicit switch in
  /// [_create] and this map is the escape hatch in front of it.
  final Map<String, Object Function()> _factories =
      <String, Object Function()>{};

  /// Resolved instances, keyed by role.
  ///
  /// Only a resolved PRESENCE is held. An absent rail resolves to `null` from a
  /// factory function that returns a literal, so re-asking costs nothing and
  /// there is no "cached absence" state to tell apart from "never asked".
  final Map<String, Object> _resolved = <String, Object>{};

  /// The five entitlement reads, always available.
  ///
  /// Every arm of the factory returns an implementation, so this getter never
  /// answers null. On a platform the package has never seen, the implementation
  /// it returns is the stub, whose reads throw
  /// [UnsupportedPlatformException]: a refusal a support ticket can read, rather
  /// than an empty answer that would render as a customer with no subscription.
  BillingService get billing => _required<BillingService>(billingRole);

  /// The WEB rail, or `null` where this build cannot serve one.
  ///
  /// `null` is not an error and must not be logged as one. It is the answer a
  /// caller acts on before it offers a hosted checkout or a portal link.
  WebBillingService? get web => _optional<WebBillingService>(webRole);

  /// The STORE rail, or `null` where this build cannot serve one.
  ///
  /// Non-null on iOS and Android, where the RevenueCat driver serves it, and
  /// `null` everywhere else: on web and on the stub arm there is no store to
  /// reach, and on macOS, Windows and Linux `dart.library.io` is satisfied
  /// without StoreKit or Play Billing being present.
  ///
  /// `null` is not an error and must not be logged as one, exactly as for
  /// [web]. It is the answer a caller acts on before it offers a purchase.
  StoreBillingService? get store => _optional<StoreBillingService>(storeRole);

  /// Registers [factory] as the implementation of [role], replacing whatever
  /// filled it.
  ///
  /// [role] is one of [roles]. Anything else throws rather than registering
  /// quietly: an override under a misspelled role is an override nothing ever
  /// reads, and the consumer would see the built-in driver with no way to tell
  /// why theirs was ignored.
  ///
  /// Calling it AFTER something has already read the role is supported, and the
  /// cache eviction here is what makes it so. That path is not an edge case: a
  /// test that fakes a rail runs after whatever resolved it, and without the
  /// eviction it would keep receiving the real driver.
  ///
  /// The registered object is type-checked when the role is first read, not
  /// here: the three roles carry three unrelated contracts and share one
  /// registry, so no single Dart map can hold them all under a static type.
  /// Registering a factory does not call it.
  ///
  /// ```dart
  /// Payments.extend(PaymentsManager.storeRole, () => MyStoreRail());
  /// ```
  void extend(String role, Object Function() factory) {
    if (!roles.contains(role)) {
      throw BillingException(
        'Unknown payments role "$role". The roles are ${roles.join(', ')}.',
      );
    }

    _factories[role] = factory;
    _resolved.remove(role);
  }

  /// Drops every override and every resolved instance, so each role answers
  /// from the factory again.
  ///
  /// The test-isolation seam, and it clears BOTH maps deliberately. This
  /// manager is a `static final` that outlives a container reset, so a
  /// surviving override would hand the next test a rail it never registered,
  /// and a rail that falsely claims to exist is worse than one that does not.
  void forgetDrivers() {
    _factories.clear();
    _resolved.clear();
  }

  /// The instance filling [role], resolved once and then held.
  Object? _instanceOf(String role) {
    final Object? held = _resolved[role];
    if (held != null) return held;

    final Object? created = _create(role);
    if (created != null) _resolved[role] = created;

    return created;
  }

  /// Builds the instance filling [role]: a consumer's override if there is one,
  /// otherwise the factory's answer for this build.
  ///
  /// The switch is explicit because Dart has no reflection to map a role name
  /// onto a constructor. Its last arm cannot be reached, since [extend] refuses
  /// an unknown role and every caller passes one of the three constants; it
  /// throws rather than answering null because a switch expression over a
  /// `String` must be total, and a null there would silently empty [billing].
  Object? _create(String role) {
    final Object Function()? override = _factories[role];
    if (override != null) return override();

    return switch (role) {
      billingRole => createBillingService(),
      webRole => createWebBillingService(),
      storeRole => createStoreBillingService(),
      _ => throw StateError('Unknown payments role "$role".'),
    };
  }

  /// The instance filling [role], which must be present and must be a [T].
  T _required<T extends Object>(String role) {
    final Object? instance = _instanceOf(role);
    if (instance is T) return instance;

    throw BillingException(_wrongType(role, instance, T));
  }

  /// The instance filling [role] when there is one, which must then be a [T].
  T? _optional<T extends Object>(String role) {
    final Object? instance = _instanceOf(role);
    if (instance == null || instance is T) return instance as T?;

    throw BillingException(_wrongType(role, instance, T));
  }

  /// The message for an override that cannot serve the role it was registered
  /// under.
  ///
  /// It names the role, what arrived and what was expected, because the
  /// alternative is a bare cast error surfacing inside a billing screen with
  /// nothing in it to say which `extend` call was wrong.
  String _wrongType(String role, Object? instance, Type expected) {
    return 'The "$role" role resolved a ${instance.runtimeType}, which does '
        'not implement $expected. Check the factory registered for "$role".';
  }
}
