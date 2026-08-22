import 'dart:convert';

import 'package:fluttersdk_artisan/artisan.dart';

// One literal, one owner: the command that WRITES the key declares what may be
// written, and this one reports anything outside it. Both stay inside the
// pure-Dart CLI tree, which is why neither can import the provider that reads it.
import 'configure_command.dart' show servedDriverModes;

/// `payments:doctor`, the read-only health check, and the only command in this
/// plugin exposed as an MCP tool.
///
/// ## Every check is falsifiable from a command line
///
/// Six checks, and each one reads a file in the consumer's project and can come
/// back false:
///
/// 1. `magic_payments` is declared in `pubspec.yaml`.
/// 2. `magic_payments` is RESOLVED in `.dart_tool/package_config.json`. Separate
///    from the first on purpose: `payments:install` finds its own config stub
///    through that file, so an operator who added the dependency by hand and
///    skipped `flutter pub get` gets a stub-not-found error from install rather
///    than a diagnosis, unless something tells the two apart.
/// 3. `lib/config/payments.dart` exists.
/// 4. That config declares the `payments` root with a non-empty `driver`.
/// 5. `PaymentsServiceProvider` is in `lib/config/app.dart`'s providers list.
/// 6. `paymentsConfig` is in `lib/main.dart`'s `configFactories`.
///
/// ## What it deliberately does NOT report
///
/// It does not say which RAIL this project's builds can serve. That answer lives
/// behind a conditional import (`dart.library.html` / `dart.library.io`), so the
/// only value a pure-Dart CLI process could read is the one for its OWN
/// compilation, which is the `dart:io` arm every single time regardless of what
/// the consumer builds for. Printing that would be a confident wrong answer
/// about the one thing this package exists to get right, so it is absent rather
/// than approximated.
///
/// Exits 0 when every check passes, 1 otherwise.
///
/// ## Usage
///
/// ```bash
/// dart run <app>:artisan payments:doctor
/// dart run <app>:artisan payments:doctor --verbose
/// ```
class DoctorCommand extends ArtisanCommand {
  @override
  String get signature =>
      'payments:doctor {--verbose : Show the path and the requirement behind '
      'each check}';

  @override
  String get description =>
      'Check the Magic Payments installation and configuration in this project';

  @override
  CommandBoot get boot => CommandBoot.none;

  /// Absolute path to the consumer's project root, resolved on access.
  String get projectRoot => getProjectRoot();

  /// Resolves the consumer's project root. Overridable so a test can point the
  /// whole check at a temp fixture.
  String getProjectRoot() => FileHelper.findProjectRoot();

  /// Project-relative path of every file a check reads, so the report and the
  /// issue text can never name a different file from the one that was opened.
  static const String _configPath = 'lib/config/payments.dart';
  static const String _appConfigPath = 'lib/config/app.dart';
  static const String _mainPath = 'lib/main.dart';
  static const String _pubspecPath = 'pubspec.yaml';
  static const String _packageConfigPath = '.dart_tool/package_config.json';

  // ---------------------------------------------------------------------------
  // Checks
  // ---------------------------------------------------------------------------

  /// `true` when `pubspec.yaml` lists `magic_payments` under `dependencies`.
  bool pluginDeclared() {
    final String path = _abs(_pubspecPath);
    if (!FileHelper.fileExists(path)) {
      return false;
    }
    final Object? dependencies = FileHelper.readYamlFile(path)['dependencies'];
    return dependencies is Map && dependencies.containsKey('magic_payments');
  }

  /// `true` when `.dart_tool/package_config.json` carries a `magic_payments`
  /// entry, which is what `flutter pub get` writes and what this plugin's own
  /// install command reads to find its bundled stubs.
  bool pluginResolved() {
    final String path = _abs(_packageConfigPath);
    if (!FileHelper.fileExists(path)) {
      return false;
    }
    final Object? decoded = jsonDecode(FileHelper.readFile(path));
    if (decoded is! Map<String, dynamic>) {
      return false;
    }
    final Object? packages = decoded['packages'];
    if (packages is! List) {
      return false;
    }
    return packages.any(
      (entry) => entry is Map && entry['name'] == 'magic_payments',
    );
  }

  /// `true` when the published config file is on disk.
  bool configExists() => FileHelper.fileExists(_abs(_configPath));

  /// The `driver` value the published config declares, or `null` when the file
  /// or the key is absent.
  ///
  /// An empty string is a DISTINCT answer from `null` and both are returned as
  /// they are: the key being present and blank is what an operator produces by
  /// deleting a value, and a presence-only check would call that healthy.
  ///
  /// Read with a regex rather than a Dart parser, which is what
  /// `payments:configure` does when it writes the same key back. The published
  /// file's shape is this package's own stub, so the two stay in step.
  String? configuredDriver() {
    if (!configExists()) {
      return null;
    }
    final RegExpMatch? match = RegExp(
      "'driver':\\s*'([^']*)'",
    ).firstMatch(FileHelper.readFile(_abs(_configPath)));
    return match?.group(1);
  }

