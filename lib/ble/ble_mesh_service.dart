import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../models/peer_id.dart';
import '../protocol/binary_protocol.dart';
import '../models/bitchat_packet.dart';
import 'ble_native_channel.dart';

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
/// On macOS, uses native CoreBluetooth via platform channel (BLEPlugin.swift).
/// On iOS/Android, uses flutter_blue_plus.
class BLEMeshService {
  BLEMeshService({required this.myPeerID, this.nickname = 'anon'});

  final PeerID myPeerID;
  String nickname;

  /// Whether we're using the native macOS BLE channel.
  bool get _useNative => BLENativeChannel.isSupported;
  BLENativeChannel get _native => BLENativeChannel.instance;

  // --- State ---
  final Map<String, BLEPeerInfo> _peers = {};
  final Map<String, BluetoothDevice> _connectedDevices = {}; // FBP only
  final Map<String, BluetoothCharacteristic> _fbpCharacteristics =
      {}; // FBP only
  final Set<String> _nativeConnected = {}; // Native only
  final Set<String> _seenMessageIds = {};
  final Set<String> _connectingDevices = {};
  final Map<String, DateTime> _failedDevices = {};

  BLEMeshStatus _status = BLEMeshStatus.idle;
  BLEMeshStatus get status => _status;
  bool _disposed = false;

  StreamSubscription? _scanSubscription;
  StreamSubscription? _connectionSubscription;
  StreamSubscription? _dataSubscription;
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

  /// Start scanning and connecting.
  Future<void> start() async {
    if (_useNative) {
      await _startNative();
    } else {
      await _startFBP();
    }
  }

