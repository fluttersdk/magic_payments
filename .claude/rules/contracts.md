---
paths:
  - "lib/src/contracts/**"
  - "lib/src/models/**"
  - "lib/src/enums/**"
---

# Contracts, models and the wire vocabulary

The reasoning behind any one class is in its docblock. What follows is the set of invariants that
span this directory, which is what a reader cannot get by opening a single file.

## The three-contract split is load-bearing

`BillingService` carries the five READS. `WebBillingService` carries the four web writes.
`StoreBillingService` carries the four store methods. None of the three extends another.

The split exists so a build that cannot serve a rail resolves it to `null` instead of declaring a
method it will refuse. A caller asks `if (web != null)` and renders a button, or does not render one.
A caller that has to call and catch is the shape this package replaced.

So:

- **Never add a purchase or management method to `BillingService`.** A read is honourable on every
  platform because the vendor's backend is the authority on an entitlement whatever rail sold it. A
  write is not, and one write on the read contract puts every implementation back to throwing.
- **Never add an `isAvailable` to a rail.** The contract's own absence IS the availability answer, and
  a second way to ask is a second answer that can disagree with the first.
- **Never merge the two rails.** Which rails a build serves is exactly what a caller needs to ask.

## A rail is not a platform

A subscription bought on an iPhone is still managed in the App Store when the customer opens the web
app. Nothing in a model or a contract may consult `kIsWeb`, `Platform.is*` or `defaultTargetPlatform`
to decide where a subscription is managed. That answer arrives on the entitlement, as `provider` and
`manageVia`. The platform question belongs to the factory alone; see `drivers.md`.

## Wire vocabulary rules

Every enum here is a wire vocabulary, and the wire is a contract with a producer in another
repository.

- **Match on LITERALS in both directions, never on `.name`.** `.name` reads shorter and works right up
  until a member is added whose Dart spelling differs from the producer's (`semiAnnual` against
  `semi_annual`). `toWire` and `fromWire` would round-trip it happily, the enum test would stay green,
  and the request would 422. Four lines of `switch` cannot do that.
- **Decode additively.** `fromWire` degrades rather than throwing, so an older client survives a
  producer that ships a new case. Every new key on a model is optional with a null or false default,
  for the same reason.
- **A fallback member is a claim, so it needs one.** Most vocabularies here carry a `none` case because
  "no rail has said" is a state they can genuinely express. `BillingCycle` deliberately has none:
  monthly and annual are the only two answers, so picking either for an unrecognised word is a
  statement about what somebody is being charged. It answers `null`. Before you give a new enum a
  fallback member, say out loud what that member claims.
- **Null is a real state and must reach the consumer as one.** A decoder that defaults a nullable field
  reports a state no rail ever confirmed, which is indistinguishable at the call site from a state one
  did. `BillingEntitlement` documents which of its fields are producer-guaranteed non-null and which
  are nullable by design; keep that count honest when you add a field.

## `providerStatus` never reaches a decision

It carries a rail's own dialect, including words the neutral vocabulary has none for. It is debug and
support text. A gate, a computed field or a rendered sentence that reads it is a bug, because it makes
this package's behaviour depend on a string only one rail emits.

## Catalogue rows pass through undecoded

`getPlans()` returns `List<Map<String, dynamic>>` on purpose. Prices, feature bullets and in-product
caps are the vendor's product, not something a payment rail understands, and a model here would either
enumerate one vendor's catalogue in a shared package or silently discard the half of each row it does
not know. The consumer owns the type it decodes these into.
