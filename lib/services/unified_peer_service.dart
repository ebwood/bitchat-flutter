/// Unified peer service — merges BLE and Nostr peer views.
///
/// Matches Android `MeshDelegateHandler.kt` concept:
/// - Single list of all known peers regardless of transport
/// - Transport type indicator (BLE, Nostr, or both)
/// - Connection quality metrics
/// - Smart network activation toggle

/// Transport type for a peer connection.
enum PeerTransport { ble, nostr, both }

/// Connection quality level.
enum ConnectionQuality { excellent, good, fair, poor, disconnected }

/// A unified peer representation across transports.
class UnifiedPeer {
  UnifiedPeer({
    required this.peerId,
    this.nickname,
    this.transport = PeerTransport.nostr,
    this.quality = ConnectionQuality.good,
    this.rssi,
    this.lastSeen,
    this.isOnline = true,
  });

  final String peerId;
  String? nickname;
  PeerTransport transport;
  ConnectionQuality quality;
  int? rssi; // BLE signal strength
  DateTime? lastSeen;
  bool isOnline;

  String get displayName =>
      nickname ?? '${peerId.substring(0, peerId.length.clamp(0, 8))}';

  /// Quality as 0.0–1.0 for UI bars.
  double get qualityScore {
    switch (quality) {
      case ConnectionQuality.excellent:
        return 1.0;
      case ConnectionQuality.good:
        return 0.75;
      case ConnectionQuality.fair:
        return 0.5;
      case ConnectionQuality.poor:
        return 0.25;
      case ConnectionQuality.disconnected:
        return 0.0;
    }
  }
}

/// Network activation mode.
enum NetworkMode {
  /// All transports active.
  all,

  /// BLE only (no internet needed).
  bleOnly,

  /// Nostr only (relay-based).
  nostrOnly,

  /// Auto — prefer BLE when available, fallback to Nostr.
  auto,
}

/// Manages unified peer list and network activation.
class UnifiedPeerService {
  final _peers = <String, UnifiedPeer>{};
  NetworkMode _networkMode = NetworkMode.auto;

  NetworkMode get networkMode => _networkMode;

  /// Set network mode.
  void setNetworkMode(NetworkMode mode) {
    _networkMode = mode;
  }

  /// Add or update a peer.
  UnifiedPeer upsertPeer({
    required String peerId,
    String? nickname,
    PeerTransport? transport,
    ConnectionQuality? quality,
    int? rssi,
  }) {
    final existing = _peers[peerId];
    if (existing != null) {
      if (nickname != null) existing.nickname = nickname;
      if (transport != null) {
        // Merge transports
        if (existing.transport != transport &&
            existing.transport != PeerTransport.both &&
            transport != PeerTransport.both) {
          existing.transport = PeerTransport.both;
        } else {
          existing.transport = transport;
        }
      }
      if (quality != null) existing.quality = quality;
      if (rssi != null) existing.rssi = rssi;
      existing.lastSeen = DateTime.now();
      existing.isOnline = true;
      return existing;
    }

    final peer = UnifiedPeer(
      peerId: peerId,
      nickname: nickname,
      transport: transport ?? PeerTransport.nostr,
      quality: quality ?? ConnectionQuality.good,
      rssi: rssi,
      lastSeen: DateTime.now(),
    );
    _peers[peerId] = peer;
    return peer;
  }

  /// Mark a peer as offline.
  void markOffline(String peerId) {
    final peer = _peers[peerId];
    if (peer != null) {
      peer.isOnline = false;
      peer.quality = ConnectionQuality.disconnected;
    }
  }

  /// Remove a peer.
  void removePeer(String peerId) {
    _peers.remove(peerId);
  }

  /// Get all peers.
  List<UnifiedPeer> get allPeers => _peers.values.toList();

  /// Get online peers only.
  List<UnifiedPeer> get onlinePeers =>
      _peers.values.where((p) => p.isOnline).toList();

  /// Get BLE peers.
  List<UnifiedPeer> get blePeers => _peers.values
      .where(
        (p) =>
            p.transport == PeerTransport.ble ||
            p.transport == PeerTransport.both,
      )
      .toList();

  /// Get Nostr peers.
  List<UnifiedPeer> get nostrPeers => _peers.values
      .where(
        (p) =>
            p.transport == PeerTransport.nostr ||
            p.transport == PeerTransport.both,
      )
      .toList();

  /// Total peer count.
  int get peerCount => _peers.length;

  /// Online peer count.
  int get onlinePeerCount => onlinePeers.length;

  /// Whether BLE should be active based on network mode.
  bool get isBleActive =>
      _networkMode == NetworkMode.all ||
      _networkMode == NetworkMode.bleOnly ||
      _networkMode == NetworkMode.auto;

  /// Whether Nostr should be active based on network mode.
  bool get isNostrActive =>
      _networkMode == NetworkMode.all ||
      _networkMode == NetworkMode.nostrOnly ||
      _networkMode == NetworkMode.auto;

  /// Clear all peers.
  void reset() {
    _peers.clear();
  }
}