  /// Stop all BLE operations.
  Future<void> stop() async {
    _maintenanceTimer?.cancel();
    _scanSubscription?.cancel();
    _connectionSubscription?.cancel();
    _dataSubscription?.cancel();

    if (_useNative) {
      await _native.stopScan();
      await _native.disconnectAll();
      _nativeConnected.clear();
    } else {
      await FlutterBluePlus.stopScan();
      for (final device in _connectedDevices.values) {
        await device.disconnect();
      }
      _connectedDevices.clear();
      _fbpCharacteristics.clear();
    }

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
  // Native macOS path
  // ---------------------------------------------------------------------------

  Future<void> _startNative() async {
    final adapterOn = await _native.getAdapterState();
    if (!adapterOn) {
      debugPrint('[ble-mesh] Native: Bluetooth not on, waiting...');
      _native.setMethodCallHandler(
        onAdapterState: (state) {
          debugPrint('[ble-mesh] Native: adapter state → $state');
          if (state == 'on' && _status != BLEMeshStatus.scanning) {
            _startNativeScan();
          }
        },
        onPeerFound: _handleNativePeerDiscovered,
      );
      return;
    }

    _startNativeScan();
  }

  /// Called when the native plugin decodes an AnnouncementPacket from a peer.
  void _handleNativePeerDiscovered(
    String peerID,
    String peerNickname,
    String deviceId,
  ) {
    debugPrint(
      '[ble-mesh] 👋 Peer discovered: $peerNickname ($peerID) via $deviceId',
    );
    if (_peers.containsKey(deviceId)) {
      _peers[deviceId]!
        ..nickname = peerNickname
        ..lastSeen = DateTime.now();
    } else {
      _peers[deviceId] = BLEPeerInfo(
        deviceId: deviceId,
        peerID: PeerID(peerID),
        nickname: peerNickname,
      );
    }
    _peerController.add(peers);
  }

  void _startNativeScan() async {
    debugPrint('[ble-mesh] Native: starting scan');
    _updateStatus(BLEMeshStatus.scanning);

    // Set nickname on native side
    await _native.setNickname(nickname);

    // Set up method call handler for peer discovery
    _native.setMethodCallHandler(
      onAdapterState: (state) {
        debugPrint('[ble-mesh] Native: adapter state → $state');
      },
      onPeerFound: _handleNativePeerDiscovered,
    );

    // Scan results
    _scanSubscription = _native.scanResults.listen((result) {
      _handleNativeScanResult(result);
    });

    // Connection events
    _connectionSubscription = _native.connectionEvents.listen((event) {
      _handleNativeConnectionEvent(event);
    });

    // Data events — native plugin sends parsed BLEMessageEvent for chat msgs
    _dataSubscription = _native.dataEvents.listen((event) {
      if (event is BLEMessageEvent) {
        // Already decoded by native BinaryProtocol — emit as BitchatPacket
        final msg = event;
        if (!msg.isOwnMessage) {
          final payloadBytes = Uint8List.fromList(msg.content.codeUnits);
          final senderBytes = _hexStringToBytes(msg.senderPeerID);
          final packet = BitchatPacket(
            type: 0x02, // message
            senderID: senderBytes,
            timestamp: msg.timestamp.millisecondsSinceEpoch,
            payload: payloadBytes,
            ttl: 0, // already processed
          );
          _packetController.add(packet);
        }
      } else {
        // Legacy raw data
        _handleReceivedData(event.data, event.deviceId);
      }
    });

    await _native.startScan();

    // Periodic maintenance
    _maintenanceTimer = Timer.periodic(
      BLEConstants.maintenanceInterval,
      (_) => _performMaintenance(),
    );
  }

  /// Convert hex string to bytes.
  Uint8List _hexStringToBytes(String hex) {
    final result = <int>[];
    for (var i = 0; i + 1 < hex.length; i += 2) {
      result.add(int.parse(hex.substring(i, i + 2), radix: 16));
    }
    return Uint8List.fromList(result);
  }

  void _handleNativeScanResult(BLEScanResult result) {
    final deviceId = result.deviceId;
    final isNew = !_peers.containsKey(deviceId);

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

    if (isNew) {
      debugPrint(
        '[ble-mesh] 📡 Native: new device $deviceId rssi=${result.rssi}',
      );
    }

    _peerController.add(peers);

    // Auto-connect if not already connected or connecting
    if (_nativeConnected.contains(deviceId)) return;
    if (_connectingDevices.contains(deviceId)) return;

    // Skip if recently failed (30s cooldown)
    final failedAt = _failedDevices[deviceId];
    if (failedAt != null) {
      final ago = DateTime.now().difference(failedAt).inSeconds;
      if (ago < 30) return;
      debugPrint('[ble-mesh] 🔄 Native: retrying $deviceId after cooldown');
    }

    _connectingDevices.add(deviceId);
    debugPrint('[ble-mesh] Native: connecting to $deviceId ...');
    _native.connect(deviceId).catchError((e) {
      debugPrint('[ble-mesh] ❌ Native: connect call failed: $e');
      _connectingDevices.remove(deviceId);
      _failedDevices[deviceId] = DateTime.now();
    });
  }

  void _handleNativeConnectionEvent(BLEConnectionEvent event) {
    final deviceId = event.deviceId;
    debugPrint(
      '[ble-mesh] Native: connection event $deviceId → ${event.state}',
    );

    switch (event.state) {
      case 'connected':
        // Connection established, waiting for service/characteristic discovery
        _connectingDevices.remove(deviceId);
        break;

      case 'ready':
        // Fully ready — service discovered, notifications subscribed
        _connectingDevices.remove(deviceId);
        _failedDevices.remove(deviceId);
        _nativeConnected.add(deviceId);
        _peers[deviceId]?.isConnected = true;
        _peerController.add(peers);
        _updateStatus(BLEMeshStatus.connected);
        debugPrint('[ble-mesh] ✅ Native: fully connected to $deviceId');
        break;

      case 'disconnected':
        _nativeConnected.remove(deviceId);
        _connectingDevices.remove(deviceId);
        _peers[deviceId]?.isConnected = false;
        _peerController.add(peers);
        if (connectedPeerCount == 0) {
          _updateStatus(BLEMeshStatus.scanning);
        }
        break;

      case 'failed':
      case 'timeout':
        _connectingDevices.remove(deviceId);
        _failedDevices[deviceId] = DateTime.now();
        debugPrint('[ble-mesh] ❌ Native: ${event.state} for $deviceId');
        break;
    }
  }

  // ---------------------------------------------------------------------------
  // flutter_blue_plus path (iOS/Android)
  // ---------------------------------------------------------------------------

  Future<void> _startFBP() async {
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

    _scanSubscription = FlutterBluePlus.onScanResults.listen((results) {
      for (final r in results) {
        _handleFBPScanResult(r);
      }
    }, onError: (e) => _updateStatus(BLEMeshStatus.error));

    await FlutterBluePlus.startScan(
      withServices: [BLEConstants.serviceUUID],
      timeout: BLEConstants.scanTimeout,
      continuousUpdates: true,
    );

    _maintenanceTimer = Timer.periodic(
      BLEConstants.maintenanceInterval,
      (_) => _performMaintenance(),
    );
  }

  void _restartScanFBP() {
    if (_disposed) return;
    FlutterBluePlus.startScan(
      withServices: [BLEConstants.serviceUUID],
      timeout: BLEConstants.scanTimeout,
      continuousUpdates: true,
    );
  }

  void _handleFBPScanResult(ScanResult result) {
    final deviceId = result.device.remoteId.str;
    final isNew = !_peers.containsKey(deviceId);

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

    if (isNew) {
      debugPrint('[ble-mesh] 📡 New device: $deviceId  rssi=${result.rssi}');
    }

    _peerController.add(peers);

    if (_connectedDevices.containsKey(deviceId)) return;
    if (_connectingDevices.contains(deviceId)) return;

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
      debugPrint('[ble-mesh] 🔄 Retrying $deviceId after 30s cooldown');
    }

    _connectToDeviceFBP(result.device);
  }

