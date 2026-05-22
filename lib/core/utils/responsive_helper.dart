import 'package:flutter/material.dart';

/// Responsive breakpoint utilities.
///
///  Mobile  : width < 600
///  Tablet  : 600 <= width < 1024
///  Desktop : width >= 1024
class ResponsiveHelper {
  const ResponsiveHelper._();

  static const double _mobileBreakpoint = 600;
  static const double _desktopBreakpoint = 1024;

  /// Maximum width for centered page content on large screens.
  static const double maxContentWidth = 1300;

  static bool isMobile(BuildContext context) =>
      MediaQuery.sizeOf(context).width < _mobileBreakpoint;

  static bool isTablet(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    return w >= _mobileBreakpoint && w < _desktopBreakpoint;
  }

  static bool isDesktop(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= _desktopBreakpoint;

  /// Horizontal page padding that scales with screen size.
  static double horizontalPadding(BuildContext context) {
    if (isMobile(context)) return 16;
    if (isTablet(context)) return 24;
    return 32;
  }

  /// Returns value based on current breakpoint.
  static T responsive<T>(
    BuildContext context, {
    required T mobile,
    T? tablet,
    required T desktop,
  }) {
    if (isDesktop(context)) return desktop;
    if (isTablet(context)) return tablet ?? desktop;
    return mobile;
  }
}