  /// What the published config says about the STORE rail's SDK key.
  ///
  /// Three answers, because an honest report needs three. `absent` means no
  /// `revenuecat` block was published at all, which is correct for a web-only or
  /// desktop-only app and wrong for one that sells through a store. `blank`
  /// means the block is there with every value left empty, which is the state a
  /// project ships in first and the one that surfaces under a customer's finger
  /// on the purchase sheet. `declared` means at least one non-empty value.
  ///
  /// Deliberately NOT part of {@see issues()}: this command runs on a laptop and
  /// cannot know whether the app will ship to a store, so failing here would
  /// turn a correct web-only project red. It is reported instead, because the
  /// alternative measured on a real consumer was worse: a doctor that passed in
  /// silence while the store rail could not be configured at all.
  ///
  /// Read as TEXT and never evaluated. The published stub resolves this key per
  /// platform through `defaultTargetPlatform` (RevenueCat issues a separate
  /// public key for each store), so what sits on disk is Dart source rather than
  /// a literal. "Did somebody fill any of these in" is the only question this
  /// layer can answer without guessing.
  String storeKeyState() {
    if (!configExists()) {
      return 'absent';
    }

    final String content = FileHelper.readFile(_abs(_configPath));
    if (!content.contains("'public_sdk_key'")) {
      return 'absent';
    }

    // Every quoted value that follows the key, across however many platform
    // arms the consumer wrote. One non-empty arm is enough to call it declared:
    // a project that filled in iOS and not Android has configured the key, and
    // which arms it needs is not this command's business.
    final Iterable<RegExpMatch> values = RegExp(
      "'public_sdk_key'\\s*:([\\s\\S]{0,400}?)(?:\\n\\s*'|\\n\\s*\\})",
    ).allMatches(content);

    for (final RegExpMatch match in values) {
      final Iterable<RegExpMatch> literals = RegExp(
        "'([^']*)'",
      ).allMatches(match.group(1) ?? '');
      if (literals.any(
        (RegExpMatch l) => (l.group(1) ?? '').trim().isNotEmpty,
      )) {
        return 'declared';
      }
    }

    return 'blank';
  }

  /// Everything wrong with the published config, empty when it is sound.
  List<String> configIssues() {
    if (!configExists()) {
      return <String>['Config file not found at $_configPath'];
    }

    final String content = FileHelper.readFile(_abs(_configPath));
    final List<String> issues = <String>[];

    // 1. The root. PaymentsServiceProvider reads `payments.*`, so a config
    //    published under any other root is a file the provider never opens.
    if (!content.contains("'payments'")) {
      issues.add(
        "$_configPath declares no 'payments' root, so the service provider "
        'reads nothing from it',
      );
    }

    // 2. The driver. Absent and blank are separate faults with the same
    //    consequence, and separate messages so the fix is obvious.
    final String? driver = configuredDriver();
    if (driver == null) {
      issues.add("$_configPath declares no 'driver' key");
    } else if (driver.isEmpty) {
      // Corrected: an empty value does NOT leave the manager resolving nothing.
      // The provider treats absent and empty alike and wires the platform
      // driver, so every read still works; what is wrong is the config, which
      // now says nothing about a deliberate choice.
      issues.add(
        "$_configPath declares an empty 'driver'; the platform driver is still "
        'wired, but the config no longer records that as a decision',
      );
    } else if (!servedDriverModes.contains(driver)) {
      // The gap this closes: doctor used to pass a value the runtime rejects.
      // An operator setting a rail name here got a green report and an error in
      // the logs, which is the worst pairing of the two.
      issues.add(
        "$_configPath declares driver '$driver', which this package does not "
        "serve; the only value is '${servedDriverModes.single}' and a driver of "
        'your own is registered with Payments.extend(role, factory)',
      );
    }

    return issues;
  }

  /// `true` when `lib/config/app.dart` references the provider as something it
  /// will construct.
  ///
  /// Matched on the name followed by `(` or `.new`, which is deliberately wider
  /// than what the installer writes and narrower than the bare name. Both
  /// alternatives were measured rather than reasoned about:
  ///
  /// - `(app) => PaymentsServiceProvider(` alone, which is exactly the injected
  ///   text, reports a false negative on a hand-written `PaymentsServiceProvider
  ///   .new`. That tear-off satisfies the list's declared
  ///   `ServiceProvider Function(MagicApplication)` type just as well, so an
  ///   operator who wrote it would be told their working project is broken.
  /// - the bare name accepts a mention in a comment or a string. It is NOT
  ///   satisfied by the injected import, which names the package barrel and not
  ///   the class, so that particular worry does not apply here.
  bool providerRegistered() {
    final String path = _abs(_appConfigPath);
    if (!FileHelper.fileExists(path)) {
      return false;
    }
    return RegExp(
      r'PaymentsServiceProvider\s*(?:\(|\.new)',
    ).hasMatch(FileHelper.readFile(path));
  }

