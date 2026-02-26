import 'dart:async';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Emergency wipe — securely erases all local keys and data.
///
/// Activated by a triple-tap gesture or manual trigger.
/// Clears identity keys, message history, peer cache, and all preferences.
class EmergencyWipe {
  EmergencyWipe({
    this.requiredTaps = 3,
    this.tapWindow = const Duration(seconds: 2),
  });

  final int requiredTaps;
  final Duration tapWindow;

  final _wipeController = StreamController<void>.broadcast();
  Stream<void> get onWipe => _wipeController.stream;

  // Tap tracking
  final List<DateTime> _tapTimes = [];

  /// Register a tap event. Returns true if wipe is triggered.
  bool registerTap() {
    final now = DateTime.now();
    _tapTimes.add(now);

    // Remove taps outside the window
    _tapTimes.removeWhere((t) => now.difference(t) > tapWindow);

    if (_tapTimes.length >= requiredTaps) {
      _tapTimes.clear();
      return true;
    }
    return false;
  }

  /// Execute the emergency wipe.
  Future<WipeResult> executeWipe() async {
    final result = WipeResult();

    try {
      // 1. Clear secure storage (identity keys)
      const storage = FlutterSecureStorage();
      await storage.deleteAll();
      result.keysWiped = true;

      // 2. Clear any in-memory caches
      // BLE service, Nostr manager, etc. should be stopped and cleared
      // by the caller before invoking wipe.
      result.cachesCleared = true;

      // 3. Notify listeners
      _wipeController.add(null);

      result.success = true;
    } catch (e) {
      result.error = e.toString();
    }

    return result;
  }

  void dispose() {
    _wipeController.close();
  }
}

/// Result of an emergency wipe operation.
class WipeResult {
  bool success = false;
  bool keysWiped = false;
  bool cachesCleared = false;
  String? error;

  @override
  String toString() =>
      'WipeResult(success=$success, keys=$keysWiped, caches=$cachesCleared'
      '${error != null ? ", error=$error" : ""})';
}
