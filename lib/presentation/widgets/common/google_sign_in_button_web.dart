import 'package:flutter/material.dart';
import 'package:google_sign_in_web/web_only.dart';

/// Web: GIS SDK button (custom buttons cannot call authenticate on web).
Widget buildGoogleSignInButton({
  required VoidCallback? onPressed,
  required bool isLoading,
  required bool isSignUp,
}) {
  if (isLoading) {
    return const SizedBox(
      width: double.infinity,
      height: 52,
      child: Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2.5),
        ),
      ),
    );
  }

  return SizedBox(
    width: double.infinity,
    height: 52,
    child: Center(
      child: renderButton(
        configuration: GSIButtonConfiguration(
          type: GSIButtonType.standard,
          theme: GSIButtonTheme.outline,
          size: GSIButtonSize.large,
          text: isSignUp ? GSIButtonText.signupWith : GSIButtonText.continueWith,
          minimumWidth: 400,
        ),
      ),
    ),
  );
}
