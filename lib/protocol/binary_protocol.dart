import 'dart:typed_data';

import 'package:bitchat/models/bitchat_packet.dart';
import 'package:bitchat/models/peer_id.dart';
import 'package:bitchat/protocol/message_padding.dart';

/// Binary protocol codec for BitchatPacket ↔ wire format.
///
/// Maintains 100% compatibility with the iOS and Android implementations.
/// All multi-byte values use network byte order (big-endian).
///
/// V1 Header (14 bytes):
/// ```
/// +--------+------+-----+----------+-------+----------+
/// | Version| Type | TTL | Timestamp| Flags | PayloadLen|
/// | 1 byte | 1 B  | 1 B | 8 bytes  | 1 B  | 2 bytes   |
/// +--------+------+-----+----------+-------+----------+
/// ```
///
/// V2 Header (16 bytes):
/// Same but PayloadLen is 4 bytes instead of 2.
class BinaryProtocol {
  BinaryProtocol._();

  static const int v1HeaderSize = 14;
  static const int v2HeaderSize = 16;
  static const int senderIDSize = 8;
  static const int recipientIDSize = 8;
  static const int signatureSize = 64;

  // Flag bits
  static const int _flagHasRecipient = 0x01;
  static const int _flagHasSignature = 0x02;
  static const int _flagIsCompressed = 0x04;
  static const int _flagHasRoute = 0x08;
  static const int _flagIsRSR = 0x10;

  // --------------------------------------------------------------------------
  // Encode
  // --------------------------------------------------------------------------

  /// Encode a [BitchatPacket] to binary wire format.
  static Uint8List? encode(BitchatPacket packet, {bool padding = true}) {
    final version = packet.version;
    if (version != 1 && version != 2) return null;

    var payload = Uint8List.fromList(packet.payload);
    final isCompressed = false; // TODO: LZ4 compression support

    // Sanitize route hops to 8 bytes each
    final sanitizedRoute = <Uint8List>[];
    if (packet.route != null) {
      for (final hop in packet.route!) {
        if (hop.length == senderIDSize) {
          sanitizedRoute.add(hop);
        } else if (hop.length > senderIDSize) {
          sanitizedRoute.add(Uint8List.sublistView(hop, 0, senderIDSize));
        } else {
          final padded = Uint8List(senderIDSize);
          padded.setRange(0, hop.length, hop);
          sanitizedRoute.add(padded);
        }
      }
    }
    if (sanitizedRoute.length > 255) return null;

    final hasRoute = sanitizedRoute.isNotEmpty;
    final routeLength = hasRoute ? 1 + sanitizedRoute.length * senderIDSize : 0;

    final headerSize = version == 2 ? v2HeaderSize : v1HeaderSize;
    final payloadLenFieldSize = version == 2 ? 4 : 2;

    // Calculate total size
    var totalSize =
        headerSize +
        senderIDSize +
        (packet.recipientID != null ? recipientIDSize : 0) +
        (hasRoute && version >= 2 ? routeLength : 0) +
        (isCompressed && version == 2 ? 4 : 0) +
        payload.length +
        (packet.signature != null ? signatureSize : 0);

    final builder = BytesBuilder(copy: false);

    // --- Header ---
    builder.addByte(version); // Version
    builder.addByte(packet.type); // Type
    builder.addByte(packet.ttl); // TTL

    // Timestamp (8 bytes big-endian)
    for (var i = 7; i >= 0; i--) {
      builder.addByte((packet.timestamp >> (i * 8)) & 0xFF);
    }

    // Flags
    int flags = 0;
    if (packet.recipientID != null) flags |= _flagHasRecipient;
    if (packet.signature != null) flags |= _flagHasSignature;
    if (isCompressed) flags |= _flagIsCompressed;
    if (hasRoute && version >= 2) flags |= _flagHasRoute;
    if (packet.isRSR) flags |= _flagIsRSR;
    builder.addByte(flags);

    // Payload length
    if (version == 2) {
      _writeUint32BE(builder, payload.length);
    } else {
      _writeUint16BE(builder, payload.length);
    }

    // --- Variable fields ---
    // Sender ID (exactly 8 bytes)
    final sid = _ensureSize(packet.senderID, senderIDSize);
    builder.add(sid);

    // Recipient ID (optional, 8 bytes)
    if (packet.recipientID != null) {
      builder.add(_ensureSize(packet.recipientID!, recipientIDSize));
    }

    // Route (v2+ only)
    if (hasRoute && version >= 2) {
      builder.addByte(sanitizedRoute.length);
      for (final hop in sanitizedRoute) {
        builder.add(hop);
      }
    }

    // Compressed original size (v2 only)
    if (isCompressed && version == 2) {
      _writeUint32BE(builder, payload.length);
    }

    // Payload
    builder.add(payload);

    // Signature
    if (packet.signature != null) {
      builder.add(_ensureSize(packet.signature!, signatureSize));
    }

    var result = builder.toBytes();

    // Padding
    if (padding) {
      final optimalSize = MessagePadding.optimalBlockSize(result.length);
      result = MessagePadding.pad(result, optimalSize);
    }

    return result;
  }

