/// Adaptive layout system for phone, tablet, and desktop.
///
/// Provides responsive breakpoints and layout builders that
/// automatically adapt the UI based on screen width.

import 'package:flutter/material.dart';

/// Device form factor based on screen width.
enum DeviceType {
  /// Phone: < 600dp
  phone,

  /// Tablet: 600–1024dp
  tablet,

  /// Desktop: > 1024dp
  desktop,
}

/// Responsive breakpoints matching Material Design guidelines.
class Breakpoints {
  const Breakpoints._();

  static const double phone = 600;
  static const double tablet = 1024;

  /// Determine device type from width.
  static DeviceType fromWidth(double width) {
    if (width < phone) return DeviceType.phone;
    if (width < tablet) return DeviceType.tablet;
    return DeviceType.desktop;
  }
}

/// Adaptive layout builder — renders different layouts per device type.
class AdaptiveLayout extends StatelessWidget {
  const AdaptiveLayout({
    super.key,
    required this.phone,
    this.tablet,
    this.desktop,
  });

  /// Layout for phone screens (required, used as fallback).
  final Widget phone;

  /// Layout for tablet screens (optional, falls back to phone).
  final Widget? tablet;

  /// Layout for desktop screens (optional, falls back to tablet → phone).
  final Widget? desktop;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final deviceType = Breakpoints.fromWidth(constraints.maxWidth);
        switch (deviceType) {
          case DeviceType.desktop:
            return desktop ?? tablet ?? phone;
          case DeviceType.tablet:
            return tablet ?? phone;
          case DeviceType.phone:
            return phone;
        }
      },
    );
  }
}

/// Master-detail layout for tablet/desktop (sidebar + content).
class MasterDetailLayout extends StatelessWidget {
  const MasterDetailLayout({
    super.key,
    required this.master,
    required this.detail,
    this.masterWidth = 320,
    this.showDetailOnPhone = false,
  });

  final Widget master;
  final Widget detail;
  final double masterWidth;
  final bool showDetailOnPhone;

  @override
  Widget build(BuildContext context) {
    return AdaptiveLayout(
      phone: showDetailOnPhone ? detail : master,
      tablet: Row(
        children: [
          SizedBox(width: masterWidth, child: master),
          const VerticalDivider(width: 1),
          Expanded(child: detail),
        ],
      ),
    );
  }
}

/// Responsive value — returns different values per device type.
T adaptiveValue<T>(
  BuildContext context, {
  required T phone,
  T? tablet,
  T? desktop,
}) {
  final width = MediaQuery.of(context).size.width;
  final deviceType = Breakpoints.fromWidth(width);
  switch (deviceType) {
    case DeviceType.desktop:
      return desktop ?? tablet ?? phone;
    case DeviceType.tablet:
      return tablet ?? phone;
    case DeviceType.phone:
      return phone;
  }
}

/// Responsive padding that increases on larger screens.
EdgeInsets adaptivePadding(BuildContext context) {
  final width = MediaQuery.of(context).size.width;
  final deviceType = Breakpoints.fromWidth(width);
  switch (deviceType) {
    case DeviceType.desktop:
      return const EdgeInsets.symmetric(horizontal: 48, vertical: 24);
    case DeviceType.tablet:
      return const EdgeInsets.symmetric(horizontal: 32, vertical: 16);
    case DeviceType.phone:
      return const EdgeInsets.symmetric(horizontal: 16, vertical: 8);
  }
}

/// Responsive grid columns.
int adaptiveColumns(BuildContext context) {
  return adaptiveValue(context, phone: 1, tablet: 2, desktop: 3);
}
