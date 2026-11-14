import 'dart:io';

import 'package:dowel/dowel.dart';
import 'package:magic_payments/src/cli/payments_dowel_provider.dart';
import 'package:test/test.dart';

/// Every Dart file reachable from `lib/cli.dart`, which is the CLI barrel plus
/// the whole `lib/src/cli/` tree.
///
/// Read off disk rather than hardcoded, so a file added to the tree later is
/// covered by the purity gate below without anyone remembering to list it.
List<File> _cliTreeFiles() {
  return <File>[
    File('lib/cli.dart'),
    ...Directory('lib/src/cli')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart')),
  ];
}

/// Every `import`/`export` target declared across [_cliTreeFiles].
Iterable<String> _cliTreeImportTargets() {
  final directive = RegExp(
    '''^\\s*(?:import|export)\\s+['"]([^'"]+)['"]''',
    multiLine: true,
  );
  return _cliTreeFiles().expand(
    (file) => directive
        .allMatches(file.readAsStringSync())
        .map((match) => match.group(1)!),
  );
}

void main() {
  group('MagicPaymentsDowelProvider command surface', () {
    late MagicPaymentsDowelProvider provider;

    setUp(() {
      provider = MagicPaymentsDowelProvider();
    });

    test('names itself payments, which is what a collision message prints', () {
      expect(provider.providerName, 'payments');
    });

    test('contributes exactly the three payments commands', () {
      final names = provider.commands().map((command) => command.name).toList();
      expect(
        names,
        containsAll(<String>[
          'payments:install',
          'payments:configure',
          'payments:doctor',
        ]),
      );
      expect(names, hasLength(3));
    });

    test('every command runs without a booted app', () {
      for (final command in provider.commands()) {
        expect(
          command.boot,
          CommandBoot.none,
          reason: '${command.name} must not need a VM Service connection',
        );
      }
    });

    test('every command carries a description for `dowel list`', () {
      for (final command in provider.commands()) {
        expect(command.description, isNotEmpty, reason: command.name);
      }
    });
  });

  group('MagicPaymentsDowelProvider MCP surface', () {
    late MagicPaymentsDowelProvider provider;

    setUp(() {
      provider = MagicPaymentsDowelProvider();
    });

    test('exposes exactly one tool, the read-only doctor', () {
      final tools = provider.mcpTools();
      expect(tools, hasLength(1));
      expect(tools.single.name, 'payments_doctor');
      expect(tools.single.extensionMethod, 'dowel:payments:doctor');
    });

    test('exposes no mutating command as a tool', () {
      // Asserted over BOTH fields: a tool renamed `payments_setup` while still
      // routing at `dowel:payments:install` would pass a name-only check.
      final surface = provider
          .mcpTools()
          .expand((tool) => <String>[tool.name, tool.extensionMethod])
          .join(' ');
      expect(surface, isNot(contains('install')));
      expect(surface, isNot(contains('configure')));
    });

    test('every tool declares a description and a routing key', () {
      for (final tool in provider.mcpTools()) {
        expect(tool.description, isNotEmpty, reason: tool.name);
        expect(tool.extensionMethod, isNotEmpty, reason: tool.name);
      }
    });

    test('the doctor tool lets an agent ask for the JSON report', () {
      // `payments:doctor --json` exists for agents, and an agent reaches the
      // command through this descriptor: a flag missing here is a mode no
      // agent can request.
      final Map<String, dynamic> properties =
          provider.mcpTools().single.inputSchema['properties']
              as Map<String, dynamic>;
      final Map<String, dynamic> json =
          properties['json'] as Map<String, dynamic>;

      expect(json['type'], 'boolean');
    });

    test('every tool input schema is a JSON-Schema object', () {
      for (final tool in provider.mcpTools()) {
        expect(tool.inputSchema['type'], 'object', reason: tool.name);
        expect(tool.inputSchema['properties'], isA<Map<String, dynamic>>());
      }
    });
  });

  group('the CLI tree is Flutter-free', () {
    // The pure-Dart dowel dispatcher imports `lib/cli.dart` from a process
    // with no Flutter engine. One `package:flutter` import anywhere in the
    // reachable graph breaks it at a consumer's command line, and nothing in
    // this package's own analyzer run would say so.

    test('lib/cli.dart names no toolkit import anywhere in its raw text', () {
      // Matched on `package:flutter/` WITH the slash, not on `package:flutter`,
      // so the check names the toolkit itself rather than any package whose
      // name merely starts with `flutter`.
      final source = File('lib/cli.dart').readAsStringSync();
      expect(source, isNot(contains('package:flutter/')));
      expect(source, isNot(contains('dart:ui')));
    });

    test('lib/cli.dart exports only the provider', () {
      final exports =
          RegExp('''^\\s*export\\s+['"]([^'"]+)['"]''', multiLine: true)
              .allMatches(File('lib/cli.dart').readAsStringSync())
              .map((match) => match.group(1)!);
      expect(exports, <String>['src/cli/payments_dowel_provider.dart']);
    });

    test('the whole CLI tree imports only dart: and dowel', () {
      // The transitive gate. `dowel` declares no `flutter`
      // dependency (pure Dart, `args`/`yaml`/`vm_service`/...), so restricting
      // the tree's package imports to that one package proves the entire
      // reachable graph is Flutter-free, which a grep for `package:flutter`
      // over these files alone could never show.
      final foreign = _cliTreeImportTargets()
          .where((target) => target.startsWith('package:'))
          .where((target) => !target.startsWith('package:dowel/'))
          .toList();
      expect(foreign, isEmpty);
    });

    test('the CLI tree reaches no runtime file of this package', () {
      // A relative import climbing out of `lib/src/cli/` would reach the
      // drivers, and those import `package:magic/magic.dart`, which imports
      // Flutter. Reached transitively, so the previous test cannot see it.
      final escaping = _cliTreeImportTargets()
          .where((target) => !target.startsWith('package:'))
          .where((target) => !target.startsWith('dart:'))
          .where((target) => target.contains('../'))
          .toList();
      expect(escaping, isEmpty);
    });
  });
}
