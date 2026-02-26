import 'dart:convert';
import 'dart:typed_data';

import 'package:pointycastle/digests/sha256.dart';

/// Golomb-Coded Set (GCS) filter for efficient message deduplication.
///
/// Matches iOS `GCSFilter.swift` — used in gossip sync protocol to
/// compactly represent "which messages I already have" so peers can
/// exchange only new messages.
///
/// GCS is a probabilistic data structure (like a Bloom filter) that
/// encodes a set of hashed elements into a compact bitstream using
/// Golomb-Rice coding. It achieves near-optimal space efficiency
/// (~1.44 bits per element at 1/M false positive rate).
class GcsFilter {
  GcsFilter({this.p = 19, this.m = 784931});

  /// Golomb parameter P (bits for remainder encoding).
  final int p;

  /// Modulus M = 2^P for hash range mapping.
  final int m;

  /// Encoded filter data.
  Uint8List? _data;

  /// Number of elements in the filter.
  int _count = 0;

  int get count => _count;
  Uint8List? get data => _data;

  /// Build a GCS filter from a list of message IDs.
  void build(List<String> messageIds) {
    if (messageIds.isEmpty) {
      _data = Uint8List(0);
      _count = 0;
      return;
    }

    _count = messageIds.length;

    // Hash each message ID to a value in [0, N*M)
    final hashes = messageIds.map((id) => _hashToRange(id, _count * m)).toList()
      ..sort();

    // Compute differences between sorted hashes
    final deltas = <int>[];
    var prev = 0;
    for (final h in hashes) {
      deltas.add(h - prev);
      prev = h;
    }

    // Golomb-Rice encode the deltas
    _data = _golombEncode(deltas);
  }

  /// Test if a message ID might be in the filter.
  /// False positives possible; false negatives impossible.
  bool mightContain(String messageId) {
    if (_data == null || _count == 0) return false;

    final targetHash = _hashToRange(messageId, _count * m);

    // Decode and check
    final decoded = _golombDecode(_data!, _count);
    var accumulated = 0;
    for (final delta in decoded) {
      accumulated += delta;
      if (accumulated == targetHash) return true;
      if (accumulated > targetHash) return false;
    }
    return false;
  }

  /// Hash a string to a value in [0, range).
  int _hashToRange(String input, int range) {
    final digest = SHA256Digest();
    final bytes = digest.process(Uint8List.fromList(utf8.encode(input)));
    // Use first 8 bytes as uint64, mod range
    var value = 0;
    for (var i = 0; i < 8 && i < bytes.length; i++) {
      value = (value << 8) | bytes[i];
    }
    return value.abs() % range;
  }

  /// Golomb-Rice encode a list of sorted deltas.
  Uint8List _golombEncode(List<int> deltas) {
    final bits = <int>[]; // individual bits

    for (final delta in deltas) {
      final q = delta >> p; // quotient
      final r = delta & ((1 << p) - 1); // remainder

      // Unary encode quotient: q 1-bits followed by a 0-bit
      for (var i = 0; i < q; i++) {
        bits.add(1);
      }
      bits.add(0);

      // Binary encode remainder in P bits
      for (var i = p - 1; i >= 0; i--) {
        bits.add((r >> i) & 1);
      }
    }

    // Pack bits into bytes
    final byteCount = (bits.length + 7) ~/ 8;
    final result = Uint8List(byteCount);
    for (var i = 0; i < bits.length; i++) {
      if (bits[i] == 1) {
        result[i ~/ 8] |= (1 << (7 - (i % 8)));
      }
    }
    return result;
  }

  /// Golomb-Rice decode from encoded bytes.
  List<int> _golombDecode(Uint8List data, int count) {
    final deltas = <int>[];
    var bitIndex = 0;

    int readBit() {
      if (bitIndex >= data.length * 8) return 0;
      final byteIdx = bitIndex ~/ 8;
      final bitIdx = 7 - (bitIndex % 8);
      bitIndex++;
      return (data[byteIdx] >> bitIdx) & 1;
    }

    for (var i = 0; i < count; i++) {
      // Decode unary quotient
      var q = 0;
      while (readBit() == 1) {
        q++;
      }

      // Decode binary remainder
      var r = 0;
      for (var j = 0; j < p; j++) {
        r = (r << 1) | readBit();
      }

      deltas.add((q << p) | r);
    }

    return deltas;
  }

  /// Serialize filter to bytes (count + data).
  Uint8List serialize() {
    final countBytes = ByteData(4)..setUint32(0, _count);
    final dataBytes = _data ?? Uint8List(0);
    return Uint8List.fromList([
      ...countBytes.buffer.asUint8List(),
      ...dataBytes,
    ]);
  }

  /// Deserialize filter from bytes.
  factory GcsFilter.deserialize(Uint8List bytes, {int p = 19, int m = 784931}) {
    final filter = GcsFilter(p: p, m: m);
    if (bytes.length < 4) return filter;

    final countData = ByteData.sublistView(bytes, 0, 4);
    filter._count = countData.getUint32(0);
    filter._data = bytes.sublist(4);
    return filter;
  }

  /// Estimated false positive rate: approximately 1/M.
  double get estimatedFalsePositiveRate => 1.0 / m;

  /// Approximate size in bits per element.
  double get bitsPerElement {
    if (_count == 0 || _data == null) return 0;
    return (_data!.length * 8) / _count;
  }
}
