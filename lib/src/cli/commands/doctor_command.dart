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
/// `--json` prints the same checks as one object, see [jsonReport], with the
/// same exit code.
///
/// ## Usage
///
/// ```bash
/// dart run <app>:artisan payments:doctor
/// dart run <app>:artisan payments:doctor --verbose
/// dart run <app>:artisan payments:doctor --json
/// ```
class DoctorCommand extends ArtisanCommand {
  @override
  String get signature =>
      'payments:doctor '
      '{--verbose : Show the path and the requirement behind each check} '
      '{--json : Print one JSON object for an agent instead of the report}';

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

    // Comments FIRST. Without this a reminder to oneself counts as the key:
    // `// paste the 'appl_' key from the RevenueCat dashboard` puts a non-empty
    // quoted literal inside the value block, the check answers `declared`, and
    // the report goes quietly green on a rail that cannot be configured, which
    // is the exact failure this method exists to remove.
    final String content = _withoutComments(
      FileHelper.readFile(_abs(_configPath)),
    );

    if (!content.contains("'public_sdk_key'")) {
      return 'absent';
    }

    final String? value = _valueSourceFor('public_sdk_key', content);

    if (value == null) {
      return 'blank';
    }

    // One non-empty arm is enough. A project that filled in iOS and not Android
    // has configured the key, and which arms it needs is not this command's
    // business; guessing would be the same overreach as failing the check.
    final bool anyFilled = RegExp("'([^']*)'")
        .allMatches(value)
        .any((RegExpMatch l) => (l.group(1) ?? '').trim().isNotEmpty);

