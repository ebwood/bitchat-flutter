import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../models/peer_id.dart';
import '../protocol/binary_protocol.dart';
import '../models/bitchat_packet.dart';

/// BLE service constants matching iOS/Android.
class BLEConstants {
  BLEConstants._();

  /// Service and characteristic UUIDs.
  static final serviceUUID = Guid('F47B5E2D-4A9E-4C5A-9B3F-8E1D2C3A4B5C');
  static final characteristicUUID = Guid(
    'A1B2C3D4-E5F6-4A5B-8C9D-0E1F2A3B4C5D',
  );

  /// Fragment size defaults.
  static const int defaultFragmentSize = 182;
  static const int bleMaxMTU = 512;
  static const int defaultTTL = 3;

  /// Scan/connect timing.
  static const Duration scanTimeout = Duration(seconds: 10);
  static const Duration connectTimeout = Duration(seconds: 30);
  static const Duration maintenanceInterval = Duration(seconds: 30);
  static const Duration announceMinInterval = Duration(seconds: 5);
  static const Duration peerStaleTimeout = Duration(minutes: 5);
}

/// Information about a discovered or connected BLE peer.
class BLEPeerInfo {
  BLEPeerInfo({
    required this.deviceId,
    required this.peerID,
    this.nickname = 'anon',
    this.isConnected = false,
    this.rssi = -100,
    DateTime? lastSeen,
  }) : lastSeen = lastSeen ?? DateTime.now();

  final String deviceId;
  final PeerID peerID;
  String nickname;
  bool isConnected;
  int rssi;
  DateTime lastSeen;

  /// Whether this peer is stale (not seen recently).
  bool get isStale =>
      DateTime.now().difference(lastSeen) > BLEConstants.peerStaleTimeout;
}

/// Status of the BLE mesh service.
enum BLEMeshStatus { idle, scanning, connected, error }

/// Callback for received messages.
typedef BLEMessageHandler =
    void Function(BitchatPacket packet, String senderDeviceId);

/// Core BLE mesh service.
///
/// Manages scanning for peers, connecting, service/characteristic discovery,
/// message sending via write, and message receiving via notifications.
///
/// Note: flutter_blue_plus only supports the Central role. Peripheral
/// (advertising) role requires platform channels — stubbed for now.
class BLEMeshService {
  BLEMeshService({required this.myPeerID, this.nickname = 'anon'});

  final PeerID myPeerID;
  String nickname;

  // --- State ---
  final Map<String, BLEPeerInfo> _peers = {};
  final Map<String, BluetoothDevice> _connectedDevices = {};
  final Map<String, BluetoothCharacteristic> _characteristics = {};
  final Set<String> _seenMessageIds = {};
  final Set<String> _connectingDevices = {}; // Currently attempting connection
  final Map<String, DateTime> _failedDevices = {}; // Cooldown after failure

  BLEMeshStatus _status = BLEMeshStatus.idle;
  BLEMeshStatus get status => _status;
  bool _disposed = false;

  StreamSubscription? _scanSubscription;
  Timer? _maintenanceTimer;

  // --- Event streams ---
  final _statusController = StreamController<BLEMeshStatus>.broadcast();
  final _peerController = StreamController<List<BLEPeerInfo>>.broadcast();
  final _packetController = StreamController<BitchatPacket>.broadcast();

  Stream<BLEMeshStatus> get statusStream => _statusController.stream;
  Stream<List<BLEPeerInfo>> get peersStream => _peerController.stream;
  Stream<BitchatPacket> get packetStream => _packetController.stream;

  /// Current peer list.
  List<BLEPeerInfo> get peers => _peers.values.toList();

