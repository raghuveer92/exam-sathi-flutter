import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/auth/google_auth_config.dart';
import '../../../core/firebase/analytics_service.dart';
import '../../../core/firebase/crashlytics_service.dart';
import '../../../core/router/app_navigation.dart';
import '../../blocs/auth/auth_bloc.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/network/api_endpoints.dart';
import '../../../core/testing/test_keys.dart';
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
  }

  @override
  void dispose() {
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
            CrashlyticsService.setUser(userId: state.user.id.toString());
          }
          if (state is AuthRegistrationPending) {
            AppNavigation.goIfDifferent(
              context,
              '/verify-email-otp?email=${Uri.encodeComponent(state.email)}&name=${Uri.encodeComponent(state.fullName)}',
            );
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
                    fieldKey: TestKeys.loginEmail,
                    controller: _emailCtrl,
                    label: AppStrings.email,
                    hint: 'you@example.com',
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    onFieldSubmitted: (_) => FocusScope.of(context).nextFocus(),
                    prefixIcon: Icons.email_outlined,
                    validator: (v) {
                      if (v == null || v.isEmpty) {
                        return AppStrings.fieldRequired;
                      }
                      if (!v.contains('@')) return AppStrings.invalidEmail;
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  AppTextField(
                    fieldKey: TestKeys.loginPassword,
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
                      if (v == null || v.isEmpty) {
                        return AppStrings.fieldRequired;
                      }
                      if (v.length < 6) return AppStrings.passwordTooShort;
                      return null;
                    },
                  ),
                  const SizedBox(height: 4),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () => AppNavigation.goIfDifferent(
                          context, '/forgot-password'),
                      child: const Text(AppStrings.forgotPassword),
                    ),
                  ),
                  const SizedBox(height: 16),
                  GradientButton(
                    key: TestKeys.loginSubmit,
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
                    if (state is AuthError) ...[
                      const SizedBox(height: 12),
                      _AuthErrorPanel(message: state.message),
                    ],
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
                        key: TestKeys.signUpLink,
                        onTap: () =>
                            AppNavigation.goIfDifferent(context, '/register'),
                        child: const Text(
                          AppStrings.signUp,
                          style: TextStyle(
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

class _AuthErrorPanel extends StatelessWidget {
  final String message;

  const _AuthErrorPanel({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.error_outline,
            color: AppColors.error,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 13,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
