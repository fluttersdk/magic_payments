import 'package:flutter_test/flutter_test.dart';
import 'package:magic_payments/magic_payments.dart';

void main() {
  group('BillingErrorCode', () {
    test('names every failure a billing screen can tell the customer apart', () {
      // Pinned as the whole list: a caller switches on these exhaustively, so a
      // member added or removed is a change every consumer's switch must see.
      expect(BillingErrorCode.values, const [
        BillingErrorCode.notConfigured,
        BillingErrorCode.notIdentified,
        BillingErrorCode.identityMismatch,
        BillingErrorCode.managedElsewhere,
        BillingErrorCode.unmappedActiveProduct,
        BillingErrorCode.productUnavailable,
        BillingErrorCode.pending,
        BillingErrorCode.receiptInUse,
        BillingErrorCode.alreadyOwned,
        BillingErrorCode.network,
        BillingErrorCode.store,
        BillingErrorCode.unknown,
      ]);
    });
  });
}
