import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards the three version floors in `pubspec.yaml`, because each one is a
/// mistake this package was created having already seen.
///
/// A caret is a FLOOR, including at `0.0.z`. Dart's is not npm's: `pub_semver`
/// bumps the minor when major is 0, so `^0.0.8` means `>=0.0.8 <0.1.0` and a
/// solver is free to hand back `0.0.13`. What a caret cannot do is reach BELOW
/// itself, which is the whole reason these floors are asserted: a sibling
/// plugin still declares `fluttersdk_artisan: ^0.0.8` against a published
/// `0.0.13`, and copying that stale caret here would let a solver satisfy this
/// package with a five-release-old CLI whenever something else in the graph
/// wanted one. Likewise the `environment` block is inherited from `magic`
/// rather than chosen, and copying a sibling's older block would claim support
/// this package cannot honour.
///
/// An earlier version of this docblock said a `0.0.z` caret pins the patch.
/// It does not, and the claim is corrected here rather than deleted because it
/// travelled: it was read as fact and cost a downstream plan a blocker that
/// did not exist. Measured with a scratch package reproducing the published
/// graph, where `^0.0.9` resolved artisan `0.0.13` and `^0.0.2` resolved
/// notifications `0.0.3`.
///
/// A test rather than a comment because a comment cannot fail.
void main() {
  late final String pubspec;

  setUpAll(() {
    pubspec = File('pubspec.yaml').readAsStringSync();
  });

  group('pubspec floors', () {
    test('the SDK constraints are inherited from magic, not from a sibling', () {
      expect(pubspec, contains('sdk: ">=3.11.0 <4.0.0"'));
      expect(pubspec, contains('flutter: ">=3.41.0"'));

      // The block a sibling plugin declares. Copying it is the specific error.
      expect(pubspec, isNot(contains('sdk: ">=3.6.0 <4.0.0"')));
      expect(pubspec, isNot(contains('flutter: ">=3.27.0"')));
    });

    test('the artisan floor is the published patch, not a stale one', () {
      expect(pubspec, contains('fluttersdk_artisan: ^0.0.13'));
      expect(pubspec, isNot(contains('fluttersdk_artisan: ^0.0.8')));
      expect(pubspec, isNot(contains('fluttersdk_artisan: ^0.0.9')));
    });

    test('magic is pinned to the floor its own API requires', () {
      expect(pubspec, contains('magic: ^0.0.6'));
    });
  });
}
