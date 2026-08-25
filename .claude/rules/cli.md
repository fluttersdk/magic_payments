---
paths:
  - "lib/src/cli/**"
  - "lib/cli.dart"
  - "install.yaml"
---

# The `payments:*` CLI

Three commands on `fluttersdk_artisan`, contributed by `PaymentsArtisanProvider`: `payments:install`
(one-time scaffold), `payments:configure` (change a value afterwards), `payments:doctor` (report).
`lib/cli.dart` is a separate barrel so an app never pays for the command tree at runtime.

## The MCP surface is one tool, and that is policy

Only `payments_doctor` is exposed. `payments:install` and `payments:configure` MUTATE the consumer's
source tree, and across this ecosystem a mutating command is deliberately absent from the MCP surface:
an agent that can rewrite `lib/config/app.dart` and `lib/main.dart` with no human at the keyboard is a
different risk from one that can read a report. Adding either is a policy change, not a convenience,
so it does not happen inside a feature branch.

## Install stays manifest-only

The whole install plan fits the v1 `install.yaml` schema: one publish, one provider entry, one config
factory. There is deliberately no fluent override, so there is no second place to look for what an
install does. `magic_notifications` has one because its OneSignal flow needs four things the schema
cannot express; that is a reason to reach for an override, not a precedent.

If a new step genuinely cannot be expressed in the manifest, say why in `install.yaml`'s own header
before writing the override.

## Idempotence is a property of the construction, not a guard

A second run converges: the published config rides a transactional write whose content is a pure
function of the stub, and the provider and config-factory injections skip when the code they would
insert is already present. Do not add an "already installed?" early return on top of that; it hides
the case the pre-flight is there to catch.

A file the OPERATOR edited by hand is a different case and is refused, because its hash no longer
matches the install record. That refusal is the pre-flight working. `--force` is the operator's
decision, never a default.

## Aliased imports

`fluttersdk_artisan` exports its own toolchain `DoctorCommand` from the barrel this provider already
imports, so `commands/doctor_command.dart` is imported with a prefix. Nothing warns about the clash
until the file is written, and a `hide` on the artisan barrel would push the same problem onto whoever
adds the next import. Keep the prefix.

## Command shape

Each command owns one file under `lib/src/cli/commands/` and declares `signature` and `description`.
What else it declares depends on the base: `configure` and `doctor` extend `ArtisanCommand` and add
`boot`; `install` extends `ArtisanInstallCommand`, adds `pluginName`, and inherits `boot` from there.

**The command name and its flags both live in `signature`**, in the DSL `fluttersdk_artisan` parses.
There is no `name` getter and no `configure(ArgParser)` hook; do not reach for either, they are the
shape a sibling package uses:

```dart
@override
String get signature =>
    'payments:configure '
    '{--show : Print the current payments configuration} '
    '{--driver= : Set the driver PaymentsManager resolves}';
```

A flag is read back through the context rather than a parser object: `ctx.input.option('driver') as
String?`, and `ctx.input.option('show') as bool? ?? false` for a boolean. The cast sits at the call
site because `option` is untyped.

`configure` and `doctor` declare `CommandBoot.none`; `install` extends `ArtisanInstallCommand`, which
declares the same (`artisan/lib/src/installer/artisan_install_command.dart:79`). Nothing here runs
`connected`, because no `payments:*` command talks to a running app, and one that wanted to would be
reading state the backend already owns.

`analysis_options.yaml` sets `avoid_print: ignore` package-wide, under the comment `# CLI tools
legitimately use print`. The scope is the whole package even though the reason is this directory, so a
stray `print` outside `lib/src/cli/` is a defect the analyzer will no longer catch for you.
