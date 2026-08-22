import 'package:flutter/foundation.dart';

import '../enums/invoice_status.dart';

/// One row in the customer's billing history.
///
/// [amount] is a string rather than a number because money is rendered by the
/// producer: it knows the currency and the customer's locale, and a client that
/// did its own amount math would eventually disagree with the receipt.
@immutable
class Invoice {
  /// Creates an [Invoice].
  const Invoice({
    required this.id,
    required this.number,
    required this.date,
    required this.amount,
    required this.status,
    this.pdfUrl,
  });

  /// The rail's invoice identifier.
  final String id;

  /// The human-readable invoice number shown next to the receipt action.
  final String number;

  /// When the invoice was issued, or `null` when the producer sent no usable
  /// date.
  ///
  /// An instant rather than a formatted string on purpose: month names and date
  /// order are display copy, so a package that formatted them here would render
  /// one language in every consumer. The caller formats it in the locale it is
  /// already rendering.
  final DateTime? date;

  /// The total, formatted and currency-aware, exactly as the producer rendered
  /// it (e.g. `"$348.00"`).
  final String amount;

  /// Settlement state.
  final InvoiceStatus status;

  /// The rail-hosted PDF receipt, or `null` when the producer offers none.
  ///
  /// Nullable and never assumed: a vendor may route its receipt action through
  /// the billing portal instead, and a dead link is worse than an absent one.
  final String? pdfUrl;

  /// Decodes an [Invoice] from one entry of the invoices endpoint's `data`
  /// array.
  factory Invoice.fromMap(Map<String, dynamic> map) {
    // A malformed or wrongly-typed date degrades to "no date" rather than
    // throwing out of a decode path; the rest of the row still renders.
    final Object? rawDate = map['date'];

    return Invoice(
      id: (map['id'] as String?) ?? '',
      number: (map['number'] as String?) ?? '',
      date: rawDate is String ? DateTime.tryParse(rawDate) : null,
      amount: (map['amount'] as String?) ?? '',
      status: InvoiceStatus.fromWire(map['status'] as String?),
      pdfUrl: map['pdf_url'] as String?,
    );
  }
}
