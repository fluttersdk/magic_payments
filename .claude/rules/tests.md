---
paths:
  - "test/**"
  - "lib/**"
---

# Testing magic_payments

TDD, and the failing test comes first. That is not a preference here: this package exists because a
billing surface accumulated defects that a green suite certified, and every one of them was a test
agreeing with its author instead of with the product.

## The four traps this package was built having already seen

**A fixture must be copied from the producer, not written from memory.** A consumer of this package
decodes a JSON payload some backend produces. A fixture carrying a key the producer never emits, or a
value its enum cannot hold, passes every assertion and proves nothing. One real case cost months: a
fixture said `status` where the producer sent `plan_status`, so the decoded field was null in
production for the life of the field and no test noticed.

**A safe fallback hides a forgotten case exactly as well as it handles a newer server.** Every
`*FromWire()` here falls back rather than throwing, so an older client survives a backend that ships a
new case. That same fallback turns a case you forgot into a silent degrade. So a fallback test is
necessary and not sufficient: loop the full vocabulary through the decoder and assert nothing lands on
the fallback, and assert the decoded values are DISTINCT, because a loop alone cannot see a case
mapped onto its neighbour.

**A guard with no test is a guess, and every `??` right side is unvisited code.** If a branch exists
for a state the current data cannot reach, reach it deliberately: override the config, build the
model by hand, inject the failure. A defensive branch nothing exercises is where the next defect
lives.

**Two guards on one outcome absorb each other's mutation.** When a single assertion would still pass
after you delete either of two guards, you have one test for two behaviours. Write one test per guard
and check it by deleting that guard and watching only its own test fail.

## Shape

- `flutter test` must pass on a clean checkout with no network and no credentials. No test may reach a
  real payment provider; a rail is exercised through its contract.
- Assert behaviour, never an implementation detail. For a value object that means the decoded values;
  for a driver, the calls it makes on its transport.
- A test's name says what breaks if it fails, not what it calls.
