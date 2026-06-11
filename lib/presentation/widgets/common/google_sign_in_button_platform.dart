import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';

/// Mobile / desktop native: custom outlined Google button.
Widget buildGoogleSignInButton({
  required VoidCallback? onPressed,
  required bool isLoading,
  required bool isSignUp,
}) {
  return SizedBox(
    width: double.infinity,
    height: 52,
    child: OutlinedButton(
      onPressed: isLoading ? null : onPressed,
      style: OutlinedButton.styleFrom(
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        side: const BorderSide(color: AppColors.divider),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
      ),
      child: isLoading
          ? const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            )
          : Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Image.asset(
                  'assets/images/google_logo.png',
                  width: 22,
                  height: 22,
                  errorBuilder: (_, __, ___) => const Icon(
                    Icons.g_mobiledata_rounded,
                    size: 28,
                    color: AppColors.error,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  isSignUp ? 'Sign up with Google' : 'Continue with Google',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
    ),
  );
}
