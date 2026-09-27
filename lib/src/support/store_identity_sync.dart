import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:magic/magic.dart';

import '../contracts/store_billing_service.dart';
import '../exceptions/billing_exception.dart';
import '../facades/payments.dart';

/// Keeps the STORE rail identified as the subject the current session pays as.
///
/// The App User ID the rail holds is what the vendor's webhook attributes a
/// purchase to, so a rail left on the previous subject hands the next purchase
/// to somebody who never made it, and a rail never identified hands it to
/// nobody. Neither shows on screen. This class decides WHEN identify fires; who
/// the paying subject is (a user, a team) stays the consumer's answer, supplied
/// through [billableId].
///
/// ```dart
/// StoreIdentitySync.billableId = () => User.current.currentTeam?.id?.toString();
/// StoreIdentitySync.attach();
///
/// // After a switch of the paying subject the auth bump alone may still name
/// // the previous one, so the switch identifies explicitly once it succeeded.
/// await StoreIdentitySync.syncNow();
/// ```
///
/// A signed-out session identifies nothing and unbinds nothing: the contract has
/// no logout (the store account belongs to the device), and the next sign-in
/// overwrites the binding.
class StoreIdentitySync {
  /// Not instantiable. The sync is process-wide, like the rail it binds.
  StoreIdentitySync._();

  /// Answers the paying subject's id for the current session, or `null` (or an
  /// empty string) when there is none yet.
  ///
  /// No default: whether a team or a user pays is the consumer's decision, and
  /// a guessed default would bind purchases to the wrong subject silently. While
  /// unset, [syncNow] identifies nothing and says so once at debug level.
  static String? Function()? billableId;

  /// The notifier [attach] listens to, held so [detach] removes the listener
  /// from the same guard even after the container rebinds `auth`.
  static ValueNotifier<int>? _notifier;

  /// The id last handed to the rail, set before the call so a [detach] during
  /// it leaves nothing behind, and cleared when the call fails or the session
  /// loses its subject.
  static String? _identified;

  /// The last queued sync while one is in flight, null while idle.
  ///
  /// Two identifies in flight at once leave the rail on whichever the vendor
  /// SDK finishes last, not on the newer subject, so syncs run one at a time.
  /// Null rather than a completed future when idle: a completed future runs
  /// its listeners in the zone it was created in, so chaining onto one would
  /// move an idle sync into another zone's microtask queue.
  static Future<void>? _tail;

  /// Whether the unset [billableId] has been reported, so the debug line lands
  /// once rather than on every auth bump.
  static bool _reportedUnset = false;

  /// Starts identifying on every `Auth.stateNotifier` change: a login, a
  /// restore, a logout.
  ///
  /// Calling it again re-attaches rather than stacking a second listener.
  static void attach() {
    _notifier?.removeListener(_onAuthChanged);

    final ValueNotifier<int> notifier = Auth.stateNotifier;
    notifier.addListener(_onAuthChanged);
    _notifier = notifier;
  }

  /// Stops listening and forgets what was identified, so a later [attach]
  /// starts from a rail it knows nothing about.
  static void detach() {
    // The queue stays: a sync still in flight (a sign-out during a slow vendor
    // call) must finish before the next one starts, attached or not.
    _notifier?.removeListener(_onAuthChanged);
    _notifier = null;
    _identified = null;
    _reportedUnset = false;
  }

  /// Identifies [Payments.store] as the subject [billableId] names, when the
  /// build has a store rail and the session has a subject.
  ///
  /// The same id twice in a row identifies once. The guard resets when the id
  /// goes absent (a sign-out), so the next sign-in as the same subject
  /// identifies again: the device may have been bound elsewhere in between.
  ///
  /// Syncs run one at a time in call order, and each reads the rail and the
  /// subject when its turn comes: a switch that lands while an identify is in
  /// flight identifies the newer subject after it, never alongside it.
  ///
  /// A [BillingException] from the rail is logged at error level and not
  /// rethrown, because whatever prompted the sync (a login, a switch) already
  /// succeeded; the failed id is forgotten so the next sync retries it.
  static Future<void> syncNow() {
    // Idle: run now, in the caller's zone and turn. Busy: queue behind the
    // sync in flight, which reads the rail and the subject when its turn comes.
    final Future<void>? previous = _tail;
    final Future<void> run = previous == null
        ? _sync()
        : previous.then((_) => _sync());

    // The queue only orders the syncs; the caller still gets [run]'s error,
    // and without this a single rethrow would fail every sync queued after it.
    final Future<void> tail = run.then((_) {}, onError: (Object _) {});
    _tail = tail;
    unawaited(
      tail.then((_) {
        if (identical(_tail, tail)) _tail = null;
      }),
    );

    return run;
  }

  static Future<void> _sync() async {
    // 1. A build without a store rail has nothing to bind; that is an answer.
    final StoreBillingService? store = Payments.store;
    if (store == null) return;

    // 2. No resolver is a wiring gap in the adopter, reported once.
    final String? Function()? resolver = billableId;
    if (resolver == null) {
      _reportUnsetResolver();

      return;
    }

    // 3. No subject yet (or signed out): forget the last one so it re-binds.
    final String? id = resolver();
    if (id == null || id.isEmpty) {
      _identified = null;

      return;
    }

    if (id == _identified) return;

    _identified = id;
    try {
      await store.identify(id);
    } catch (error) {
      _identified = null;
      if (error is! BillingException) rethrow;

      // Not rethrown: the caller's own action succeeded. Error level because
      // the rail keeps the previous binding until the next successful sync.
      Log.error('[StoreIdentitySync] store identify failed for $id: $error');
    }
  }

  /// The auth listener. Listeners are synchronous and [syncNow] is not, so the
  /// call runs unawaited and anything it rethrows is logged rather than
  /// escaping as an unhandled async error.
  static void _onAuthChanged() {
    unawaited(
      syncNow().catchError((Object error) {
        Log.error('[StoreIdentitySync] store identity sync failed: $error');
      }),
    );
  }

  static void _reportUnsetResolver() {
    if (_reportedUnset) return;

    _reportedUnset = true;
    Log.debug(
      '[StoreIdentitySync] billableId is not set, so the store rail is not '
      'identified. Set StoreIdentitySync.billableId to the paying subject.',
    );
  }
}