  /// Number of connected peers.
  int get connectedPeerCount =>
      _peers.values.where((p) => p.isConnected).length;

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  /// Start scanning and advertising.
  Future<void> start() async {
    // Check Bluetooth state — skip `unknown` on macOS
    try {
      final state = await FlutterBluePlus.adapterState
          .where((s) => s != BluetoothAdapterState.unknown)
          .first
          .timeout(const Duration(seconds: 5));
      if (state != BluetoothAdapterState.on) {
        _updateStatus(BLEMeshStatus.error);
        return;
      }
    } catch (_) {
      _updateStatus(BLEMeshStatus.error);
      return;
    }

    _updateStatus(BLEMeshStatus.scanning);

    // Start scanning for peers advertising our service UUID
    _scanSubscription = FlutterBluePlus.onScanResults.listen((results) {
      for (final r in results) {
        _handleScanResult(r);
      }
    }, onError: (e) => _updateStatus(BLEMeshStatus.error));

    await FlutterBluePlus.startScan(
      withServices: [BLEConstants.serviceUUID],
      timeout: BLEConstants.scanTimeout,
      continuousUpdates: true,
    );

    // Periodic maintenance (cleanup stale peers, re-scan)
    _maintenanceTimer = Timer.periodic(
      BLEConstants.maintenanceInterval,
      (_) => _performMaintenance(),
    );
  }

  /// Restart BLE scanning (e.g. after a connection attempt paused it).
  void _restartScan() {
    if (_disposed) return;
    FlutterBluePlus.startScan(
      withServices: [BLEConstants.serviceUUID],
      timeout: BLEConstants.scanTimeout,
      continuousUpdates: true,
    );
  }

  /// Stop all BLE operations.
  Future<void> stop() async {
    _maintenanceTimer?.cancel();
    _scanSubscription?.cancel();

    await FlutterBluePlus.stopScan();

    // Disconnect all
    for (final device in _connectedDevices.values) {
      await device.disconnect();
    }
    _connectedDevices.clear();
    _characteristics.clear();
    _connectingDevices.clear();
    _failedDevices.clear();
    _peers.clear();
    _seenMessageIds.clear();

    if (!_disposed) {
      _updateStatus(BLEMeshStatus.idle);
      _peerController.add([]);
    }
  }

  /// Dispose all resources.
  void dispose() {
    _disposed = true;
    stop();
    _statusController.close();
    _peerController.close();
    _packetController.close();
  }

  // ---------------------------------------------------------------------------
  // Scanning & Connection
  // ---------------------------------------------------------------------------

  void _handleScanResult(ScanResult result) {
    final deviceId = result.device.remoteId.str;
    final isNew = !_peers.containsKey(deviceId);

    // Update or create peer info
    if (_peers.containsKey(deviceId)) {
      _peers[deviceId]!
        ..rssi = result.rssi
        ..lastSeen = DateTime.now();
    } else {
      _peers[deviceId] = BLEPeerInfo(
        deviceId: deviceId,
        peerID: PeerID(deviceId.substring(0, 16).padRight(16, '0')),
        rssi: result.rssi,
      );
    }

    // Only log first discovery to reduce noise
    if (isNew) {
      debugPrint('[ble-mesh] 📡 New device: $deviceId  rssi=${result.rssi}');
    }

    _peerController.add(peers);

    // Auto-connect if not already connected or connecting
    if (_connectedDevices.containsKey(deviceId)) return;

    if (_connectingDevices.contains(deviceId)) return; // already attempting

    // Skip if recently failed (30s cooldown)
    final failedAt = _failedDevices[deviceId];
    if (failedAt != null) {
      final ago = DateTime.now().difference(failedAt).inSeconds;
      if (ago < 30) {
        if (isNew) {
          debugPrint(
            '[ble-mesh] ⏳ Skipping $deviceId — failed ${ago}s ago, cooldown ${30 - ago}s',
          );
        }
        return;
      }
      // Cooldown expired — allow retry
      debugPrint('[ble-mesh] 🔄 Retrying $deviceId after 30s cooldown');
    }

    _connectToDevice(result.device);
  }

