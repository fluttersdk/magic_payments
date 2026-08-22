/// Multi-rail billing for the Magic Framework.
///
/// One entitlement contract over more than one payment rail: Stripe on the web,
/// and store in-app purchase on iOS and Android. A consumer asks what a customer
/// is entitled to and where they manage it; which rail sold the subscription is
/// the package's problem, not the caller's.
///
/// This barrel is deliberately empty at `0.0.1`. The scaffold ships first so the
/// repository, its CI and its publish workflow are proven against an empty tree,
/// and the exports arrive with the code they name.
library;
