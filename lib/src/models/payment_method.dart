import 'package:flutter/foundation.dart';

/// The card the customer has on file, and when it is next charged.
///
/// Every field is nullable, and that is the contract rather than defensiveness:
/// reading a card is the one billing call that dials the rail live, so the
/// producer soft-fails a rail outage to an all-null payload with a 200. This
/// value object therefore has to represent "no card on file" and "the rail did
/// not answer" without throwing. [available] is the producer's own answer to
/// which of the two it was; a caller on a backend too old to send it falls back
/// to reading its own request state.
@immutable
class PaymentMethod {
  /// Creates a [PaymentMethod].
  const PaymentMethod({
    this.brand,
    this.last4,
    this.expMonth,
    this.expYear,
    this.renewalDate,
    this.available,
  });

  /// The card network as the rail names it (e.g. `"visa"`), or `null` when no
  /// card is on file.
  final String? brand;

  /// The last four digits of the card number, or `null` when no card is on
  /// file.
  final String? last4;

  /// The expiry month (`1` to `12`), or `null` when no card is on file.
  ///
  /// The rail's own two numbers rather than one formatted `"08 / 27"` string:
  /// the separator, the padding and the two-versus-four digit year are a
  /// rendering decision, and freezing one of them in a package would hand every
  /// consumer the same card row.
  final int? expMonth;

  /// The expiry year in full (e.g. `2027`), or `null` when no card is on file.
  final int? expYear;

  /// When the subscription is next charged, or `null` when there is no active
  /// subscription or the rail did not answer.
  ///
  /// An instant rather than a formatted string, for the same reason as
  /// `Invoice.date`: date formatting is display copy the consumer owns.
  final DateTime? renewalDate;

  /// Whether the rail could be asked for a card, in three states.
  ///
  /// `false` means the rail could not be asked (the read failed). `true` with
  /// a `null` [last4] means the rail answered and there is genuinely no card
  /// on file. `null` means this backend does not report the field at all,
  /// which is what an adopter on an older release sends; a caller must not
  /// read that as `false`, or every adopter on an older backend would see
  /// their payment rail reported as down.
  final bool? available;

  /// Decodes a [PaymentMethod] from the payment-method response.
  ///
  /// Every field may be `null`, both on a genuine "no card on file" state and on
  /// the endpoint's rail-outage soft-fail.
  factory PaymentMethod.fromMap(Map<String, dynamic> map) {
    // A malformed or wrongly-typed date degrades to "not reported" rather than
    // throwing; the card itself still renders.
    final Object? rawRenewalDate = map['renewal_date'];

    // Same treatment, and for a sharper reason: this decode runs on the billing
    // screen's own read, so a TypeError here blanks the whole card instead of
    // degrading one field. `as bool?` throws on a `1` or a `"false"`, which a
    // rail behind a different serializer can send, and "not reported" is the
    // honest reading of a value this object cannot interpret.
    final Object? rawAvailable = map['available'];

    return PaymentMethod(
      brand: map['brand'] as String?,
      last4: map['last4'] as String?,
      expMonth: (map['exp_month'] as num?)?.toInt(),
      expYear: (map['exp_year'] as num?)?.toInt(),
      renewalDate: rawRenewalDate is String
          ? DateTime.tryParse(rawRenewalDate)
          : null,
      // An absent key degrades to `null`, not `false`: an adopter on an older
      // backend must not be told its payment rail is down.
      available: rawAvailable is bool ? rawAvailable : null,
    );
  }
}
