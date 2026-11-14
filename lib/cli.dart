/// The CLI surface of `magic_payments`, kept separate from the runtime barrel.
///
/// A consumer's app imports `magic_payments.dart` and must not pay for the
/// command-line tree; the `dowel` provider and its commands are
/// reached through this entry point instead. That split is why there are two
/// barrels rather than one.
///
/// ## Nothing reachable from here may reach the UI toolkit
///
/// The dowel dispatcher is a PURE DART process with no engine behind it, so a
/// single import of the UI toolkit anywhere in the graph below this file breaks
/// every `payments:*` command at a consumer's command line, and the analyzer in
/// this package says nothing about it. Two consequences worth holding:
///
/// - this barrel exports ONLY the provider, never the runtime surface, and the
///   whole `lib/src/cli/` tree imports nothing but `dart:` libraries and
///   `package:dowel/dowel.dart`, which is itself toolkit-free;
/// - no file under `lib/src/cli/` reaches the package's own runtime, even
///   relatively. The drivers, the models and the manager all import the magic
///   barrel, which reaches the toolkit, so one `../models/...` import from a
///   command would pull the engine in transitively.
///
/// The prose above deliberately does not spell either forbidden import token
/// out. The gate on this rule is a grep over this raw file, and a docblock
/// naming what it forbids is how a review grep matches the sentence warning
/// against the thing it was searching for. Both halves of the rule are held as
/// assertions in `test/cli/payments_dowel_provider_test.dart`, which is where
/// a rule this easy to break by accident belongs.
///
/// `plugin:install` registers the provider in the consumer's
/// `bin/dispatcher.dart`; wiring it by hand looks like:
///
/// ```dart
/// import 'package:dowel/dowel.dart';
/// import 'package:magic_payments/cli.dart' show MagicPaymentsDowelProvider;
///
/// Future<void> main(List<String> args) async {
///   final registry = DowelRegistry()
///     ..registerProvider(MagicPaymentsDowelProvider());
///   exit(await DowelApplication(registry: registry).dispatch(args));
/// }
/// ```
///
/// Runtime consumers (the `lib/main.dart` of a Magic app) keep importing
/// `package:magic_payments/magic_payments.dart` for the facade and the rails.
library;

export 'src/cli/payments_dowel_provider.dart';
