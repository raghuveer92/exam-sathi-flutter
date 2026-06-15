import 'google_sign_in_web_registration_stub.dart'
    if (dart.library.html) 'google_sign_in_web_registration_web.dart' as impl;

void registerGoogleSignInWebIfNeeded() => impl.registerGoogleSignInWebIfNeeded();
