import 'dart:io';

import 'package:test/test.dart';

/// The five reads, and the gate that keeps them in ONE place.
///
/// These assertions read source text rather than calling anything, and that is
/// deliberate: the property under test is structural. A conditional import
/// compiles exactly one driver arm per target, so two copies of a read method
/// can never be observed disagreeing by any test, on any platform, however many
/// of them run. The duplication that prompted this file was 106 lines in each
/// arm differing by a single line wrap, and it was invisible to a green analyze,
/// a green format check and 184 passing tests at once.
void main() {
  const String mixinPath = 'lib/src/drivers/billing_reads_over_http.dart';
  const String ioPath = 'lib/src/drivers/billing_service_io.dart';
  const String webPath = 'lib/src/drivers/billing_service_web.dart';

  const List<String> reads = <String>[
    'currentEntitlement(',
    'getPlans(',
    'getUsage(',
    'getInvoices(',
    'getPaymentMethod(',
  ];

  /// Source with comments removed, so prose naming a method cannot pass or fail
  /// an assertion about the code declaring one.
  String stripped(String path) {
    return File(path)
        .readAsStringSync()
        .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '')
        .replaceAll(RegExp(r'^\s*///.*$', multiLine: true), '')
        .replaceAll(RegExp(r'^\s*//.*$', multiLine: true), '');
  }

  group('the shared reads live in exactly one place', () {
    test('the mixin declares all five', () {
      final String source = stripped(mixinPath);

      // Vacuity guard: an unreadable or emptied file would satisfy a `contains`
      // loop over nothing.
      expect(source, contains('mixin BillingReadsOverHttp'));

      for (final String read in reads) {
        expect(
          source,
          contains(read),
          reason:
              'A read missing from the mixin is a read missing from BOTH arms, '
              'and the analyzer will only say so for the arm being compiled.',
        );
      }
    });

    test('neither driver declares one of its own', () {
      for (final String path in <String>[ioPath, webPath]) {
        final String source = stripped(path);

        // Each arm must still be the file it claims to be, or the loop below
        // asserts the absence of methods from an empty string.
        expect(source, contains('with BillingReadsOverHttp'));

        for (final String read in reads) {
          expect(
            source,
            isNot(contains(read)),
            reason:
                '$path declares $read itself, so the mixin is being shadowed '
                'and the two arms can drift apart again. Only one arm compiles '
                'per target, so no run of this suite would catch that.',
          );
        }
      }
    });

    test('the mixin carries no platform seam of its own', () {
      // It is taken by BOTH arms, so a platform import here would drag one
      // arm's libraries into the other and a platform branch would answer
      // "which rail" with "which device". Raw source, comments included, so
      // prose that named one fails too: a docblock is where the next one
      // arrives.
      final String raw = File(mixinPath).readAsStringSync();

      for (final String seam in <String>[
        'dart.library',
        'dart:html',
        'dart:io',
        'kIsWeb',
        'Platform.is',
        'defaultTargetPlatform',
      ]) {
        expect(raw, isNot(contains(seam)));
      }
    });
  });
}
