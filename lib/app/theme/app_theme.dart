import 'package:flutter/material.dart';

class AppTheme {
  static const Color primaryColor = Colors.black;
  static const Color lightSurface = Colors.white;
  static const Color darkSurface = Colors.black;
  static const Color highlight = Color.fromARGB(255, 70, 154, 249);

  static Color readableOn(Color color) {
    return color.computeLuminance() > 0.55 ? Colors.black : Colors.white;
  }

  static Color subtleOn(Color color, double alpha) {
    return color.withValues(alpha: alpha);
  }

  static AppBarTheme appBarTheme({
    String fontFamily = 'Inter',
    required Color primaryColor,
    required Color surfaceColor,
  }) {
    return AppBarTheme(
      titleSpacing: 0,
      leadingWidth: 40,
      centerTitle: false,
      backgroundColor: surfaceColor,
      foregroundColor: primaryColor,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleTextStyle: TextStyle(
        fontFamily: fontFamily,
        fontSize: 18,
        color: primaryColor,
        fontWeight: FontWeight.bold,
      ),
      toolbarTextStyle: TextStyle(
        fontFamily: fontFamily,
        fontSize: 16,
        color: primaryColor,
        fontWeight: FontWeight.w500,
      ),
    );
  }

  static const TextStyle headingLarge = TextStyle(
    fontSize: 28,
    fontWeight: FontWeight.bold,
  );

  static const TextStyle headingMedium = TextStyle(
    fontSize: 22,
    fontWeight: FontWeight.w600,
  );

  static const TextStyle headingSmall = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w600,
  );

  static const TextStyle bodyLarge = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.normal,
  );

  static const TextStyle bodyMedium = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.normal,
  );

  static const TextStyle bodySmall = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.normal,
    color: Color(0xFF757575),
  );

  static ThemeData light({String fontFamily = 'Inter'}) {
    return _build(
      fontFamily: fontFamily,
      brightness: Brightness.light,
      primaryColor: Colors.black,
      surfaceColor: lightSurface,
    );
  }

  static ThemeData dark({String fontFamily = 'Inter'}) {
    return _build(
      fontFamily: fontFamily,
      brightness: Brightness.dark,
      primaryColor: Colors.white,
      surfaceColor: darkSurface,
    );
  }

  static ThemeData _build({
    required String fontFamily,
    required Brightness brightness,
    required Color primaryColor,
    required Color surfaceColor,
  }) {
    final onPrimary = readableOn(primaryColor);
    final onSurface = primaryColor;
    final onSurfaceVariant = primaryColor.withValues(alpha: 0.68);
    final outline = primaryColor.withValues(alpha: 0.3);
    final surfaceContainer = primaryColor.withValues(alpha: 0.05);
    final surfaceContainerHighest = primaryColor.withValues(alpha: 0.1);

    return ThemeData(
      fontFamily: fontFamily,
      useMaterial3: true,
      brightness: brightness,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primaryColor,
        brightness: brightness,
        primary: primaryColor,
        onPrimary: onPrimary,
        secondary: primaryColor,
        onSecondary: onPrimary,
        surface: surfaceColor,
        onSurface: onSurface,
        onSurfaceVariant: onSurfaceVariant,
        outline: outline,
        surfaceContainer: surfaceContainer,
        surfaceContainerHighest: surfaceContainerHighest,
      ),
      scaffoldBackgroundColor: surfaceColor,
      appBarTheme: appBarTheme(
        fontFamily: fontFamily,
        primaryColor: primaryColor,
        surfaceColor: surfaceColor,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceColor,
        hintStyle: TextStyle(color: onSurfaceVariant),
        prefixIconColor: primaryColor,
        suffixIconColor: primaryColor,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: primaryColor.withValues(alpha: 0.2)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: primaryColor, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surfaceColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: primaryColor.withValues(alpha: 0.12)),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primaryColor,
          foregroundColor: onPrimary,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryColor,
          foregroundColor: onPrimary,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primaryColor,
          side: BorderSide(color: outline),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: primaryColor),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          return states.contains(WidgetState.selected)
              ? onPrimary
              : surfaceColor;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          return states.contains(WidgetState.selected)
              ? primaryColor
              : primaryColor.withValues(alpha: 0.15);
        }),
      ),
      snackBarTheme: SnackBarThemeData(
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(16),
            topRight: Radius.circular(4),
            bottomLeft: Radius.circular(16),
            bottomRight: Radius.circular(16),
          ),
        ),
        backgroundColor: primaryColor,
        contentTextStyle: TextStyle(
          color: onPrimary,
          fontStyle: FontStyle.italic,
          fontSize: 12,
        ),
        behavior: SnackBarBehavior.floating,
        elevation: 0,
      ),
      dividerColor: primaryColor.withValues(alpha: 0.1),
      iconTheme: IconThemeData(color: primaryColor),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: primaryColor,
        selectionColor: primaryColor.withValues(alpha: 0.2),
        selectionHandleColor: primaryColor,
      ),
      textTheme: TextTheme(
        headlineLarge: headingLarge.copyWith(color: onSurface),
        headlineMedium: headingMedium.copyWith(color: onSurface),
        headlineSmall: headingSmall.copyWith(color: onSurface),
        bodyLarge: bodyLarge.copyWith(color: onSurface),
        bodyMedium: bodyMedium.copyWith(color: onSurface),
        bodySmall: bodySmall.copyWith(color: onSurfaceVariant),
      ),
    );
  }

  static ThemeData custom({String fontFamily = 'Google Sans'}) {
    return light(fontFamily: fontFamily);
  }
}
