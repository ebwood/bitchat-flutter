import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Native macOS BLE Central — platform channel interface.
///
/// On macOS, this uses the native CoreBluetooth plugin (BLEPlugin.swift)
/// instead of flutter_blue_plus for reliable connections.
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

  // ---------------------------------------------------------------------------
  // Adapter
  // ---------------------------------------------------------------------------

  /// Check if Bluetooth adapter is on.
  Future<bool> getAdapterState() async {
    final result = await _method.invokeMethod<bool>('getAdapterState');
    return result ?? false;
  }

  /// Listen for adapter state changes from native side.
  void setAdapterStateCallback(void Function(String state) callback) {
    _method.setMethodCallHandler((call) async {
      if (call.method == 'onAdapterStateChanged') {
        callback(call.arguments as String);
      }
    });
  }

  // ---------------------------------------------------------------------------
  // Scanning
  // ---------------------------------------------------------------------------

  /// Start scanning for BLE devices with the bitchat service UUID.
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
  // Data
  // ---------------------------------------------------------------------------

  /// Write data to a connected device's characteristic.
  Future<void> write(String deviceId, Uint8List data) =>
      _method.invokeMethod('write', {'deviceId': deviceId, 'data': data});

  /// Stream of received data from connected devices.
  Stream<BLEDataEvent> get dataEvents =>
      _dataChannel.receiveBroadcastStream().map((event) {
        final map = Map<String, dynamic>.from(event as Map);
        return BLEDataEvent(
          deviceId: map['deviceId'] as String,
          data: map['data'] as Uint8List,
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
}
