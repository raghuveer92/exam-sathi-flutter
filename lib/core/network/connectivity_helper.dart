import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Returns whether the device likely has network access.
///
/// On web, connectivity_plus has no platform implementation — always assume online
/// and let API calls succeed or fail naturally.
Future<bool> isDeviceOnline() async {
  if (kIsWeb) return true;
  try {
    final results = await Connectivity().checkConnectivity();
    return results.any((r) => r != ConnectivityResult.none);
  } on MissingPluginException {
    return true;
  } catch (_) {
    return true;
  }
}

/// Starts listening for connectivity changes. Returns null on web.
StreamSubscription<List<ConnectivityResult>>? listenForConnectivity(
  void Function(bool online) onChanged,
) {
  if (kIsWeb) return null;
  try {
    return Connectivity().onConnectivityChanged.listen((results) {
      onChanged(results.any((r) => r != ConnectivityResult.none));
    });
  } on MissingPluginException {
    return null;
  } catch (_) {
    return null;
  }
}
