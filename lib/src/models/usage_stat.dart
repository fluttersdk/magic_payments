import 'package:flutter/foundation.dart';

/// One metered resource, counted against the plan limit that caps it.
///
/// A `null` [limit] means unlimited, never zero: a tier that lifts a cap
/// reports no cap, and reading that as "none allowed" would gate a paying
/// customer out of what they bought.
@immutable
class UsageStat {
  /// Creates a [UsageStat].
  const UsageStat({
    required this.key,
    required this.used,
    required this.limit,
    this.label,
    this.unit = '',
  });

  /// The resource's stable wire key (e.g. `monitors`), untranslated.
  ///
  /// This is the field logic keys on. [label] is the same resource's display
  /// copy, which differs in every language, so a gate that matched on it read
  /// zero usage for every non-English session and silently opened itself.
  final String key;

  /// How much of the resource is in use this cycle.
  final int used;

  /// The plan's cap on the resource, or `null` for unlimited.
  final int? limit;

  /// The resource's display name, or `null` when nobody has supplied one.
  ///
  /// Never decoded here and never defaulted to the [key]: the usage wire carries
  /// only numbers, and a display name comes from the consumer's own translation
  /// catalogue. A label this package invented would ship one vendor's English
  /// into every app that depends on it.
  final String? label;

  /// A short suffix rendered after the numbers (e.g. `"checks"`), empty when the
  /// numbers speak for themselves. Consumer-supplied display copy, like
  /// [label].
  final String unit;

  /// Decodes every metered resource in a usage payload, in the order the
  /// producer sent them.
  ///
  /// Keyed off the payload's own keys rather than a list this package holds: the
  /// resources a vendor meters are its product's, not a payment concept, and a
  /// hardcoded key list would silently drop the fourth resource a backend starts
  /// reporting. Display copy is left to the consumer, which pairs it up by
  /// [key].
  static List<UsageStat> fromWireMap(Map<String, dynamic> map) {
    return map.keys
        .map((String key) => UsageStat.fromWire(key, map[key]))
        .toList();
  }

  /// Decodes the `{used, limit}` entry a usage payload holds under [key].
  ///
  /// An [entry] that is absent or not an object decodes to zero used and no
  /// cap, keeping [key]: a resource the producer stopped reporting is one the
  /// caller can still look up, and "unknown" must not read as "at the limit".
  factory UsageStat.fromWire(String key, Object? entry) {
    final Map<String, dynamic> values = entry is Map<String, dynamic>
        ? entry
        : const <String, dynamic>{};

    return UsageStat(
      key: key,
      used: (values['used'] as num?)?.toInt() ?? 0,
      limit: (values['limit'] as num?)?.toInt(),
    );
  }
}
