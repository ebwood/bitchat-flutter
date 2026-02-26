import 'package:flutter/material.dart';

/// Permission request service — manages BLE, Location, and Mic permissions.
///
/// Matches Android `onboarding/` permission flow.
/// Abstracts platform permission checks into a unified service.

/// Permission types the app needs.
enum AppPermission { bluetooth, location, microphone }

/// Current status of a permission.
enum PermissionStatus {
  /// Not yet requested.
  notRequested,

  /// Permission granted.
  granted,

  /// Permission denied (can ask again).
  denied,

  /// Permission permanently denied (must go to settings).
  permanentlyDenied,

  /// Permission restricted by system policy.
  restricted,
}

/// Result of a permission check/request.
class PermissionResult {
  const PermissionResult({required this.permission, required this.status});

  final AppPermission permission;
  final PermissionStatus status;

  bool get isGranted => status == PermissionStatus.granted;
}

/// Manages permission checking and requesting.
///
/// NOTE: This is the data model / logic layer. Actual platform
/// permission requests require the `permission_handler` package.
/// This service provides the abstraction and state management.
class PermissionService {
  final _statuses = <AppPermission, PermissionStatus>{
    AppPermission.bluetooth: PermissionStatus.notRequested,
    AppPermission.location: PermissionStatus.notRequested,
    AppPermission.microphone: PermissionStatus.notRequested,
  };

  /// Get current status of a permission.
  PermissionStatus getStatus(AppPermission permission) {
    return _statuses[permission] ?? PermissionStatus.notRequested;
  }

  /// Check if a permission is granted.
  bool isGranted(AppPermission permission) {
    return getStatus(permission) == PermissionStatus.granted;
  }

  /// Check if all required permissions are granted.
  bool get allGranted =>
      _statuses.values.every((s) => s == PermissionStatus.granted);

  /// Check if any permission needs attention.
  bool get needsAttention => _statuses.values.any(
    (s) =>
        s == PermissionStatus.denied || s == PermissionStatus.permanentlyDenied,
  );

  /// Simulate setting permission status (for testing / stub).
  /// In production, this would call platform permission handler.
  void setStatus(AppPermission permission, PermissionStatus status) {
    _statuses[permission] = status;
  }

  /// Get all permission results.
  List<PermissionResult> get allResults => _statuses.entries
      .map((e) => PermissionResult(permission: e.key, status: e.value))
      .toList();

  /// Get permissions that still need to be requested.
  List<AppPermission> get pendingPermissions => _statuses.entries
      .where((e) => e.value == PermissionStatus.notRequested)
      .map((e) => e.key)
      .toList();

  /// Human-readable explanation for each permission.
  static String explanation(AppPermission permission) {
    switch (permission) {
      case AppPermission.bluetooth:
        return 'Bluetooth is used for peer-to-peer mesh networking. '
            'It allows BitChat to discover nearby peers and relay messages '
            'without internet connectivity.';
      case AppPermission.location:
        return 'Location access is required on Android for Bluetooth LE scanning. '
            'It is also used for geohash-based local chat channels. '
            'Your exact location is never shared with servers.';
      case AppPermission.microphone:
        return 'Microphone access is needed for recording voice notes. '
            'Audio is processed locally and encrypted before sending.';
    }
  }

  /// Icon for each permission.
  static IconData icon(AppPermission permission) {
    switch (permission) {
      case AppPermission.bluetooth:
        return Icons.bluetooth;
      case AppPermission.location:
        return Icons.location_on_outlined;
      case AppPermission.microphone:
        return Icons.mic_outlined;
    }
  }

  /// Color for each permission.
  static Color color(AppPermission permission) {
    switch (permission) {
      case AppPermission.bluetooth:
        return const Color(0xFF007AFF);
      case AppPermission.location:
        return const Color(0xFFFF9500);
      case AppPermission.microphone:
        return const Color(0xFFFF3B30);
    }
  }
}
