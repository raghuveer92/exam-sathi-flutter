import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/router/app_navigation.dart';
import '../../blocs/auth/auth_bloc.dart';
import '../../widgets/common/auth_form_layout.dart';
import '../../widgets/common/gradient_button.dart';

class ForgotPasswordOtpScreen extends StatefulWidget {
  final String email;

  const ForgotPasswordOtpScreen({super.key, required this.email});

  @override
  State<ForgotPasswordOtpScreen> createState() => _ForgotPasswordOtpScreenState();
}

class _ForgotPasswordOtpScreenState extends State<ForgotPasswordOtpScreen> {
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
    context.read<AuthBloc>().add(AuthVerifyForgotPasswordOtpRequested(
          email: widget.email,
          otp: otp,
        ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(leading: const BackButton()),
      body: BlocConsumer<AuthBloc, AuthState>(
        listener: (context, state) {
          if (state is AuthForgotPasswordOtpVerified) {
            AppNavigation.goIfDifferent(
              context,
              '/reset-password?email=${Uri.encodeComponent(state.email)}&otp=${Uri.encodeComponent(state.otp)}',
            );
          }
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
                const Text('Enter reset code'),
                const SizedBox(height: 12),
                Text('We sent a 6-digit code to ${widget.email}.'),
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
                const SizedBox(height: 32),
                GradientButton(
                  label: 'Continue',
                  isLoading: state is AuthLoading,
                  onPressed: _verify,
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
