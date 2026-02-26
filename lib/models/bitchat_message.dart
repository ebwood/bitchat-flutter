import 'dart:convert';
import 'dart:typed_data';

import 'message_type.dart';
import 'peer_id.dart';

/// Represents a user-visible message in the BitChat system.
///
/// Handles both broadcast messages and private encrypted messages,
/// with support for mentions, replies, and delivery tracking.
class BitchatMessage {
  BitchatMessage({
    String? id,
    required this.sender,
    required this.content,
    required this.timestamp,
    required this.isRelay,
    this.originalSender,
    this.isPrivate = false,
    this.recipientNickname,
    this.senderPeerID,
    this.mentions,
    DeliveryStatus? deliveryStatus,
  }) : id = id ?? _generateId(),
       deliveryStatus =
           deliveryStatus ?? (isPrivate ? const DeliveryStatusSending() : null);

  final String id;
  final String sender;
  final String content;
  final DateTime timestamp;
  final bool isRelay;
  final String? originalSender;
  final bool isPrivate;
  final String? recipientNickname;
  final PeerID? senderPeerID;
  final List<String>? mentions;
  DeliveryStatus? deliveryStatus;

  /// Formatted timestamp (HH:mm:ss).
  String get formattedTimestamp {
    final h = timestamp.hour.toString().padLeft(2, '0');
    final m = timestamp.minute.toString().padLeft(2, '0');
    final s = timestamp.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  // ---------------------------------------------------------------------------
  // Binary encoding — matches iOS/Android format exactly
  // ---------------------------------------------------------------------------

  /// Encode to binary payload for embedding in a BitchatPacket.
  Uint8List? toBinaryPayload() {
    final builder = BytesBuilder(copy: false);

    // Flags byte
    int flags = 0;
    if (isRelay) flags |= 0x01;
    if (isPrivate) flags |= 0x02;
    if (originalSender != null) flags |= 0x04;
    if (recipientNickname != null) flags |= 0x08;
    if (senderPeerID != null) flags |= 0x10;
    if (mentions != null && mentions!.isNotEmpty) flags |= 0x20;
    builder.addByte(flags);

    // Timestamp (8 bytes, big-endian, milliseconds)
    final ms = timestamp.millisecondsSinceEpoch;
    for (var i = 7; i >= 0; i--) {
      builder.addByte((ms >> (i * 8)) & 0xFF);
    }

    // ID (1-byte length + UTF-8)
    _writeString8(builder, id);

    // Sender (1-byte length + UTF-8)
    _writeString8(builder, sender);

    // Content (2-byte length + UTF-8)
    _writeString16(builder, content);

    // Optional: original sender
    if (originalSender != null) _writeString8(builder, originalSender!);

    // Optional: recipient nickname
    if (recipientNickname != null) _writeString8(builder, recipientNickname!);

    // Optional: sender peer ID
    if (senderPeerID != null) _writeString8(builder, senderPeerID!.id);

    // Optional: mentions
    if (mentions != null && mentions!.isNotEmpty) {
      final count = mentions!.length.clamp(0, 255);
      builder.addByte(count);
      for (var i = 0; i < count; i++) {
        _writeString8(builder, mentions![i]);
      }
    }

    return builder.toBytes();
  }

  /// Decode from binary payload.
  static BitchatMessage? fromBinaryPayload(Uint8List data) {
    if (data.length < 13) return null;
    var offset = 0;

    // Flags
    final flags = data[offset++];
    final isRelay = (flags & 0x01) != 0;
    final isPrivate = (flags & 0x02) != 0;
    final hasOriginalSender = (flags & 0x04) != 0;
    final hasRecipientNickname = (flags & 0x08) != 0;
    final hasSenderPeerID = (flags & 0x10) != 0;
    final hasMentions = (flags & 0x20) != 0;

    // Timestamp (8 bytes big-endian)
    if (offset + 8 > data.length) return null;
    int ms = 0;
    for (var i = 0; i < 8; i++) {
      ms = (ms << 8) | data[offset++];
    }
    final timestamp = DateTime.fromMillisecondsSinceEpoch(ms);

    // ID
    final (id, o1) = _readString8(data, offset);
    if (id == null) return null;
    offset = o1;

    // Sender
    final (sender, o2) = _readString8(data, offset);
    if (sender == null) return null;
    offset = o2;

    // Content
    final (content, o3) = _readString16(data, offset);
    if (content == null) return null;
    offset = o3;

    // Optional fields
    String? originalSender;
    if (hasOriginalSender && offset < data.length) {
      final (val, o) = _readString8(data, offset);
      originalSender = val;
      offset = o;
    }

    String? recipientNickname;
    if (hasRecipientNickname && offset < data.length) {
      final (val, o) = _readString8(data, offset);
      recipientNickname = val;
      offset = o;
    }

    PeerID? senderPeerID;
    if (hasSenderPeerID && offset < data.length) {
      final (val, o) = _readString8(data, offset);
      if (val != null) senderPeerID = PeerID(val);
      offset = o;
    }

    List<String>? mentions;
    if (hasMentions && offset < data.length) {
      final count = data[offset++];
      if (count > 0) {
        mentions = [];
        for (var i = 0; i < count && offset < data.length; i++) {
          final (val, o) = _readString8(data, offset);
          if (val != null) mentions.add(val);
          offset = o;
        }
      }
    }

    return BitchatMessage(
      id: id,
      sender: sender,
      content: content,
      timestamp: timestamp,
      isRelay: isRelay,
      originalSender: originalSender,
      isPrivate: isPrivate,
      recipientNickname: recipientNickname,
      senderPeerID: senderPeerID,
      mentions: mentions,
    );
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  static int _idCounter = 0;
  static String _generateId() {
    _idCounter++;
    final now = DateTime.now().microsecondsSinceEpoch;
    return '${now.toRadixString(36)}-${_idCounter.toRadixString(36)}';
  }

  static void _writeString8(BytesBuilder builder, String s) {
    final bytes = utf8.encode(s);
    final len = bytes.length.clamp(0, 255);
    builder.addByte(len);
    builder.add(bytes.sublist(0, len));
  }

  static void _writeString16(BytesBuilder builder, String s) {
    final bytes = utf8.encode(s);
    final len = bytes.length.clamp(0, 65535);
    builder.addByte((len >> 8) & 0xFF);
    builder.addByte(len & 0xFF);
    builder.add(bytes.sublist(0, len));
  }

  static (String?, int) _readString8(Uint8List data, int offset) {
    if (offset >= data.length) return (null, offset);
    final len = data[offset++];
    if (offset + len > data.length) return (null, offset);
    final s = utf8.decode(
      data.sublist(offset, offset + len),
      allowMalformed: true,
    );
    return (s, offset + len);
  }

  static (String?, int) _readString16(Uint8List data, int offset) {
    if (offset + 2 > data.length) return (null, offset);
    final len = (data[offset] << 8) | data[offset + 1];
    offset += 2;
    if (offset + len > data.length) return (null, offset);
    final s = utf8.decode(
      data.sublist(offset, offset + len),
      allowMalformed: true,
    );
    return (s, offset + len);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is BitchatMessage && other.id == id);

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() =>
      'BitchatMessage($id, sender=$sender, '
      '${isPrivate ? "private" : "public"})';
}