  Future<void> _connectToDevice(BluetoothDevice device) async {
    final deviceId = device.remoteId.str;

    try {
      _connectingDevices.add(deviceId);
      debugPrint('[ble-mesh] Connecting to $deviceId ...');

      // macOS CoreBluetooth cannot reliably connect while scanning.
      // Pause scan → connect → resume scan.
      await FlutterBluePlus.stopScan();
      await Future.delayed(const Duration(milliseconds: 200));

      await device.connect(
        license: License.free,
        timeout: BLEConstants.connectTimeout,
        autoConnect: false,
      );

      debugPrint('[ble-mesh] Connected to $deviceId — requesting MTU');

      // Negotiate MTU before service discovery (matching Android flow)
      try {
        await device.requestMtu(512);
      } catch (_) {
        debugPrint(
          '[ble-mesh] MTU negotiation failed for $deviceId, continuing',
        );
      }

      _connectingDevices.remove(deviceId);
      _failedDevices.remove(deviceId);
      _connectedDevices[deviceId] = device;

      // Discover services
      debugPrint('[ble-mesh] Discovering services on $deviceId ...');
      final services = await device.discoverServices();
      for (final service in services) {
        if (service.serviceUuid == BLEConstants.serviceUUID) {
          debugPrint('[ble-mesh] Found bitchat service on $deviceId');
          for (final char in service.characteristics) {
            if (char.characteristicUuid == BLEConstants.characteristicUUID) {
              _characteristics[deviceId] = char;

              // Subscribe to notifications
              await char.setNotifyValue(true);
              char.onValueReceived.listen((data) {
                _handleReceivedData(Uint8List.fromList(data), deviceId);
              });

              // Update peer as connected
              _peers[deviceId]?.isConnected = true;
              _peerController.add(peers);
              _updateStatus(BLEMeshStatus.connected);
              debugPrint('[ble-mesh] ✅ Fully connected to $deviceId');
            }
          }
        }
      }

      // Listen for disconnection
      device.connectionState.listen((state) {
        if (state == BluetoothConnectionState.disconnected) {
          _handleDisconnection(deviceId);
        }
      });
    } catch (e) {
      // Connection failed — record failure time for cooldown
      debugPrint('[ble-mesh] ❌ Connection failed to $deviceId: $e');
      _connectingDevices.remove(deviceId);
      _failedDevices[deviceId] = DateTime.now();
      _connectedDevices.remove(deviceId);
    } finally {
      // Always restart scanning after connection attempt
      _restartScan();
    }
  }

  void _handleDisconnection(String deviceId) {
    _connectedDevices.remove(deviceId);
    _characteristics.remove(deviceId);
    _peers[deviceId]?.isConnected = false;
    _peerController.add(peers);

    if (connectedPeerCount == 0) {
      _updateStatus(BLEMeshStatus.scanning);
    }
  }

  // ---------------------------------------------------------------------------
  // Message sending
  // ---------------------------------------------------------------------------

  /// Send a packet to all connected peers (broadcast).
  Future<void> broadcastPacket(BitchatPacket packet) async {
    final data = BinaryProtocol.encode(packet);
    if (data == null) return;
    final fragments = _fragment(data);

    for (final entry in _characteristics.entries) {
      for (final fragment in fragments) {
        try {
          await entry.value.write(fragment.toList(), withoutResponse: true);
        } catch (_) {
          // Write failed — peer may have disconnected
        }
      }
    }
  }

