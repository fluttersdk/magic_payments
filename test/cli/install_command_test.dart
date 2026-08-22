import 'dart:io';

import 'package:fluttersdk_artisan/artisan.dart';
import 'package:magic_payments/src/cli/commands/install_command.dart';
import 'package:test/test.dart';

/// Test subclass pinning the project root at a temp fixture.
///
/// The install is manifest-driven, but `injectProvider` and
/// `injectConfigFactory` are helper-backed ops that write through `dart:io`
/// directly rather than through the context's [VirtualFs], so the fixture has
/// to be a REAL directory: an in-memory filesystem would never observe those
/// two writes and the idempotency assertion below would be vacuous.
class _PinnedInstallCommand extends InstallCommand {
  _PinnedInstallCommand(this._root);

  final String _root;

  @override
  String getProjectRoot() => _root;
}

/// The parsed CLI surface for a non-interactive run, with [overrides] applied.
Map<String, dynamic> _options([Map<String, dynamic> overrides = const {}]) =>
    <String, dynamic>{
      'force': false,
      'dry-run': false,
      'non-interactive': true,
      'no-bootstrap': false,
      ...overrides,
    };

ArtisanContext _ctx(
  InstallCommand command, [
  Map<String, dynamic> over = const {},
]) {
  return ArtisanContext.bare(
    MapInput(_options(over), signature: command.parsedSignature),
    BufferedOutput(),
  );
}

