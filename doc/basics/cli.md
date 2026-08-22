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
```

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