  /// Send a packet to a specific peer.
  Future<bool> sendPacketToPeer(BitchatPacket packet, String deviceId) async {
    final char = _characteristics[deviceId];
    if (char == null) return false;

    final data = BinaryProtocol.encode(packet);
    if (data == null) return false;
    final fragments = _fragment(data);

    try {
      for (final fragment in fragments) {
        await char.write(fragment.toList(), withoutResponse: true);
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // Message receiving & relay
  // ---------------------------------------------------------------------------

  /// Reassembly buffers for fragmented messages.
  final Map<String, List<Uint8List>> _reassemblyBuffers = {};

  void _handleReceivedData(Uint8List data, String senderDeviceId) {
    if (data.isEmpty) return;

    // Check fragment header
    if (_isFragment(data)) {
      _handleFragment(data, senderDeviceId);
      return;
    }

    _processCompleteMessage(data, senderDeviceId);
  }

  void _processCompleteMessage(Uint8List data, String senderDeviceId) {
    try {
      final packet = BinaryProtocol.decode(data);
      if (packet == null) return;

      // Deduplication
      final senderHex = packet.senderID
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join();
      final dedupId = '$senderHex-${packet.timestamp}-${packet.type}';
      if (_seenMessageIds.contains(dedupId)) return;
      _seenMessageIds.add(dedupId);

      // Cap dedup cache
      if (_seenMessageIds.length > 5000) {
        _seenMessageIds.remove(_seenMessageIds.first);
      }

      // Emit to listeners
      _packetController.add(packet);

      // Relay with TTL decrement
      if (packet.ttl > 1) {
        final relayPacket = BitchatPacket(
          type: packet.type,
          senderID: packet.senderID,
          recipientID: packet.recipientID,
          timestamp: packet.timestamp,
          payload: packet.payload,
          signature: packet.signature,
          ttl: packet.ttl - 1,
        );
        _relayPacket(relayPacket, excludeDeviceId: senderDeviceId);
      }
    } catch (_) {
      // Malformed packet
    }
  }

  /// Relay a packet to all peers except the sender.
  Future<void> _relayPacket(
    BitchatPacket packet, {
    required String excludeDeviceId,
  }) async {
    final data = BinaryProtocol.encode(packet);
    if (data == null) return;
    final fragments = _fragment(data);

    for (final entry in _characteristics.entries) {
      if (entry.key == excludeDeviceId) continue;
      for (final fragment in fragments) {
        try {
          await entry.value.write(fragment.toList(), withoutResponse: true);
        } catch (_) {}
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Fragmentation
  // ---------------------------------------------------------------------------

  /// Fragment header: [0xBB] [fragment_index:2] [total:2] [message_id:4]
  static const int _fragmentHeaderSize = 9;

  List<Uint8List> _fragment(Uint8List data) {
    final chunkSize = BLEConstants.defaultFragmentSize - _fragmentHeaderSize;
    if (data.length <= chunkSize) return [data];

    final totalFragments = (data.length / chunkSize).ceil();
    final messageId = data.length ^ DateTime.now().millisecondsSinceEpoch;
    final fragments = <Uint8List>[];

    for (var i = 0; i < totalFragments; i++) {
      final start = i * chunkSize;
      final end = (start + chunkSize > data.length)
          ? data.length
          : start + chunkSize;
      final chunk = data.sublist(start, end);

      final header = ByteData(9);
      header.setUint8(0, 0xBB); // fragment marker
      header.setUint16(1, i);
      header.setUint16(3, totalFragments);
      header.setUint32(5, messageId);

      final fragment = Uint8List(_fragmentHeaderSize + chunk.length);
      fragment.setRange(0, _fragmentHeaderSize, header.buffer.asUint8List());
      fragment.setRange(_fragmentHeaderSize, fragment.length, chunk);
      fragments.add(fragment);
    }
    return fragments;
  }

  bool _isFragment(Uint8List data) =>
      data.isNotEmpty && data[0] == 0xBB && data.length > _fragmentHeaderSize;

  void _handleFragment(Uint8List data, String senderDeviceId) {
    final header = ByteData.sublistView(data, 0, _fragmentHeaderSize);
    final index = header.getUint16(1);
    final total = header.getUint16(3);
    final messageId = header.getUint32(5);
    final key = '$senderDeviceId-$messageId';
    final payload = data.sublist(_fragmentHeaderSize);

    _reassemblyBuffers.putIfAbsent(key, () => List.filled(total, Uint8List(0)));
    final buffer = _reassemblyBuffers[key]!;

    if (index < total) {
      buffer[index] = payload;
    }

    // Check if complete
    if (buffer.every((b) => b.isNotEmpty)) {
      final complete = Uint8List.fromList(buffer.expand((b) => b).toList());
      _reassemblyBuffers.remove(key);
      _processCompleteMessage(complete, senderDeviceId);
    }
  }

  // ---------------------------------------------------------------------------
  // Maintenance
  // ---------------------------------------------------------------------------

  void _performMaintenance() {
    // Remove stale peers
    final staleKeys = _peers.entries
        .where((e) => e.value.isStale && !e.value.isConnected)
        .map((e) => e.key)
        .toList();
    for (final key in staleKeys) {
      _peers.remove(key);
    }

    // Clean old reassembly buffers (>30s old)
    _reassemblyBuffers.removeWhere((key, _) => true); // simplified

    if (staleKeys.isNotEmpty) {
      _peerController.add(peers);
    }

    // Restart scan if no peers connected
    if (connectedPeerCount == 0 && _status != BLEMeshStatus.error) {
      FlutterBluePlus.startScan(
        withServices: [BLEConstants.serviceUUID],
        timeout: BLEConstants.scanTimeout,
        continuousUpdates: true,
      );
    }
  }

  void _updateStatus(BLEMeshStatus newStatus) {
    if (_status != newStatus) {
      _status = newStatus;
      if (!_disposed) _statusController.add(newStatus);
    }
  }
}
