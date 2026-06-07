import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../constants/app_colors.dart';

class AppTheme {
  AppTheme._();

  /// Dark icons on light backgrounds (Dashboard, Subjects, etc.).
  static const SystemUiOverlayStyle lightScreenOverlay = SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
    statusBarBrightness: Brightness.light,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarIconBrightness: Brightness.dark,
  );

  /// Light icons on dark/colored backgrounds (splash, login hero).
  static const SystemUiOverlayStyle darkScreenOverlay = SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    statusBarBrightness: Brightness.dark,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarIconBrightness: Brightness.light,
  );

  static ThemeData get lightTheme => ThemeData(
        useMaterial3: true,
        fontFamily: 'Poppins',
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.primary,
          brightness: Brightness.light,
          primary: AppColors.primary,
          secondary: AppColors.secondary,
          surface: AppColors.surface,
          background: AppColors.background,
          error: AppColors.error,
        ),
        scaffoldBackgroundColor: AppColors.background,
        appBarTheme: const AppBarTheme(
          backgroundColor: AppColors.background,
          elevation: 0,
          scrolledUnderElevation: 0,
          centerTitle: false,
          foregroundColor: AppColors.textPrimary,
          systemOverlayStyle: lightScreenOverlay,
        ),
        cardTheme: CardTheme(
          color: AppColors.cardBg,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          clipBehavior: Clip.antiAlias,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            textStyle: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: AppColors.surface,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.divider),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.divider),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.primary, width: 2),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.error),
          ),
          hintStyle: const TextStyle(color: AppColors.textHint, fontSize: 14),
          labelStyle: const TextStyle(color: AppColors.textSecondary),
        ),
        textTheme: const TextTheme(
          displayLarge: TextStyle(
            fontSize: 32, fontWeight: FontWeight.w700, color: AppColors.textPrimary, height: 1.2),
          displayMedium: TextStyle(
            fontSize: 28, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
          displaySmall: TextStyle(
            fontSize: 24, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
          headlineMedium: TextStyle(
            fontSize: 20, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
          headlineSmall: TextStyle(
            fontSize: 18, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
          titleLarge: TextStyle(
            fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
          titleMedium: TextStyle(
            fontSize: 14, fontWeight: FontWeight.w500, color: AppColors.textPrimary),
          bodyLarge: TextStyle(fontSize: 16, color: AppColors.textPrimary, height: 1.5),
          bodyMedium: TextStyle(fontSize: 14, color: AppColors.textSecondary, height: 1.5),
          bodySmall: TextStyle(fontSize: 12, color: AppColors.textHint),
          labelLarge: TextStyle(
            fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.primary),
        ),
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: AppColors.surface,
          selectedItemColor: AppColors.primary,
          unselectedItemColor: AppColors.textHint,
          type: BottomNavigationBarType.fixed,
          elevation: 8,
          selectedLabelStyle: TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
          unselectedLabelStyle: TextStyle(fontSize: 11),
        ),
        dividerTheme: const DividerThemeData(
          color: AppColors.divider,
          thickness: 1,
          space: 0,
        ),
        progressIndicatorTheme: const ProgressIndicatorThemeData(
          color: AppColors.primary,
          linearTrackColor: AppColors.divider,
        ),
      );
}
