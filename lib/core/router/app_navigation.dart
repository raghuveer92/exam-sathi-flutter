import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Safe GoRouter helpers — prevents duplicate routes and browser history pollution.
class AppNavigation {
  AppNavigation._();

  /// Bottom-tab root paths → [StatefulNavigationShell] branch index.
  static const tabBranchIndex = <String, int>{
    '/home': 0,
    '/subjects': 1,
    '/analytics': 2,
    '/profile': 3,
  };

  static String currentLocation(BuildContext context) {
    return GoRouterState.of(context).uri.toString();
  }

  static String normalizeLocation(String location) {
    final uri = Uri.parse(location);
    var path = uri.path;
    if (path.length > 1 && path.endsWith('/')) {
      path = path.substring(0, path.length - 1);
    }
    if (uri.query.isEmpty) return path;

    final params = Map<String, String>.from(uri.queryParameters)
      ..removeWhere((_, value) => value.isEmpty);
    final entries = params.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final query = entries
        .map(
          (entry) =>
              '${Uri.encodeComponent(entry.key)}=${Uri.encodeComponent(entry.value)}',
        )
        .join('&');
    return query.isEmpty ? path : '$path?$query';
  }

  static bool isSameLocation(BuildContext context, String location) {
    return normalizeLocation(currentLocation(context)) ==
        normalizeLocation(location);
  }

  static StatefulNavigationShellState? _shellState(BuildContext context) {
    return StatefulNavigationShell.maybeOf(context);
  }

  /// Run [action] without adding a browser history entry (web only).
  static void _neglectOnWeb(BuildContext context, void Function() action) {
    if (kIsWeb) {
      Router.neglect(context, action);
      return;
    }
    action();
  }

  /// Enter main app / leave a one-time flow — does NOT leave the old screen in
  /// browser history (fixes back → download/login/onboarding loops on web).
  static void resetTo(
    BuildContext context,
    String location, {
    Object? extra,
  }) {
    if (isSameLocation(context, location)) return;
    _neglectOnWeb(context, () => context.go(location, extra: extra));
  }

  /// Swap the current screen (wizard step, download screen) without stacking.
  static void replaceTo(
    BuildContext context,
    String location, {
    Object? extra,
  }) {
    if (isSameLocation(context, location)) return;
    _neglectOnWeb(context, () => context.replace(location, extra: extra));
  }

  /// Switch bottom tab without growing the navigation stack.
  static void switchTab(
    BuildContext context,
    int index, {
    bool toRoot = false,
  }) {
    final shellState = _shellState(context);
    if (shellState != null) {
      _neglectOnWeb(
        context,
        () => shellState.goBranch(index, initialLocation: toRoot),
      );
      return;
    }
    const fallbacks = ['/home', '/subjects', '/analytics', '/profile'];
    if (index >= 0 && index < fallbacks.length) {
      resetTo(context, fallbacks[index]);
    }
  }

  /// Declarative navigation — tab roots use [switchTab]; other paths use [go].
  static void goIfDifferent(
    BuildContext context,
    String location, {
    Object? extra,
  }) {
    if (isSameLocation(context, location)) return;

    final pathOnly = normalizeLocation(location).split('?').first;
    final tabIndex = tabBranchIndex[pathOnly];
    if (tabIndex != null) {
      final shellState = _shellState(context);
      if (shellState != null) {
        switchTab(
          context,
          tabIndex,
          toRoot: tabIndex == shellState.currentIndex,
        );
        return;
      }
      resetTo(context, location, extra: extra);
      return;
    }
    resetTo(context, location, extra: extra);
  }

  /// Stack navigation — drill-down within a tab (exam → subject).
  static Future<Object?>? pushIfDifferent(
    BuildContext context,
    String location, {
    Object? extra,
  }) {
    if (isSameLocation(context, location)) return Future.value(null);
    return context.push<Object?>(location, extra: extra);
  }

  /// Pop only — never pushes a replacement route.
  static bool pop<T extends Object?>(BuildContext context, [T? result]) {
    if (!context.canPop()) return false;
    context.pop(result);
    return true;
  }

  /// Route-level back: pop when possible, otherwise navigate to [fallback].
  static void back(BuildContext context, String fallback) {
    popOrGoIfDifferent(context, fallback);
  }

  /// Prefer pop for back; fall back to [resetTo] only when stack is empty.
  static void popOrGoIfDifferent(BuildContext context, String fallback) {
    if (context.canPop()) {
      context.pop();
      return;
    }
    resetTo(context, fallback);
  }

  /// Handle system / browser back for a screen with an inner stack.
  static void handleNestedBack(BuildContext context, String tabRootFallback) {
    if (context.canPop()) {
      pop(context);
      return;
    }
    resetTo(context, tabRootFallback);
  }
}
