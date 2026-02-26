import 'dart:async';
import 'package:flutter/services.dart';

/// BLE Peripheral platform channel — Dart side.
///
/// Bridges to native CBPeripheralManager (iOS) and
/// BluetoothLeAdvertiser (Android) via MethodChannel.
class BLEPeripheralChannel {
  BLEPeripheralChannel._();
  static final instance = BLEPeripheralChannel._();

  static const _channel = MethodChannel('com.ebwood.bitchat/ble_peripheral');

  final _stateController = StreamController<PeripheralState>.broadcast();
  final _dataController = StreamController<BLEReceivedData>.broadcast();

  /// Stream of peripheral state changes.
  Stream<PeripheralState> get stateChanges => _stateController.stream;

  /// Stream of data received from connected centrals.
  Stream<BLEReceivedData> get receivedData => _dataController.stream;

  PeripheralState _state = PeripheralState.unknown;
  PeripheralState get state => _state;

  /// Initialize the peripheral and set up event handling.
  Future<void> initialize() async {
    _channel.setMethodCallHandler(_handleMethodCall);
    try {
      final result = await _channel.invokeMethod<String>('initialize');
      _state = PeripheralState.values.firstWhere(
        (s) => s.name == result,
        orElse: () => PeripheralState.unknown,
      );
    } on MissingPluginException {
      _state = PeripheralState.unsupported;
    } on PlatformException catch (e) {
      _state = PeripheralState.error;
      _stateController.addError(e);
    }
  }

  /// Start advertising as a BLE peripheral.
  Future<bool> startAdvertising({
    required String serviceUUID,
    required String characteristicUUID,
    String? localName,
  }) async {
    try {
      final result = await _channel.invokeMethod<bool>('startAdvertising', {
        'serviceUUID': serviceUUID,
        'characteristicUUID': characteristicUUID,
        'localName': localName ?? 'BitChat',
      });
      if (result == true) {
        _state = PeripheralState.advertising;
        _stateController.add(_state);
      }
      return result ?? false;
    } on PlatformException {
      return false;
    }
  }

  /// Stop advertising.
  Future<void> stopAdvertising() async {
    try {
      await _channel.invokeMethod<void>('stopAdvertising');
      _state = PeripheralState.idle;
      _stateController.add(_state);
    } on PlatformException {
      // Ignore
    }
  }

  /// Send data to a connected central.
  Future<bool> sendData(List<int> data, {String? centralId}) async {
    try {
      final result = await _channel.invokeMethod<bool>('sendData', {
        'data': data,
        'centralId': centralId,
      });
      return result ?? false;
    } on PlatformException {
      return false;
    }
  }

  /// Get number of connected centrals.
  Future<int> get connectedCentralCount async {
    try {
      return await _channel.invokeMethod<int>('getConnectedCount') ?? 0;
    } on PlatformException {
      return 0;
    }
  }

  /// Handle incoming method calls from native.
  Future<dynamic> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'onStateChanged':
        final stateName = call.arguments as String?;
        _state = PeripheralState.values.firstWhere(
          (s) => s.name == stateName,
          orElse: () => PeripheralState.unknown,
        );
        _stateController.add(_state);
      case 'onDataReceived':
        final args = call.arguments as Map;
        _dataController.add(
          BLEReceivedData(
            data: List<int>.from(args['data'] as List),
            centralId: args['centralId'] as String?,
          ),
        );
      case 'onCentralConnected':
        _stateController.add(PeripheralState.connected);
      case 'onCentralDisconnected':
        _stateController.add(
          _state == PeripheralState.advertising
              ? PeripheralState.advertising
              : PeripheralState.idle,
        );
    }
  }

  /// Exposed for testing — simulates a native method call.
  Future<dynamic> handleMethodCallForTest(MethodCall call) =>
      _handleMethodCall(call);

  /// Dispose resources.
  void dispose() {
    _stateController.close();
    _dataController.close();
  }
}

/// BLE Peripheral state.
enum PeripheralState {
  unknown,
  unsupported,
  unauthorized,
  idle,
  advertising,
  connected,
  error,
}

/// Data received from a connected BLE central.
class BLEReceivedData {
  const BLEReceivedData({required this.data, this.centralId});
  final List<int> data;
  final String? centralId;
}

/// Android foreground service platform channel.
class ForegroundServiceChannel {
  ForegroundServiceChannel._();
  static final instance = ForegroundServiceChannel._();

  static const _channel = MethodChannel(
    'com.ebwood.bitchat/foreground_service',
  );

  bool _isRunning = false;
  bool get isRunning => _isRunning;

  /// Start the mesh foreground service.
  Future<bool> startService({
    String title = 'BitChat Mesh',
    String body = 'Mesh networking active',
  }) async {
    try {
      final result = await _channel.invokeMethod<bool>('startService', {
        'title': title,
        'body': body,
      });
      _isRunning = result ?? false;
      return _isRunning;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Stop the foreground service.
  Future<void> stopService() async {
    try {
      await _channel.invokeMethod<void>('stopService');
      _isRunning = false;
    } on PlatformException {
      // Ignore
    }
  }

  /// Update the notification text.
  Future<void> updateNotification({
    required String title,
    required String body,
  }) async {
    try {
      await _channel.invokeMethod<void>('updateNotification', {
        'title': title,
        'body': body,
      });
    } on PlatformException {
      // Ignore
    }
  }
}

/// Boot receiver check — whether the app is configured to auto-start.
class BootReceiverChannel {
  BootReceiverChannel._();
  static final instance = BootReceiverChannel._();

  static const _channel = MethodChannel('com.ebwood.bitchat/boot_receiver');

  /// Check if auto-start on boot is enabled.
  Future<bool> isEnabled() async {
    try {
      return await _channel.invokeMethod<bool>('isEnabled') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Enable auto-start on boot.
  Future<bool> setEnabled(bool enabled) async {
    try {
      return await _channel.invokeMethod<bool>('setEnabled', {
            'enabled': enabled,
          }) ??
          false;
    } on PlatformException {
      return false;
    }
  }
}
