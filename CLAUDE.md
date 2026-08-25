# Magic Payments Plugin

Multi-rail billing for the Magic Framework: one entitlement contract over Stripe on the web and store
in-app purchase on iOS and Android. A `magic` plugin, with its CLI on `fluttersdk_artisan`.

`0.0.1` is unreleased and still the only version. It started as a scaffold with empty barrels, so the
repository, its CI and its publish workflow were proven against an empty tree first; the barrels now
carry the three service contracts, the drivers behind them, the entitlement model and its vocabulary
enums. Nothing is on pub.dev yet, so a downstream package naming `magic_payments` resolves only
through a local override until that first publish happens.

## The one idea worth holding

**The rail and the platform are different axes, and conflating them is the bug this package prevents.**
A subscription bought on an iPhone is still managed in the App Store when the customer opens the web
app. So nothing here branches on `kIsWeb`, `Platform.is` or `defaultTargetPlatform` to decide where a
subscription is managed. That answer comes from the rail that sold it.

Where the platform genuinely matters, which is what a given build is CAPABLE of, the answer belongs to
which implementation the factory returns, not to a conditional inside shared code.

## Structure

- `lib/magic_payments.dart`: the runtime barrel a consumer app imports.
- `lib/cli.dart`: the CLI barrel. Separate so an app does not pay for the command tree.
- `lib/src/`: everything else. Nothing outside `src` except the two barrels.

## Conventions

- English only, in identifiers, comments, docblocks and commits.
- Every public API carries a docblock saying WHY, not restating the signature.
- Types everywhere. No dynamic, no implicit returns.
- Multi-line collections with trailing commas, even for two elements.
- 120-character lines.
- No linter suppressions. `analysis_options.yaml` allows `avoid_print` for the CLI and nothing else.

## Verifying a change

```
flutter pub get
flutter analyze --no-fatal-infos
dart format --set-exit-if-changed .
flutter test
```

All four are CI jobs, so all four must pass locally first.

**`dart format` IS the gate here.** If you also work in a consumer app that forbids it (uptizm does,
because its tree predates the current tall formatter), keep the two straight: run the formatter in
this repository, never in that one, and treat the resulting whitespace difference between two copies
of a moved file as expected.

## Rules

`.claude/rules/` holds path-scoped guidance, and a rule arrives with the subsystem it governs rather
than ahead of it. Every subsystem now has code, so every subsystem now has a rule:

- `tests.md`: the four traps a fixture-driven suite falls into.
- `contracts.md`: the three-contract split, and the vocabulary rules the wire types follow.
- `drivers.md`: the conditional-import graph, and why nothing here branches on the runtime platform.
- `cli.md`: the three `payments:*` commands, the manifest-only install, and the one-tool MCP policy.

None of them restate a docblock. The source carries the reasoning for a given class; a rule carries
the invariant that spans the directory, which is the thing a reader cannot get by opening one file.

## References

`magic_notifications` is the structural sibling to follow for plugin shape (service provider, a
singleton manager, a facade, driver strategy). Read it for the pattern, not for its content: its
domain is notifications and its dependency floors are older than this package's.