  /// `true` when `lib/main.dart` passes `paymentsConfig` to `configFactories`.
  bool configFactoryWired() {
    final String path = _abs(_mainPath);
    if (!FileHelper.fileExists(path)) {
      return false;
    }
    return RegExp(
      r'\(\)\s*=>\s*paymentsConfig\b',
    ).hasMatch(FileHelper.readFile(path));
  }

  // ---------------------------------------------------------------------------
  // Aggregation
  // ---------------------------------------------------------------------------

  /// Every unmet requirement, in the order the checks run. Empty means healthy.
  List<String> issues() {
    final List<String> issues = <String>[];

    if (!pluginDeclared()) {
      return <String>[
        '$_pubspecPath does not declare magic_payments under dependencies',
      ];
    }
    if (!pluginResolved()) {
      issues.add(
        'magic_payments is declared but not resolved in $_packageConfigPath; '
        'run `flutter pub get`',
      );
    }

    issues.addAll(configIssues());

    if (!providerRegistered()) {
      issues.add(
        '$_appConfigPath does not register PaymentsServiceProvider in its '
        'providers list',
      );
    }
    if (!configFactoryWired()) {
      issues.add('$_mainPath does not pass paymentsConfig to configFactories');
    }

    return issues;
  }

  /// The human-readable report. Every line states something that was read off
  /// disk; nothing here is a checklist of work the command did not do.
  String report({bool verbose = false}) {
    final StringBuffer out = StringBuffer()
      ..writeln('Magic Payments, doctor report')
      ..writeln('=' * 50)
      ..writeln();

    _line(out, 'Dependency declared', pluginDeclared(), verbose, <String>[
      '$_pubspecPath, dependencies: magic_payments',
    ]);
    _line(out, 'Dependency resolved', pluginResolved(), verbose, <String>[
      '$_packageConfigPath, written by `flutter pub get`',
    ]);
    _line(out, 'Config published', configExists(), verbose, <String>[
      _configPath,
    ]);
    _line(out, 'Provider registered', providerRegistered(), verbose, <String>[
      "$_appConfigPath, '(app) => PaymentsServiceProvider(app),'",
    ]);
    _line(out, 'Config factory wired', configFactoryWired(), verbose, <String>[
      "$_mainPath, '() => paymentsConfig,'",
    ]);
    out.writeln();

    // Config contents, echoed rather than asserted: the value below is the one
    // the manager will resolve, so an operator reading this report can see what
    // the project is actually configured to do.
    out.writeln('Config state:');
    if (!configExists()) {
      out.writeln('  ✗ not published, nothing to read');
    } else {
      final String? driver = configuredDriver();
      out.writeln("  driver: ${driver == null ? '(absent)' : "'$driver'"}");

      // The store rail's key, echoed with its consequence rather than asserted.
      // A web-only app is correct without it, so this cannot be a failure; a
      // store app without it throws under the customer's finger, so it cannot
      // be silence either.
      final String storeKey = storeKeyState();
      out.writeln('  store rail key: $storeKey');
      if (storeKey != 'declared') {
        out.writeln(
          '    note: iOS and Android builds read '
          "'payments.revenuecat.public_sdk_key' and throw at purchase time "
          'without it. Web and desktop builds never read it.',
        );
      }

      for (final String issue in configIssues()) {
        out.writeln('  ✗ $issue');
      }
    }
    out.writeln();

    final List<String> unmet = issues();
    if (unmet.isEmpty) {
      out.writeln('✓ Every check passed.');
    } else {
      out.writeln('Unmet requirements:');
      for (final String issue in unmet) {
        out.writeln('  ✗ $issue');
      }
    }

    return out.toString();
  }

  @override
  Future<int> handle(ArtisanContext ctx) async {
    ctx.output.info(ConsoleStyle.header('Magic Payments'));

    final bool verbose = ctx.input.option('verbose') as bool? ?? false;
    final List<String> unmet = issues();

    ctx.output.writeln(report(verbose: verbose));

    if (unmet.isEmpty) {
      ctx.output.success('Magic Payments is installed and configured.');
      return 0;
    }

    ctx.output.warning('Fix the above, then re-run this command:');
    ctx.output.writeln(
      '  • scaffold:   dart run <app>:artisan payments:install',
    );
    ctx.output.writeln(
      '  • edit a key: dart run <app>:artisan payments:configure --show',
    );
    return 1;
  }

  /// Renders one check line, plus its detail lines when [verbose].
  void _line(
    StringBuffer out,
    String label,
    bool passed,
    bool verbose,
    List<String> details,
  ) {
    out.writeln('$label: ${passed ? '✓' : '✗'}');
    if (!verbose) {
      return;
    }
    for (final String detail in details) {
      out.writeln('    $detail');
    }
  }

  /// Resolves a project-relative path against [projectRoot].
  String _abs(String relative) => '$projectRoot/$relative';
}
