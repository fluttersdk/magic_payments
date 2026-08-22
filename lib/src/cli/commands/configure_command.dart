import 'dart:io';

import 'package:fluttersdk_artisan/artisan.dart';

/// The only `payments.driver` value the runtime serves.
///
/// Duplicated deliberately rather than imported: the provider that reads this
/// key lives in the RUNTIME tree, which reaches `package:magic/magic.dart` and
/// therefore Flutter, and one such import anywhere under `lib/src/cli/` breaks
/// every command in a pure-Dart dispatcher. So the boundary is paid for with one
/// literal instead of an engine.
///
/// The drift that duplication invites is bounded on both ends: `payments:doctor`
/// reports a config value outside this set, and the provider logs an error and
/// wires the platform driver anyway rather than going dark. A build's capability
/// is decided by the conditional import, so no config string could change it;
/// this key exists to say "the default, deliberately", and a driver of one's own
/// is registered in code with `Payments.extend(role, factory)`.
const Set<String> servedDriverModes = {'platform'};

/// `payments:configure`, the re-runnable one.
///
/// The split with `payments:install` is real and load-bearing, not two names for
/// one job. Install is the one-time SCAFFOLD: it creates
/// `lib/config/payments.dart` and mutates `lib/config/app.dart` and
/// `lib/main.dart` to wire it in. Configure never creates a file and never
/// touches those two: it changes a VALUE inside a config the project already
/// has, and refuses outright when there is nothing installed to configure.
///
/// That refusal is the point. Re-running install to change one key would push
/// the published config through the conflict pre-flight, where a value the
/// operator had already edited by hand reads as a modified file and the whole
/// transaction stops. So the command that changes a value is the one that does
/// not go near the installer.
///
/// ## The surface is one key, because the config is one key
///
/// `payments.driver` is the only thing there is to configure. Which RAIL a build
/// serves is settled by the conditional import in the package's billing service
/// factory, so there is no rail flag here to be a second, disagreeing answer.
/// See the published config file's own docblock.
///
/// And today that key has exactly one value the runtime serves. Measured against
/// `PaymentsServiceProvider.boot()`: it reads `payments.driver`, and anything but
/// `platform` is logged as an error and then ignored, because a config string
/// cannot change what a build is capable of. So `--driver` can write a value the
/// runtime will refuse, and this command does not reject it here: the accepted
/// set lives in the runtime half of the package, and a copy of it in the
/// Flutter-free CLI half would be a second source of truth that drifts the first
/// time either side changes. `payments:doctor` reports the key it finds; the
/// runtime reports whether it can serve it.
///
/// ## Usage
///
/// ```bash
/// dart run <app>:artisan payments:configure --show
/// dart run <app>:artisan payments:configure --driver=platform
/// ```
class ConfigureCommand extends ArtisanCommand {
  @override
  String get signature =>
      'payments:configure '
      '{--show : Print the current payments configuration} '
      '{--driver= : Set the driver PaymentsManager resolves}';

  @override
  String get description =>
      'Change a value in an installed Magic Payments '
      'configuration';

  @override
  CommandBoot get boot => CommandBoot.none;

  /// Absolute path to the consumer's project root, resolved on access.
  String get projectRoot => getProjectRoot();

  /// Resolves the consumer's project root. Overridable so a test can point the
  /// command at a temp fixture.
  String getProjectRoot() => FileHelper.findProjectRoot();

  /// Absolute path of the published config this command edits.
  String get configPath => '$projectRoot/lib/config/payments.dart';

  /// Matches the `driver` entry in the published config.
  ///
  /// A regex rather than a Dart parser, and `payments:doctor` reads the same key
  /// the same way. Two call sites is not three, so neither extracts a helper for
  /// it; the file's shape is this package's own stub, so the two stay in step by
  /// construction rather than by an abstraction.
  static final RegExp _driverEntry = RegExp("('driver':\\s*')([^']*)(')");

  /// `true` when the published config is on disk.
  bool configExists() => FileHelper.fileExists(configPath);

  /// The current `driver` value, or `null` when the key is absent.
  String? currentDriver() {
    if (!configExists()) {
      return null;
    }
    return _driverEntry.firstMatch(FileHelper.readFile(configPath))?.group(2);
  }

  /// Rewrites the `driver` value in place.
  ///
  /// Replaces the VALUE inside the existing entry rather than rewriting the
  /// whole line, so the comment above the key and everything else in the
  /// operator's file survive the edit.
  ///
  /// Throws [FileSystemException] when the config file is absent, and
  /// [StateError] when it carries no `driver` key. Neither is swallowed: a
  /// silent no-op here would report success over a value that never changed.
  void setDriver(String driver) {
    if (!configExists()) {
      throw FileSystemException('Config file not found', configPath);
    }

    final String content = FileHelper.readFile(configPath);
    if (!_driverEntry.hasMatch(content)) {
      throw StateError(
        "$configPath carries no 'driver' key to set. Re-publish it with "
        '`payments:install --force`, or add the key by hand.',
      );
    }

    FileHelper.writeFile(
      configPath,
      // Groups 1 and 3 are the key with its whitespace and the closing quote,
      // carried through verbatim so whatever spacing the operator's formatter
      // chose survives the edit. `replaceFirst` takes no group references, so
      // the mapped form is the only one that can do this.
      content.replaceFirstMapped(
        _driverEntry,
        (match) => '${match.group(1)}$driver${match.group(3)}',
      ),
    );
  }

  @override
  Future<int> handle(ArtisanContext ctx) async {
    ctx.output.info(ConsoleStyle.header('Magic Payments'));

    // 1. Nothing to configure is a distinct outcome from a bad value, and it
    //    has a different fix, so it is named rather than folded into an error.
    if (!configExists()) {
      ctx.output.error('No configuration at lib/config/payments.dart.');
      ctx.output.info(
        'Scaffold it first: dart run <app>:artisan payments:install',
      );
      return 1;
    }

    // 2. --show is a read and returns before any write path.
    if (ctx.input.option('show') as bool? ?? false) {
      _show(ctx);
      return 0;
    }

    // 3. The one mutable key.
    final String? driver = ctx.input.option('driver') as String?;
    if (driver == null) {
      ctx.output.warning('Nothing to change: pass --driver=<name> or --show.');
      return 0;
    }
    if (driver.isEmpty) {
      // An empty driver is a fault `payments:doctor` reports, so refuse to
      // write one even though the provider would fall back to the platform.
      ctx.output.error('--driver cannot be empty.');
      return 1;
    }
    if (!servedDriverModes.contains(driver)) {
      // Refused rather than written, because writing it would report success
      // over a value the runtime logs an error about and then ignores. A CLI
      // that can put a config into a state its own runtime rejects is a footgun
      // whether or not anything crashes.
      ctx.output.error(
        "'$driver' is not a mode this package serves. The only value is "
        "'${servedDriverModes.single}'. To supply a driver of your own, "
        'register it in code with Payments.extend(role, factory) rather than '
        'naming it here.',
      );
      return 1;
    }

    setDriver(driver);
    ctx.output.success("driver set to '$driver'.");
    _show(ctx);
    return 0;
  }

  /// Prints the values currently in the published config.
  void _show(ArtisanContext ctx) {
    final String? driver = currentDriver();
    ctx.output.info('lib/config/payments.dart');
    ctx.output.info("  driver: ${driver == null ? '(absent)' : "'$driver'"}");
  }
}
