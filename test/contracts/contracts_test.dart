import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The three contracts, by name and by file.
///
/// The name is the key because it is also what a sibling file must NOT contain:
/// the claim under test is that these three are unrelated types, and a contract
/// that referenced another would be the first step towards one extending it.
const Map<String, String> _contracts = {
  'BillingService': 'lib/src/contracts/billing_service.dart',
  'WebBillingService': 'lib/src/contracts/web_billing_service.dart',
  'StoreBillingService': 'lib/src/contracts/store_billing_service.dart',
};

/// The five reads, which are the whole of [BillingService].
const List<String> _reads = [
  'currentEntitlement',
  'getPlans',
  'getUsage',
  'getInvoices',
  'getPaymentMethod',
];

/// The four writes of each rail, keyed by the contract that owns them.
const Map<String, List<String>> _railWrites = {
  'WebBillingService': ['checkout', 'swap', 'cancel', 'openPortal'],
  'StoreBillingService': [
    'identify',
    'purchase',
    'restore',
    'openStoreManagement',
  ],
};

/// A member declaration inside a contract, which is a two-space-indented line
/// carrying a return type and a name.
final RegExp _memberDeclaration = RegExp(
  r'^  (?:Future<.+>|void|Never)\s+(\w+)\s*\(',
  multiLine: true,
);

/// Any of the three contract names, whole-word, with the two prefixed names
/// matched in full so `WebBillingService` is never read as a mention of
/// `BillingService`.
final RegExp _contractName = RegExp(r'\b(?:Web|Store)?BillingService\b');

void main() {
  // ---------------------------------------------------------------------------
  // Contracts carry no behaviour, so what is testable about them is the SPLIT:
  // which call lives on which of the three, and that none of the three is
  // reachable through another. Both are claims about the source, so that is what
  // these tests read.
  //
  // Every read here strips comments first, and it has to: all three docblocks
  // name all three contracts (the store contract's says "Neither contract
  // extends the other"), so the same assertions over raw source would report
  // three related types and be wrong about every one of them.
  // ---------------------------------------------------------------------------

  group('the three contracts are unrelated types', () {
    test('none of them extends, implements or mentions another', () {
      for (final MapEntry<String, String> contract in _contracts.entries) {
        final String source = _strippedSource(File(contract.value));

        // The declaration with nothing between the name and the brace: an
        // `implements BillingService` on either rail would put the reads back on
        // a rail contract and make "which rails does this build serve" an
        // unanswerable question.
        expect(
          source,
          contains('abstract class ${contract.key} {'),
          reason: '${contract.value} declares its class with a clause.',
        );

        expect(
          _contractName.allMatches(source).map((Match m) => m.group(0)).toSet(),
          {contract.key},
          reason:
              '${contract.value} names a sibling contract in its code. A '
              'reference is how the next version of this file ends up '
              'depending on one.',
        );
      }
    });
  });

  group('each call lives on exactly one contract', () {
    test('the reads contract declares the five reads and no write', () {
      final List<String> declared = _declaredMembers('BillingService');

      // Asserted as the whole list rather than as a `containsAll`: a write
      // added here would be a purchase call every implementation has to serve,
      // including the stub, on a contract whose promise is that no
      // implementation ever throws for want of a platform.
      expect(declared, _reads);
    });

    test('each rail declares its own four writes and nothing else', () {
      for (final MapEntry<String, List<String>> rail in _railWrites.entries) {
        expect(_declaredMembers(rail.key), rail.value, reason: rail.key);
      }
    });

    test('no member name is declared on two contracts', () {
      final List<String> all = [
        for (final String name in _contracts.keys) ..._declaredMembers(name),
      ];

      // The vacuity guard first: thirteen members, or the sweep read something
      // other than the contracts.
      expect(all, hasLength(13));
      expect(
        all.toSet(),
        hasLength(all.length),
        reason:
            'A name on two contracts means a caller holding one of them cannot '
            'tell which rail will serve the call.',
      );
    });
  });
}

/// The member names [contract] declares, in declaration order.
List<String> _declaredMembers(String contract) {
  final String source = _strippedSource(File(_contracts[contract]!));
  expect(
    source,
    contains('abstract class $contract'),
    reason: '$contract was not read.',
  );

  return _memberDeclaration
      .allMatches(source)
      .map((RegExpMatch match) => match.group(1)!)
      .toList();
}

/// Reads [file] with its comments removed.
///
/// A grep over raw source hits the docblock that explains why the thing it
/// searches for is absent, which is how a review grep once certified the
/// opposite of what it measured.
String _strippedSource(File file) {
  return file
      .readAsStringSync()
      .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '')
      .replaceAll(RegExp(r'^\s*///.*$', multiLine: true), '')
      .replaceAll(RegExp(r'^\s*//.*$', multiLine: true), '');
}
