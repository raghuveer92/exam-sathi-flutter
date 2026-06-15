import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'package:google_sign_in_web/google_sign_in_web.dart';

void registerGoogleSignInWebIfNeeded() {
  GoogleSignInPlugin.registerWith(webPluginRegistrar);
}
