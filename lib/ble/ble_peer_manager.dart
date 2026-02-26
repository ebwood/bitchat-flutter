import 'dart:async';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'ble_mesh_service.dart';

/// Manages peer discovery, connection scheduling, and RSSI tracking.
///
/// Works with [BLEMeshService] to implement connection budget controls,
/// backoff on failed connections, and adaptive RSSI thresholds.
class BLEPeerManager {
  BLEPeerManager({
    this.maxConnections = 7,
    this.minRSSI = -80,
    this.connectionBackoff = const Duration(seconds: 30),
  });

  final int maxConnections;
  final int minRSSI;
  final Duration connectionBackoff;

  /// Peer ID → last failed connection attempt.
  final Map<String, DateTime> _failedConnections = {};

  /// Peer ID → failure count (for exponential backoff).
  final Map<String, int> _failureCounts = {};

  /// Decide whether to connect to a discovered device.
  bool shouldConnect({
    required String deviceId,
    required int rssi,
    required int currentConnectionCount,
  }) {
    // Connection budget
    if (currentConnectionCount >= maxConnections) return false;

    // RSSI threshold
    if (rssi < minRSSI) return false;

    // Backoff check
    final lastFailure = _failedConnections[deviceId];
    if (lastFailure != null) {
      final failures = _failureCounts[deviceId] ?? 1;
      final backoff = connectionBackoff * failures;
      if (DateTime.now().difference(lastFailure) < backoff) return false;
    }

    return true;
  }

  /// Record a failed connection attempt.
  void recordFailure(String deviceId) {
    _failedConnections[deviceId] = DateTime.now();
    _failureCounts[deviceId] = (_failureCounts[deviceId] ?? 0) + 1;
  }

  /// Record a successful connection (reset backoff).
  void recordSuccess(String deviceId) {
    _failedConnections.remove(deviceId);
    _failureCounts.remove(deviceId);
  }

  /// Clean up old failure records.
  void sweep() {
    final cutoff = DateTime.now().subtract(const Duration(minutes: 10));
    _failedConnections.removeWhere((_, time) => time.isBefore(cutoff));
    _failureCounts.removeWhere((id, _) => !_failedConnections.containsKey(id));
  }

  /// Sort peers by signal strength for connection priority.
  List<BLEPeerInfo> prioritize(List<BLEPeerInfo> peers) {
    final sorted = List<BLEPeerInfo>.from(peers);
    sorted.sort((a, b) => b.rssi.compareTo(a.rssi)); // strongest first
    return sorted;
  }
}
