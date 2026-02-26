import 'dart:typed_data';

/// Represents a peer identity in the BitChat mesh network.
///
/// PeerID is an 8-byte truncated identifier derived from the peer's
/// cryptographic public key. It is represented as a 16-character hex string.
class PeerID {
  PeerID(this.id);

  /// Creates a PeerID from raw binary data (8 bytes).
  factory PeerID.fromBytes(Uint8List data) {
    if (data.length < idByteLength) {
      final padded = Uint8List(idByteLength);
      padded.setRange(0, data.length, data);
      return PeerID(_bytesToHex(padded));
    }
    return PeerID(_bytesToHex(Uint8List.sublistView(data, 0, idByteLength)));
  }

  /// Creates a broadcast PeerID (all 0xFF bytes).
  factory PeerID.broadcast() =>
      PeerID('ff' * idByteLength); // "ffffffffffffffff"

  /// The hex string representation of the peer ID.
  final String id;

  /// Size of PeerID in bytes.
  static const int idByteLength = 8;

  /// Whether this is a broadcast address.
  bool get isBroadcast => id == 'ff' * idByteLength;

  /// Converts the hex ID to raw bytes.
  Uint8List toBytes() => _hexToBytes(id);

  /// Returns a short display form (first 8 hex chars).
  String get shortId => id.length >= 8 ? id.substring(0, 8) : id;

  @override
  String toString() => id;

  @override
  bool operator ==(Object other) => other is PeerID && other.id == id;

  @override
  int get hashCode => id.hashCode;

  // --- Helpers ---

  static String _bytesToHex(Uint8List bytes) {
    final sb = StringBuffer();
    for (final b in bytes) {
      sb.write(b.toRadixString(16).padLeft(2, '0'));
    }
    return sb.toString();
  }

  static Uint8List _hexToBytes(String hex) {
    final result = Uint8List(hex.length ~/ 2);
    for (var i = 0; i < result.length; i++) {
      result[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return result;
  }
}
