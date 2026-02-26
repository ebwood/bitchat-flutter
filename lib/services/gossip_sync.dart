import 'package:bitchat/services/gcs_filter.dart';

/// Gossip sync protocol — exchange message filters to sync missed messages.
///
/// Matches iOS `GossipSyncManager.swift`, `RequestSyncManager.swift`,
/// `SyncTypeFlags.swift`.

/// What types of data get synced between peers.
class SyncTypeFlags {
  const SyncTypeFlags({
    this.messages = true,
    this.presence = true,
    this.files = false,
    this.channels = true,
  });

  final bool messages;
  final bool presence;
  final bool files;
  final bool channels;

  /// Encode to a single byte bitmask.
  int toByte() {
    var b = 0;
    if (messages) b |= 0x01;
    if (presence) b |= 0x02;
    if (files) b |= 0x04;
    if (channels) b |= 0x08;
    return b;
  }

  factory SyncTypeFlags.fromByte(int b) {
    return SyncTypeFlags(
      messages: (b & 0x01) != 0,
      presence: (b & 0x02) != 0,
      files: (b & 0x04) != 0,
      channels: (b & 0x08) != 0,
    );
  }

  /// Default: sync everything except files.
  static const standard = SyncTypeFlags();

  /// Sync everything including files.
  static const full = SyncTypeFlags(files: true);

  @override
  String toString() =>
      'SyncTypeFlags(msg=${messages ? 1 : 0}, pres=${presence ? 1 : 0}, '
      'file=${files ? 1 : 0}, chan=${channels ? 1 : 0})';
}

/// A sync request — "here's what I have, send me what I'm missing".
class SyncRequest {
  const SyncRequest({
    required this.senderPeerId,
    required this.filter,
    required this.syncFlags,
    required this.timestamp,
  });

  /// Peer sending the request.
  final String senderPeerId;

  /// GCS filter of message IDs the sender already has.
  final GcsFilter filter;

  /// What to sync.
  final SyncTypeFlags syncFlags;

  /// Request timestamp.
  final DateTime timestamp;
}

/// A specific message request by ID.
class MessageRequest {
  const MessageRequest({
    required this.messageIds,
    required this.requesterPeerId,
  });

  final List<String> messageIds;
  final String requesterPeerId;
}

/// Gossip sync manager — coordinates filter exchange and message sync.
class GossipSyncManager {
  GossipSyncManager();

  /// Known message IDs (for building outgoing filters).
  final _knownMessageIds = <String>{};

  /// Pending message requests from peers.
  final _pendingRequests = <MessageRequest>[];

  /// Add a known message ID.
  void addKnownMessage(String messageId) {
    _knownMessageIds.add(messageId);
  }

  /// Add multiple known message IDs.
  void addKnownMessages(Iterable<String> messageIds) {
    _knownMessageIds.addAll(messageIds);
  }

  /// Build a GCS filter of all known messages for outgoing sync.
  GcsFilter buildFilter() {
    final filter = GcsFilter();
    filter.build(_knownMessageIds.toList());
    return filter;
  }

  /// Create a sync request to send to peers.
  SyncRequest createSyncRequest(String myPeerId) {
    return SyncRequest(
      senderPeerId: myPeerId,
      filter: buildFilter(),
      syncFlags: SyncTypeFlags.standard,
      timestamp: DateTime.now(),
    );
  }

  /// Process an incoming sync request — figure out which messages
  /// we have that the peer is missing.
  List<String> findMissingMessages(SyncRequest request) {
    final missing = <String>[];
    for (final id in _knownMessageIds) {
      if (!request.filter.mightContain(id)) {
        missing.add(id);
      }
    }
    return missing;
  }

  /// Queue a message request from a peer.
  void addMessageRequest(MessageRequest request) {
    _pendingRequests.add(request);
  }

  /// Get and clear pending requests.
  List<MessageRequest> drainPendingRequests() {
    final requests = List<MessageRequest>.from(_pendingRequests);
    _pendingRequests.clear();
    return requests;
  }

  /// Number of known messages.
  int get knownMessageCount => _knownMessageIds.length;

  /// Clear all state.
  void reset() {
    _knownMessageIds.clear();
    _pendingRequests.clear();
  }
}
