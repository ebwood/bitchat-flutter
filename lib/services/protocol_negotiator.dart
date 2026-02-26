import 'dart:typed_data';

/// Protocol version negotiation for BitChat peers.
///
/// When two peers connect, they exchange version info to determine
/// the highest mutually supported protocol version and feature set.
class ProtocolNegotiator {
  ProtocolNegotiator({
    this.localVersion = currentVersion,
    Set<ProtocolFeature>? supportedFeatures,
  }) : supportedFeatures = supportedFeatures ?? ProtocolFeature.values.toSet();

  /// Current protocol version.
  static const int currentVersion = 2;

  /// Minimum supported version.
  static const int minVersion = 1;

  final int localVersion;
  final Set<ProtocolFeature> supportedFeatures;

  /// Build a version negotiation message (sent on connect).
  Uint8List buildVersionMessage() {
    // Format: [magic:2][version:1][minVersion:1][featureFlags:2][reserved:2]
    final data = ByteData(8);
    data.setUint16(0, 0xBC01); // BitChat magic
    data.setUint8(2, localVersion);
    data.setUint8(3, minVersion);
    data.setUint16(4, _encodeFeatures());
    data.setUint16(6, 0); // reserved
    return data.buffer.asUint8List();
  }

  /// Parse a version message from a peer and negotiate.
  NegotiationResult negotiate(Uint8List peerMessage) {
    if (peerMessage.length < 8) {
      return NegotiationResult.failed('Message too short');
    }

    final data = ByteData.sublistView(peerMessage);

    // Check magic
    final magic = data.getUint16(0);
    if (magic != 0xBC01) {
      return NegotiationResult.failed(
        'Invalid magic: 0x${magic.toRadixString(16)}',
      );
    }

    final peerVersion = data.getUint8(2);
    final peerMinVersion = data.getUint8(3);
    final peerFeatureFlags = data.getUint16(4);

    // Check version compatibility
    if (localVersion < peerMinVersion || peerVersion < minVersion) {
      return NegotiationResult.failed(
        'Incompatible versions: local=$localVersion, peer=$peerVersion '
        '(peerMin=$peerMinVersion, localMin=$minVersion)',
      );
    }

    // Use the lower of the two versions
    final negotiatedVersion = localVersion < peerVersion
        ? localVersion
        : peerVersion;

    // Intersect features
    final localFlags = _encodeFeatures();
    final commonFlags = localFlags & peerFeatureFlags;
    final commonFeatures = _decodeFeatures(commonFlags);

    return NegotiationResult.success(
      version: negotiatedVersion,
      features: commonFeatures,
    );
  }

  int _encodeFeatures() {
    int flags = 0;
    for (final f in supportedFeatures) {
      flags |= (1 << f.index);
    }
    return flags;
  }

  static Set<ProtocolFeature> _decodeFeatures(int flags) {
    final features = <ProtocolFeature>{};
    for (final f in ProtocolFeature.values) {
      if (flags & (1 << f.index) != 0) {
        features.add(f);
      }
    }
    return features;
  }
}

/// Supported protocol features (bit-flags).
enum ProtocolFeature {
  compression, // 0: zlib compression
  noiseEncryption, // 1: Noise XX handshake
  meshRelay, // 2: TTL-based mesh relay
  storeForward, // 3: store & forward
  coverTraffic, // 4: dummy packet cover traffic
  nostr, // 5: Nostr relay bridge
  fileTransfer, // 6: chunked file transfer
  voiceNote, // 7: voice note encoding
}

/// Result of a version negotiation.
class NegotiationResult {
  NegotiationResult.success({required this.version, required this.features})
    : compatible = true,
      error = null;

  NegotiationResult.failed(this.error)
    : compatible = false,
      version = 0,
      features = {};

  final bool compatible;
  final int version;
  final Set<ProtocolFeature> features;
  final String? error;

  bool hasFeature(ProtocolFeature f) => features.contains(f);

  @override
  String toString() => compatible
      ? 'NegotiationResult(v$version, features=${features.map((f) => f.name).join(",")})'
      : 'NegotiationResult(FAILED: $error)';
}
