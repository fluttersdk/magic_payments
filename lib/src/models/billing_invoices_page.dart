import 'package:flutter/foundation.dart';

import 'invoice.dart';

/// A cursor-paginated page of the customer's invoices.
///
/// A cursor rather than a page number because the producer paginates a rail's
/// own list, which grows at the head: an offset would show the same invoice
/// twice on the second page.
@immutable
class BillingInvoicesPage {
  /// Creates a [BillingInvoicesPage].
  const BillingInvoicesPage({required this.invoices, required this.nextCursor});

  /// The page of invoices, most recent first (the order the producer returns).
  final List<Invoice> invoices;

  /// The encoded cursor for the next page, or `null` when this is the last
  /// page.
  final String? nextCursor;

  /// Decodes a [BillingInvoicesPage] from the invoices response body
  /// (`{data: [...], next_cursor}`).
  ///
  /// A `data` value that is not a list decodes to an empty page rather than
  /// throwing: a billing history that cannot be read renders no rows, which is
  /// recoverable, where an exception out of the decode takes the screen with it.
  factory BillingInvoicesPage.fromMap(Map<String, dynamic> map) {
    final Object? rawData = map['data'];

    return BillingInvoicesPage(
      invoices: rawData is List
          ? rawData
                .whereType<Map<String, dynamic>>()
                .map(Invoice.fromMap)
                .toList()
          : const <Invoice>[],
      nextCursor: map['next_cursor'] as String?,
    );
  }
}
