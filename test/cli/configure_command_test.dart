import 'dart:io';

import 'package:fluttersdk_artisan/artisan.dart';
import 'package:magic_payments/src/cli/commands/configure_command.dart';
import 'package:test/test.dart';

/// Test subclass pinning the project root at a temp fixture, matching the
/// pattern the doctor and install tests use.
class _PinnedConfigureCommand extends ConfigureCommand {
  _PinnedConfigureCommand(this._root);

  final String _root;

  @override
  String getProjectRoot() => _root;
}

void main() {
  late Directory temp;
  late _PinnedConfigureCommand command;

  String at(String relative) => '${temp.path}/$relative';

  /// Runs the command and returns `(exitCode, capturedOutput)`.
  Future<(int, String)> run({String? driver, bool show = false}) async {
    final output = BufferedOutput();
    final code = await command.handle(
      ArtisanContext.bare(
        MapInput(<String, dynamic>{
          // Null-aware element: omitted entirely when no driver is passed, so a
          // `--show`-only run does not present the flag as an empty string.
          'driver': ?driver,
          'show': show,
        }, signature: command.parsedSignature),
        output,
      ),
    );

    return (code, output.content);
  }

  /// Writes the fixture into the state a completed `payments:install` leaves.
  ///
  /// The config is COPIED FROM THE PRODUCER (the shipped stub) rather than
  /// retyped, for the reason the sibling tests give: a hand-written fixture
  /// carrying a key the stub never emits would satisfy every assertion here and
  /// prove nothing about the file `payments:install` actually publishes.
  void writeInstalledConfig() {
    Directory(at('lib/config')).createSync(recursive: true);
    File(at('lib/config/payments.dart')).writeAsStringSync(
      File('assets/stubs/install/payments_config.stub').readAsStringSync(),
    );
  }

  setUp(() {
    temp = Directory.systemTemp.createTempSync('mp_configure_');
    command = _PinnedConfigureCommand(temp.path);
  });

  tearDown(() => temp.deleteSync(recursive: true));

  group('payments:configure refuses what the runtime will not serve', () {
    test(
      'a mode outside the served set is rejected and nothing is written',
      () async {
        // The gap this closes: the command used to write any string it was given,
        // so an operator naming a rail got a success message, a green
        // `payments:doctor`, and an error in the runtime logs. That pairing is
        // worse than either half alone, because the CLI said the change landed.
        writeInstalledConfig();
        final String before = File(
          at('lib/config/payments.dart'),
        ).readAsStringSync();

        final (int code, String out) = await run(driver: 'revenuecat');

        expect(code, 1);
        expect(out, contains('revenuecat'));
        // The message has to name the real override path, or an operator who was
        // refused has nowhere to go.
        expect(out, contains('Payments.extend'));
        expect(
          File(at('lib/config/payments.dart')).readAsStringSync(),
          before,
          reason: 'a refused mode must leave the config byte-identical',
        );
      },
    );

    test('the one served mode is accepted', () async {
      // The other side of the same guard. Without this, a refusal test alone
      // would pass just as well against a command that refused everything.
      writeInstalledConfig();

      final (int code, String out) = await run(
        driver: servedDriverModes.single,
      );

      expect(code, 0);
      expect(out, contains(servedDriverModes.single));
      expect(
        File(at('lib/config/payments.dart')).readAsStringSync(),
        contains("'driver': '${servedDriverModes.single}'"),
      );
    });

    test('an empty mode is refused before it reaches the file', () async {
      writeInstalledConfig();
      final String before = File(
        at('lib/config/payments.dart'),
      ).readAsStringSync();

      final (int code, String out) = await run(driver: '');

      expect(code, 1);
      expect(out, contains('cannot be empty'));
      expect(File(at('lib/config/payments.dart')).readAsStringSync(), before);
    });
  });

  group('payments:configure needs something installed', () {
    test('it refuses rather than creating a config', () async {
      // The install/configure split, asserted rather than described: configure
      // never creates a file, so an uninstalled project is a refusal and not a
      // silent scaffold.
      final (int code, String out) = await run(driver: 'platform');

      expect(code, 1);
      expect(out.toLowerCase(), contains('install'));
      expect(File(at('lib/config/payments.dart')).existsSync(), isFalse);
    });
  });
}
