/// Delivery status tracking for messages.
///
/// Matches iOS `ReadReceipt.swift` and Android `DeliveryStatusView.swift`:
/// - Tracks sent/delivered/read states
/// - Timestamps for each transition
/// - Read receipt generation and processing

/// Message delivery state.
enum DeliveryState {
  /// Message is queued locally, not yet sent.
  pending,

  /// Message has been sent to relay/peer.
  sent,

  /// Message has been delivered to recipient's device.
  delivered,

  /// Message has been read by the recipient.
  read,

  /// Message delivery failed.
  failed,
}

/// A delivery status record for a single message.
class DeliveryStatus {
  DeliveryStatus({
    required this.messageId,
    this.state = DeliveryState.pending,
    this.sentAt,
    this.deliveredAt,
    this.readAt,
    this.error,
  });

  final String messageId;
  DeliveryState state;
  DateTime? sentAt;
  DateTime? deliveredAt;
  DateTime? readAt;
  String? error;

  /// Transition to sent state.
  void markSent() {
    if (state.index < DeliveryState.sent.index) {
      state = DeliveryState.sent;
      sentAt = DateTime.now();
    }
  }

  /// Transition to delivered state.
  void markDelivered() {
    if (state.index < DeliveryState.delivered.index) {
      state = DeliveryState.delivered;
      deliveredAt = DateTime.now();
      sentAt ??= deliveredAt;
    }
  }

  /// Transition to read state.
  void markRead() {
    if (state.index < DeliveryState.read.index) {
      state = DeliveryState.read;
      readAt = DateTime.now();
      deliveredAt ??= readAt;
      sentAt ??= readAt;
    }
  }

  /// Mark as failed with optional error message.
  void markFailed([String? errorMsg]) {
    state = DeliveryState.failed;
    error = errorMsg;
  }

  /// Status icon text (for monospace terminal UI).
  String get statusIcon {
    switch (state) {
      case DeliveryState.pending:
        return '⏳';
      case DeliveryState.sent:
        return '✓';
      case DeliveryState.delivered:
        return '✓✓';
      case DeliveryState.read:
        return '✓✓'; // blue in UI
      case DeliveryState.failed:
        return '✗';
    }
  }
}

/// Read receipt — sent by recipient to confirm message read.
class ReadReceipt {
  const ReadReceipt({
    required this.messageId,
    required this.readerPeerId,
    required this.timestamp,
  });

  final String messageId;
  final String readerPeerId;
  final DateTime timestamp;

  /// Serialize to map for Nostr event content.
  Map<String, dynamic> toJson() => {
    'type': 'read_receipt',
    'message_id': messageId,
    'reader': readerPeerId,
    'timestamp': timestamp.millisecondsSinceEpoch,
  };

  factory ReadReceipt.fromJson(Map<String, dynamic> json) {
    return ReadReceipt(
      messageId: json['message_id'] as String,
      readerPeerId: json['reader'] as String,
      timestamp: DateTime.fromMillisecondsSinceEpoch(json['timestamp'] as int),
    );
  }
}

/// Manages delivery tracking for all outgoing messages.
class DeliveryTracker {
  final _statuses = <String, DeliveryStatus>{};

  /// Track a new outgoing message.
  DeliveryStatus track(String messageId) {
    final status = DeliveryStatus(messageId: messageId);
    _statuses[messageId] = status;
    return status;
  }

  /// Get status for a message.
  DeliveryStatus? getStatus(String messageId) => _statuses[messageId];

  /// Process an incoming read receipt.
  void processReceipt(ReadReceipt receipt) {
    final status = _statuses[receipt.messageId];
    if (status != null) {
      status.markRead();
    }
  }

  /// Mark a message as sent.
  void markSent(String messageId) {
    _statuses[messageId]?.markSent();
  }

  /// Mark a message as delivered.
  void markDelivered(String messageId) {
    _statuses[messageId]?.markDelivered();
  }

  /// Get all pending/failed messages for retry.
  List<DeliveryStatus> getPendingMessages() {
    return _statuses.values
        .where(
          (s) =>
              s.state == DeliveryState.pending ||
              s.state == DeliveryState.failed,
        )
        .toList();
  }

  /// Number of tracked messages.
  int get trackedCount => _statuses.length;

  /// Clear all tracking.
  void clear() => _statuses.clear();
}
