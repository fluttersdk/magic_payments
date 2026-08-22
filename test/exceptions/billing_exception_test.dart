import 'package:flutter_test/flutter_test.dart';
import 'package:magic_payments/magic_payments.dart';

void main() {
  group('BillingException', () {
    test('carries the failure message it was raised with', () {
      const BillingException exception = BillingException('Stripe said no.');

      expect(exception.message, 'Stripe said no.');
      expect(exception.toString(), 'BillingException: Stripe said no.');
    });

    test('lets a caller catch an unavailable rail on its own, without losing '
        'the general billing catch', () {
      const UnsupportedPlatformException exception =
          UnsupportedPlatformException('No store rail in this build.');

      expect(exception, isA<BillingException>());
      expect(exception.message, 'No store rail in this build.');
      expect(
        exception.toString(),
        'UnsupportedPlatformException: No store rail in this build.',
      );
    });
  });
}
