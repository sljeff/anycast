import 'package:flutter/material.dart';

/// Anycast 2.0 design tokens, ported from the UIKit source of truth.
abstract final class AnycastColor {
  static const sand1 = Color(0xFFFDFDFC);
  static const sand2 = Color(0xFFF9F9F8);
  static const sand3 = Color(0xFFF1F0EF);
  static const sand4 = Color(0xFFE9E8E6);
  static const sand6 = Color(0xFFDAD9D6);
  static const sand7 = Color(0xFFCFCECA);
  static const sand9 = Color(0xFF8D8D86);
  static const sand10 = Color(0xFF82827C);
  static const sand11 = Color(0xFF63635E);
  static const sand12 = Color(0xFF21201C);

  static const sandDark1 = Color(0xFF111110);
  static const sandDark2 = Color(0xFF191918);
  static const sandDark3 = Color(0xFF222221);
  static const sandDark4 = Color(0xFF2A2A28);
  static const sandDark6 = Color(0xFF3B3A37);
  static const sandDark9 = Color(0xFFB5B3AD);
  static const sandDark11 = Color(0xFFD2D0CA);
  static const sandDark12 = Color(0xFFEEEEEC);

  static const gold9 = Color(0xFF978365);
  static const gold10 = Color(0xFF8C7A5E);
  static const goldDark9 = Color(0xFFCBB99F);
  static const goldDark10 = Color(0xFFD8C8AE);
  static const goldSoft = Color(0xFFF4F0E7);
  static const orange10 = Color(0xFFEF5F00);
  static Color grass9(Brightness brightness) => _dynamic(
        brightness,
        const Color(0xFF46A758),
        const Color(0xFF63C174),
      );

  static Color sandAlpha2(Brightness brightness) => _dynamic(
        brightness,
        const Color.fromRGBO(37, 37, 0, .03),
        const Color.fromRGBO(246, 246, 245, .05),
      );

  static Color sandAlpha3(Brightness brightness) => _dynamic(
        brightness,
        const Color.fromRGBO(32, 16, 0, .06),
        const Color.fromRGBO(246, 246, 245, .08),
      );

  static Color sandAlpha4(Brightness brightness) => _dynamic(
        brightness,
        const Color.fromRGBO(31, 21, 0, .10),
        const Color.fromRGBO(254, 254, 243, .12),
      );

  static Color sandAlpha5(Brightness brightness) => _dynamic(
        brightness,
        const Color.fromRGBO(31, 24, 0, .13),
        const Color.fromRGBO(251, 251, 235, .17),
      );

  static Color sandAlpha8(Brightness brightness) => _dynamic(
        brightness,
        const Color.fromRGBO(25, 21, 1, .29),
        const Color.fromRGBO(255, 249, 235, .34),
      );

  static Color sandAlpha9(Brightness brightness) => _dynamic(
        brightness,
        const Color.fromRGBO(15, 15, 0, .47),
        const Color.fromRGBO(255, 250, 233, .48),
      );

  static Color sandAlpha10(Brightness brightness) => _dynamic(
        brightness,
        const Color.fromRGBO(12, 12, 0, .51),
        const Color.fromRGBO(255, 253, 238, .58),
      );

  static Color sandAlpha11(Brightness brightness) => _dynamic(
        brightness,
        const Color.fromRGBO(8, 8, 0, .63),
        const Color.fromRGBO(255, 252, 244, .72),
      );

  static Color sandAlpha12(Brightness brightness) => _dynamic(
        brightness,
        const Color.fromRGBO(6, 5, 0, .89),
        const Color.fromRGBO(255, 255, 253, .93),
      );

  static Color goldAlpha2(Brightness brightness) => _dynamic(
        brightness,
        const Color.fromRGBO(157, 138, 0, .05),
        const Color.fromRGBO(249, 226, 157, .08),
      );

  static Color goldAlpha3(Brightness brightness) => _dynamic(
        brightness,
        const Color.fromRGBO(117, 96, 0, .09),
        const Color.fromRGBO(248, 236, 187, .14),
      );

