import 'package:anycast/design_system/anycast_components.dart';
import 'package:anycast/design_system/anycast_theme.dart';
import 'package:anycast/main.dart';
import 'package:anycast/utils/formatters.dart';
import 'package:anycast/widgets/card.dart' as episode_card;
import 'package:anycast/widgets/play_icon.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

double contrastRatio(Color first, Color second) {
  final lighter =
      first.computeLuminance() > second.computeLuminance() ? first : second;
  final darker = lighter == first ? second : first;
  return (lighter.computeLuminance() + .05) / (darker.computeLuminance() + .05);
}

void main() {
  test('root application widget can be constructed', () {
    expect(const NavigationBarApp(), isA<StatelessWidget>());
  });

  test('Anycast 2.0 spacing scale stays on the 4-point grid', () {
    expect(
      [
        AnycastSpacing.xxs,
        AnycastSpacing.xs,
        AnycastSpacing.sm,
        AnycastSpacing.md,
        AnycastSpacing.row,
        AnycastSpacing.gap,
        AnycastSpacing.chip,
        AnycastSpacing.pageH,
        AnycastSpacing.cardInner,
        AnycastSpacing.pageHeader,
        AnycastSpacing.sectionGap,
        AnycastSpacing.large,
        AnycastSpacing.pageSection,
        AnycastSpacing.xl,
        AnycastSpacing.xxl,
      ],
      [2, 4, 6, 8, 10, 12, 14, 16, 20, 24, 28, 32, 36, 40, 48],
    );
    expect(AnycastSpacing.pageBottomSafe, 88);
    expect(AnycastSpacing.compactProgress, 4);
    expect(AnycastSpacing.playerProgress, 6);
  });

  test('Anycast 2.0 typography keeps its semantic size hierarchy', () {
    final lightTextTheme = AnycastTheme.light.textTheme;
    final darkTextTheme = AnycastTheme.dark.textTheme;

    expect(lightTextTheme.displayLarge?.fontSize, 48);
    expect(lightTextTheme.headlineMedium?.fontSize, 22);
    expect(lightTextTheme.titleLarge?.fontSize, 20);
    expect(lightTextTheme.bodyLarge?.fontSize, 17);
    expect(lightTextTheme.bodySmall?.fontSize, 13);
    expect(lightTextTheme.labelMedium?.fontSize, 12);
    expect(lightTextTheme.labelSmall?.fontSize, 11);
    expect(lightTextTheme.bodyLarge?.fontFamily, '.AppleSystemUIFont');
    expect(
        darkTextTheme.bodyLarge?.fontSize, lightTextTheme.bodyLarge?.fontSize);
    expect(
      darkTextTheme.bodyLarge?.fontFamily,
      lightTextTheme.bodyLarge?.fontFamily,
    );
  });

  test('Anycast 2.0 provides distinct light and dark color schemes', () {
    final light = AnycastTheme.light;
    final dark = AnycastTheme.dark;

    expect(light.brightness, Brightness.light);
    expect(dark.brightness, Brightness.dark);
    expect(light.scaffoldBackgroundColor, AnycastColor.sand2);
    expect(dark.scaffoldBackgroundColor, AnycastColor.sandDark2);
    expect(light.colorScheme.onSurface, AnycastColor.sand12);
    expect(dark.colorScheme.onSurface, AnycastColor.sandDark12);
    expect(light.colorScheme.inverseSurface, AnycastColor.sand12);
    expect(dark.colorScheme.inverseSurface, AnycastColor.sandDark12);
  });

  test('light and dark secondary text keeps readable endpoint contrast', () {
    for (final theme in [AnycastTheme.light, AnycastTheme.dark]) {
      final color = theme.colorScheme.onSurfaceVariant;

      expect(
        contrastRatio(color, theme.scaffoldBackgroundColor),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        contrastRatio(color, theme.colorScheme.surface),
        greaterThanOrEqualTo(4.5),
      );
    }
  });

  test('player gradient keeps dark text-safe stops', () {
    final colors = AnycastColor.playerGradientColors;

    expect(colors, hasLength(5));
    for (var index = 1; index < colors.length; index++) {
      expect(
        colors[index].computeLuminance(),
        lessThan(colors[index - 1].computeLuminance()),
      );
    }
    for (final color in colors) {
      expect(
        contrastRatio(color, AnycastColor.playerText),
        greaterThanOrEqualTo(4.5),
      );
    }
  });

  test('playback progress covers unknown, partial, and completed states', () {
    expect(playbackProgress(Duration.zero, Duration.zero), 0);
    expect(
      playbackProgress(
        const Duration(seconds: -1),
        const Duration(seconds: 10),
      ),
      0,
    );
    expect(
      playbackProgress(
        const Duration(seconds: 5),
        const Duration(seconds: 10),
      ),
      .5,
    );
    expect(
      playbackProgress(
        const Duration(seconds: 10),
        const Duration(seconds: 10),
      ),
      1,
    );
    expect(
      playbackProgress(
        const Duration(seconds: 12),
        const Duration(seconds: 10),
      ),
      1,
    );
  });

  test('playback progress visual states gate seeking', () {
    expect(
      playbackProgressVisualState(
        hasEpisode: false,
        isLoading: false,
        duration: Duration.zero,
      ),
      PlaybackProgressVisualState.disabled,
    );
    expect(
      playbackProgressVisualState(
        hasEpisode: true,
        isLoading: true,
        duration: const Duration(seconds: 10),
      ),
      PlaybackProgressVisualState.loading,
    );
    expect(
      playbackProgressVisualState(
        hasEpisode: true,
        isLoading: false,
        duration: Duration.zero,
      ),
      PlaybackProgressVisualState.unknown,
    );
    expect(
      playbackProgressVisualState(
        hasEpisode: true,
        isLoading: false,
        duration: const Duration(seconds: 10),
      ),
      PlaybackProgressVisualState.normal,
    );
    expect(PlaybackProgressVisualState.normal.allowsSeek, isTrue);
    expect(PlaybackProgressVisualState.loading.allowsSeek, isFalse);
    expect(PlaybackProgressVisualState.unknown.allowsSeek, isFalse);
    expect(PlaybackProgressVisualState.disabled.allowsSeek, isFalse);
  });

  test('Anycast alpha colors match the UIKit sand and gold scales', () {
    expect(
      AnycastColor.grass9(Brightness.light),
      const Color(0xFF46A758),
    );
    expect(
      AnycastColor.grass9(Brightness.dark),
      const Color(0xFF63C174),
    );
    expect(
      [
        AnycastColor.sandAlpha2(Brightness.light),
        AnycastColor.sandAlpha3(Brightness.light),
        AnycastColor.sandAlpha4(Brightness.light),
        AnycastColor.sandAlpha5(Brightness.light),
        AnycastColor.sandAlpha8(Brightness.light),
        AnycastColor.sandAlpha9(Brightness.light),
        AnycastColor.sandAlpha10(Brightness.light),
        AnycastColor.sandAlpha11(Brightness.light),
        AnycastColor.sandAlpha12(Brightness.light),
      ],
      const [
        Color.fromRGBO(37, 37, 0, .03),
        Color.fromRGBO(32, 16, 0, .06),
        Color.fromRGBO(31, 21, 0, .10),
        Color.fromRGBO(31, 24, 0, .13),
        Color.fromRGBO(25, 21, 1, .29),
        Color.fromRGBO(15, 15, 0, .47),
        Color.fromRGBO(12, 12, 0, .51),
        Color.fromRGBO(8, 8, 0, .63),
        Color.fromRGBO(6, 5, 0, .89),
      ],
    );
    expect(
      [
        AnycastColor.sandAlpha2(Brightness.dark),
        AnycastColor.sandAlpha3(Brightness.dark),
        AnycastColor.sandAlpha4(Brightness.dark),
        AnycastColor.sandAlpha5(Brightness.dark),
        AnycastColor.sandAlpha8(Brightness.dark),
        AnycastColor.sandAlpha9(Brightness.dark),
        AnycastColor.sandAlpha10(Brightness.dark),
        AnycastColor.sandAlpha11(Brightness.dark),
        AnycastColor.sandAlpha12(Brightness.dark),
      ],
      const [
        Color.fromRGBO(246, 246, 245, .05),
        Color.fromRGBO(246, 246, 245, .08),
        Color.fromRGBO(254, 254, 243, .12),
        Color.fromRGBO(251, 251, 235, .17),
        Color.fromRGBO(255, 249, 235, .34),
        Color.fromRGBO(255, 250, 233, .48),
        Color.fromRGBO(255, 253, 238, .58),
        Color.fromRGBO(255, 252, 244, .72),
        Color.fromRGBO(255, 255, 253, .93),
      ],
    );
    expect(
      [
        AnycastColor.goldAlpha2(Brightness.light),
        AnycastColor.goldAlpha3(Brightness.light),
        AnycastColor.goldAlpha7(Brightness.light),
        AnycastColor.goldAlpha9(Brightness.light),
        AnycastColor.goldAlpha10(Brightness.light),
        AnycastColor.goldAlpha2(Brightness.dark),
        AnycastColor.goldAlpha3(Brightness.dark),
        AnycastColor.goldAlpha7(Brightness.dark),
        AnycastColor.goldAlpha9(Brightness.dark),
        AnycastColor.goldAlpha10(Brightness.dark),
      ],
      const [
        Color.fromRGBO(157, 138, 0, .05),
        Color.fromRGBO(117, 96, 0, .09),
        Color.fromRGBO(99, 66, 0, .33),
        Color.fromRGBO(83, 50, 0, .60),
        Color.fromRGBO(73, 45, 0, .63),
        Color.fromRGBO(249, 226, 157, .08),
        Color.fromRGBO(248, 236, 187, .14),
        Color.fromRGBO(255, 224, 164, .42),
        Color.fromRGBO(255, 219, 166, .70),
        Color.fromRGBO(254, 223, 176, .80),
      ],
    );
  });

  testWidgets('playlist card actions keep adaptive icon contrast',
      (tester) async {
    expect(const PlayIcon().color, isNull);
    expect(const AIIcon(enclosureUrl: 'episode').color, isNull);

    for (final theme in [AnycastTheme.light, AnycastTheme.dark]) {
      await tester.pumpWidget(
        MaterialApp(
          key: ValueKey(theme.brightness),
          theme: theme,
          home: Scaffold(
            body: episode_card.CardBtn(
              icon: const Icon(Icons.play_arrow),
              onPressed: () {},
            ),
          ),
        ),
      );

      final button = tester.widget<IconButton>(find.byType(IconButton));
      final background = button.style!.backgroundColor!.resolve({});
      final foreground = button.style!.foregroundColor!.resolve({});

      expect(background, theme.colorScheme.inverseSurface);
      expect(foreground, theme.colorScheme.onInverseSurface);
      expect(
          contrastRatio(background!, foreground!), greaterThanOrEqualTo(4.5));
      expect(
        IconTheme.of(tester.element(find.byIcon(Icons.play_arrow))).color,
        foreground,
      );
      expect(find.byType(ColorFiltered), findsOneWidget);
    }
  });

  testWidgets('compact progress covers light and dark playback states',
      (tester) async {
    for (final theme in [AnycastTheme.light, AnycastTheme.dark]) {
      for (final value in [0.0, .5, 1.0]) {
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            darkTheme: theme,
            themeMode: theme.brightness == Brightness.dark
                ? ThemeMode.dark
                : ThemeMode.light,
            home: Scaffold(
              body: AnycastCompactProgress(value: value),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final indicator = tester.widget<LinearProgressIndicator>(
          find.byType(LinearProgressIndicator),
        );
        expect(indicator.value, value);
        expect(indicator.minHeight, AnycastSpacing.compactProgress);
        expect(indicator.color, theme.colorScheme.primary);
        expect(
          indicator.backgroundColor,
          AnycastColor.sandAlpha4(theme.brightness),
        );
      }
    }
  });

  test('Anycast controls do not fall back to Material purple', () {
    const materialPurple = Color(0xFF6750A4);
    const materialInversePurple = Color(0xFF322F35);

    for (final theme in [AnycastTheme.light, AnycastTheme.dark]) {
      final states = <WidgetState>{};
      final selected = {WidgetState.selected};
      final filledBackground =
          theme.filledButtonTheme.style?.backgroundColor?.resolve(states);

      expect(theme.colorScheme.primary, isNot(materialPurple));
      expect(filledBackground, theme.colorScheme.onSurface);
      expect(filledBackground, isNot(materialPurple));
      expect(filledBackground, isNot(materialInversePurple));
      expect(
        contrastRatio(
          filledBackground!,
          theme.filledButtonTheme.style!.foregroundColor!.resolve(states)!,
        ),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        theme.elevatedButtonTheme.style?.backgroundColor?.resolve(states),
        theme.colorScheme.onSurface,
      );
      expect(
        theme.textButtonTheme.style?.foregroundColor?.resolve(states),
        theme.colorScheme.primary,
      );
      expect(theme.sliderTheme.activeTrackColor, theme.colorScheme.primary);
      expect(
        theme.checkboxTheme.fillColor?.resolve(selected),
        theme.colorScheme.primary,
      );
      expect(
        theme.radioTheme.fillColor?.resolve(selected),
        theme.colorScheme.primary,
      );
      expect(theme.progressIndicatorTheme.color, theme.colorScheme.primary);
      expect(
        theme.sliderTheme.disabledActiveTrackColor,
        theme.colorScheme.primary.withValues(alpha: .38),
      );
      expect(
        theme.sliderTheme.disabledThumbColor,
        theme.colorScheme.onSurfaceVariant.withValues(alpha: .38),
      );
      expect(
        theme.switchTheme.thumbColor?.resolve({
          WidgetState.selected,
          WidgetState.disabled,
        }),
        theme.colorScheme.onPrimary.withValues(alpha: .38),
      );
      expect(
        theme.switchTheme.trackColor?.resolve({
          WidgetState.selected,
          WidgetState.disabled,
        }),
        theme.colorScheme.primary.withValues(alpha: .38),
      );
      expect(
        theme.hoverColor,
        AnycastColor.goldAlpha2(theme.brightness),
      );
      expect(
        theme.focusColor,
        AnycastColor.goldAlpha3(theme.brightness),
      );
      expect(
        theme.colorScheme.outlineVariant,
        AnycastColor.sandAlpha4(theme.brightness),
      );
      expect(
        theme.colorScheme.primaryContainer,
        AnycastColor.sandAlpha4(theme.brightness),
      );
      expect(
        (theme.tabBarTheme.indicator! as BoxDecoration).color,
        AnycastColor.sandAlpha2(theme.brightness),
      );
      expect(
        theme.navigationBarTheme.indicatorColor,
        AnycastColor.sandAlpha2(theme.brightness),
      );
      expect(
        theme.floatingActionButtonTheme.backgroundColor,
        theme.colorScheme.inverseSurface,
      );
      expect(theme.chipTheme.selectedColor, theme.colorScheme.primaryContainer);
      expect(
        theme.snackBarTheme.actionTextColor,
        theme.colorScheme.inversePrimary,
      );
      expect(
        contrastRatio(
          theme.navigationBarTheme.labelTextStyle!.resolve(selected)!.color!,
          Color.alphaBlend(
            theme.navigationBarTheme.indicatorColor!,
            theme.scaffoldBackgroundColor,
          ),
        ),
        greaterThanOrEqualTo(4.5),
      );
    }
  });
}