    return anyFilled ? 'declared' : 'blank';
  }

  /// The SOURCE TEXT of the value assigned to [key], or null when the key has
  /// no value to read.
  ///
  /// A depth scan rather than a regex, and the three regexes it replaces are the
  /// argument for it. Each had to guess where a Dart value ends, and every
  /// widening of the guess broke a shape the previous one handled: stopping at
  /// the next quote read a wrapped value as empty; requiring a sibling key of
  /// `[a-z_]+` on its own line let a single-line map run past the boundary and
  /// read the NEXT key's value as this one's; dropping the newline anchor to fix
  /// that then let a TERNARY (`cond ? 'appl_x' : 'goog_y'`) end the capture at
  /// its own first literal, so a correctly configured project read as blank.
  ///
  /// A value ends where Dart says it ends: at the first `,` or closing bracket
  /// seen at depth zero, outside a string. That is one rule instead of a growing
  /// alternation, and it holds for the switch the stub publishes, for a ternary,
  /// for a nested map and for a whole config written on one line.
  String? _valueSourceFor(String key, String source) {
    final int keyAt = source.indexOf("'$key'");
    if (keyAt < 0) {
      return null;
    }

    final int colon = source.indexOf(':', keyAt + key.length + 2);
    if (colon < 0) {
      return null;
    }

    int depth = 0;
    bool inSingle = false;
    bool inDouble = false;

    for (int i = colon + 1; i < source.length; i++) {
      final String character = source[i];

      if (character == r'\') {
        i++;

        continue;
      }

      if (character == "'" && !inDouble) {
        inSingle = !inSingle;

        continue;
      }

      if (character == '"' && !inSingle) {
        inDouble = !inDouble;

        continue;
      }

      if (inSingle || inDouble) {
        continue;
      }

      if (character == '(' || character == '[' || character == '{') {
        depth++;

        continue;
      }

      if (character == ')' || character == ']' || character == '}') {
        if (depth == 0) {
          return source.substring(colon + 1, i);
        }

        depth--;

        continue;
      }

      if (character == ',' && depth == 0) {
        return source.substring(colon + 1, i);
      }
    }

    return source.substring(colon + 1);
  }

  /// [source] with its Dart comments removed, including TRAILING ones.
  ///
  /// A `^\s*//` sweep is not enough and the difference is not academic: it only
  /// removes a comment that IS the whole line, so
  /// `TargetPlatform.iOS => '', // paste the 'appl_' key` survives it and the
  /// quoted word in the note reads as a configured key. That placement is at
  /// least as common as a comment on its own line.
  ///
  /// The scan is quote-aware rather than a regex, because the one thing it must
  /// not do is cut a value in half: `'https://...'` contains the token it is
  /// looking for. Escapes are skipped so `'it\'s'` does not flip the state.
  ///
  /// The sibling helper in `test/drivers/billing_reads_over_http_test.dart` uses
  /// the simple sweep on purpose and is right to: it reads THIS package's own
  /// source, where house style keeps comments on their own line. This method
  /// reads a CONSUMER's file, which the package does not control, so borrowing
  /// that shortcut across the boundary is what made it wrong here.
  String _withoutComments(String source) {
    final String withoutBlocks = source.replaceAll(
      RegExp(r'/\*[\s\S]*?\*/'),
      '',
    );

    return withoutBlocks.split('\n').map(_withoutLineComment).join('\n');
  }

  /// One line with any `//` comment outside a string literal removed.
  String _withoutLineComment(String line) {
    bool inSingle = false;
    bool inDouble = false;

    for (int i = 0; i < line.length; i++) {
      final String character = line[i];

      if (character == r'\') {
        i++;

        continue;
      }

      if (character == "'" && !inDouble) {
        inSingle = !inSingle;

        continue;
      }

      if (character == '"' && !inSingle) {
        inDouble = !inDouble;

        continue;
      }

      if (!inSingle &&
          !inDouble &&
          character == '/' &&
          i + 1 < line.length &&
          line[i + 1] == '/') {
        return line.substring(0, i);
      }
    }

    return line;
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

  /// Every check this command runs, in the order both reports render them.
  ///
  /// The ONE list [issues], [report] and [jsonReport] are built from. The two
  /// modes used to restate the same checks side by side, so a check added to
  /// one could be missed by the other and an agent and an operator would read
  /// different facts about the same project; with one list that cannot happen.
  List<DoctorCheck> checks() {
    final List<String> configProblems = configIssues();

    return <DoctorCheck>[
      _check(
        'dependency_declared',
        pluginDeclared(),
        label: 'Dependency declared',
        details: <String>['$_pubspecPath, dependencies: magic_payments'],
        okMessage: 'magic_payments is declared in $_pubspecPath',
        errorMessage:
            '$_pubspecPath does not declare magic_payments under dependencies',
        fix:
            'add magic_payments to the dependencies in $_pubspecPath, then run '
            '`flutter pub get`',
        blocking: true,
      ),
      _check(
        'dependency_resolved',
        pluginResolved(),
        label: 'Dependency resolved',
        details: <String>['$_packageConfigPath, written by `flutter pub get`'],
        okMessage: 'magic_payments is resolved in $_packageConfigPath',
        errorMessage: 'magic_payments is not resolved in $_packageConfigPath',
        fix: 'run `flutter pub get`',
        issues: <String>[
          'magic_payments is declared but not resolved in $_packageConfigPath; '
              'run `flutter pub get`',
        ],
      ),
      // No unmet line of its own: an absent file is the first of
      // [configIssues], which `config_valid` below already carries.
      _check(
        'config_published',
        configExists(),
        label: 'Config published',
        details: <String>[_configPath],
        okMessage: '$_configPath exists',
        errorMessage: '$_configPath not found',
        fix: 'run `dart run <app>:artisan payments:install`',
        issues: const <String>[],
      ),
      _check(
        'config_valid',
        configProblems.isEmpty,
        okMessage:
            '$_configPath declares the payments root and a served driver',
        errorMessage: configProblems.join('; '),
        fix:
            'run `dart run <app>:artisan payments:install`, or set the driver '
            'with `dart run <app>:artisan payments:configure --driver=platform`',
        issues: configProblems,
      ),
      _check(
        'provider_registered',
        providerRegistered(),
        label: 'Provider registered',
        details: <String>[
          "$_appConfigPath, '(app) => PaymentsServiceProvider(app),'",
        ],
        okMessage: '$_appConfigPath registers PaymentsServiceProvider',
        errorMessage:
            '$_appConfigPath does not register PaymentsServiceProvider in its '
            'providers list',
        fix: 'run `dart run <app>:artisan payments:install`',
      ),
      _check(
        'config_factory_wired',
        configFactoryWired(),
        label: 'Config factory wired',
        details: <String>["$_mainPath, '() => paymentsConfig,'"],
        okMessage: '$_mainPath passes paymentsConfig to configFactories',
        errorMessage:
            '$_mainPath does not pass paymentsConfig to configFactories',
        fix: 'run `dart run <app>:artisan payments:install`',
      ),
      _storeKeyCheck(),
    ];
  }

  /// Every unmet requirement, in the order the checks run. Empty means healthy.
  List<String> issues() => _unmet(checks());

  /// The human-readable report. Every line states something that was read off
  /// disk; nothing here is a checklist of work the command did not do.
  String report({bool verbose = false}) {
    final List<DoctorCheck> all = checks();
    final StringBuffer out = StringBuffer()
      ..writeln('Magic Payments, doctor report')
      ..writeln('=' * 50)
      ..writeln();

    for (final DoctorCheck check in all) {
      final String? label = check.label;
      if (label != null) {
        _line(out, label, check.passed, verbose, check.details);
      }
    }
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

    final List<String> unmet = _unmet(all);
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

  /// The machine-readable report: `{ok, checks: [{id, status, message, fix?}]}`.
  ///
  /// Every id is one of [checks], in the order they run, so an agent and an
  /// operator read the same facts. `status` is `ok`, `warn` or `error`; `ok` is
  /// true exactly when no check is an `error`. `fix` is present only on a check
  /// that is not `ok`, and names the command or the file to change.
  ///
  /// A configured key is reported as `present`, `absent` or `blank` and never as
  /// its value: the `store_rail_key` message is built from the state alone, so
  /// there is no path from the consumer's config text into this output. The
  /// config is read as text and the key's literal never leaves
  /// [storeKeyState].
  Map<String, Object> jsonReport() {
    final List<DoctorCheck> all = checks();

    return <String, Object>{
      'ok': all.every(
        (DoctorCheck check) => check.status != DoctorCheckStatus.error,
      ),
      'checks': <Map<String, Object>>[
        for (final DoctorCheck check in all) check.toJson(),
      ],
    };
  }

  /// The unmet lines of [all], stopping at the first failed blocking check.
  ///
  /// A project that does not declare the package at all gets that one line and
  /// nothing else: every later check would only restate the same missing
  /// install.
  List<String> _unmet(List<DoctorCheck> all) {
    final List<String> unmet = <String>[];

    for (final DoctorCheck check in all) {
      if (check.passed) {
        continue;
      }
      if (check.blocking) {
        return List<String>.of(check.issues);
      }
      unmet.addAll(check.issues);
    }

    return unmet;
  }

  /// One pass-or-fail check: `ok` when [passed], otherwise `error` carrying
  /// [fix] and, in the human report, [issues] (the [errorMessage] alone when
  /// omitted).
  DoctorCheck _check(
    String id,
    bool passed, {
    String? label,
    List<String> details = const <String>[],
    required String okMessage,
    required String errorMessage,
    required String fix,
    List<String>? issues,
    bool blocking = false,
  }) {
    return DoctorCheck(
      id: id,
      status: passed ? DoctorCheckStatus.ok : DoctorCheckStatus.error,
      message: passed ? okMessage : errorMessage,
      fix: passed ? null : fix,
      label: label,
      details: details,
      issues: passed ? const <String>[] : issues ?? <String>[errorMessage],
      blocking: blocking,
    );
  }

  /// The store rail's key as a check that can warn but never fail, for the reason
  /// [storeKeyState] gives. [storeKeyState] answers `declared` where this
  /// vocabulary says `present`, so an agent reads the same three words in every
  /// report this command emits.
  ///
  /// No checklist line and no unmet line: the human report echoes the key under
  /// its config state instead, with the note a web-only project can ignore.
  DoctorCheck _storeKeyCheck() {
    final String declared = storeKeyState();
    final bool present = declared == 'declared';
    final String state = present ? 'present' : declared;

    return DoctorCheck(
      id: 'store_rail_key',
      status: present ? DoctorCheckStatus.ok : DoctorCheckStatus.warn,
      message: 'payments.revenuecat.public_sdk_key: $state',
      fix: present
          ? null
          : "set payments.revenuecat.public_sdk_key in $_configPath; iOS and "
                'Android builds throw at purchase time without it, web and '
                'desktop builds never read it',
    );
  }

  @override
  Future<int> handle(ArtisanContext ctx) async {
    if (ctx.input.option('json') as bool? ?? false) {
      final Map<String, Object> report = jsonReport();

      // Nothing but the object on stdout: a banner would make the output
      // unparseable, which is the one thing this mode is for.
      ctx.output.writeln(jsonEncode(report));

      return report['ok'] == true ? 0 : 1;
    }

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

/// How a [DoctorCheck] came out, spelled on the wire by [DoctorCheck.toJson].
enum DoctorCheckStatus {
  /// The requirement holds.
  ok,

  /// Worth an operator's attention, never a failure: the exit code ignores it.
  warn,

  /// An unmet requirement: the command exits 1.
  error,
}

/// One check of `payments:doctor`, carrying everything both of its reports
/// render: the JSON fields, the human checklist line and the unmet lines.
///
/// Every field is final and the constructor const. Not `@immutable`: that is
/// `package:meta`, and the CLI tree imports nothing but `dart:` and
/// `fluttersdk_artisan` so a process with no Flutter engine can load it.
class DoctorCheck {
  /// Creates a [DoctorCheck].
  const DoctorCheck({
    required this.id,
    required this.status,
    required this.message,
    this.fix,
    this.label,
    this.details = const <String>[],
    this.issues = const <String>[],
    this.blocking = false,
  });

  /// The stable id an agent matches on (`config_factory_wired`).
  final String id;

  /// How the check came out.
  final DoctorCheckStatus status;

  /// The JSON report's sentence for [status].
  final String message;

  /// What to run or edit, present only when [status] is not `ok`.
  final String? fix;

  /// The human checklist label, or null for a check the human report shows
  /// elsewhere (under its config state) or not as a line of its own.
  final String? label;

  /// The `--verbose` lines under [label]: the file and the requirement.
  final List<String> details;

  /// The human report's unmet lines, empty when the check passed.
  final List<String> issues;

  /// Whether a failure here makes every later unmet line noise, so the human
  /// report stops at this one.
  final bool blocking;

  /// Whether the check passed. A warning passes: only an error is unmet.
  bool get passed => status != DoctorCheckStatus.error;

  /// The check as one entry of `jsonReport()['checks']`.
  Map<String, Object> toJson() => <String, Object>{
    'id': id,
    'status': switch (status) {
      DoctorCheckStatus.ok => 'ok',
      DoctorCheckStatus.warn => 'warn',
      DoctorCheckStatus.error => 'error',
    },
    'message': message,
    if (fix case final String fix) 'fix': fix,
  };
}