  static Color goldAlpha7(Brightness brightness) => _dynamic(
        brightness,
        const Color.fromRGBO(99, 66, 0, .33),
        const Color.fromRGBO(255, 224, 164, .42),
      );

  static Color goldAlpha9(Brightness brightness) => _dynamic(
        brightness,
        const Color.fromRGBO(83, 50, 0, .60),
        const Color.fromRGBO(255, 219, 166, .70),
      );

  static Color goldAlpha10(Brightness brightness) => _dynamic(
        brightness,
        const Color.fromRGBO(73, 45, 0, .63),
        const Color.fromRGBO(254, 223, 176, .80),
      );

  static const playerWarm = Color(0xFF867D75);
  static const playerBackground = Color(0xFF222221);
  static const playerText = Color(0xFFEEEEEC);
  static const playerSecondary = Color(0xFFD2D0CA);
  static const playerArtworkScrim = Color.fromRGBO(0, 0, 0, .50);
  static const transcriptSurface = Color.fromRGBO(0, 0, 0, .32);

  static const playerGradientOverlayColors = [
    Color.fromRGBO(0, 0, 0, .20),
    Color.fromRGBO(0, 0, 0, .25),
    Color.fromRGBO(0, 0, 0, .376),
    Color.fromRGBO(0, 0, 0, .40),
    Color.fromRGBO(0, 0, 0, .50),
  ];

  static List<Color> get playerGradientColors => playerGradientOverlayColors
      .map((color) => Color.alphaBlend(color, playerWarm))
      .toList(growable: false);

  static Color _dynamic(
    Brightness brightness,
    Color light,
    Color dark,
  ) =>
      brightness == Brightness.dark ? dark : light;
}

abstract final class AnycastSpacing {
  static const unit = 4.0;
  static const hairline = 1.0;
  static const xxs = 2.0;
  static const xs = 4.0;
  static const sm = 6.0;
  static const md = 8.0;
  static const row = 10.0;
  static const gap = 12.0;
  static const chip = 14.0;
  static const pageH = 16.0;
  static const cardInner = 20.0;
  static const pageHeader = 24.0;
  static const sectionGap = 28.0;
  static const large = 32.0;
  static const pageSection = 36.0;
  static const xl = 40.0;
  static const xxl = 48.0;

  static const compactProgress = xs;
  static const playerProgress = sm;
  static const floatingOutset = pageHeader - pageH;
  static const sheetTitleH = 64.0;
  static const rowH = 70.0;
  static const pageBottomSafe = xxl + xl;
}

abstract final class AnycastRadius {
  static const sm = 8.0;
  static const md = 16.0;
  static const artwork = 18.0;
  static const card = 24.0;
  static const largeCard = 32.0;
  static const modal = 58.0;
  static const pill = 999.0;
}

abstract final class AnycastMotion {
  static const quick = Duration(milliseconds: 180);
  static const standard = Duration(milliseconds: 280);
  static const emphasized = Duration(milliseconds: 420);

  static const standardCurve = Curves.easeOutCubic;
}

abstract final class AnycastTheme {
  static ThemeData get light => _build(Brightness.light);
  static ThemeData get dark => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final background = isDark ? AnycastColor.sandDark2 : AnycastColor.sand2;
    final surface = isDark ? AnycastColor.sandDark1 : AnycastColor.sand1;
    final surfaceContainer =
        isDark ? AnycastColor.sandDark3 : AnycastColor.sand3;
    final outline = isDark ? AnycastColor.sandDark6 : AnycastColor.sand6;
    final onSurface = isDark ? AnycastColor.sandDark12 : AnycastColor.sand12;
    final onSurfaceVariant =
        isDark ? AnycastColor.sandDark11 : AnycastColor.sand11;
    final sandAlpha2 = AnycastColor.sandAlpha2(brightness);
    final sandAlpha4 = AnycastColor.sandAlpha4(brightness);
    final goldAlpha2 = AnycastColor.goldAlpha2(brightness);
    final goldAlpha3 = AnycastColor.goldAlpha3(brightness);
    final goldAlpha7 = AnycastColor.goldAlpha7(brightness);

