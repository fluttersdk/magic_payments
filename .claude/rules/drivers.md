---
paths:
  - "lib/src/drivers/**"
---

# Drivers and the platform question

`billing_service_factory.dart` is the ONE place in this package that knows about platforms, and it
knows through the import graph rather than through a branch. Everything below follows from that.

## Three arms, and the third is not optional

The conditional import has a stub default, a web-library arm and a `dart:io` arm. Drop the `dart:io`
guard and every iOS and Android build silently resolves the stub, whose every method throws, breaking
the five mobile read paths that work today with no analyzer error on any platform to say so.

A conditional import resolves a whole FILE, so every arm has to declare every factory function. The
web and stub arms return `null` for the store rail; the io arm delegates to `createStoreRail()`, which
asks the runtime device separately, because macOS, Windows and Linux match the same import guard as
mobile while having no StoreKit or Play Billing. That is the one legitimate runtime-platform check in
the package, and it lives there because the import graph genuinely cannot answer it.

## Do not spell a guard string in prose

`test/drivers/billing_service_factory_test.dart` counts each guard string over the RAW source, comments
included, because two copies of one guard would silently shadow each other. A docblock that quotes the
token fails that count. A review grep has already matched the comment explaining the thing it was
searching for; that is why the docblocks in that file describe the guards without naming them. Keep it
that way.

## The stub throws, and must keep throwing

Elsewhere a read is honourable on every platform because the vendor's backend is the authority. In the
stub arm there is no assumed transport to ask over, so a silent empty answer would render as a customer
with no subscription: a lie about a paying account, and one a support ticket cannot distinguish from a
genuine free tier. Both rails resolving to `null` from that same file is correct for the opposite
reason, an absent rail is a button nobody renders.

## What a driver test asserts

The calls the driver makes on its transport, not the shape of its private helpers. `flutter test` must
pass on a clean checkout with no network and no credentials, so no test may reach a real payment
provider; a rail is exercised through its contract. See `tests.md` for the fixture discipline, which is
where the expensive defects in this domain actually come from.

## Errors

A failed call logs with the `[ClassName.method]` prefix already used across the drivers and then throws
a `BillingException`. Never swallow a transport failure into a default entitlement: a caller cannot
tell a network error from a customer on the free tier, and one of those two is a support ticket.
