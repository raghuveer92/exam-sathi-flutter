import 'dart:html' as html;

import 'package:hive_flutter/hive_flutter.dart';

import '../local/local_store.dart';

Future<void> resetIntegrationTestPersistence() async {
  html.window.localStorage.clear();
  html.window.sessionStorage.clear();

  try {
    await Hive.initFlutter();
    if (await Hive.boxExists(LocalStore.boxNameForTests)) {
      await Hive.deleteBoxFromDisk(LocalStore.boxNameForTests);
    }
  } catch (_) {
    // Best-effort — a fresh box is opened on the next init().
  }
}