void main() {
  late Directory temp;
  late _PinnedInstallCommand command;

  String at(String relative) => '${temp.path}/$relative';

  setUp(() {
    temp = Directory.systemTemp.createTempSync('magic_payments_install_');
    command = _PinnedInstallCommand(temp.path);

    File(at('pubspec.yaml')).writeAsStringSync('''
name: test_app
dependencies:
  flutter:
    sdk: flutter
  magic_payments: ^0.0.1
''');

    // The manifest installer resolves the plugin's own assets/stubs/ through
    // the CONSUMER's package config, so a fixture without this file silently
    // falls back to the artisan substrate's stub search paths and the publish
    // fails on a stub that was never missing.
    Directory(at('.dart_tool')).createSync(recursive: true);
    File(at('.dart_tool/package_config.json')).writeAsStringSync('''
{
  "configVersion": 2,
  "packages": [
    {
      "name": "magic_payments",
      "rootUri": "file://${Directory.current.path}",
      "packageUri": "lib/",
      "languageVersion": "3.11"
    }
  ]
}
''');

    Directory(at('lib/config')).createSync(recursive: true);
    File(at('lib/config/app.dart')).writeAsStringSync('''
import 'package:magic/magic.dart';

final appConfig = {
  'providers': [
    (app) => RouteServiceProvider(app),
  ],
};
''');

    File(at('lib/main.dart')).writeAsStringSync('''
import 'package:magic/magic.dart';
import 'config/app.dart';

void main() async {
  await Magic.init(
    configFactories: [
      () => appConfig,
    ],
  );
}
''');
  });

  tearDown(() {
    if (temp.existsSync()) {
      temp.deleteSync(recursive: true);
    }
  });

  group('InstallCommand surface', () {
    test('is an install command carrying the four standard flags', () {
      expect(command, isA<ArtisanInstallCommand>());
      expect(command.signature, contains('payments:install'));
      expect(command.signature, contains('--force'));
      expect(command.signature, contains('--dry-run'));
      expect(command.signature, contains('--non-interactive'));
    });

    test('writes its install record under the package name', () {
      expect(command.pluginName(_ctx(command)), 'magic_payments');
    });

    test('resolves the bundled install.yaml off the package root', () {
      final path = command.resolveManifestPath();
      expect(path, isNotNull);
      expect(File(path!).existsSync(), isTrue);
      expect(path, endsWith('/install.yaml'));
    });

    test('reports rather than throws when pub get has not run', () async {
      File(at('.dart_tool/package_config.json')).deleteSync();
      expect(command.resolveManifestPath(), isNull);

      final ctx = _ctx(command);
      expect(await command.handle(ctx), 1);
      expect(
        (ctx.output as BufferedOutput).content,
        contains('flutter pub get'),
      );
    });
  });

  group('payments:install against a fixture project', () {
    test(
      'publishes the config, registers the provider, wires the factory',
      () async {
        final exitCode = await command.handle(_ctx(command));
        expect(exitCode, 0);

        final config = File(at('lib/config/payments.dart'));
        expect(config.existsSync(), isTrue);
        // Asserted on the config ROOT rather than on the getter name: the root
        // is what `PaymentsServiceProvider.boot()` reads, and a stub that
        // renamed it would publish a file the provider cannot find.
        expect(config.readAsStringSync(), contains("'payments'"));

        expect(
          File(at('lib/config/app.dart')).readAsStringSync(),
          contains('(app) => PaymentsServiceProvider(app),'),
        );
        expect(
          File(at('lib/main.dart')).readAsStringSync(),
          contains('() => paymentsConfig,'),
        );
        expect(
          File(at('lib/main.dart')).readAsStringSync(),
          contains("import 'config/payments.dart';"),
        );
      },
    );

    test('--dry-run writes nothing at all', () async {
      final exitCode = await command.handle(
        _ctx(command, const {'dry-run': true}),
      );
      expect(exitCode, 0);
      expect(File(at('lib/config/payments.dart')).existsSync(), isFalse);
      expect(
        File(at('lib/config/app.dart')).readAsStringSync(),
        isNot(contains('PaymentsServiceProvider')),
      );
    });

    test('a second run changes nothing on disk', () async {
      expect(await command.handle(_ctx(command)), 0);

      final after = <String, String>{
        for (final relative in const <String>[
          'lib/config/payments.dart',
          'lib/config/app.dart',
          'lib/main.dart',
        ])
          relative: File(at(relative)).readAsStringSync(),
      };

      // A fresh command instance, because PluginInstaller is one-shot: reusing
      // the first one would throw a StateError and the test would pass for the
      // wrong reason.
      final second = _PinnedInstallCommand(temp.path);
      expect(await second.handle(_ctx(second)), 0);

      after.forEach((relative, before) {
        expect(
          File(at(relative)).readAsStringSync(),
          before,
          reason: '$relative changed on the second install',
        );
      });
    });

    test(
      'a second run does not duplicate the provider or the factory',
      () async {
        expect(await command.handle(_ctx(command)), 0);
        final second = _PinnedInstallCommand(temp.path);
        expect(await second.handle(_ctx(second)), 0);

        // Counted rather than merely `contains`: byte equality above would also
        // pass if BOTH runs duplicated the entry identically, and this is the
        // guard for that.
        //
        // The injected import names the package BARREL, not the class, so the
        // class name occurs exactly once. Read off `injectProvider` rather than
        // assumed: an expectation of two here passes only against an import
        // statement the installer does not write.
        final app = File(at('lib/config/app.dart')).readAsStringSync();
        expect(
          '(app) => PaymentsServiceProvider(app),'.allMatches(app).length,
          1,
        );
        expect(
          "import 'package:magic_payments/magic_payments.dart';"
              .allMatches(app)
              .length,
          1,
        );

        final main = File(at('lib/main.dart')).readAsStringSync();
        expect('() => paymentsConfig,'.allMatches(main).length, 1);
        expect("import 'config/payments.dart';".allMatches(main).length, 1);
      },
    );

    test('a hand-edited config is refused without --force', () async {
      expect(await command.handle(_ctx(command)), 0);
      File(
        at('lib/config/payments.dart'),
      ).writeAsStringSync('// the operator changed this by hand\n');

      final second = _PinnedInstallCommand(temp.path);
      expect(await second.handle(_ctx(second)), 1);
      expect(
        File(at('lib/config/payments.dart')).readAsStringSync(),
        '// the operator changed this by hand\n',
      );
    });
  });
}
