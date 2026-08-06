// lib/theme/app_theme.dart

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Direct port of the CSS custom properties in `app/globals.css`.
/// Keep these in sync with the web app if the brand palette ever changes.
class AppColors {
  AppColors._();

  static const background = Color(0xFFF7F7F5);
  static const blush = Color(0xFFF2D2CF);
  static const dustyRose = Color(0xFFD7A5A5);
  static const primary = Color(0xFF9A5965);
  static const primaryHover = Color(0xFF83454F);
  static const charcoal = Color(0xFF555555);
  static const lightGray = Color(0xFFE3E3E0);
  static const textPrimary = Color(0xFF242424);
  static const white = Color(0xFFFFFFFF);

  static const surface = white;
  static const textSecondary = charcoal;
  static const border = lightGray;

  static const statusGreen = Color(0xFF2F7A4D);
  static const statusGreenBg = Color(0xE6D2F0DC);
  static const statusYellow = Color(0xFFA3730F);
  static const statusYellowBg = Color(0xE6FAE8C4);
  static const statusRed = primary;
  static const statusRedBg = Color(0xE6F2D2CF);

  static const calendarAvailable = Color(0xFF2F7A4D);
  static const calendarAvailableBg = Color(0x1F2F7A4D);
  static const calendarBooked = Color(0xFFC0392B);
  static const calendarBookedBg = Color(0x1FC0392B);
  static const calendarSelected = Color(0xFF145A32);
  static const calendarSelectedHover = Color(0xFF0E4527);
}

class AppTheme {
  AppTheme._();

  static ThemeData get light {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.primary,
        primary: AppColors.primary,
        surface: AppColors.surface,
        background: AppColors.background,
        error: AppColors.calendarBooked,
      ),
      scaffoldBackgroundColor: AppColors.background,
      textTheme: GoogleFonts.poppinsTextTheme().apply(
        bodyColor: AppColors.textPrimary,
        displayColor: AppColors.textPrimary,
      ),
    );

    return base.copyWith(
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.white,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: GoogleFonts.poppins(
          color: AppColors.textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.white,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          textStyle: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 15),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.textPrimary,
          side: const BorderSide(color: AppColors.border),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          textStyle: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 15),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.calendarBooked),
        ),
      ),
      cardTheme: CardThemeData(
        color: AppColors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: AppColors.border),
        ),
      ),
      dividerTheme: const DividerThemeData(color: AppColors.border, thickness: 1),
    );
  }
}
