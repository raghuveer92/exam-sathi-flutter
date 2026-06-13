import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/google_auth_config.dart';
import '../../../core/auth/google_auth_service.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/sync/sync_service.dart';
import '../../../core/utils/responsive_helper.dart';
import '../../blocs/auth/auth_bloc.dart';
import '../../blocs/dashboard/dashboard_bloc.dart';
import '../../widgets/manual_sync_button.dart';
import '../../widgets/common/google_sign_in_button.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: BlocBuilder<DashboardBloc, DashboardState>(
        builder: (context, state) {
          final user = state is DashboardLoaded ? state.dashboard.user : null;
          return Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: ResponsiveHelper.isDesktop(context) ? 700 : double.infinity,
              ),
              child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                // Avatar
                Center(
                  child: Container(
                    width: 90,
                    height: 90,
                    decoration: const BoxDecoration(
                      gradient: AppColors.primaryGradient,
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        user?.firstName[0].toUpperCase() ?? 'S',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 36,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  user?.fullName ?? 'Student',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                Text(
                  user?.email ?? '',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                if (user?.selectedExamName != null) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      user!.selectedExamName!,
                      style: const TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 32),
                // Streak stat
                if (user != null) ...[
                  _StatRow(
                    icon: Icons.local_fire_department_rounded,
                    color: AppColors.streakFire,
                    label: 'Study Streak',
                    value: '${user.studyStreakDays} days',
                  ),
                  const Divider(height: 24),
                ],
                const Divider(height: 24),
                ManualSyncButton(
                  onComplete: () =>
                      context.read<DashboardBloc>().add(DashboardLoadRequested()),
                ),
                const SizedBox(height: 16),
                _ProfileTile(
                  icon: Icons.refresh_rounded,
                  label: 'Reset & Re-download',
                  onTap: () => _confirmResetDownload(context),
                ),
                const SizedBox(height: 16),
                _ProfileTile(
                  icon: Icons.school_outlined,
                  label: 'My Exams',
                  onTap: () => context.go('/my-exams'),
                ),
                _ProfileTile(
                  icon: Icons.notifications_outlined,
                  label: 'Notifications',
                  onTap: () {},
                ),
                _ProfileTile(
                  icon: Icons.help_outline_rounded,
                  label: 'Help & Support',
                  onTap: () {},
                ),
                const Divider(height: 24),
                _ProfileTile(
                  icon: Icons.delete_forever_outlined,
                  label: 'Delete Account',
                  color: AppColors.error,
                  onTap: () => _confirmDeleteAccount(context),
                ),
                _ProfileTile(
                  icon: Icons.logout_rounded,
                  label: 'Logout',
                  color: AppColors.error,
                  onTap: () {
                    context.read<AuthBloc>().add(AuthLogoutRequested());
                    context.go('/login');
                  },
                ),
              ],
            ),
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _confirmResetDownload(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reset & Re-download?'),
        content: const Text(
          'This clears the sync cursor and downloads all exam content again. '
          'Your local study progress is kept unless the server differs.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Re-download'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 20),
            Expanded(child: Text('Downloading all content…')),
          ],
        ),
      ),
    );

    try {
      await GetIt.I<SyncService>().resetAndRedownload(
        onProgress: (_) {},
      );
      if (!context.mounted) return;
      Navigator.pop(context);
      context.read<DashboardBloc>().add(DashboardLoadRequested());
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Full re-download complete')),
      );
    } catch (e) {
      if (!context.mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Re-download failed: $e')),
      );
    }
  }

  Future<void> _confirmDeleteAccount(BuildContext context) async {
    final authState = context.read<AuthBloc>().state;
    final dashboardState = context.read<DashboardBloc>().state;
    final authUser = authState is AuthAuthenticated ? authState.user : null;
    final dashboardUser =
        dashboardState is DashboardLoaded ? dashboardState.dashboard.user : null;
    final isGoogleAccount =
        authUser?.isGoogleAccount == true || dashboardUser?.isGoogleAccount == true;

    if (isGoogleAccount) {
      await _confirmDeleteGoogleAccount(context);
      return;
    }

    await _confirmDeleteWithPassword(context);
  }

  Future<void> _confirmDeleteGoogleAccount(BuildContext context) async {
    final proceed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete account?'),
        content: const Text(
          'This permanently deletes your account, exam enrollments, '
          'study progress, and test history. This cannot be undone.\n\n'
          'You will sign in with Google again to confirm.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    if (proceed != true || !context.mounted) return;

    String? idToken;
    if (kIsWeb) {
      idToken = await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => const _GoogleDeleteConfirmDialog(),
      );
    } else {
      try {
        idToken = await GetIt.I<GoogleAuthService>().signInAndGetIdToken();
      } catch (e) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Google Sign-In failed: $e')),
        );
        return;
      }
    }

    if (idToken == null || idToken.isEmpty || !context.mounted) return;
    await _runDeleteAccount(context, idToken: idToken);
  }

  Future<void> _confirmDeleteWithPassword(BuildContext context) async {
    final passwordController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete account?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'This permanently deletes your account, exam enrollments, '
              'study progress, and test history. This cannot be undone.',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: passwordController,
              obscureText: true,
              autofillHints: const [AutofillHints.password],
              decoration: const InputDecoration(
                labelText: 'Confirm your password',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete account'),
          ),
        ],
      ),
    );
    final password = passwordController.text;
    passwordController.dispose();
    if (confirmed != true || password.isEmpty || !context.mounted) {
      if (confirmed == true && password.isEmpty && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Enter your password to continue')),
        );
      }
      return;
    }

    await _runDeleteAccount(context, password: password);
  }

  Future<void> _runDeleteAccount(
    BuildContext context, {
    String? password,
    String? idToken,
  }) async {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 20),
            Expanded(child: Text('Deleting account…')),
          ],
        ),
      ),
    );

    final authBloc = context.read<AuthBloc>();
    final resultFuture = authBloc.stream.firstWhere(
      (state) => state is AuthUnauthenticated || state is AuthError,
    );
    authBloc.add(AuthDeleteAccountRequested(
      password: password,
      idToken: idToken,
    ));
    await resultFuture;

    if (!context.mounted) return;
    Navigator.pop(context);

    final state = authBloc.state;
    if (state is AuthError) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(state.message)),
      );
      return;
    }

    context.go('/login');
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Your account has been deleted')),
    );
  }
}

