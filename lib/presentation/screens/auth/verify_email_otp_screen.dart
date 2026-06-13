import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/utils/responsive_helper.dart';
import '../../blocs/auth/auth_bloc.dart';
import '../../widgets/common/auth_form_layout.dart';
import '../../widgets/common/gradient_button.dart';

class VerifyEmailOtpScreen extends StatefulWidget {
  final String email;
  final String fullName;
  final String password;

  const VerifyEmailOtpScreen({
    super.key,
    required this.email,
    required this.fullName,
    required this.password,
  });

  @override
  State<VerifyEmailOtpScreen> createState() => _VerifyEmailOtpScreenState();
}

class _VerifyEmailOtpScreenState extends State<VerifyEmailOtpScreen> {
  final _otpCtrl = TextEditingController();

  @override
  void dispose() {
    _otpCtrl.dispose();
    super.dispose();
  }

  void _verify() {
    final otp = _otpCtrl.text.trim();
    if (otp.length != 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter the 6-digit OTP from your email'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }
    context.read<AuthBloc>().add(AuthVerifyEmailOtpRequested(
          email: widget.email,
          otp: otp,
          password: widget.password,
        ));
  }

  void _resend() {
    context.read<AuthBloc>().add(AuthResendEmailOtpRequested(email: widget.email));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('A new OTP has been sent to your email.'),
        backgroundColor: AppColors.success,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isWide = !ResponsiveHelper.isMobile(context);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/login'),
        ),
      ),
      body: BlocConsumer<AuthBloc, AuthState>(
        listener: (context, state) {
          if (state is AuthError) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(state.message), backgroundColor: AppColors.error),
            );
          }
        },
        builder: (context, state) {
          return AuthFormLayout(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(Icons.pin_outlined, size: isWide ? 72 : 64, color: AppColors.primary),
                const SizedBox(height: 24),
                Text(
                  'Enter verification code',
                  style: isWide
                      ? Theme.of(context).textTheme.headlineMedium
                      : Theme.of(context).textTheme.displaySmall,
                ),
                const SizedBox(height: 12),
                Text(
                  'Hi ${widget.fullName}, we sent a 6-digit code to ${widget.email}.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: _otpCtrl,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  maxLength: 6,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  style: const TextStyle(fontSize: 28, letterSpacing: 12, fontWeight: FontWeight.w600),
                  decoration: const InputDecoration(
                    labelText: 'OTP',
                    hintText: '000000',
                    counterText: '',
                  ),
                  onSubmitted: (_) => _verify(),
                ),
                const SizedBox(height: 8),
                Text(
                  'The code expires in 10 minutes.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
                ),
                const SizedBox(height: 32),
                GradientButton(
                  label: 'Verify Email',
                  isLoading: state is AuthLoading,
                  onPressed: _verify,
                ),
                const SizedBox(height: 16),
                OutlinedButton(
                  onPressed: state is AuthLoading ? null : _resend,
                  child: const Text('Resend OTP'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
