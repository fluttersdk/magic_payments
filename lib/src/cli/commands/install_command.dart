import 'dart:convert';
import 'dart:io';

import 'package:fluttersdk_artisan/artisan.dart';

/// `payments:install`, the one-time scaffold.
///
/// It publishes `lib/config/payments.dart`, registers `PaymentsServiceProvider`
/// in the consumer's `lib/config/app.dart`, and wires `paymentsConfig` into
/// `lib/main.dart`'s `configFactories`. Changing a value in an already-installed
/// project is `payments:configure`'s job, not this command's: keeping the two
/// apart is what makes a re-run safe, because this command only ever needs to
/// converge on the same three edits.
///
/// Driven ENTIRELY by the bundled `install.yaml`. The whole install plan is
/// expressible in the v1 manifest schema (one publish, one provider, one config
/// factory), so there is no fluent override here and no second place to look for
/// what an install does. `install.yaml`'s own header says why this differs from
/// magic_notifications, whose OneSignal flow needs four things the schema cannot
/// express.
///
/// ## Idempotent by construction, not by a guard
///
/// A second run converges rather than duplicating, and each of the three edits
/// gets there its own way:
///
/// - the published config rides a transactional write whose content is a pure
///   function of the stub, and the install record's hash makes the pre-flight
///   recognise the file as one this plugin wrote rather than an unmanaged file;
/// - the provider and config-factory injections are helper-backed and skip when
///   the code they would insert is already in the file.
///
/// A file the OPERATOR edited by hand is a different case and is refused: the
/// hash no longer matches the record, so the conflict pre-flight stops the whole
/// transaction and asks for `--force`. That is the point of the pre-flight, so
/// this command does not soften it.
///
/// ## Usage
///
/// ```bash
/// dart run <app>:artisan payments:install
/// dart run <app>:artisan payments:install --dry-run
/// dart run <app>:artisan payments:install --force
/// ```
class InstallCommand extends ArtisanInstallCommand {
  @override
  String get signature => 'payments:install $baseFlags';

  @override
  String get description =>
      'Install Magic Payments: publish lib/config/payments.dart, register the '
      'provider and wire the config factory.';

  @override
  String pluginName(ArtisanContext ctx) => 'magic_payments';

  /// Absolute path to the consumer's project root, resolved on access.
  String get projectRoot => getProjectRoot();

  /// Resolves the consumer's project root. Overridable so a test can point the
  /// whole install at a temp fixture.
  String getProjectRoot() => FileHelper.findProjectRoot();

  /// Targets [projectRoot] rather than the process's working directory, so the
  /// command behaves the same whether it was invoked from the project root or
  /// from a subdirectory of it.
  @override
  InstallContext buildContext(ArtisanContext ctx) =>
      InstallContext.real(ctx, projectRoot: projectRoot);

  /// Resolves the absolute path of this package's bundled `install.yaml`.
  ///
  /// Returns `null` when the manifest cannot be located, so [handle] reports it
  /// rather than throwing.
  String? resolveManifestPath() {
    final String? root = resolvePluginRoot();
    if (root == null) {
      return null;
    }
    final String manifestPath = '$root/install.yaml';
    return FileHelper.fileExists(manifestPath) ? manifestPath : null;
  }

