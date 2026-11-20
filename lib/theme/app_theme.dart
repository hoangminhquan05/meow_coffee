import 'package:flutter/material.dart';

class AppColors {
  static const Color purple80 = Color(0xFFD0BCFF);
  static const Color purpleGrey80 = Color(0xFFCCC2DC);
  static const Color pink80 = Color(0xFFEFB8C8);

  static const Color purple40 = Color(0xFF6650A4);
  static const Color purpleGrey40 = Color(0xFF625B71);
  static const Color pink40 = Color(0xFF7D5260);

  // Brand colors used across Meow Coffee screens
  static const Color mutedPurple = Color(0xFF6D597A);
  static const Color softPurple = Color(0xFF9F86C0);
  static const Color deepPurple = Color(0xFF6200EA);
  static const Color coffeeBrown = Color(0xFF6D4C41);
}

class AppTheme {
  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      colorScheme: const ColorScheme.light(
        primary: AppColors.purple40,
        secondary: AppColors.purpleGrey40,
        tertiary: AppColors.pink40,
      ),
    );
  }

  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      colorScheme: const ColorScheme.dark(
        primary: AppColors.purple80,
        secondary: AppColors.purpleGrey80,
        tertiary: AppColors.pink80,
      ),
    );
  }
}