  Future<void> _connectToDeviceFBP(BluetoothDevice device) async {
    final deviceId = device.remoteId.str;

    try {
      _connectingDevices.add(deviceId);
      debugPrint('[ble-mesh] Connecting to $deviceId ...');

      await FlutterBluePlus.stopScan();
      await Future.delayed(const Duration(milliseconds: 200));

      await device.connect(
        license: License.free,
        timeout: BLEConstants.connectTimeout,
        autoConnect: false,
      );

      debugPrint('[ble-mesh] Connected to $deviceId — requesting MTU');

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

      debugPrint('[ble-mesh] Discovering services on $deviceId ...');
      final services = await device.discoverServices();
      for (final service in services) {
        if (service.serviceUuid == BLEConstants.serviceUUID) {
          debugPrint('[ble-mesh] Found bitchat service on $deviceId');
          for (final char in service.characteristics) {
            if (char.characteristicUuid == BLEConstants.characteristicUUID) {
              _fbpCharacteristics[deviceId] = char;

              await char.setNotifyValue(true);
              char.onValueReceived.listen((data) {
                _handleReceivedData(Uint8List.fromList(data), deviceId);
              });

              _peers[deviceId]?.isConnected = true;
              _peerController.add(peers);
              _updateStatus(BLEMeshStatus.connected);
              debugPrint('[ble-mesh] ✅ Fully connected to $deviceId');
            }
          }
        }
      }

      device.connectionState.listen((state) {
        if (state == BluetoothConnectionState.disconnected) {
          _handleDisconnectionFBP(deviceId);
        }
      });
    } catch (e) {
      debugPrint('[ble-mesh] ❌ Connection failed to $deviceId: $e');
      _connectingDevices.remove(deviceId);
      _failedDevices[deviceId] = DateTime.now();
      _connectedDevices.remove(deviceId);
    } finally {
      _restartScanFBP();
    }
  }