  /// This package's own root directory, read out of the CONSUMER's
  /// `.dart_tool/package_config.json`.
  ///
  /// The same source `ManifestInstaller` uses to locate this package's
  /// `assets/stubs/`, and deliberately the ONLY one: a second mechanism could
  /// resolve a different copy of the package, and then the manifest would come
  /// from one root while the stub it names came from another.
  ///
  /// `Isolate.resolvePackageUri` is the obvious alternative, and is what a
  /// sibling plugin uses. Measured here rather than assumed: under
  /// `flutter test` it raises `Unsupported operation:
  /// Isolate.resolvePackageUriSync`, so the first step of every install would be
  /// a step no test can execute.
  String? resolvePluginRoot() {
    final String configPath = '$projectRoot/.dart_tool/package_config.json';
    if (!FileHelper.fileExists(configPath)) {
      return null;
    }

    final Object? decoded = jsonDecode(FileHelper.readFile(configPath));
    if (decoded is! Map<String, dynamic>) {
      return null;
    }
    final Object? packages = decoded['packages'];
    if (packages is! List) {
      return null;
    }

    for (final Object? entry in packages) {
      if (entry is! Map || entry['name'] != 'magic_payments') {
        continue;
      }
      final Object? rootUri = entry['rootUri'];
      if (rootUri is! String) {
        return null;
      }
      // A relative rootUri resolves against the DIRECTORY HOLDING the config
      // file, not against the project root, which is what `pub` writes for a
      // path dependency inside the same workspace.
      final String resolved = rootUri.startsWith('file://')
          ? Uri.parse(rootUri).toFilePath()
          : Directory(
              '$projectRoot/.dart_tool',
            ).uri.resolve(rootUri).toFilePath();
      return resolved.endsWith(Platform.pathSeparator)
          ? resolved.substring(0, resolved.length - 1)
          : resolved;
    }

    return null;
  }

  @override
  Future<int> handle(ArtisanContext ctx) async {
    ctx.output.info(ConsoleStyle.header('Magic Payments'));

    // 1. Locate the bundled manifest. A null here almost always means
    //    `flutter pub get` has not run in this project, which is worth naming:
    //    the same missing file would otherwise surface later as a stub that
    //    could not be found.
    final String? manifestPath = resolveManifestPath();
    if (manifestPath == null) {
      ctx.output.error(
        'magic_payments install.yaml could not be resolved through '
        '.dart_tool/package_config.json. Run `flutter pub get` first.',
      );
      return 1;
    }

    // 2. Parse it. A malformed manifest is a bug in THIS package rather than in
    //    the consumer's project, so the message names the file.
    final InstallManifest manifest;
    try {
      manifest = ManifestParser.parseFile(manifestPath);
    } on FormatException catch (e) {
      ctx.output.error('install.yaml at $manifestPath: $e');
      return 1;
    } on ManifestValidationException catch (e) {
      ctx.output.error('install.yaml at $manifestPath: ${e.message}');
      return 1;
    }

    // 3. Run it. ManifestInstaller echoes the manifest's post-install message
    //    itself on Success, so this command must not echo it a second time.
    final TransactionResult result =
        await ManifestInstaller(buildContext(ctx), manifest).install(
          dryRun: isDryRun(ctx),
          force: isForce(ctx),
          nonInteractive: isNonInteractive(ctx),
        );

    return _renderResult(ctx, result);
  }

  /// Turns a [TransactionResult] into a process exit code, and says what the
  /// operator should do about it.
  int _renderResult(ArtisanContext ctx, TransactionResult result) {
    switch (result) {
      case Success():
        ctx.output.success('Magic Payments installed.');
        return 0;
      case DryRun(opCount: final count):
        ctx.output.info('Dry-run: $count op(s) staged; nothing was written.');
        return 0;
      case Conflict(conflicts: final conflicts):
        ctx.output.error(
          'Refused: ${conflicts.length} file(s) differ from what this plugin '
          'last wrote, so overwriting them would discard your edits. Re-run '
          'with --force to overwrite anyway.',
        );
        for (final conflict in conflicts) {
          ctx.output.warning('  ${conflict.absPath} (${conflict.reason})');
        }
        return 1;
      case Error(error: final message, rolledBack: final rolledBack):
        ctx.output.error('Install failed: $message');
        if (!rolledBack) {
          ctx.output.warning(
            'The transaction was NOT rolled back. Inspect '
            'lib/config/payments.dart, lib/config/app.dart and lib/main.dart '
            'before re-running.',
          );
        }
        return 1;
    }
  }
}
