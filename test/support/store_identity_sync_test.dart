import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:magic/magic.dart';
import 'package:magic_payments/magic_payments.dart';

import '../test_helper.dart';

/// A store rail that records every identify, and can be told to refuse.
///
/// The list of ids rather than a flag: the id IS what a webhook attributes a
/// purchase to, so every assertion here is about which id reached the rail and
/// how many times.
class _RecordingStoreRail implements StoreBillingService {
  final List<String> identifiedIds = [];

  /// Thrown from [identify] while set, after the call was recorded.
  BillingException? refusal;

  @override
  Future<void> identify(String appUserId) async {
    identifiedIds.add(appUserId);

    final BillingException? error = refusal;
    if (error != null) throw error;
  }

  @override
  Future<bool> purchase({required String plan}) async => false;

  @override
  Future<bool> restore() async => false;

  @override
  Future<void> openStoreManagement() async {}
}

/// A store rail whose identify for an id finishes only when the test releases
/// that id, the way a vendor SDK can finish two calls in either order.
///
/// [bound] is the id of the identify that finished LAST: that is the binding a
/// real rail is left holding.
class _GatedStoreRail implements StoreBillingService {
  final Map<String, Completer<void>> _gates = {};
  final List<String> startedIds = [];
  String? bound;

  Completer<void> _gate(String appUserId) =>
      _gates.putIfAbsent(appUserId, Completer<void>.new);

  /// Lets the identify for [appUserId] finish, now or whenever it starts.
  void release(String appUserId) => _gate(appUserId).complete();

  @override
  Future<void> identify(String appUserId) async {
    startedIds.add(appUserId);
    await _gate(appUserId).future;
    bound = appUserId;
  }

  @override
  Future<bool> purchase({required String plan}) async => false;

  @override
  Future<bool> restore() async => false;

  @override
  Future<void> openStoreManagement() async {}
}

/// A store rail whose identify fails with something other than a
/// [BillingException]: a defect in the rail, not a refusal.
class _BrokenStoreRail extends _RecordingStoreRail {
  /// Fails every identify while set.
  bool broken = true;

  @override
  Future<void> identify(String appUserId) async {
    identifiedIds.add(appUserId);
    if (broken) throw StateError('rail defect');
  }
}