  void _handleDisconnectionFBP(String deviceId) {
    _connectedDevices.remove(deviceId);
    _fbpCharacteristics.remove(deviceId);
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
  ///
  /// On native macOS, uses the native plugin's sendMessage for chat messages
  /// (which handles BinaryProtocol encoding internally), or raw write for
  /// other packet types.
  Future<void> broadcastPacket(BitchatPacket packet) async {
    if (_useNative && packet.type == 0x02) {
      // Chat message — let native handle BinaryProtocol encoding
      final content = String.fromCharCodes(packet.payload);
      await _native.sendMessage(content, nickname: nickname);
      return;
    }

    final data = BinaryProtocol.encode(packet);
    if (data == null) return;
    final fragments = _fragment(data);

    if (_useNative) {
      for (final deviceId in _nativeConnected) {
        for (final fragment in fragments) {
          try {
            await _native.write(deviceId, fragment);
          } catch (_) {}
        }
      }
    } else {
      for (final entry in _fbpCharacteristics.entries) {
        for (final fragment in fragments) {
          try {
            await entry.value.write(fragment.toList(), withoutResponse: true);
          } catch (_) {}
        }
      }
    }
  }

  /// Send a packet to a specific peer.
  Future<bool> sendPacketToPeer(BitchatPacket packet, String deviceId) async {
    final data = BinaryProtocol.encode(packet);
    if (data == null) return false;
    final fragments = _fragment(data);

    try {
      if (_useNative) {
        for (final fragment in fragments) {
          await _native.write(deviceId, fragment);
        }
      } else {
        final char = _fbpCharacteristics[deviceId];
        if (char == null) return false;
        for (final fragment in fragments) {
          await char.write(fragment.toList(), withoutResponse: true);
        }
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // Message receiving & relay
  // ---------------------------------------------------------------------------

  final Map<String, List<Uint8List>> _reassemblyBuffers = {};

  void _handleReceivedData(Uint8List data, String senderDeviceId) {
    if (data.isEmpty) return;

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

      if (_seenMessageIds.length > 5000) {
        _seenMessageIds.remove(_seenMessageIds.first);
      }

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
    } catch (_) {}
  }

  Future<void> _relayPacket(
    BitchatPacket packet, {
    required String excludeDeviceId,
  }) async {
    final data = BinaryProtocol.encode(packet);
    if (data == null) return;
    final fragments = _fragment(data);

    if (_useNative) {
      for (final deviceId in _nativeConnected) {
        if (deviceId == excludeDeviceId) continue;
        for (final fragment in fragments) {
          try {
            await _native.write(deviceId, fragment);
          } catch (_) {}
        }
      }
    } else {
      for (final entry in _fbpCharacteristics.entries) {
        if (entry.key == excludeDeviceId) continue;
        for (final fragment in fragments) {
          try {
            await entry.value.write(fragment.toList(), withoutResponse: true);
          } catch (_) {}
        }
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Fragmentation
  // ---------------------------------------------------------------------------

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
      header.setUint8(0, 0xBB);
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
    final staleKeys = _peers.entries
        .where((e) => e.value.isStale && !e.value.isConnected)
        .map((e) => e.key)
        .toList();
    for (final key in staleKeys) {
      _peers.remove(key);
    }

    _reassemblyBuffers.removeWhere((key, _) => true);

    if (staleKeys.isNotEmpty) {
      _peerController.add(peers);
    }

    // Restart scan if no peers connected
    if (connectedPeerCount == 0 && _status != BLEMeshStatus.error) {
      if (_useNative) {
        _native.startScan();
      } else {
        FlutterBluePlus.startScan(
          withServices: [BLEConstants.serviceUUID],
          timeout: BLEConstants.scanTimeout,
          continuousUpdates: true,
        );
      }
    }
  }

  void _updateStatus(BLEMeshStatus newStatus) {
    if (_status != newStatus) {
      _status = newStatus;
      if (!_disposed) _statusController.add(newStatus);
    }
  }
}
