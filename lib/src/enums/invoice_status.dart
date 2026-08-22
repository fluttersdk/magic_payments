/// The settlement state of a billing invoice.
///
/// Three states rather than the rail's own five, because a receipt list answers
/// one question: has this been paid, is it still coming, or did it never
/// settle.
///
/// Deliberately label-free. A display word is display copy, and it belongs to
/// the consumer's own translation catalogue: a label resolved inside this
/// package would render one vendor's key, in one language, in every app that
/// depends on it.
enum InvoiceStatus {
  /// Settled.
  paid,

  /// Issued and still awaiting settlement.
  pending,

  /// Never settled, and no longer being collected.
  failed;

  /// Decodes an invoice `status` wire string into an [InvoiceStatus], folding
  /// the rail's own vocabulary into these three states.
  ///
  /// Stripe's raw invoice statuses (`draft`, `open`, `paid`, `uncollectible`,
  /// `void`) do not line up one for one with a three-state settlement
  /// vocabulary: `open` and `draft` are both still awaiting settlement, and
  /// `uncollectible` and `void` both never settled. An absent or unrecognised
  /// value falls back to [pending] rather than silently claiming [paid].
  static InvoiceStatus fromWire(String? raw) {
    return switch (raw) {
      'paid' => InvoiceStatus.paid,
      'open' => InvoiceStatus.pending,
      'draft' => InvoiceStatus.pending,
      'uncollectible' => InvoiceStatus.failed,
      'void' => InvoiceStatus.failed,
      _ => InvoiceStatus.pending,
    };
  }
}
