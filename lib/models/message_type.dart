/// BitChat protocol message types.
///
/// Matches the iOS/Android protocol exactly for cross-platform compatibility.
/// All private communication metadata (receipts, status) is embedded
/// in noiseEncrypted payloads.
enum MessageType {
  /// "I'm here" announcement with nickname
  announce(0x01),

  /// Public chat message
  message(0x02),

  /// "I'm leaving" notification
  leave(0x03),

  /// Noise Protocol handshake (init or response)
  noiseHandshake(0x10),

  /// All Noise-encrypted payloads (messages, receipts, etc.)
  noiseEncrypted(0x11),

  /// Fragment for large message reassembly
  fragment(0x20),

  /// GCS filter-based sync request (local-only)
  requestSync(0x21),

  /// Binary file/audio/image payloads
  fileTransfer(0x22);

  const MessageType(this.value);
  final int value;

  static MessageType? fromValue(int value) {
    for (final type in MessageType.values) {
      if (type.value == value) return type;
    }
    return null;
  }
}

/// Types of payloads embedded within noiseEncrypted messages.
///
/// The first byte of decrypted Noise payload indicates the type.
/// This provides privacy — observers can't distinguish message types.
enum NoisePayloadType {
  /// Private chat message
  privateMessage(0x01),

  /// Message was read
  readReceipt(0x02),

  /// Message was delivered
  delivered(0x03),

  /// Verification challenge (QR-based OOB binding)
  verifyChallenge(0x10),

  /// Verification response
  verifyResponse(0x11);

  const NoisePayloadType(this.value);
  final int value;

  static NoisePayloadType? fromValue(int value) {
    for (final type in NoisePayloadType.values) {
      if (type.value == value) return type;
    }
    return null;
  }
}

/// Delivery status for private messages.
sealed class DeliveryStatus {
  const DeliveryStatus();
}

class DeliveryStatusSending extends DeliveryStatus {
  const DeliveryStatusSending();
}

class DeliveryStatusSent extends DeliveryStatus {
  const DeliveryStatusSent();
}

class DeliveryStatusDelivered extends DeliveryStatus {
  const DeliveryStatusDelivered({required this.to, required this.at});
  final String to;
  final DateTime at;
}

class DeliveryStatusRead extends DeliveryStatus {
  const DeliveryStatusRead({required this.by, required this.at});
  final String by;
  final DateTime at;
}

class DeliveryStatusFailed extends DeliveryStatus {
  const DeliveryStatusFailed({required this.reason});
  final String reason;
}

class DeliveryStatusPartiallyDelivered extends DeliveryStatus {
  const DeliveryStatusPartiallyDelivered({
    required this.reached,
    required this.total,
  });
  final int reached;
  final int total;
}
