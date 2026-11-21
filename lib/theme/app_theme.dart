import 'package:flutter/material.dart';

class AppColors {
  // Figma Page 3 — Meow Coffee Design System Tokens
  static const Color bg = Color(0xFFFCFAF7);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color ink = Color(0xFF241C35);
  static const Color inkSlate = Color(0xFF1E293B);
  static const Color muted = Color(0xFF766F83);
  static const Color mutedLight = Color(0xFF94A3B8);
  static const Color brand = Color(0xFF6D3EE8);
  static const Color brandDark = Color(0xFF592DC2);
  static const Color brandLight = Color(0xFF8B5CF6);
  static const Color soft = Color(0xFFF2ECFC);
  static const Color softBorder = Color(0xFFE6DCF7);
  static const Color border = Color(0xFFEBE5F0);
  static const Color borderSubtle = Color(0xFFE5DCFA);
  static const Color warmLabel = Color(0xFF9A7F5F);
  static const Color storyBg = Color(0xFF342344);
  static const Color storyGold = Color(0xFFE7C798);
  static const Color success = Color(0xFF059669);
  static const Color successSoft = Color(0xFFECFDF5);
  static const Color danger = Color(0xFFF43F5E);
  static const Color dangerSoft = Color(0xFFFFF1F2);
  static const Color warning = Color(0xFFD97706);
  static const Color warningSoft = Color(0xFFFEF3C7);

  static const LinearGradient brandGradient = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [brandDark, brandLight],
  );

  static const List<BoxShadow> cardShadow = [
    BoxShadow(
      color: Color(0x123C245E),
      blurRadius: 14,
      offset: Offset(0, 6),
    ),
  ];

  static const List<BoxShadow> buttonShadow = [
    BoxShadow(
      color: Color(0x336D3EE8),
      blurRadius: 12,
      offset: Offset(0, 5),
    ),
  ];

  static const List<BoxShadow> inputShadow = [
    BoxShadow(
      color: Color(0x083C245E),
      blurRadius: 8,
      offset: Offset(0, 2),
    ),
  ];

  // Legacy aliases kept for backwards compatibility across screens
  static const Color purple80 = Color(0xFFD0BCFF);
  static const Color purpleGrey80 = Color(0xFFCCC2DC);
  static const Color pink80 = Color(0xFFEFB8C8);
  static const Color purple40 = brand;
  static const Color purpleGrey40 = muted;
  static const Color pink40 = Color(0xFF7D5260);
  static const Color mutedPurple = muted;
  static const Color softPurple = brandLight;
  static const Color deepPurple = brand;
  static const Color coffeeBrown = ink;
}

class AppTheme {
  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: AppColors.bg,
      colorScheme: const ColorScheme.light(
        primary: AppColors.brand,
        onPrimary: Colors.white,
        primaryContainer: AppColors.soft,
        onPrimaryContainer: AppColors.ink,
        secondary: AppColors.brandLight,
        onSecondary: Colors.white,
        secondaryContainer: AppColors.bg,
        onSecondaryContainer: AppColors.ink,
        surface: AppColors.surface,
        onSurface: AppColors.ink,
        onSurfaceVariant: AppColors.muted,
        outline: AppColors.border,
        error: AppColors.danger,
        onError: Colors.white,
        errorContainer: AppColors.dangerSoft,
        onErrorContainer: AppColors.danger,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.bg,
        foregroundColor: AppColors.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w700,
          color: AppColors.ink,
          letterSpacing: -0.3,
        ),
      ),
      cardTheme: CardThemeData(
        color: AppColors.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: AppColors.border),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.ink,
        contentTextStyle: const TextStyle(color: Colors.white, fontSize: 13),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        behavior: SnackBarBehavior.floating,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        hintStyle: const TextStyle(color: AppColors.mutedLight, fontSize: 14),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.brand, width: 1.5),
        ),
      ),
    );
  }

  static ThemeData get darkTheme => lightTheme;
}
