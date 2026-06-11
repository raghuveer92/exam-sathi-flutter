import 'package:flutter/material.dart';

import 'google_sign_in_button_platform.dart'
    if (dart.library.html) 'google_sign_in_button_web.dart' as platform;

/// Google Sign-In button — GIS native button on web, custom button elsewhere.
class GoogleSignInButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final bool isLoading;
  final bool isSignUp;

  const GoogleSignInButton({
    super.key,
    required this.onPressed,
    this.isLoading = false,
    this.isSignUp = false,
  });

  @override
  Widget build(BuildContext context) {
    return platform.buildGoogleSignInButton(
      onPressed: onPressed,
      isLoading: isLoading,
      isSignUp: isSignUp,
    );
  }
}
