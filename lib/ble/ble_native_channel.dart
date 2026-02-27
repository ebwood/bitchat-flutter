import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Native macOS BLE Mesh — platform channel interface.
///
/// On macOS, this uses the native CoreBluetooth plugin (BLEPlugin.swift)
/// which implements the full BitChat BLE mesh protocol:
/// - Dual-role: Central (scanning) + Peripheral (advertising)
/// - BinaryProtocol wire format matching original bitchat
/// - AnnouncementPacket TLV for peer discovery
/// - Automatic periodic announcements
class BLENativeChannel {
  BLENativeChannel._();
  static final instance = BLENativeChannel._();

  static const _method = MethodChannel('com.bitchat/ble');
  static const _scanChannel = EventChannel('com.bitchat/ble/scan');
  static const _connectionChannel = EventChannel('com.bitchat/ble/connection');
  static const _dataChannel = EventChannel('com.bitchat/ble/data');

  /// Override for testing — set to false to disable native channel in tests.
  static bool? overrideSupported;

  /// Whether this platform should use the native BLE channel.
  static bool get isSupported {
    if (overrideSupported != null) return overrideSupported!;
    if (kIsWeb) return false;
    return Platform.isMacOS;
  }

  // Callbacks from native
  void Function(String peerID, String nickname, String deviceId)?
  onPeerDiscovered;

  // ---------------------------------------------------------------------------
  // Adapter
  // ---------------------------------------------------------------------------

  /// Check if Bluetooth adapter is on.
  Future<bool> getAdapterState() async {
    final result = await _method.invokeMethod<bool>('getAdapterState');
    return result ?? false;
  }

