/// The CLI surface of `magic_payments`, kept separate from the runtime barrel.
///
/// A consumer's app imports `magic_payments.dart` and must not pay for the
/// command-line tree; the `fluttersdk_artisan` provider and its commands are
/// reached through this entry point instead. That split is why there are two
/// barrels rather than one.
///
/// Deliberately empty at `0.0.1`. See `lib/magic_payments.dart`.
library;