    final scheme = ColorScheme(
      brightness: brightness,
      primary: isDark ? AnycastColor.goldDark9 : AnycastColor.gold9,
      onPrimary: isDark ? AnycastColor.sand12 : AnycastColor.sand1,
      primaryContainer: sandAlpha4,
      onPrimaryContainer: onSurface,
      secondary: isDark ? AnycastColor.sandDark11 : AnycastColor.sand11,
      onSecondary: surface,
      secondaryContainer: surfaceContainer,
      onSecondaryContainer: onSurface,
      tertiary: isDark ? const Color(0xFFFF8B3E) : AnycastColor.orange10,
      onTertiary: surface,
      error: isDark ? const Color(0xFFFF8B8B) : const Color(0xFFBA1A1A),
      onError: surface,
      surface: surface,
      onSurface: onSurface,
      surfaceContainerLowest: surface,
      surfaceContainerLow: background,
      surfaceContainer: surfaceContainer,
      surfaceContainerHigh:
          isDark ? AnycastColor.sandDark4 : AnycastColor.sand4,
      surfaceContainerHighest:
          isDark ? AnycastColor.sandDark6 : AnycastColor.sand6,
      onSurfaceVariant: onSurfaceVariant,
      outline: outline,
      outlineVariant: sandAlpha4,
      shadow: Colors.black,
      scrim: Colors.black,
      inverseSurface: onSurface,
      onInverseSurface: surface,
      inversePrimary: isDark ? AnycastColor.gold9 : AnycastColor.goldDark9,
    );

    final baseTextTheme = ThemeData(
      brightness: brightness,
      useMaterial3: true,
    ).textTheme.apply(
          bodyColor: onSurface,
          displayColor: onSurface,
          fontFamily: '.AppleSystemUIFont',
        );
    final textTheme = baseTextTheme.copyWith(
      displayLarge: baseTextTheme.displayLarge?.copyWith(
        fontSize: 48,
        height: 1,
        letterSpacing: 0,
        fontWeight: FontWeight.w900,
      ),
      displayMedium: baseTextTheme.displayMedium?.copyWith(
        fontSize: 34,
        height: 41 / 34,
        letterSpacing: 0,
        fontWeight: FontWeight.w400,
      ),
      displaySmall: baseTextTheme.displaySmall?.copyWith(
        fontSize: 28,
        height: 34 / 28,
        letterSpacing: 0,
        fontWeight: FontWeight.w400,
      ),
      headlineLarge: baseTextTheme.headlineLarge?.copyWith(
        fontSize: 28,
        height: 34 / 28,
        letterSpacing: 0,
        fontWeight: FontWeight.w600,
      ),
      headlineMedium: baseTextTheme.headlineMedium?.copyWith(
        fontSize: 22,
        height: 28 / 22,
        letterSpacing: 0,
        fontWeight: FontWeight.w600,
      ),
      headlineSmall: baseTextTheme.headlineSmall?.copyWith(
        fontSize: 17,
        height: 22 / 17,
        letterSpacing: 0,
        fontWeight: FontWeight.w600,
      ),
      titleLarge: baseTextTheme.titleLarge?.copyWith(
        fontSize: 20,
        height: 25 / 20,
        letterSpacing: 0,
        fontWeight: FontWeight.w600,
      ),
      titleMedium: baseTextTheme.titleMedium?.copyWith(
        fontSize: 16,
        height: 21 / 16,
        letterSpacing: 0,
        fontWeight: FontWeight.w500,
      ),
      titleSmall: baseTextTheme.titleSmall?.copyWith(
        fontSize: 15,
        height: 20 / 15,
        letterSpacing: 0,
        fontWeight: FontWeight.w600,
      ),
      bodyLarge: baseTextTheme.bodyLarge?.copyWith(
        fontSize: 17,
        height: 22 / 17,
        letterSpacing: 0,
        fontWeight: FontWeight.w400,
      ),
      bodyMedium: baseTextTheme.bodyMedium?.copyWith(
        fontSize: 15,
        height: 20 / 15,
        letterSpacing: 0,
        fontWeight: FontWeight.w400,
      ),
      bodySmall: baseTextTheme.bodySmall?.copyWith(
        fontSize: 13,
        height: 18 / 13,
        letterSpacing: 0,
        fontWeight: FontWeight.w400,
      ),
      labelLarge: baseTextTheme.labelLarge?.copyWith(
        fontSize: 17,
        height: 22 / 17,
        letterSpacing: 0,
        fontWeight: FontWeight.w600,
      ),
      labelMedium: baseTextTheme.labelMedium?.copyWith(
        fontSize: 12,
        height: 16 / 12,
        letterSpacing: 0,
        fontWeight: FontWeight.w600,
      ),
      labelSmall: baseTextTheme.labelSmall?.copyWith(
        fontSize: 11,
        height: 13 / 11,
        letterSpacing: 0,
        fontWeight: FontWeight.w500,
      ),
    );