/// Web: GIS button to re-authenticate before account deletion.
class _GoogleDeleteConfirmDialog extends StatefulWidget {
  const _GoogleDeleteConfirmDialog();

  @override
  State<_GoogleDeleteConfirmDialog> createState() =>
      _GoogleDeleteConfirmDialogState();
}

class _GoogleDeleteConfirmDialogState extends State<_GoogleDeleteConfirmDialog> {
  StreamSubscription<String>? _tokenSub;

  @override
  void initState() {
    super.initState();
    if (GoogleAuthConfig.isConfigured) {
      _tokenSub = GetIt.I<GoogleAuthService>().webIdTokens.listen((idToken) {
        if (mounted) Navigator.pop(context, idToken);
      });
    }
  }

  @override
  void dispose() {
    _tokenSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Confirm with Google'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Sign in with the Google account linked to this profile to '
            'confirm deletion.',
          ),
          const SizedBox(height: 20),
          if (GoogleAuthConfig.isConfigured)
            GoogleSignInButton(
              isLoading: false,
              isSignUp: false,
              onPressed: () {},
            )
          else
            const Text('Google Sign-In is not configured.'),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}

class _StatRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String value;

  const _StatRow({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 10),
        Text(label, style: Theme.of(context).textTheme.titleMedium),
        const Spacer(),
        Text(value,
            style: TextStyle(
                fontWeight: FontWeight.w700, color: color, fontSize: 15)),
      ],
    );
  }
}

class _ProfileTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  const _ProfileTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.textPrimary;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: c),
      title: Text(label, style: TextStyle(color: c, fontWeight: FontWeight.w500)),
      trailing: color == null
          ? const Icon(Icons.chevron_right_rounded, color: AppColors.textHint)
          : null,
      onTap: onTap,
    );
  }
}
