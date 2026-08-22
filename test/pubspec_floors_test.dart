import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards the three version floors in `pubspec.yaml`, because each one is a
/// mistake this package was created having already seen.
///
/// A `0.0.z` caret pins the PATCH, so `^0.0.8` resolves exactly `0.0.8` and
/// nothing else. A sibling plugin still declares `fluttersdk_artisan: ^0.0.8`
/// against a published `0.0.13`, and it only survives because its consumer
/// path-overrides the dependency; this package's CI has no override, so a copied
/// caret would silently build against a five-release-old CLI. Likewise the
/// `environment` block is inherited from `magic` rather than chosen, and copying
/// a sibling's older block would claim support this package cannot honour.
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

    test('artisan is pinned to the published patch, not a stale one', () {
      expect(pubspec, contains('fluttersdk_artisan: ^0.0.13'));
      expect(pubspec, isNot(contains('fluttersdk_artisan: ^0.0.8')));
      expect(pubspec, isNot(contains('fluttersdk_artisan: ^0.0.9')));
    });

    test('magic is pinned to the floor its own API requires', () {
      expect(pubspec, contains('magic: ^0.0.6'));
    });
  });
}
