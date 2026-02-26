import 'dart:typed_data';

/// Deduplicates messages using a time-bounded seen-set.
///
/// Each message ID is stored with a timestamp. Old entries are
/// evicted during periodic sweeps.
class MessageDeduplicator {
  MessageDeduplicator({
    this.capacity = 10000,
    this.maxAge = const Duration(minutes: 10),
  });

  final int capacity;
  final Duration maxAge;

  final Map<String, DateTime> _seen = {};

  /// Check if this ID has been seen. If not, mark it.
  /// Returns true if the message is a duplicate.
  bool isDuplicate(String messageId) {
    if (_seen.containsKey(messageId)) return true;
    _seen[messageId] = DateTime.now();

    // Evict if over capacity
    if (_seen.length > capacity) {
      _evictOldest();
    }
    return false;
  }

  /// Explicitly mark a message as processed.
  void markProcessed(String messageId) {
    _seen[messageId] = DateTime.now();
  }

  /// Check without marking.
  bool hasSeen(String messageId) => _seen.containsKey(messageId);

  /// Remove expired entries.
  void sweep() {
    final cutoff = DateTime.now().subtract(maxAge);
    _seen.removeWhere((_, timestamp) => timestamp.isBefore(cutoff));
  }

  /// Clear all entries.
  void reset() => _seen.clear();

  /// Current cache size.
  int get size => _seen.length;

  void _evictOldest() {
    // Remove oldest 20% when over capacity
    final sorted = _seen.entries.toList()
      ..sort((a, b) => a.value.compareTo(b.value));
    final removeCount = (capacity * 0.2).ceil();
    for (var i = 0; i < removeCount && i < sorted.length; i++) {
      _seen.remove(sorted[i].key);
    }
  }
}
