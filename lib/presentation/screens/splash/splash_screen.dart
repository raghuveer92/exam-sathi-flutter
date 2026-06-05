import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../blocs/auth/auth_bloc.dart';
import '../../../core/constants/app_colors.dart';

/// Splash screen — checks auth state and redirects.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocListener<AuthBloc, AuthState>(
      listener: (context, state) {
        if (state is AuthError) {
          context.go('/login');
        }
      },
      child: Scaffold(
        body: Container(
          decoration: const BoxDecoration(gradient: AppColors.primaryGradient),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Image.asset(
                  'assets/images/logo.png',
                  width: 160,
                  height: 160,
                ),
                const SizedBox(height: 24),
                const Text(
                  'ExamSaathi',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 36,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.0,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Study Smarter, Not Harder',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.85),
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 60),
                const CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
