import 'dart:typed_data';

import 'package:bitchat/protocol/binary_protocol.dart';

import 'peer_id.dart';

/// The core packet structure for all BitChat protocol messages.
///
/// Encapsulates all data needed for routing through the mesh network,
/// including TTL for hop limiting and optional encryption.
/// Packets larger than BLE MTU (512 bytes) are automatically fragmented.
class BitchatPacket {
  BitchatPacket({
    this.version = 1,
    required this.type,
    required this.senderID,
    this.recipientID,
    required this.timestamp,
    required this.payload,
    this.signature,
    required this.ttl,
    this.route,
    this.isRSR = false,
  });

  /// Convenience constructor with PeerID and auto-timestamp.
  factory BitchatPacket.create({
    required int type,
    required int ttl,
    required PeerID senderPeerID,
    required Uint8List payload,
    bool isRSR = false,
  }) {
    return BitchatPacket(
      version: 1,
      type: type,
      senderID: senderPeerID.toBytes(),
      timestamp: DateTime.now().millisecondsSinceEpoch,
      payload: payload,
      ttl: ttl,
      isRSR: isRSR,
    );
  }

  final int version; // UInt8
  final int type; // UInt8
  final Uint8List senderID; // 8 bytes
  final Uint8List? recipientID; // 8 bytes, optional
  final int timestamp; // UInt64, milliseconds since epoch
  final Uint8List payload;
  Uint8List? signature; // 64 bytes Ed25519, optional
  int ttl; // UInt8
  List<Uint8List>? route; // v2: route hops
  bool isRSR;

  /// Encode to binary wire format (with padding).
  Uint8List? toBytes({bool padding = true}) =>
      BinaryProtocol.encode(this, padding: padding);

  /// Decode from binary wire format.
  static BitchatPacket? fromBytes(Uint8List data) =>
      BinaryProtocol.decode(data);

  /// Create binary representation for signing.
  /// TTL is excluded because it changes during relay.
  Uint8List? toBytesForSigning() {
    final unsigned = BitchatPacket(
      version: version,
      type: type,
      senderID: senderID,
      recipientID: recipientID,
      timestamp: timestamp,
      payload: payload,
      signature: null,
      ttl: 0, // Fixed TTL=0 for signing
      route: route,
      isRSR: false, // RSR flag is mutable
    );
    return BinaryProtocol.encode(unsigned, padding: false);
  }

  @override
  String toString() =>
      'BitchatPacket(v$version, type=0x${type.toRadixString(16)}, '
      'ttl=$ttl, sender=${PeerID.fromBytes(senderID).shortId})';
}
