import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/google_auth_config.dart';
import '../../../core/auth/google_auth_service.dart';
import '../../../core/firebase/analytics_service.dart';
import '../../blocs/auth/auth_bloc.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/utils/responsive_helper.dart';
import '../../widgets/common/auth_or_divider.dart';
import '../../widgets/common/google_sign_in_button.dart';
import '../../widgets/common/auth_form_layout.dart';
import '../../widgets/common/gradient_button.dart';
import '../../widgets/common/app_text_field.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  bool _obscurePassword = true;
  StreamSubscription? _googleWebSub;

  @override
  void initState() {
    super.initState();
    if (kIsWeb && GoogleAuthConfig.isConfigured) {
      final googleAuth = GetIt.I<GoogleAuthService>();
      _googleWebSub = googleAuth.listenForWebSignIn(
        onSignedIn: (idToken) {
          if (!mounted) return;
          context.read<AuthBloc>().add(AuthGoogleSignInWithIdToken(idToken));
        },
        onError: (e) {
          if (!mounted) return;
          final message = e is StateError
              ? e.message
              : 'Google Sign-In failed. Please try again.';
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(message), backgroundColor: AppColors.error),
          );
        },
      );
    }
  }

  @override
  void dispose() {
    _googleWebSub?.cancel();
    if (kIsWeb) {
      GetIt.I<GoogleAuthService>().cancelWebSignInListener();
    }
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  void _register() {
    if (_formKey.currentState?.validate() != true) return;
    context.read<AuthBloc>().add(AuthRegisterRequested(
      fullName: _nameCtrl.text.trim(),
      email: _emailCtrl.text.trim(),
      password: _passwordCtrl.text,
      phone: _phoneCtrl.text.trim().isEmpty ? null : _phoneCtrl.text.trim(),
    ));
  }

  void _googleSignIn() {
    if (kIsWeb) return;
    context.read<AuthBloc>().add(AuthGoogleSignInRequested());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(leading: const BackButton()),
      body: BlocConsumer<AuthBloc, AuthState>(
        listener: (context, state) {
          if (state is AuthAuthenticated) {
            AnalyticsService.logLogin();
          }
          if (state is AuthError) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(state.message),
                backgroundColor: AppColors.error,
              ),
            );
          }
        },
        builder: (context, state) {
          final isWide = !ResponsiveHelper.isMobile(context);
          final googleEnabled = GoogleAuthConfig.isConfigured;
          final titleStyle = isWide
              ? Theme.of(context).textTheme.headlineMedium
              : Theme.of(context).textTheme.displaySmall;

          return AuthFormLayout(
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Create Account ✨',
                    style: titleStyle,
                    textAlign: isWide ? TextAlign.center : TextAlign.start,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Join thousands of students achieving their goals',
                    style: Theme.of(context).textTheme.bodyMedium,
                    textAlign: isWide ? TextAlign.center : TextAlign.start,
                  ),
                  SizedBox(height: isWide ? 24 : 32),
                    AppTextField(
                      controller: _nameCtrl,
                      label: AppStrings.fullName,
                      hint: 'Aarav Sharma',
                      prefixIcon: Icons.person_outline,
                      validator: (v) =>
                          (v == null || v.isEmpty) ? AppStrings.fieldRequired : null,
                    ),
                    const SizedBox(height: 16),
                    AppTextField(
                      controller: _emailCtrl,
                      label: AppStrings.email,
                      hint: 'you@example.com',
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      onFieldSubmitted: (_) => FocusScope.of(context).nextFocus(),
                      prefixIcon: Icons.email_outlined,
                      validator: (v) {
                        if (v == null || v.isEmpty) return AppStrings.fieldRequired;
                        if (!v.contains('@')) return AppStrings.invalidEmail;
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    AppTextField(
                      controller: _passwordCtrl,
                      label: AppStrings.password,
                      hint: 'Min 6 characters',
                      obscureText: _obscurePassword,
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) => _register(),
                      prefixIcon: Icons.lock_outline,
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                          color: AppColors.textHint,
                        ),
                        onPressed: () =>
                            setState(() => _obscurePassword = !_obscurePassword),
                      ),
                      validator: (v) {
                        if (v == null || v.isEmpty) return AppStrings.fieldRequired;
                        if (v.length < 6) return AppStrings.passwordTooShort;
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    AppTextField(
                      controller: _phoneCtrl,
                      label: 'Phone (optional)',
                      hint: '+91 98765 43210',
                      keyboardType: TextInputType.phone,
                      prefixIcon: Icons.phone_outlined,
                    ),
                    const SizedBox(height: 32),
                    if (googleEnabled) ...[
                      GoogleSignInButton(
                        isLoading: state is AuthLoading,
                        onPressed: _googleSignIn,
                        isSignUp: true,
                      ),
                      const SizedBox(height: 20),
                      const AuthOrDivider(),
                      const SizedBox(height: 20),
                    ],
                    GradientButton(
                      label: 'Create Account',
                      isLoading: state is AuthLoading,
                      onPressed: _register,
                    ),
                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          AppStrings.alreadyHaveAccount,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        GestureDetector(
                          onTap: () => context.go('/login'),
                          child: const Text(
                            AppStrings.signIn,
                            style: TextStyle(
                              color: AppColors.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
