import 'dart:convert';

import 'nostr_event.dart';

/// Nostr subscription filter (NIP-01).
///
/// Used to subscribe to specific events from relays. Supports
/// filtering by IDs, authors, kinds, time range, and tag values.
class NostrFilter {
  NostrFilter({
    this.ids,
    this.authors,
    this.kinds,
    this.since,
    this.until,
    this.limit,
    this.tagFilters,
  });

  final List<String>? ids;
  final List<String>? authors;
  final List<int>? kinds;
  final int? since;
  final int? until;
  final int? limit;
  final Map<String, List<String>>? tagFilters;

  // --- Factory constructors for common patterns ---

  /// Filter for NIP-17 gift wraps addressed to a pubkey.
  factory NostrFilter.giftWrapsFor(String pubkey, {int? since}) {
    return NostrFilter(
      kinds: [NostrKind.giftWrap],
      since: since,
      tagFilters: {'p': [pubkey]},
      limit: 100,
    );
  }

  /// Filter for geohash ephemeral events (kind 20000 + 20001).
  factory NostrFilter.geohashEphemeral(String geohash,
      {int? since, int limit = 1000}) {
    return NostrFilter(
      kinds: [NostrKind.ephemeralEvent, NostrKind.geohashPresence],
      since: since,
      tagFilters: {'g': [geohash]},
      limit: limit,
    );
  }

  /// Filter for text notes from specific authors.
  factory NostrFilter.textNotesFrom(List<String> authors,
      {int? since, int limit = 50}) {
    return NostrFilter(
      kinds: [NostrKind.textNote],
      authors: authors,
      since: since,
      limit: limit,
    );
  }

  /// Filter for geohash-scoped text notes (kind 1 with g tag).
  factory NostrFilter.geohashNotes(String geohash,
      {int? since, int limit = 200}) {
    return NostrFilter(
      kinds: [NostrKind.textNote],
      since: since,
      tagFilters: {'g': [geohash]},
      limit: limit,
    );
  }

  /// Filter for specific event IDs.
  factory NostrFilter.forEvents(List<String> ids) {
    return NostrFilter(ids: ids);
  }

  /// Convert filter to JSON map for relay protocol.
  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{};
    if (ids != null) map['ids'] = ids;
    if (authors != null) map['authors'] = authors;
    if (kinds != null) map['kinds'] = kinds;
    if (since != null) map['since'] = since;
    if (until != null) map['until'] = until;
    if (limit != null) map['limit'] = limit;
    tagFilters?.forEach((tag, values) {
      map['#$tag'] = values;
    });
    return map;
  }

  /// Check if this filter matches an event.
  bool matches(NostrEvent event) {
    if (ids != null && !ids!.contains(event.id)) return false;
    if (authors != null && !authors!.contains(event.pubkey)) return false;
    if (kinds != null && !kinds!.contains(event.kind)) return false;
    if (since != null && event.createdAt < since!) return false;
    if (until != null && event.createdAt > until!) return false;

    if (tagFilters != null) {
      for (final entry in tagFilters!.entries) {
        final eventTags = event.tags
            .where((t) => t.isNotEmpty && t[0] == entry.key)
            .map((t) => t.length > 1 ? t[1] : null)
            .whereType<String>()
            .toList();
        if (!entry.value.any((v) => eventTags.contains(v))) return false;
      }
    }
    return true;
  }

  /// Get geohash from g tag filter.
  String? get geohash => tagFilters?['g']?.firstOrNull;

  @override
  String toString() {
    final parts = <String>[];
    if (ids != null) parts.add('ids=${ids!.length}');
    if (authors != null) parts.add('authors=${authors!.length}');
    if (kinds != null) parts.add('kinds=$kinds');
    if (since != null) parts.add('since=$since');
    if (limit != null) parts.add('limit=$limit');
    tagFilters?.forEach((t, v) => parts.add('#$t=${v.length}'));
    return 'NostrFilter(${parts.join(', ')})';
  }
}
