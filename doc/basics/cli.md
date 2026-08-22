# CLI Reference

## Table of Contents

- <a name="toc-overview"></a>[Overview](#overview)
- <a name="toc-install"></a>[install](#install)
- <a name="toc-configure"></a>[configure](#configure)
- <a name="toc-doctor"></a>[doctor](#doctor)
- <a name="toc-mcp"></a>[MCP Exposure](#mcp)

---

## <a name="overview"></a>Overview

Magic Payments ships a CLI on top of `fluttersdk_artisan`, the same substrate `magic_notifications`
and `magic_social_auth` use. Every command runs through:

```bash
dart run magic_payments <command> [options]
```

`lib/cli.dart` is a separate entry point from `lib/magic_payments.dart` deliberately, so an app that
never touches the CLI does not pay for the command tree in its runtime build; it imports nothing from
Flutter or `dart:ui`.

> [!NOTE]
> The exact flags each command accepts are still settling in this version. Run any command with
> `--help` for the authoritative, current set rather than relying on this page for flag names.

---

## <a name="install"></a>install

Sets up the package in a consuming app: creating the config file, registering
`PaymentsServiceProvider` and wiring the config factory into `main.dart`, the same shape as
`magic_notifications install`.

```bash
dart run magic_payments install
```

Safe to run more than once: a second run is idempotent and changes nothing it has already put in
place.

---

## <a name="configure"></a>configure

Reads or updates individual settings without re-running the full install step.

```bash
dart run magic_payments configure [options]
```

As of this version, `payments.*` defines no keys of its own (see
[Configuration](../getting-started/configuration.md)), so `configure` has little to configure yet.
Expect this command's surface to grow alongside the store rail.

---

## <a name="doctor"></a>doctor

A health check over the plugin's installation and configuration state, in the same spirit as
`magic_notifications doctor`: it validates what is present rather than mutating anything.

```bash
dart run magic_payments doctor
dart run magic_payments doctor --verbose
```

Five checks, each of which reads a file in your project and can come back false, then the config
state it actually read:

```
Magic Payments, doctor report
==================================================

Dependency declared: ✓
Dependency resolved: ✓
Config published: ✓
Provider registered: ✓
Config factory wired: ✓

Config state:
  driver: 'platform'
  store rail key: blank
    note: iOS and Android builds read 'payments.revenuecat.public_sdk_key' and
    throw at purchase time without it. Web and desktop builds never read it.

✓ Every check passed.
```

`--verbose` adds the path and the requirement behind each check, so a false line names the file to
open rather than leaving you to guess which of the five it meant.

### The store rail key is REPORTED, not enforced

`store rail key` answers `absent`, `blank` or `declared`, and none of them fails the command.

That is deliberate rather than lenient. This command runs on your laptop and cannot know which
platform you will ship: a web-only or desktop-only app is CORRECT without the key, and failing on it
would turn a sound project red. But the alternative measured on a real consumer was worse, because
the driver throws under a customer's finger on the purchase sheet when the key is missing, and doctor
used to pass in silence while that was true. So it reports, with the consequence attached.

- `absent` means no `revenuecat` block was published at all.
- `blank` means the block is there with every platform arm empty, which is the state a project ships
  in first.
- `declared` means at least one arm carries a value. One is enough: a project that filled in iOS and
  not Android has configured the key, and which arms it needs is not this command's business.

The value is read as TEXT, with comments stripped first, and never evaluated. The published stub
resolves the key per platform through `defaultTargetPlatform` (see
[Configuration](../getting-started/configuration.md)), so what sits on disk is Dart source rather
than a literal.

> [!NOTE]
> Comment-stripping is not cosmetic. Before it, a reminder like
> `// TODO: paste the key from the 'RevenueCat' dashboard` put a quoted word inside the value block,
> the check answered `declared`, and the report went green on a rail that could not be configured.

### What it deliberately does NOT report

It does not say which RAIL your builds can serve. That answer lives behind a conditional import, so
the only value a pure-Dart CLI process could read is the one for its OWN compilation, which is the
`dart:io` arm every time regardless of what you build for. Printing that would be a confident wrong
answer about the one thing this package exists to get right, so it is absent rather than
approximated. See [Drivers](./drivers.md).

---

## <a name="mcp"></a>MCP Exposure

Only `doctor` is exposed as an MCP tool. `install` and `configure` both mutate a consuming project's
files, and this ecosystem's CLI providers deliberately do not expose a mutating command as an MCP
tool: an agent can ask whether a project's billing setup is healthy, but installing or reconfiguring
it stays a command a human runs.

---

**Related**

- [Installation](https://magic.fluttersdk.com/packages/payments/getting-started/installation)
- [Configuration](https://magic.fluttersdk.com/packages/payments/getting-started/configuration)
- [Service Provider](https://magic.fluttersdk.com/packages/payments/architecture/service-provider)
