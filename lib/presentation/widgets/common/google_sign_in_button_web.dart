import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:google_sign_in_web/web_only.dart';

import '../../../core/auth/google_auth_service.dart';
import '../../../core/constants/app_colors.dart';

/// Web: GIS SDK button (custom buttons cannot call authenticate on web).
Widget buildGoogleSignInButton({
  required VoidCallback? onPressed,
  required bool isLoading,
  required bool isSignUp,
}) {
  return _GoogleSignInWebButton(
    isLoading: isLoading,
    isSignUp: isSignUp,
  );
}

class _GoogleSignInWebButton extends StatefulWidget {
  final bool isLoading;
  final bool isSignUp;

  const _GoogleSignInWebButton({
    required this.isLoading,
    required this.isSignUp,
  });

  @override
  State<_GoogleSignInWebButton> createState() => _GoogleSignInWebButtonState();
}

class _GoogleSignInWebButtonState extends State<_GoogleSignInWebButton> {
  late final Future<void> _ready;

  @override
  void initState() {
    super.initState();
    _ready = GetIt.I<GoogleAuthService>().initialize();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isLoading) {
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

    return FutureBuilder<void>(
      future: _ready,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return _loadingShell();
        }
        if (snapshot.hasError) {
          return _fallbackButton(context);
        }

        return LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth.isFinite
                ? constraints.maxWidth.clamp(240.0, 400.0)
                : 400.0;

            return SizedBox(
              width: double.infinity,
              height: 52,
              child: Center(
                child: renderButton(
                  configuration: GSIButtonConfiguration(
                    type: GSIButtonType.standard,
                    theme: GSIButtonTheme.outline,
                    size: GSIButtonSize.large,
                    text: widget.isSignUp
                        ? GSIButtonText.signupWith
                        : GSIButtonText.continueWith,
                    minimumWidth: width,
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _loadingShell() {
    return Container(
      width: double.infinity,
      height: 52,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.divider),
        borderRadius: BorderRadius.circular(14),
        color: AppColors.surface,
      ),
      child: const SizedBox(
        width: 22,
        height: 22,
        child: CircularProgressIndicator(strokeWidth: 2.5),
      ),
    );
  }

  /// Visible fallback if GIS fails to initialize (e.g. OAuth origin not registered).
  Widget _fallbackButton(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: OutlinedButton(
        onPressed: () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Google Sign-In is unavailable. Add this site URL to '
                'Authorized JavaScript origins in Google Cloud Console.',
              ),
              duration: Duration(seconds: 5),
            ),
          );
        },
        style: OutlinedButton.styleFrom(
          backgroundColor: AppColors.surface,
          foregroundColor: AppColors.textPrimary,
          side: const BorderSide(color: AppColors.divider),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.g_mobiledata_rounded, size: 28, color: AppColors.error),
            const SizedBox(width: 12),
            Text(
              widget.isSignUp ? 'Sign up with Google' : 'Continue with Google',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}
