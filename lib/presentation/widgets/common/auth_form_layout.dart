import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/utils/responsive_helper.dart';

/// Centers auth forms on tablet/web with a compact max width.
class AuthFormLayout extends StatelessWidget {
  final Widget child;

  const AuthFormLayout({super.key, required this.child});

  static const double _formMaxWidth = 420;

  @override
  Widget build(BuildContext context) {
    final isWide = !ResponsiveHelper.isMobile(context);
    final horizontal = ResponsiveHelper.horizontalPadding(context);

    return SafeArea(
      child: Align(
        alignment: isWide ? Alignment.center : Alignment.topCenter,
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            horizontal,
            isWide ? 24 : 16,
            horizontal,
            24,
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: isWide ? _formMaxWidth : double.infinity,
            ),
            child: isWide
                ? DecoratedBox(
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppColors.divider),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.04),
                          blurRadius: 24,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(28, 28, 28, 24),
                      child: child,
                    ),
                  )
                : child,
          ),
        ),
      ),
    );
  }
}
