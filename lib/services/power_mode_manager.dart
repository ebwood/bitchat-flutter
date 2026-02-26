import 'dart:async';

/// Adaptive power modes for BLE mesh networking.
///
/// Controls scan interval, connection budget, and relay behavior to
/// balance battery life with mesh participation.
enum PowerMode {
  /// Maximum performance — continuous scan, full relay.
  performance,

  /// Balanced — periodic scan, moderate relay.
  balanced,

  /// Low power — infrequent scan, minimal relay.
  lowPower,

  /// Ultra low — scan only on demand, no relay.
  ultraLow,
}

/// Per-mode configuration parameters.
class PowerModeConfig {
  const PowerModeConfig({
    required this.scanInterval,
    required this.scanDuration,
    required this.maxConnections,
    required this.relayEnabled,
    required this.maintenanceInterval,
    required this.coverTrafficEnabled,
  });

  final Duration scanInterval;
  final Duration scanDuration;
  final int maxConnections;
  final bool relayEnabled;
  final Duration maintenanceInterval;
  final bool coverTrafficEnabled;

  static const configs = <PowerMode, PowerModeConfig>{
    PowerMode.performance: PowerModeConfig(
      scanInterval: Duration(seconds: 5),
      scanDuration: Duration(seconds: 10),
      maxConnections: 7,
      relayEnabled: true,
      maintenanceInterval: Duration(seconds: 15),
      coverTrafficEnabled: true,
    ),
    PowerMode.balanced: PowerModeConfig(
      scanInterval: Duration(seconds: 30),
      scanDuration: Duration(seconds: 8),
      maxConnections: 5,
      relayEnabled: true,
      maintenanceInterval: Duration(seconds: 30),
      coverTrafficEnabled: false,
    ),
    PowerMode.lowPower: PowerModeConfig(
      scanInterval: Duration(minutes: 2),
      scanDuration: Duration(seconds: 5),
      maxConnections: 3,
      relayEnabled: false,
      maintenanceInterval: Duration(minutes: 1),
      coverTrafficEnabled: false,
    ),
    PowerMode.ultraLow: PowerModeConfig(
      scanInterval: Duration(minutes: 10),
      scanDuration: Duration(seconds: 3),
      maxConnections: 1,
      relayEnabled: false,
      maintenanceInterval: Duration(minutes: 5),
      coverTrafficEnabled: false,
    ),
  };
}

/// Manages adaptive power modes based on battery level and user preference.
class PowerModeManager {
  PowerModeManager({PowerMode initialMode = PowerMode.balanced})
    : _currentMode = initialMode;

  PowerMode _currentMode;
  PowerMode get currentMode => _currentMode;

  final _modeController = StreamController<PowerMode>.broadcast();
  Stream<PowerMode> get modeStream => _modeController.stream;

  /// Current configuration.
  PowerModeConfig get config =>
      PowerModeConfig.configs[_currentMode] ??
      PowerModeConfig.configs[PowerMode.balanced]!;

  /// Switch to a specific power mode.
  void setMode(PowerMode mode) {
    if (_currentMode != mode) {
      _currentMode = mode;
      _modeController.add(mode);
    }
  }

  /// Auto-select mode based on battery percentage.
  void adaptToBattery(int batteryPercent) {
    if (batteryPercent <= 10) {
      setMode(PowerMode.ultraLow);
    } else if (batteryPercent <= 25) {
      setMode(PowerMode.lowPower);
    } else if (batteryPercent <= 50) {
      setMode(PowerMode.balanced);
    } else {
      setMode(PowerMode.performance);
    }
  }

  /// Human-readable mode description.
  String get modeDescription {
    switch (_currentMode) {
      case PowerMode.performance:
        return 'Performance — max range, full relay';
      case PowerMode.balanced:
        return 'Balanced — moderate scan, relay on';
      case PowerMode.lowPower:
        return 'Low Power — reduced scan, no relay';
      case PowerMode.ultraLow:
        return 'Ultra Low — minimal activity';
    }
  }

  void dispose() {
    _modeController.close();
  }
}