void main() {
  late FakeLogManager log;
  String? billable;

  setUp(() {
    resetPaymentsState();
    Magic.flush();
    log = Log.fake();
    Auth.fake();
    billable = 'team-alpha';
    StoreIdentitySync.billableId = () => billable;
  });

  tearDown(() {
    StoreIdentitySync.detach();
    StoreIdentitySync.billableId = null;
    resetPaymentsState();
    Magic.flush();
  });

  _RecordingStoreRail useStoreRail() {
    final _RecordingStoreRail store = _RecordingStoreRail();
    Payments.extend(PaymentsManager.storeRole, () => store);

    return store;
  }

  group('an auth change re-identifies the store', () {
    test('a bump of the auth state identifies the resolved id', () async {
      final _RecordingStoreRail store = useStoreRail();
      StoreIdentitySync.attach();

      Auth.stateNotifier.value++;
      await pumpEventQueue();

      expect(store.identifiedIds, ['team-alpha']);
    });

    test('detach stops listening to auth changes', () async {
      final _RecordingStoreRail store = useStoreRail();
      StoreIdentitySync.attach();
      StoreIdentitySync.detach();

      Auth.stateNotifier.value++;
      await pumpEventQueue();

      expect(store.identifiedIds, isEmpty);
    });

    test('attaching twice listens once', () async {
      final _RecordingStoreRail store = useStoreRail();
      StoreIdentitySync.attach();
      StoreIdentitySync.attach();
      billable = 'team-beta';

      Auth.stateNotifier.value++;
      await pumpEventQueue();
      StoreIdentitySync.detach();
      billable = 'team-gamma';
      Auth.stateNotifier.value++;
      await pumpEventQueue();

      // A second listener left behind by the double attach would survive the
      // single detach and identify team-gamma.
      expect(store.identifiedIds, ['team-beta']);
    });
  });

  group('nothing to identify', () {
    test('an empty id skips the store', () async {
      final _RecordingStoreRail store = useStoreRail();
      billable = '';

      await StoreIdentitySync.syncNow();

      expect(store.identifiedIds, isEmpty);
    });

    test('a null id skips the store', () async {
      final _RecordingStoreRail store = useStoreRail();
      billable = null;

      await StoreIdentitySync.syncNow();

      expect(store.identifiedIds, isEmpty);
    });

    test(
      'a build without a store rail asks nothing and does not throw',
      () async {
        int resolved = 0;
        StoreIdentitySync.billableId = () {
          resolved++;

          return 'team-alpha';
        };

        await StoreIdentitySync.syncNow();

        expect(Payments.store, isNull);
        expect(resolved, 0);
      },
    );

    test(
      'an unset resolver identifies nothing and says so once, at debug',
      () async {
        final _RecordingStoreRail store = useStoreRail();
        StoreIdentitySync.billableId = null;

        await StoreIdentitySync.syncNow();
        await StoreIdentitySync.syncNow();

        expect(store.identifiedIds, isEmpty);
        expect(
          log.entries
              .where((FakeLogEntry entry) => entry.level == 'debug')
              .length,
          1,
        );
      },
    );
  });

  group('an idle sync runs in the caller\'s zone', () {
    test('it starts identifying in the caller\'s own turn', () {
      // The queue used to chain every sync onto a stored future, and a
      // completed future runs its listener in the zone it was CREATED in. A
      // sync started inside a widget test's fake-async zone then waited on
      // another zone's microtask queue, which nothing there flushes: the team
      // switch awaiting it never returned.
      final _RecordingStoreRail store = useStoreRail();

      unawaited(StoreIdentitySync.syncNow());

      expect(store.identifiedIds, ['team-alpha']);
    });

    test('a detach during an identify keeps the next sync behind it', () async {
      // A sign-out during a slow vendor call, then a sign-in: the two
      // identifies must not run side by side, or the rail keeps whichever
      // the SDK finishes last rather than the newer subject.
      final _GatedStoreRail store = _GatedStoreRail();
      Payments.extend(PaymentsManager.storeRole, () => store);

      final Future<void> first = StoreIdentitySync.syncNow();
      await pumpEventQueue();
      StoreIdentitySync.detach();
      billable = 'team-beta';
      final Future<void> second = StoreIdentitySync.syncNow();
      await pumpEventQueue();

      expect(store.startedIds, ['team-alpha']);

      store.release('team-beta');
      await pumpEventQueue();
      store.release('team-alpha');
      await Future.wait(<Future<void>>[first, second]);

      expect(store.startedIds, ['team-alpha', 'team-beta']);
      expect(store.bound, 'team-beta');
    });
  });

  group('identify runs once per subject', () {
    test('the same id twice in a row identifies exactly once', () async {
      final _RecordingStoreRail store = useStoreRail();

      await StoreIdentitySync.syncNow();
      await StoreIdentitySync.syncNow();

      expect(store.identifiedIds, ['team-alpha']);
    });

    test(
      'two overlapping syncs for the same id identify exactly once',
      () async {
        final _RecordingStoreRail store = useStoreRail();

        await Future.wait(<Future<void>>[
          StoreIdentitySync.syncNow(),
          StoreIdentitySync.syncNow(),
        ]);

        expect(store.identifiedIds, ['team-alpha']);
      },
    );

    test('a different id identifies again', () async {
      final _RecordingStoreRail store = useStoreRail();

      await StoreIdentitySync.syncNow();
      billable = 'team-beta';
      await StoreIdentitySync.syncNow();

      expect(store.identifiedIds, ['team-alpha', 'team-beta']);
    });

    test('signing out and back in as the same subject identifies again', () async {
      // The device may have been identified as someone else in between (another
      // app, a restore), so a fresh session must never be skipped as a repeat.
      final _RecordingStoreRail store = useStoreRail();

      await StoreIdentitySync.syncNow();
      billable = null;
      await StoreIdentitySync.syncNow();
      billable = 'team-alpha';
      await StoreIdentitySync.syncNow();

      expect(store.identifiedIds, ['team-alpha', 'team-alpha']);
    });

    test('an empty id also resets the repeat guard', () async {
      final _RecordingStoreRail store = useStoreRail();

      await StoreIdentitySync.syncNow();
      billable = '';
      await StoreIdentitySync.syncNow();
      billable = 'team-alpha';
      await StoreIdentitySync.syncNow();

      expect(store.identifiedIds, ['team-alpha', 'team-alpha']);
    });
  });

  group('syncs for different subjects', () {
    test(
      'a switch during an identify leaves the rail on the newer subject, whatever order the rail finishes in',
      () async {
        final _GatedStoreRail store = _GatedStoreRail();
        Payments.extend(PaymentsManager.storeRole, () => store);

        final Future<void> first = StoreIdentitySync.syncNow();
        await pumpEventQueue();
        billable = 'team-beta';
        final Future<void> second = StoreIdentitySync.syncNow();
        await pumpEventQueue();

        // The rail finishes the newer call first, then the older one.
        store.release('team-beta');
        await pumpEventQueue();
        store.release('team-alpha');
        await Future.wait(<Future<void>>[first, second]);

        expect(store.startedIds, ['team-alpha', 'team-beta']);
        expect(store.bound, 'team-beta');
      },
    );

    test(
      'a sync reads the subject when its turn comes, not when it was called',
      () async {
        final _GatedStoreRail store = _GatedStoreRail();
        Payments.extend(PaymentsManager.storeRole, () => store);

        final Future<void> first = StoreIdentitySync.syncNow();
        await pumpEventQueue();
        final Future<void> second = StoreIdentitySync.syncNow();
        billable = 'team-beta';
        store
          ..release('team-alpha')
          ..release('team-beta');
        await Future.wait(<Future<void>>[first, second]);

        expect(store.startedIds, ['team-alpha', 'team-beta']);
        expect(store.bound, 'team-beta');
      },
    );
  });

  group('a refusing store', () {
    test('a throwing identify is logged at error and does not throw', () async {
      final _RecordingStoreRail store = useStoreRail()
        ..refusal = const BillingException('rail down');

      await expectLater(StoreIdentitySync.syncNow(), completes);

      expect(store.identifiedIds, ['team-alpha']);
      expect(
        log.entries
            .where((FakeLogEntry entry) => entry.level == 'error')
            .map((FakeLogEntry entry) => entry.message),
        [contains('rail down')],
      );
    });

    test(
      'an error that is not a BillingException reaches the caller and is retried',
      () async {
        final _BrokenStoreRail store = _BrokenStoreRail();
        Payments.extend(PaymentsManager.storeRole, () => store);

        await expectLater(StoreIdentitySync.syncNow(), throwsStateError);
        await expectLater(StoreIdentitySync.syncNow(), throwsStateError);

        // Forgotten on failure, so the second sync asked the rail again.
        expect(store.identifiedIds, ['team-alpha', 'team-alpha']);
      },
    );

    test(
      'an auth change whose sync throws logs the error instead of escaping',
      () async {
        final _BrokenStoreRail store = _BrokenStoreRail();
        Payments.extend(PaymentsManager.storeRole, () => store);
        StoreIdentitySync.attach();

        Auth.stateNotifier.value++;
        await pumpEventQueue();

        expect(store.identifiedIds, ['team-alpha']);
        expect(
          log.entries
              .where((FakeLogEntry entry) => entry.level == 'error')
              .map((FakeLogEntry entry) => entry.message),
          [contains('rail defect')],
        );
      },
    );

    test(
      'a sync that throws does not stop the syncs queued after it',
      () async {
        // Only a rethrown error reaches the queue: a BillingException is logged
        // inside the sync and completes it normally.
        final _BrokenStoreRail store = _BrokenStoreRail();
        Payments.extend(PaymentsManager.storeRole, () => store);

        await expectLater(StoreIdentitySync.syncNow(), throwsStateError);
        store.broken = false;
        billable = 'team-beta';
        await StoreIdentitySync.syncNow();

        expect(store.identifiedIds, ['team-alpha', 'team-beta']);
      },
    );

    test('a failed identify is retried for the same id', () async {
      // The rail still holds the previous binding, so skipping the retry as a
      // repeat would leave purchases attributed to the previous subject.
      final _RecordingStoreRail store = useStoreRail()
        ..refusal = const BillingException('rail down');

      await StoreIdentitySync.syncNow();
      store.refusal = null;
      await StoreIdentitySync.syncNow();

      expect(store.identifiedIds, ['team-alpha', 'team-alpha']);
    });
  });
}
