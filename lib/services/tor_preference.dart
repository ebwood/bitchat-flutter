/// Tor integration preferences and mode management.
///
/// Matches Android `TorMode.kt`, `TorPreferenceManager.kt`.
/// Provides the preference/state layer. Actual Tor routing
/// requires Arti Rust FFI integration.

/// Tor connection mode.
enum TorMode {
  /// Tor is completely disabled.
  off,

  /// Use Tor when available, fallback to direct connection.
  whenAvailable,

  /// Always use Tor, block if unavailable.
  always,
}

/// Tor connection state.
enum TorConnectionState {
  /// Not connected, Tor disabled.
  disabled,

  /// Connecting to Tor network.
  connecting,

  /// Connected and routing through Tor.
  connected,

  /// Connection failed.
  failed,

  /// Not available (Arti not installed).
  unavailable,
}

/// Tor preference and state manager.
class TorPreferenceManager {
  TorPreferenceManager();

  TorMode _mode = TorMode.off;
  TorConnectionState _connectionState = TorConnectionState.disabled;
  String? _socksAddress;
  int? _socksPort;
  String? _lastError;
  DateTime? _connectedSince;

  /// Current Tor mode.
  TorMode get mode => _mode;

  /// Current connection state.
  TorConnectionState get connectionState => _connectionState;

  /// SOCKS proxy address (when connected).
  String? get socksAddress => _socksAddress;

  /// SOCKS proxy port (when connected).
  int? get socksPort => _socksPort;

  /// Full SOCKS5 proxy URL.
  String? get socksProxyUrl => _socksAddress != null && _socksPort != null
      ? 'socks5://$_socksAddress:$_socksPort'
      : null;

  /// Last error message.
  String? get lastError => _lastError;

  /// How long Tor has been connected.
  Duration? get uptime => _connectedSince != null
      ? DateTime.now().difference(_connectedSince!)
      : null;

  /// Set Tor mode.
  void setMode(TorMode newMode) {
    _mode = newMode;
    if (newMode == TorMode.off) {
      _connectionState = TorConnectionState.disabled;
      _socksAddress = null;
      _socksPort = null;
      _connectedSince = null;
    }
  }

  /// Simulate connecting (for testing / stub).
  void simulateConnecting() {
    if (_mode == TorMode.off) return;
    _connectionState = TorConnectionState.connecting;
    _lastError = null;
  }

  /// Simulate connected state.
  void simulateConnected({String address = '127.0.0.1', int port = 9050}) {
    _connectionState = TorConnectionState.connected;
    _socksAddress = address;
    _socksPort = port;
    _connectedSince = DateTime.now();
    _lastError = null;
  }

  /// Simulate connection failure.
  void simulateFailed(String error) {
    _connectionState = TorConnectionState.failed;
    _lastError = error;
    _socksAddress = null;
    _socksPort = null;
  }

  /// Whether traffic should be routed through Tor right now.
  bool get shouldRouteThrough {
    if (_mode == TorMode.off) return false;
    if (_mode == TorMode.always)
      return _connectionState == TorConnectionState.connected;
    // whenAvailable: route if connected
    return _connectionState == TorConnectionState.connected;
  }

  /// Whether direct connections are allowed.
  bool get allowDirectConnection {
    if (_mode == TorMode.always) return false;
    return true;
  }

  /// Human-readable status string.
  String get statusText {
    switch (_connectionState) {
      case TorConnectionState.disabled:
        return 'Tor disabled';
      case TorConnectionState.connecting:
        return 'Connecting to Tor…';
      case TorConnectionState.connected:
        return 'Connected via Tor';
      case TorConnectionState.failed:
        return 'Tor connection failed';
      case TorConnectionState.unavailable:
        return 'Tor not available';
    }
  }

  /// Mode description.
  static String modeDescription(TorMode mode) {
    switch (mode) {
      case TorMode.off:
        return 'Direct connection (no Tor)';
      case TorMode.whenAvailable:
        return 'Use Tor when available, fallback to direct';
      case TorMode.always:
        return 'Always use Tor (blocks if unavailable)';
    }
  }

  /// Reset state.
  void reset() {
    _mode = TorMode.off;
    _connectionState = TorConnectionState.disabled;
    _socksAddress = null;
    _socksPort = null;
    _lastError = null;
    _connectedSince = null;
  }
}
