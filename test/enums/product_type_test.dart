import 'package:flutter_test/flutter_test.dart';
import 'package:magic_payments/magic_payments.dart';

/// The complete `type` vocabulary of a catalogue product row, copied from the
/// producer's product types rather than written from memory.
const Map<String, ProductType> _productTypeWire = {
  'subscription': ProductType.subscription,
  'consumable': ProductType.consumable,
  'non_consumable': ProductType.nonConsumable,
  'physical': ProductType.physical,
};

void main() {
  group('ProductType', () {
    test('decodes every type the producer can name', () {
      _productTypeWire.forEach((String wire, ProductType expected) {
        expect(ProductType.fromWire(wire), expected, reason: wire);
      });
    });

    test(
      'mirrors the wire completely, so no type is mapped onto a neighbour',
      () {
        final List<ProductType?> decoded = _productTypeWire.keys
            .map(ProductType.fromWire)
            .toList();

        expect(decoded.toSet().length, decoded.length);
        expect(decoded.toSet(), ProductType.values.toSet());
        expect(_productTypeWire.length, ProductType.values.length);
      },
    );

    test('encodes the snake_case literal, never the Dart member name', () {
      // `nonConsumable.name` would send a word the producer rejects.
      _productTypeWire.forEach((String wire, ProductType type) {
        expect(type.toWire(), wire, reason: wire);
      });
    });

    test(
      'answers null for an unknown type rather than guessing what a customer bought',
      () {
        expect(ProductType.fromWire('weird'), isNull);
        expect(ProductType.fromWire(null), isNull);
        expect(ProductType.fromWire('nonConsumable'), isNull);
        expect(ProductType.fromWire('Subscription'), isNull);
      },
    );
  });
}