  /// Listen for adapter state changes and peer discovery from native side.
  void setMethodCallHandler({
    void Function(String state)? onAdapterState,
    void Function(String peerID, String nickname, String deviceId)? onPeerFound,
  }) {
    onPeerDiscovered = onPeerFound;
    _method.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'onAdapterStateChanged':
          onAdapterState?.call(call.arguments as String);
          break;
        case 'onPeerDiscovered':
          final map = Map<String, dynamic>.from(call.arguments as Map);
          onPeerFound?.call(
            map['peerID'] as String,
            map['nickname'] as String,
            map['deviceId'] as String,
          );
          break;
      }
    });
  }

  // ---------------------------------------------------------------------------
  // Scanning
  // ---------------------------------------------------------------------------

  /// Start scanning for BLE devices with the bitchat service UUID.
  /// Also starts the Peripheral role (advertising) and periodic announcements.
  Future<void> startScan() => _method.invokeMethod('startScan');

  /// Stop scanning.
  Future<void> stopScan() => _method.invokeMethod('stopScan');

  /// Stream of scan results: {deviceId: String, rssi: int}
  Stream<BLEScanResult> get scanResults =>
      _scanChannel.receiveBroadcastStream().map((event) {
        final map = Map<String, dynamic>.from(event as Map);
        return BLEScanResult(
          deviceId: map['deviceId'] as String,
          rssi: map['rssi'] as int,
        );
      });

  // ---------------------------------------------------------------------------
  // Connection
  // ---------------------------------------------------------------------------

  /// Connect to a discovered device.
  Future<void> connect(String deviceId) =>
      _method.invokeMethod('connect', {'deviceId': deviceId});

  /// Disconnect from a device.
  Future<void> disconnect(String deviceId) =>
      _method.invokeMethod('disconnect', {'deviceId': deviceId});

  /// Disconnect all devices.
  Future<void> disconnectAll() => _method.invokeMethod('disconnectAll');

  /// Stream of connection state changes: {deviceId, state}
  /// States: "connected", "ready", "disconnected", "failed", "timeout"
  Stream<BLEConnectionEvent> get connectionEvents =>
      _connectionChannel.receiveBroadcastStream().map((event) {
        final map = Map<String, dynamic>.from(event as Map);
        return BLEConnectionEvent(
          deviceId: map['deviceId'] as String,
          state: map['state'] as String,
        );
      });

  // ---------------------------------------------------------------------------
  // Messaging (BitChat mesh protocol)
  // ---------------------------------------------------------------------------

  /// Set nickname for announcements.
  Future<void> setNickname(String nickname) =>
      _method.invokeMethod('setNickname', {'nickname': nickname});

  /// Send a broadcast announcement to all connected peers.
  Future<void> sendAnnounce({String? nickname}) => _method.invokeMethod(
    'sendAnnounce',
    {if (nickname != null) 'nickname': nickname},
  );

  /// Send a public chat message to all connected peers.
  /// The plugin handles BinaryProtocol encoding.
  Future<void> sendMessage(String content, {String? nickname}) =>
      _method.invokeMethod('sendMessage', {
        'content': content,
        if (nickname != null) 'nickname': nickname,
      });

  /// Fetch location natively using CoreLocation (bypasses geolocator to avoid IP fallback issues)
  Future<Map<String, dynamic>?> getLocation() async {
    try {
      final result = await _method.invokeMapMethod<String, dynamic>(
        'getLocation',
      );
      return result;
    } catch (e) {
      debugPrint('[ble-mesh] Native getLocation failed: $e');
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // Data (raw and parsed)
  // ---------------------------------------------------------------------------

  /// Write raw data to a connected device's characteristic.
  Future<void> write(String deviceId, Uint8List data) =>
      _method.invokeMethod('write', {'deviceId': deviceId, 'data': data});

  /// Stream of received data/messages from connected devices.
  ///
  /// Events can be either:
  /// - Raw data: {deviceId, data} (legacy)
  /// - Parsed message: {type: "message", senderPeerID, nickname, content,
  ///   timestamp, isOwnMessage}
  Stream<BLEDataEvent> get dataEvents =>
      _dataChannel.receiveBroadcastStream().map((event) {
        final map = Map<String, dynamic>.from(event as Map);

        // Check if this is a parsed message from BinaryProtocol
        if (map.containsKey('type') && map['type'] == 'message') {
          return BLEMessageEvent(
            senderPeerID: map['senderPeerID'] as String,
            nickname: map['nickname'] as String,
            content: map['content'] as String,
            timestamp: DateTime.fromMillisecondsSinceEpoch(
              (map['timestamp'] as int),
            ),
            isOwnMessage: map['isOwnMessage'] as bool? ?? false,
          );
        }

        // Legacy raw data event
        return BLEDataEvent(
          deviceId: map['deviceId'] as String? ?? '',
          data: map['data'] as Uint8List? ?? Uint8List(0),
        );
      });
}

// ---------------------------------------------------------------------------
// Data classes
// ---------------------------------------------------------------------------

class BLEScanResult {
  const BLEScanResult({required this.deviceId, required this.rssi});
  final String deviceId;
  final int rssi;
}

class BLEConnectionEvent {
  const BLEConnectionEvent({required this.deviceId, required this.state});
  final String deviceId;
  final String state;

  bool get isConnected => state == 'connected';
  bool get isReady => state == 'ready';
  bool get isDisconnected => state == 'disconnected';
  bool get isFailed => state == 'failed' || state == 'timeout';
}

class BLEDataEvent {
  const BLEDataEvent({required this.deviceId, required this.data});
  final String deviceId;
  final Uint8List data;

  /// Whether this is a parsed message (vs raw data).
  bool get isMessage => false;
}

/// A parsed BLE mesh chat message.
class BLEMessageEvent extends BLEDataEvent {
  BLEMessageEvent({
    required this.senderPeerID,
    required this.nickname,
    required this.content,
    required this.timestamp,
    this.isOwnMessage = false,
  }) : super(deviceId: senderPeerID, data: Uint8List(0));

  final String senderPeerID;
  final String nickname;
  final String content;
  final DateTime timestamp;
  final bool isOwnMessage;

  @override
  bool get isMessage => true;
}
