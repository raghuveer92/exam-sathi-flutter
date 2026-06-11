import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/google_auth_config.dart';
import '../../../core/auth/google_auth_service.dart';
import '../../../core/firebase/analytics_service.dart';
import '../../../core/firebase/crashlytics_service.dart';
import '../../blocs/auth/auth_bloc.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/network/api_endpoints.dart';
import '../../../core/utils/responsive_helper.dart';
import '../../widgets/common/auth_or_divider.dart';
import '../../widgets/common/google_sign_in_button.dart';
import '../../widgets/common/auth_form_layout.dart';
import '../../widgets/common/gradient_button.dart';
import '../../widgets/common/app_text_field.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _obscurePassword = true;
  StreamSubscription? _googleWebSub;

  static bool get _isLocalBackend {
    const url = ApiEndpoints.baseUrl;
    return url.contains('localhost') || url.contains('127.0.0.1');
  }

  @override
  void initState() {
    super.initState();
    if (_isLocalBackend) {
      _emailCtrl.text = 'abc@gmail.comm';
      _passwordCtrl.text = 'Abc@123';
    }
    if (kIsWeb && GoogleAuthConfig.isConfigured) {
      unawaited(_setupWebGoogleSignIn());
    }
  }

  Future<void> _setupWebGoogleSignIn() async {
    final googleAuth = GetIt.I<GoogleAuthService>();
    _googleWebSub = await googleAuth.listenForWebSignIn(
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

  @override
  void dispose() {
    _googleWebSub?.cancel();
    if (kIsWeb) {
      GetIt.I<GoogleAuthService>().cancelWebSignInListener();
    }
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  void _login() {
    if (_formKey.currentState?.validate() != true) return;
    context.read<AuthBloc>().add(AuthLoginRequested(
      email: _emailCtrl.text.trim(),
      password: _passwordCtrl.text,
    ));
  }

  void _googleSignIn() {
    if (kIsWeb) return;
    context.read<AuthBloc>().add(AuthGoogleSignInRequested());
  }

  @override
  Widget build(BuildContext context) {
    final googleEnabled = GoogleAuthConfig.isConfigured;
    return Scaffold(
      body: BlocConsumer<AuthBloc, AuthState>(
        listener: (context, state) {
          if (state is AuthAuthenticated) {
            AnalyticsService.logLogin();
            CrashlyticsService.setUser(userId: state.user.id.toString(), email: state.user.email);
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
          final logoSize = isWide ? 72.0 : 100.0;
          final topSpacing = isWide ? 0.0 : 24.0;
          final titleStyle = isWide
              ? Theme.of(context).textTheme.headlineMedium
              : Theme.of(context).textTheme.displaySmall;

          return AuthFormLayout(
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(height: topSpacing),
                  Center(
                    child: Image.asset(
                      'assets/images/logo.png',
                      width: logoSize,
                      height: logoSize,
                    ),
                  ),
                  SizedBox(height: isWide ? 20 : 24),
                  Text(
                    'Welcome back! 👋',
                    style: titleStyle,
                    textAlign: isWide ? TextAlign.center : TextAlign.start,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Login to continue your study journey',
                    style: Theme.of(context).textTheme.bodyMedium,
                    textAlign: isWide ? TextAlign.center : TextAlign.start,
                  ),
                  SizedBox(height: isWide ? 28 : 32),
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
                    hint: '••••••••',
                    obscureText: _obscurePassword,
                    textInputAction: TextInputAction.done,
                    onFieldSubmitted: (_) => _login(),
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
                  const SizedBox(height: 4),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () {},
                      child: const Text(AppStrings.forgotPassword),
                    ),
                  ),
                  const SizedBox(height: 16),
                  GradientButton(
                    label: AppStrings.signIn,
                    isLoading: state is AuthLoading,
                    onPressed: _login,
                  ),
                  if (googleEnabled) ...[
                    const SizedBox(height: 20),
                    const AuthOrDivider(),
                    const SizedBox(height: 20),
                    GoogleSignInButton(
                      isLoading: state is AuthLoading,
                      onPressed: _googleSignIn,
                    ),
                  ],
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        AppStrings.dontHaveAccount,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      GestureDetector(
                        onTap: () => context.go('/register'),
                        child: Text(
                          AppStrings.signUp,
                          style: const TextStyle(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