  // --------------------------------------------------------------------------
  // Decode
  // --------------------------------------------------------------------------

  /// Decode binary data to [BitchatPacket].
  static BitchatPacket? decode(Uint8List data) {
    // Try as-is first
    final pkt = _decodeCore(data);
    if (pkt != null) return pkt;

    // Try removing padding
    final unpadded = MessagePadding.unpad(data);
    if (identical(unpadded, data) || unpadded.length == data.length) {
      return null;
    }
    return _decodeCore(unpadded);
  }

  static BitchatPacket? _decodeCore(Uint8List raw) {
    if (raw.length < v1HeaderSize + senderIDSize) return null;

    var offset = 0;

    // Version
    final version = raw[offset++];
    if (version != 1 && version != 2) return null;

    final headerSize = version == 2 ? v2HeaderSize : v1HeaderSize;
    if (raw.length < headerSize + senderIDSize) return null;

    // Type
    final type = raw[offset++];

    // TTL
    final ttl = raw[offset++];

    // Timestamp (8 bytes big-endian)
    int timestamp = 0;
    for (var i = 0; i < 8; i++) {
      timestamp = (timestamp << 8) | raw[offset++];
    }

    // Flags
    final flags = raw[offset++];
    final hasRecipient = (flags & _flagHasRecipient) != 0;
    final hasSignature = (flags & _flagHasSignature) != 0;
    final isCompressed = (flags & _flagIsCompressed) != 0;
    final hasRoute = (flags & _flagHasRoute) != 0 && version >= 2;
    final isRSR = (flags & _flagIsRSR) != 0;

    // Payload length
    int payloadLength;
    if (version == 2) {
      if (offset + 4 > raw.length) return null;
      payloadLength = _readUint32BE(raw, offset);
      offset += 4;
    } else {
      if (offset + 2 > raw.length) return null;
      payloadLength = _readUint16BE(raw, offset);
      offset += 2;
    }

    // Sender ID
    if (offset + senderIDSize > raw.length) return null;
    final senderID = Uint8List.fromList(
      raw.sublist(offset, offset + senderIDSize),
    );
    offset += senderIDSize;

    // Recipient ID
    Uint8List? recipientID;
    if (hasRecipient) {
      if (offset + recipientIDSize > raw.length) return null;
      recipientID = Uint8List.fromList(
        raw.sublist(offset, offset + recipientIDSize),
      );
      offset += recipientIDSize;
    }

    // Route
    List<Uint8List>? route;
    if (hasRoute) {
      if (offset >= raw.length) return null;
      final routeCount = raw[offset++];
      route = [];
      for (var i = 0; i < routeCount; i++) {
        if (offset + senderIDSize > raw.length) return null;
        route.add(
          Uint8List.fromList(raw.sublist(offset, offset + senderIDSize)),
        );
        offset += senderIDSize;
      }
    }

    // Compressed original size (skip for now)
    if (isCompressed && version == 2) {
      if (offset + 4 > raw.length) return null;
      // final originalSize = _readUint32BE(raw, offset);
      offset += 4;
    }

    // Payload
    if (offset + payloadLength > raw.length) return null;
    final payload = Uint8List.fromList(
      raw.sublist(offset, offset + payloadLength),
    );
    offset += payloadLength;

    // Signature
    Uint8List? signature;
    if (hasSignature) {
      if (offset + signatureSize > raw.length) return null;
      signature = Uint8List.fromList(
        raw.sublist(offset, offset + signatureSize),
      );
      offset += signatureSize;
    }

    return BitchatPacket(
      version: version,
      type: type,
      senderID: senderID,
      recipientID: recipientID,
      timestamp: timestamp,
      payload: payload,
      signature: signature,
      ttl: ttl,
      route: route,
      isRSR: isRSR,
    );
  }

  // --------------------------------------------------------------------------
  // Helpers
  // --------------------------------------------------------------------------

  static Uint8List _ensureSize(Uint8List data, int size) {
    if (data.length == size) return data;
    final result = Uint8List(size);
    final copyLen = data.length < size ? data.length : size;
    result.setRange(0, copyLen, data);
    return result;
  }

  static void _writeUint16BE(BytesBuilder builder, int value) {
    builder.addByte((value >> 8) & 0xFF);
    builder.addByte(value & 0xFF);
  }

  static void _writeUint32BE(BytesBuilder builder, int value) {
    builder.addByte((value >> 24) & 0xFF);
    builder.addByte((value >> 16) & 0xFF);
    builder.addByte((value >> 8) & 0xFF);
    builder.addByte(value & 0xFF);
  }

  static int _readUint16BE(Uint8List data, int offset) =>
      (data[offset] << 8) | data[offset + 1];

  static int _readUint32BE(Uint8List data, int offset) =>
      (data[offset] << 24) |
      (data[offset + 1] << 16) |
      (data[offset + 2] << 8) |
      data[offset + 3];
}
