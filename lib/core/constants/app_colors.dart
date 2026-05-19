import 'package:flutter/material.dart';

/// App-wide color palette — purple-blue gradient theme.
class AppColors {
  AppColors._();

  // Primary gradient
  static const Color primary = Color(0xFF6C63FF);
  static const Color primaryDark = Color(0xFF4B44D6);
  static const Color primaryLight = Color(0xFF9D97FF);
  static const Color secondary = Color(0xFF54A0FF);

  // Gradient stops
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [Color(0xFF6C63FF), Color(0xFF54A0FF)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient cardGradient = LinearGradient(
    colors: [Color(0xFF7B73FF), Color(0xFF6C63FF)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // Background & surfaces
  static const Color background = Color(0xFFF8F9FE);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color cardBg = Color(0xFFFFFFFF);

  // Text
  static const Color textPrimary = Color(0xFF1A1A2E);
  static const Color textSecondary = Color(0xFF6B7280);
  static const Color textHint = Color(0xFFADB5BD);
  static const Color textOnPrimary = Color(0xFFFFFFFF);

  // Subject colors (stored in DB, these are defaults)
  static const Color mathBlue = Color(0xFF1565C0);
  static const Color scienceGreen = Color(0xFF2E7D32);
  static const Color englishPurple = Color(0xFF6A1B9A);
  static const Color hindiPink = Color(0xFFAD1457);
  static const Color socialOrange = Color(0xFFE65100);
  static const Color chemYellow = Color(0xFFF9A825);
  static const Color bioTeal = Color(0xFF00695C);
  static const Color physicsIndigo = Color(0xFF283593);

  // Status colors
  static const Color success = Color(0xFF43D854);
  static const Color error = Color(0xFFFF6B6B);
  static const Color warning = Color(0xFFFF9F43);
  static const Color info = Color(0xFF54A0FF);

  // UI elements
  static const Color divider = Color(0xFFEEEFF5);
  static const Color shadow = Color(0x1A6C63FF);
  static const Color shimmerBase = Color(0xFFE8EBF5);
  static const Color shimmerHighlight = Color(0xFFF5F7FF);

  // Streak / fire
  static const Color streakFire = Color(0xFFFF6B35);
}
