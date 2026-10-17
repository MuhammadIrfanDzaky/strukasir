import 'package:flutter/material.dart';

import 'tokens.dart';

/// ThemeData Strukasir: semua widget Material mengambil warna, tipe & bentuk dari token.
ThemeData buildAppTheme() {
  const scheme = ColorScheme(
    brightness: Brightness.light,
    primary: AppColors.primary,
    onPrimary: AppColors.onPrimary,
    primaryContainer: AppColors.primarySoft,
    onPrimaryContainer: AppColors.primaryStrong,
    secondary: AppColors.accent,
    onSecondary: AppColors.onAccent,
    secondaryContainer: AppColors.accentSoft,
    onSecondaryContainer: AppColors.warning,
    tertiary: AppColors.warning,
    onTertiary: AppColors.onPrimary,
    tertiaryContainer: AppColors.warningSoft,
    onTertiaryContainer: AppColors.warning,
    error: AppColors.danger,
    onError: AppColors.onPrimary,
    errorContainer: AppColors.dangerSoft,
    onErrorContainer: AppColors.danger,
    surface: AppColors.surface,
    onSurface: AppColors.ink,
    onSurfaceVariant: AppColors.inkMuted,
    surfaceContainerLowest: AppColors.surface,
    surfaceContainerLow: AppColors.surfaceApp,
    surfaceContainer: AppColors.surfaceApp,
    surfaceContainerHigh: AppColors.surfaceSunken,
    surfaceContainerHighest: AppColors.surfaceSunken,
    outline: AppColors.lineStrong,
    outlineVariant: AppColors.line,
    shadow: AppColors.ink,
    scrim: AppColors.ink,
    inverseSurface: AppColors.ink,
    onInverseSurface: AppColors.onInk,
    inversePrimary: AppColors.primaryOnDark,
    surfaceTint: Colors.transparent,
  );

  final text = TextTheme(
    displaySmall: AppType.display,
    headlineMedium: AppType.headline,
    headlineSmall: AppType.headline.copyWith(fontSize: 24, height: 32 / 24),
    titleLarge: AppType.titleLg,
    titleMedium: AppType.title,
    titleSmall: AppType.bodyStrong,
    bodyLarge: AppType.body.copyWith(fontSize: 16, height: 24 / 16),
    bodyMedium: AppType.body,
    bodySmall: AppType.caption,
    labelLarge: AppType.label,
    labelMedium: AppType.caption.copyWith(fontWeight: FontWeight.w600),
    labelSmall: AppType.overline,
  ).apply(bodyColor: AppColors.ink, displayColor: AppColors.ink);

  final mdShape = RoundedRectangleBorder(borderRadius: AppRadius.mdAll);
  const buttonSize = Size(64, AppSize.touch);
  const buttonPadding = EdgeInsets.symmetric(horizontal: AppSpace.s5);

  OutlineInputBorder field(Color color, [double width = 1]) =>
      OutlineInputBorder(borderRadius: AppRadius.mdAll, borderSide: BorderSide(color: color, width: width));

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    fontFamily: AppType.family,
    textTheme: text,
    scaffoldBackgroundColor: AppColors.surfaceApp,
    canvasColor: AppColors.surface,
    dividerColor: AppColors.line,
    visualDensity: VisualDensity.standard,
    // Ripple klasik lebih ringan dari InkSparkle di tablet CPU lemah.
    splashFactory: InkRipple.splashFactory,
    appBarTheme: AppBarTheme(
      backgroundColor: AppColors.surface,
      foregroundColor: AppColors.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      toolbarHeight: AppSize.topBar,
      titleTextStyle: AppType.titleLg.copyWith(color: AppColors.ink),
      shape: const Border(bottom: BorderSide(color: AppColors.line)),
    ),
    cardTheme: CardThemeData(
      color: AppColors.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: AppRadius.lgAll, side: const BorderSide(color: AppColors.line)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: buttonSize,
        padding: buttonPadding,
        shape: mdShape,
        textStyle: AppType.label,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.ink,
        minimumSize: buttonSize,
        padding: buttonPadding,
        shape: mdShape,
        textStyle: AppType.label,
        side: const BorderSide(color: AppColors.lineStrong),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.primary,
        backgroundColor: AppColors.surfaceSunken,
        disabledBackgroundColor: AppColors.surfaceSunken,
        minimumSize: buttonSize,
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.s4),
        shape: mdShape,
        textStyle: AppType.label,
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: AppColors.inkMuted,
        minimumSize: const Size.square(AppSize.touch),
        shape: mdShape,
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        minimumSize: const WidgetStatePropertyAll(Size(0, AppSize.touch)),
        textStyle: const WidgetStatePropertyAll(AppType.label),
        shape: WidgetStatePropertyAll(mdShape),
        side: const WidgetStatePropertyAll(BorderSide(color: AppColors.lineStrong)),
        backgroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? AppColors.primarySoft : AppColors.surface),
        foregroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? AppColors.primaryStrong : AppColors.ink),
      ),
    ),
    chipTheme: ChipThemeData(
      color: WidgetStateProperty.resolveWith((s) {
        if (s.contains(WidgetState.disabled)) return AppColors.surfaceSunken;
        return s.contains(WidgetState.selected) ? AppColors.primary : AppColors.surface;
      }),
      labelStyle: AppType.label.copyWith(
        color: WidgetStateColor.resolveWith(
            (s) => s.contains(WidgetState.selected) ? AppColors.onPrimary : AppColors.ink),
      ),
      side: WidgetStateBorderSide.resolveWith((s) =>
          BorderSide(color: s.contains(WidgetState.selected) ? AppColors.primary : AppColors.line)),
      checkmarkColor: AppColors.onPrimary,
      iconTheme: const IconThemeData(color: AppColors.inkMuted, size: 18),
      shape: const StadiumBorder(),
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.s2, vertical: AppSpace.s2),
      labelPadding: const EdgeInsets.symmetric(horizontal: AppSpace.s1),
    ),
    inputDecorationTheme: InputDecorationThemeData(
      filled: true,
      fillColor: AppColors.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: AppSpace.s4, vertical: 14),
      border: field(AppColors.lineStrong),
      enabledBorder: field(AppColors.lineStrong),
      focusedBorder: field(AppColors.focusRing, 2),
      errorBorder: field(AppColors.danger),
      focusedErrorBorder: field(AppColors.danger, 2),
      disabledBorder: field(AppColors.line),
      labelStyle: AppType.body.copyWith(color: AppColors.inkMuted),
      floatingLabelStyle: AppType.caption.copyWith(color: AppColors.primary, fontWeight: FontWeight.w600),
      hintStyle: AppType.body.copyWith(color: AppColors.inkMuted),
      prefixStyle: AppType.body.copyWith(color: AppColors.inkMuted),
      suffixStyle: AppType.body.copyWith(color: AppColors.inkMuted),
      errorStyle: AppType.caption.copyWith(color: AppColors.danger),
      prefixIconColor: AppColors.inkMuted,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: AppColors.surface,
      elevation: 8,
      shadowColor: const Color(0x4D2B1D18),
      shape: RoundedRectangleBorder(borderRadius: AppRadius.xlAll),
      titleTextStyle: AppType.titleLg.copyWith(color: AppColors.ink),
      contentTextStyle: AppType.body.copyWith(color: AppColors.ink),
      actionsPadding: const EdgeInsets.fromLTRB(AppSpace.s6, 0, AppSpace.s6, AppSpace.s5),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: AppColors.ink,
      minWidth: AppSize.rail,
      indicatorColor: AppColors.primarySoft,
      indicatorShape: RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
      selectedIconTheme: const IconThemeData(color: AppColors.primaryStrong, size: 24),
      unselectedIconTheme: const IconThemeData(color: AppColors.onInkMuted, size: 24),
      selectedLabelTextStyle: AppType.caption.copyWith(color: AppColors.onInk, fontWeight: FontWeight.w700),
      unselectedLabelTextStyle: AppType.caption.copyWith(color: AppColors.onInkMuted),
      labelType: NavigationRailLabelType.all,
      groupAlignment: -1,
    ),
    // Bar navigasi bawah (HP portrait): putih agar tidak bersaing dengan isi layar.
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      height: 68,
      elevation: 0,
      indicatorColor: AppColors.primarySoft,
      indicatorShape: RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
      iconTheme: WidgetStateProperty.resolveWith((s) => IconThemeData(
          size: 24, color: s.contains(WidgetState.selected) ? AppColors.primaryStrong : AppColors.inkMuted)),
      labelTextStyle: WidgetStateProperty.resolveWith((s) => AppType.caption.copyWith(
          color: s.contains(WidgetState.selected) ? AppColors.ink : AppColors.inkMuted,
          fontWeight: s.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500)),
    ),
    tabBarTheme: TabBarThemeData(
      labelColor: AppColors.primary,
      unselectedLabelColor: AppColors.inkMuted,
      labelStyle: AppType.label,
      unselectedLabelStyle: AppType.label.copyWith(fontWeight: FontWeight.w600),
      indicatorColor: AppColors.primary,
      indicatorSize: TabBarIndicatorSize.label,
      dividerColor: AppColors.line,
    ),
    dividerTheme: const DividerThemeData(color: AppColors.line, thickness: 1, space: 1),
    listTileTheme: ListTileThemeData(
      iconColor: AppColors.inkMuted,
      titleTextStyle: AppType.bodyStrong.copyWith(color: AppColors.ink),
      subtitleTextStyle: AppType.caption.copyWith(color: AppColors.inkMuted),
      leadingAndTrailingTextStyle: AppType.bodyStrong.copyWith(color: AppColors.ink),
      contentPadding: const EdgeInsets.symmetric(horizontal: AppSpace.s4),
      minVerticalPadding: AppSpace.s3,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: AppColors.ink,
      contentTextStyle: AppType.body.copyWith(color: AppColors.onInk),
      actionTextColor: AppColors.primaryOnDark,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
    ),
    bannerTheme: MaterialBannerThemeData(
      backgroundColor: AppColors.warningSoft,
      contentTextStyle: AppType.body.copyWith(color: AppColors.ink),
      dividerColor: AppColors.line,
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: AppColors.primary,
      linearTrackColor: AppColors.primarySoft,
      circularTrackColor: Colors.transparent,
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(color: AppColors.ink, borderRadius: AppRadius.smAll),
      textStyle: AppType.caption.copyWith(color: AppColors.onInk),
    ),
  );
}
