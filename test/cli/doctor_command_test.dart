import 'dart:io';

import 'package:fluttersdk_artisan/artisan.dart';
// ALIASED for the same reason the provider aliases it: `artisan.dart` above
// exports its own toolchain `DoctorCommand`, so an unprefixed import here makes
// every mention of the name ambiguous and the file will not compile.
import 'package:magic_payments/src/cli/commands/doctor_command.dart'
    as payments_doctor;
import 'package:test/test.dart';

/// Test subclass pinning the project root at a temp fixture.
class _PinnedDoctorCommand extends payments_doctor.DoctorCommand {
  _PinnedDoctorCommand(this._root);

  final String _root;

  @override
  String getProjectRoot() => _root;
}

void main() {
  late Directory temp;
  late _PinnedDoctorCommand command;

  String at(String relative) => '${temp.path}/$relative';

  /// Runs the command and returns `(exitCode, capturedOutput)`.
  Future<(int, String)> run({bool verbose = false}) async {
    final output = BufferedOutput();
    final code = await command.handle(
      ArtisanContext.bare(
        MapInput(<String, dynamic>{
          'verbose': verbose,
        }, signature: command.parsedSignature),
        output,
      ),
    );
    return (code, output.content);
  }

  /// Writes the fixture into the state a completed `payments:install` leaves.
  ///
  /// The config is COPIED FROM THE PRODUCER (the shipped stub) rather than
  /// retyped: a hand-written fixture carrying a root or a key the stub never
  /// emits would satisfy every assertion here and prove nothing about the file
  /// `payments:install` actually publishes.
  void writeInstalledState() {
    File(at('lib/config/payments.dart')).writeAsStringSync(
      File('assets/stubs/install/payments_config.stub').readAsStringSync(),
    );
    File(at('lib/config/app.dart')).writeAsStringSync('''
import 'package:magic/magic.dart';
import 'package:magic_payments/magic_payments.dart';

final appConfig = {
  'providers': [
    (app) => RouteServiceProvider(app),
    (app) => PaymentsServiceProvider(app),
  ],
};
''');
    File(at('lib/main.dart')).writeAsStringSync('''
import 'package:magic/magic.dart';
import 'config/app.dart';
import 'config/payments.dart';

void main() async {
  await Magic.init(
    configFactories: [
      () => appConfig,
      () => paymentsConfig,
    ],
  );
}
''');
  }

  setUp(() {
    temp = Directory.systemTemp.createTempSync('magic_payments_doctor_');
    command = _PinnedDoctorCommand(temp.path);

    File(at('pubspec.yaml')).writeAsStringSync('''
name: test_app
dependencies:
  flutter:
    sdk: flutter
  magic_payments: ^0.0.1
''');
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
  });

  tearDown(() {
    if (temp.existsSync()) {
      temp.deleteSync(recursive: true);
    }
  });

  group('DoctorCommand surface', () {
    test('is a read-only command that needs no booted app', () {
      expect(command.signature, contains('payments:doctor'));
      expect(command.boot, CommandBoot.none);
      expect(command.description, isNotEmpty);
    });
  });

  group('payments:doctor on an installed project', () {
    setUp(writeInstalledState);

    test('finds nothing wrong and exits 0', () async {
      expect(command.issues(), isEmpty);
      final (code, _) = await run();
      expect(code, 0);
    });

    test('reports the config state it actually read', () async {
      final (_, output) = await run();
      // The driver the published config declares, echoed back. A doctor that
      // printed a fixed line here would say the same thing about a config it
      // never opened.
      expect(output, contains(command.configuredDriver()!));
    });

    test('echoes a driver value the stub never carried', () async {
      // The assertion above passes against a hardcoded `'platform'`, because
      // that IS the stub's value. This one cannot: the value is one no file in
      // this package contains, so it can only reach the report by being read.
      File(at('lib/config/payments.dart')).writeAsStringSync('''
Map<String, dynamic> get paymentsConfig => {
  'payments': {
    'driver': 'a-driver-no-stub-carries',
  },
};
''');
      final (_, output) = await run();
      expect(output, contains('a-driver-no-stub-carries'));
    });

    test('a clean report carries no failure marker', () async {
      final (_, output) = await run();
      expect(output, isNot(contains('✗')));
    });
  });

  group('payments:doctor names what is missing', () {
    test('the config file, when install never ran', () async {
      final (code, output) = await run();
      expect(code, 1);
      expect(command.configExists(), isFalse);
      expect(output, contains('lib/config/payments.dart'));
    });

    test('the provider registration, when app.dart was not touched', () async {
      writeInstalledState();
      File(at('lib/config/app.dart')).writeAsStringSync('''
final appConfig = {
  'providers': [],
};
''');
      expect(command.providerRegistered(), isFalse);
      final (code, output) = await run();
      expect(code, 1);
      expect(output, contains('lib/config/app.dart'));
    });

    test('the config factory, when main.dart was not touched', () async {
      writeInstalledState();
      File(at('lib/main.dart')).writeAsStringSync('''
void main() async {
  await Magic.init(configFactories: []);
}
''');
      expect(command.configFactoryWired(), isFalse);
      final (code, output) = await run();
      expect(code, 1);
      expect(output, contains('lib/main.dart'));
    });

    test('a provider named in prose but never constructed', () async {
      writeInstalledState();
      // The guard is "name followed by ( or .new", and this fixture is what
      // reaches it: a bare-name check reports this project healthy while
      // nothing registers the provider. Confirmed by mutation, replacing the
      // regex with `contains('PaymentsServiceProvider')` fails this test and
      // only this test.
      File(at('lib/config/app.dart')).writeAsStringSync('''
import 'package:magic/magic.dart';

// TODO: register PaymentsServiceProvider here.
final appConfig = {
  'providers': [],
};
''');
      expect(command.providerRegistered(), isFalse);
      expect((await run()).$1, 1);
    });

    test('a provider registered as a tear-off is accepted', () async {
      writeInstalledState();
      // The other side of the same guard. `PaymentsServiceProvider.new`
      // satisfies the providers list's declared
      // `ServiceProvider Function(MagicApplication)` type, so a check pinned to
      // the exact text the installer writes would call a working project broken.
      File(at('lib/config/app.dart')).writeAsStringSync('''
import 'package:magic/magic.dart';
import 'package:magic_payments/magic_payments.dart';

final appConfig = {
  'providers': [
    PaymentsServiceProvider.new,
  ],
};
''');
      expect(command.providerRegistered(), isTrue);
      expect((await run()).$1, 0);
    });

    test('a config carrying the root but no driver key at all', () async {
      writeInstalledState();
      // Distinct from the blank driver below and from an absent FILE: the
      // branch that reports a missing key is reachable only from here, because
      // an absent file short-circuits the config checks before it.
      File(at('lib/config/payments.dart')).writeAsStringSync('''
Map<String, dynamic> get paymentsConfig => {
  'payments': {},
};
''');
      expect(command.configExists(), isTrue);
      expect(command.configuredDriver(), isNull);
      expect(command.configIssues(), isNotEmpty);
      expect((await run()).$1, 1);
    });

    test('a config whose driver was blanked out', () async {
      writeInstalledState();
      File(at('lib/config/payments.dart')).writeAsStringSync('''
Map<String, dynamic> get paymentsConfig => {
  'payments': {
    'driver': '',
  },
};
''');
      // Distinct from an ABSENT driver: the key is there, so a presence-only
      // check would call this healthy and the manager would resolve nothing.
      expect(command.configuredDriver(), isEmpty);
      expect(command.configIssues(), isNotEmpty);
      expect((await run()).$1, 1);
    });

    test('a config that publishes the wrong root', () async {
      writeInstalledState();
      File(at('lib/config/payments.dart')).writeAsStringSync('''
Map<String, dynamic> get paymentsConfig => {
  'billing': {
    'driver': 'platform',
  },
};
''');
      // The root is what the service provider reads. Wrong root, no reads.
      expect(command.configIssues(), isNotEmpty);
      expect((await run()).$1, 1);
    });

    test('the dependency, when pubspec.yaml does not declare it', () async {
      writeInstalledState();
      File(at('pubspec.yaml')).writeAsStringSync('''
name: test_app
dependencies:
  flutter:
    sdk: flutter
''');
      expect(command.pluginDeclared(), isFalse);
      final (code, output) = await run();
      expect(code, 1);
      expect(output, contains('pubspec.yaml'));
    });

    test('an unresolved dependency, when pub get never ran', () async {
      writeInstalledState();
      File(at('.dart_tool/package_config.json')).deleteSync();
      // Declared is not resolved: the install command reads its own stubs
      // through this file, so an operator who edited pubspec by hand and
      // skipped `flutter pub get` gets a stub-not-found error rather than a
      // diagnosis, unless doctor separates the two.
      expect(command.pluginDeclared(), isTrue);
      expect(command.pluginResolved(), isFalse);
      expect((await run()).$1, 1);
    });
  });
}