    return ThemeData(
      brightness: brightness,
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      canvasColor: background,
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        toolbarHeight: 148,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleSpacing: 0,
        foregroundColor: onSurface,
        backgroundColor: background,
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: surface,
        surfaceTintColor: Colors.transparent,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: scheme.outlineVariant),
          borderRadius: BorderRadius.circular(AnycastRadius.card),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        thickness: AnycastSpacing.hairline,
        space: AnycastSpacing.hairline,
      ),
      iconTheme: IconThemeData(color: onSurface, size: 22),
      focusColor: goldAlpha3,
      hoverColor: goldAlpha2,
      highlightColor: goldAlpha3,
      splashColor: goldAlpha3,
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceContainer,
        hintStyle: textTheme.bodyLarge?.copyWith(color: onSurfaceVariant),
        prefixIconColor: onSurfaceVariant,
        suffixIconColor: onSurfaceVariant,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AnycastSpacing.pageH,
          vertical: AnycastSpacing.gap,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AnycastRadius.md),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AnycastRadius.md),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AnycastRadius.md),
          borderSide: BorderSide(color: scheme.primary, width: 1.5),
        ),
      ),
      tabBarTheme: TabBarThemeData(
        dividerColor: Colors.transparent,
        indicatorSize: TabBarIndicatorSize.tab,
        indicator: BoxDecoration(
          color: sandAlpha2,
          borderRadius: BorderRadius.circular(AnycastRadius.pill),
        ),
        labelColor: onSurface,
        unselectedLabelColor: onSurfaceVariant,
        labelStyle: textTheme.labelLarge,
        unselectedLabelStyle: textTheme.labelLarge,
        overlayColor: WidgetStateProperty.all(Colors.transparent),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 72,
        elevation: 0,
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        indicatorColor: sandAlpha2,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          return textTheme.labelMedium?.copyWith(
            color: states.contains(WidgetState.selected)
                ? scheme.onPrimaryContainer
                : onSurfaceVariant,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w700
                : FontWeight.w500,
          );
        }),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(44, 48),
          backgroundColor: onSurface,
          foregroundColor: surface,
          padding: const EdgeInsets.symmetric(
            horizontal: AnycastSpacing.cardInner,
            vertical: AnycastSpacing.gap,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AnycastRadius.pill),
          ),
          textStyle: textTheme.labelLarge,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          minimumSize: const Size(44, 48),
          elevation: 0,
          backgroundColor: onSurface,
          foregroundColor: surface,
          surfaceTintColor: Colors.transparent,
          padding: const EdgeInsets.symmetric(
            horizontal: AnycastSpacing.cardInner,
            vertical: AnycastSpacing.gap,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AnycastRadius.pill),
          ),
          textStyle: textTheme.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(44, 48),
          foregroundColor: onSurface,
          padding: const EdgeInsets.symmetric(
            horizontal: AnycastSpacing.cardInner,
            vertical: AnycastSpacing.gap,
          ),
          side: BorderSide(color: scheme.outline),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AnycastRadius.pill),
          ),
          textStyle: textTheme.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: scheme.primary,
          minimumSize: const Size(44, 44),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AnycastRadius.pill),
          ),
          textStyle: textTheme.labelLarge,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size(44, 44),
          foregroundColor: onSurface,
          backgroundColor: surfaceContainer,
          shape: const CircleBorder(),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        elevation: 0,
        foregroundColor: surface,
        backgroundColor: onSurface,
        focusColor: goldAlpha7,
        hoverColor: goldAlpha3,
        splashColor: goldAlpha7,
        shape: const CircleBorder(),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return scheme.primary;
          }
          return Colors.transparent;
        }),
        checkColor: WidgetStatePropertyAll(scheme.onPrimary),
        overlayColor: WidgetStatePropertyAll(goldAlpha3),
        side: BorderSide(color: outline, width: 1.5),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AnycastSpacing.xs),
        ),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          return states.contains(WidgetState.selected)
              ? scheme.primary
              : onSurfaceVariant;
        }),
        overlayColor: WidgetStatePropertyAll(goldAlpha3),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: scheme.primary,
        inactiveTrackColor: surfaceContainer,
        thumbColor: scheme.primary,
        disabledActiveTrackColor: scheme.primary.withValues(alpha: .38),
        disabledInactiveTrackColor: sandAlpha2,
        disabledThumbColor: onSurfaceVariant.withValues(alpha: .38),
        overlayColor: goldAlpha3,
        valueIndicatorColor: scheme.inverseSurface,
        valueIndicatorTextStyle: textTheme.labelMedium?.copyWith(
          color: scheme.onInverseSurface,
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: surfaceContainer,
        selectedColor: scheme.primaryContainer,
        disabledColor: sandAlpha2,
        checkmarkColor: scheme.primary,
        deleteIconColor: onSurfaceVariant,
        side: BorderSide(color: scheme.outlineVariant),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AnycastRadius.pill),
        ),
        labelStyle: textTheme.labelMedium?.copyWith(color: onSurface),
        secondaryLabelStyle: textTheme.labelMedium?.copyWith(
          color: scheme.onPrimaryContainer,
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: AnycastSpacing.gap,
          vertical: AnycastSpacing.xs,
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        showDragHandle: true,
        dragHandleColor: scheme.outline,
        modalBackgroundColor: surface,
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        modalElevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AnycastRadius.largeCard),
          ),
        ),
      ),
      dialogTheme: DialogThemeData(
        elevation: 0,
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: scheme.outlineVariant),
          borderRadius: BorderRadius.circular(AnycastRadius.largeCard),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        elevation: 0,
        behavior: SnackBarBehavior.floating,
        backgroundColor: scheme.inverseSurface,
        actionTextColor: scheme.inversePrimary,
        closeIconColor: scheme.onInverseSurface,
        contentTextStyle: textTheme.bodyMedium?.copyWith(
          color: scheme.onInverseSurface,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AnycastRadius.md),
        ),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: scheme.inverseSurface,
          borderRadius: BorderRadius.circular(AnycastRadius.sm),
        ),
        textStyle: textTheme.bodySmall?.copyWith(
          color: scheme.onInverseSurface,
        ),
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: scheme.primary,
        selectionColor: goldAlpha7,
        selectionHandleColor: scheme.primary,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        linearTrackColor: surfaceContainer,
        circularTrackColor: surfaceContainer,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          final isSelected = states.contains(WidgetState.selected);
          if (states.contains(WidgetState.disabled)) {
            return (isSelected ? scheme.onPrimary : onSurfaceVariant)
                .withValues(alpha: .38);
          }
          return isSelected ? scheme.onPrimary : onSurfaceVariant;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          final isSelected = states.contains(WidgetState.selected);
          if (states.contains(WidgetState.disabled)) {
            return (isSelected ? scheme.primary : surfaceContainer)
                .withValues(alpha: .38);
          }
          return isSelected ? scheme.primary : surfaceContainer;
        }),
      ),
    );
  }
}
