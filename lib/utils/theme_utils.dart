import 'package:PiliPlus/common/style.dart';
import 'package:PiliPlus/utils/extension/theme_ext.dart';
import 'package:PiliPlus/utils/font_utils.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoThemeData;
import 'package:flutter/foundation.dart' show PlatformDispatcher;
import 'package:material_ui/material_ui.dart';

abstract final class ThemeUtils {
  static late ThemeData lightTheme;

  static late ThemeData darkTheme;

  static late ThemeMode themeMode;

  static ThemeData get theme {
    if (themeMode == .dark ||
        (themeMode == .system &&
            PlatformDispatcher.instance.platformBrightness == .dark)) {
      return darkTheme;
    }
    return lightTheme;
  }

  static bool get isDarkMode => theme.isDark;

  static String themeUrl(bool isDark) =>
      'native.theme=${isDark ? 2 : 1}&night=${isDark ? 1 : 0}';

  static ThemeData getThemeData({
    required ColorScheme colorScheme,
    required bool isDynamic,
    bool isDark = false,
  }) {
    final fontWeight = Pref.appFontWeight;
    final fontFamily = FontUtils.fontFamily;

    TextTheme? textTheme;
    if (fontWeight != .normal) {
      final textStyle = TextStyle(fontWeight: fontWeight);
      textTheme = TextTheme(
        displayLarge: textStyle,
        displayMedium: textStyle,
        displaySmall: textStyle,
        headlineLarge: textStyle,
        headlineMedium: textStyle,
        headlineSmall: textStyle,
        titleLarge: textStyle,
        titleMedium: textStyle,
        titleSmall: textStyle,
        bodyLarge: textStyle,
        bodyMedium: textStyle,
        bodySmall: textStyle,
        labelLarge: textStyle,
        labelMedium: textStyle,
        labelSmall: textStyle,
      );
    }

    final borderSide = BorderSide(
      color: isDark ? Colors.white : Colors.black,
      width: 1.0,
    );

    // 墨水屏：浅色模式一律纯白底 + 纯黑线。
    // 原 seed 配色带一层淡绿底（#FBFDF8），在墨水屏上会显示成脏灰色，这里全部压成纯白。
    if (!isDark) {
      colorScheme = colorScheme.copyWith(
        surface: Colors.white,
        onSurface: Colors.black,
        surfaceContainerLowest: Colors.white,
        surfaceContainerLow: Colors.white,
        surfaceContainer: Colors.white,
        surfaceContainerHigh: Colors.white,
        surfaceContainerHighest: Colors.white,
        // 全库有 50 多处把 onInverseSurface 当"次级面板底色"用，
        // 压成纯白会让这些面板在白底上直接消失，所以留一层极浅中性灰（去绿调），
        // 真正靠黑边框划分区域。
        onInverseSurface: const Color(0xFFF0F0F0),
        inverseSurface: Colors.black,
        outline: Colors.black,
        outlineVariant: const Color(0xFF000000),
        // 种子色的 onSurfaceVariant 是带绿的深灰，直接用它当正文/次要文字
        // 在墨水屏上会显得发闷，压成中性深灰保留层级但去掉绿调。
        onSurfaceVariant: const Color(0xFF333333),
        // 种子色的 primary 是全站绿色（昵称、链接、"查看更多"、"立即播放"、
        // 评论区嵌套回复里的 @ 名等都用它），逐个组件改不现实且容易漏。
        // 这里直接把主色族压成黑白，链接靠"黑色 + 下划线"、选中态靠"加粗 + 黑框"
        // 表达，一次性消掉大部分残留彩色。
        primary: Colors.black,
        onPrimary: Colors.white,
        primaryContainer: Colors.white,
        onPrimaryContainer: Colors.black,
        inversePrimary: Colors.black,
        secondary: Colors.black,
        onSecondary: Colors.white,
        // NavigationBar / NavigationDrawer 的选中胶囊底用的是它，
        // 压成白色后配合 indicatorShape 的黑描边正好是"白底黑框"。
        secondaryContainer: Colors.white,
        onSecondaryContainer: Colors.black,
        tertiary: Colors.black,
        onTertiary: Colors.white,
        tertiaryContainer: Colors.white,
        onTertiaryContainer: Colors.black,
      );
    } else {
      // 深色模式同样去掉绿调，只保留灰度层级。
      colorScheme = colorScheme.copyWith(
        primary: Colors.white,
        onPrimary: Colors.black,
        primaryContainer: const Color(0xFF1F1F1F),
        onPrimaryContainer: Colors.white,
        inversePrimary: Colors.white,
        secondary: Colors.white,
        onSecondary: Colors.black,
        secondaryContainer: const Color(0xFF1F1F1F),
        onSecondaryContainer: Colors.white,
        tertiary: Colors.white,
        onTertiary: Colors.black,
        tertiaryContainer: const Color(0xFF1F1F1F),
        onTertiaryContainer: Colors.white,
      );
    }

    final theme = ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: isDark ? Colors.black : Colors.white,
      canvasColor: isDark ? Colors.black : Colors.white,
      fontFamily: fontFamily,
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        elevation: 0,
        titleSpacing: 0,
        centerTitle: false,
        scrolledUnderElevation: 0,
        backgroundColor: colorScheme.surface,
        shape: Border(bottom: borderSide),
        titleTextStyle: TextStyle(
          fontSize: 16,
          fontWeight: fontWeight,
          fontFamily: fontFamily,
          color: colorScheme.onSurface,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        surfaceTintColor: isDark ? colorScheme.surfaceContainerHighest : null,
        elevation: 0,
        indicatorShape: RoundedRectangleBorder(
          borderRadius: const BorderRadius.all(Radius.circular(16)),
          side: borderSide,
        ),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        elevation: 0,
        backgroundColor: colorScheme.surface,
        selectedItemColor: isDark ? Colors.white : Colors.black,
        unselectedItemColor: isDark ? Colors.white70 : Colors.black54,
      ),
      tabBarTheme: TabBarThemeData(
        indicatorColor: isDark ? Colors.white : Colors.black,
        indicatorSize: TabBarIndicatorSize.label,
        // 墨水屏上去掉颜色后，选中态只能靠「加粗 + 更明显的下划线」表达，
        // 默认 2dp 指示条和页签底部的 1dp 分割线太接近，看不出来。
        labelStyle: const TextStyle(fontWeight: FontWeight.w600),
        unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w400),
        dividerColor: isDark ? Colors.white24 : Colors.black,
        dividerHeight: 1.0,
        labelColor: isDark ? Colors.white : Colors.black,
        unselectedLabelColor: isDark ? Colors.white70 : Colors.black54,
      ),
      // 默认 Badge 底是 colorScheme.error（红色），墨水屏上是一块深灰噪点。
      // 统一成"黑底白字"（深色模式反过来），未读角标靠形状而不是颜色区分。
      badgeTheme: BadgeThemeData(
        backgroundColor: isDark ? Colors.white : Colors.black,
        textColor: isDark ? Colors.black : Colors.white,
      ),
      snackBarTheme: SnackBarThemeData(
        elevation: 0,
        actionTextColor: colorScheme.onSurface,
        closeIconColor: colorScheme.onSurface,
        // 原来是浅绿底 + 深绿字，墨水屏上是一块脏灰
        backgroundColor: colorScheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: const BorderRadius.all(Radius.circular(8)),
          side: borderSide,
        ),
        contentTextStyle: TextStyle(
          fontFamily: fontFamily,
          fontWeight: fontWeight,
          color: colorScheme.onSurface,
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        elevation: 0,
        // M3 默认 popupMenu 底色取 surfaceContainer（浅灰紫），墨水屏上是一块
        // 脏灰。播放器右上角「更多」菜单、各类下拉菜单统一压成白底。
        color: isDark ? colorScheme.surfaceContainerHighest : Colors.white,
        surfaceTintColor: isDark ? colorScheme.surfaceContainerHighest : null,
        shape: RoundedRectangleBorder(
          borderRadius: const BorderRadius.all(Radius.circular(8)),
          side: borderSide,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        shadowColor: Colors.transparent,
        surfaceTintColor: isDark ? colorScheme.onSurfaceVariant : null,
        shape: RoundedRectangleBorder(
          borderRadius: const BorderRadius.all(Radius.circular(8)),
          side: borderSide,
        ),
      ),
      progressIndicatorTheme: isDark
          ? ProgressIndicatorThemeData(
              // ignore: deprecated_member_use
              year2023: false,
              refreshBackgroundColor: colorScheme.onInverseSurface,
            )
          // ignore: deprecated_member_use
          : const ProgressIndicatorThemeData(year2023: false),
      dialogTheme: DialogThemeData(
        barrierColor: Colors.transparent,
        titleTextStyle: TextStyle(
          fontSize: 18,
          fontWeight: fontWeight,
          fontFamily: fontFamily,
          color: colorScheme.onSurface,
        ),
        backgroundColor: colorScheme.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: const BorderRadius.all(Radius.circular(12)),
          side: borderSide,
        ),
        constraints: const BoxConstraints(minWidth: 280, maxWidth: 420),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: colorScheme.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: Style.bottomSheetRadius,
          side: borderSide,
        ),
      ),
      // ignore: deprecated_member_use
      sliderTheme: const SliderThemeData(year2023: false),
      tooltipTheme: TooltipThemeData(
        textStyle: TextStyle(
          fontSize: 14,
          color: Colors.white,
          fontFamily: fontFamily,
          fontWeight: fontWeight,
        ),
        decoration: BoxDecoration(
          color: Colors.black,
          border: Border.all(color: Colors.white, width: 1.0),
          borderRadius: const BorderRadius.all(Radius.circular(4)),
        ),
      ),
      cupertinoOverrideTheme: CupertinoThemeData(
        selectionHandleColor: colorScheme.primary,
      ),
      switchTheme: SwitchThemeData(
        padding: .zero,
        materialTapTargetSize: .shrinkWrap,
        trackOutlineColor: WidgetStateProperty.resolveWith(
          (states) => isDark ? Colors.white : Colors.black,
        ),
        trackOutlineWidth: const WidgetStatePropertyAll(1.5),
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? (isDark ? Colors.black : Colors.white)
              : (isDark ? Colors.white : Colors.black),
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? (isDark ? Colors.white : Colors.black)
              : Colors.transparent,
        ),
        thumbIcon: const WidgetStateProperty<Icon?>.fromMap(
          <WidgetStatesConstraint, Icon?>{
            WidgetState.selected: Icon(Icons.done),
            WidgetState.any: null,
          },
        ),
      ),
      checkboxTheme: CheckboxThemeData(
        side: borderSide,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(4)),
        ),
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? (isDark ? Colors.white : Colors.black)
              : Colors.transparent,
        ),
        checkColor: WidgetStateProperty.resolveWith(
          (states) => isDark ? Colors.black : Colors.white,
        ),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? (isDark ? Colors.white : Colors.black)
              : (isDark ? Colors.white70 : Colors.black54),
        ),
      ),
      expansionTileTheme: const ExpansionTileThemeData(
        shape: Border(),
        collapsedShape: Border(),
      ),
      listTileTheme: ListTileThemeData(
        controlAffinity: .leading,
        shape: Border(
          bottom: BorderSide(
            color: isDark ? const Color(0xFF444444) : Colors.black,
            width: 1.0,
          ),
        ),
      ),
      // FilledButton.tonal 默认用 secondaryContainer（主题绿），转灰后是一块
      // 深浅不一的灰绿底，和「白底黑框」体系冲突。统一成白底黑框。
      // FilledButton.tonal 默认用 secondaryContainer（主题绿），转灰后是一块
      // 脏灰绿底，和「白底黑框」体系冲突。统一成白底黑框。
      filledButtonTheme: FilledButtonThemeData(
        style: ButtonStyle(
          elevation: const WidgetStatePropertyAll(0),
          shadowColor: const WidgetStatePropertyAll(Colors.transparent),
          backgroundColor: WidgetStatePropertyAll(colorScheme.surface),
          foregroundColor: WidgetStatePropertyAll(colorScheme.onSurface),
          side: WidgetStatePropertyAll(borderSide),
          shape: const WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(8)),
            ),
          ),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ButtonStyle(
          elevation: const WidgetStatePropertyAll(0),
          shadowColor: const WidgetStatePropertyAll(Colors.transparent),
          side: WidgetStatePropertyAll(borderSide),
          shape: const WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(8)),
            ),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: ButtonStyle(
          side: WidgetStatePropertyAll(borderSide),
          shape: const WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(8)),
            ),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: ButtonStyle(
          side: WidgetStatePropertyAll(borderSide),
          shape: const WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(8)),
            ),
          ),
        ),
      ),
      // FilledButton.tonal 默认用 secondaryContainer（主题绿），转灰后是一块
      // 深浅不一的灰绿底，和「白底黑框」体系冲突。统一成白底黑框。
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          side: WidgetStatePropertyAll(borderSide),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        elevation: 0,
        focusElevation: 0,
        hoverElevation: 0,
        highlightElevation: 0,
        backgroundColor: isDark ? Colors.black : Colors.white,
        foregroundColor: isDark ? Colors.white : Colors.black,
        shape: RoundedRectangleBorder(
          borderRadius: const BorderRadius.all(Radius.circular(16)),
          side: borderSide,
        ),
      ),
      searchBarTheme: SearchBarThemeData(
        elevation: const WidgetStatePropertyAll(0),
        side: WidgetStatePropertyAll(borderSide),
        shape: const WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(8)),
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        elevation: 0,
        pressElevation: 0,
        side: borderSide,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(8)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: const BorderRadius.all(Radius.circular(8)),
          borderSide: borderSide,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: const BorderRadius.all(Radius.circular(8)),
          borderSide: borderSide,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: const BorderRadius.all(Radius.circular(8)),
          borderSide: BorderSide(
            color: isDark ? Colors.white : Colors.black,
            width: 1.5,
          ),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: isDark ? Colors.white : Colors.black,
        thickness: 1.0,
        space: 1.0,
      ),
      menuTheme: MenuThemeData(
        style: MenuStyle(
          elevation: const WidgetStatePropertyAll(0),
          side: WidgetStatePropertyAll(borderSide),
          shape: const WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(8)),
            ),
          ),
        ),
      ),
      dropdownMenuTheme: DropdownMenuThemeData(
        menuStyle: MenuStyle(
          elevation: const WidgetStatePropertyAll(0),
          side: WidgetStatePropertyAll(borderSide),
        ),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: NoAnimationPageTransitionsBuilder(),
          TargetPlatform.iOS: NoAnimationPageTransitionsBuilder(),
          TargetPlatform.linux: NoAnimationPageTransitionsBuilder(),
          TargetPlatform.macOS: NoAnimationPageTransitionsBuilder(),
          TargetPlatform.windows: NoAnimationPageTransitionsBuilder(),
        },
      ),
    );
    if (isDark && Pref.isPureBlackTheme) {
      return darkenTheme(theme);
    }
    return theme;
  }

  static ThemeData darkenTheme(ThemeData theme) {
    final colorScheme = theme.colorScheme;
    final color = colorScheme.surfaceContainerHighest.darken(0.7);
    return theme.copyWith(
      canvasColor: Colors.black,
      scaffoldBackgroundColor: Colors.black,
      appBarTheme: theme.appBarTheme.copyWith(
        backgroundColor: Colors.black,
      ),
      cardTheme: theme.cardTheme.copyWith(
        color: colorScheme.surfaceContainer.darken(0.75),
      ),
      dialogTheme: theme.dialogTheme.copyWith(backgroundColor: color),
      bottomSheetTheme: theme.bottomSheetTheme.copyWith(
        backgroundColor: color,
      ),
      bottomNavigationBarTheme: theme.bottomNavigationBarTheme.copyWith(
        backgroundColor: color,
      ),
      navigationBarTheme: theme.navigationBarTheme.copyWith(
        backgroundColor: color,
      ),
      navigationRailTheme: theme.navigationRailTheme.copyWith(
        backgroundColor: Colors.black,
      ),
      popupMenuTheme: theme.popupMenuTheme.copyWith(color: color),
      colorScheme: colorScheme.copyWith(
        primary: colorScheme.primary.darken(0.1),
        onPrimary: colorScheme.onPrimary.darken(0.1),
        primaryContainer: colorScheme.primaryContainer.darken(0.1),
        onPrimaryContainer: colorScheme.onPrimaryContainer.darken(0.1),
        inversePrimary: colorScheme.inversePrimary.darken(0.1),
        secondary: colorScheme.secondary.darken(0.05),
        onSecondary: colorScheme.onSecondary.darken(0.05),
        secondaryContainer: colorScheme.secondaryContainer.darken(0.05),
        onSecondaryContainer: colorScheme.onSecondaryContainer.darken(0.05),
        error: colorScheme.error.darken(0.05),
        surface: Colors.black,
        onSurface: colorScheme.onSurface.darken(0.15),
        surfaceTint: colorScheme.surfaceTint.darken(),
        inverseSurface: colorScheme.inverseSurface.darken(),
        onInverseSurface: colorScheme.onInverseSurface.darken(),
        surfaceContainer: colorScheme.surfaceContainer.darken(),
        surfaceContainerHigh: colorScheme.surfaceContainerHigh.darken(),
        surfaceContainerHighest: colorScheme.surfaceContainerHighest.darken(
          0.4,
        ),
      ),
    );
  }
}

class NoAnimationPageTransitionsBuilder extends PageTransitionsBuilder {
  const NoAnimationPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return child;
  }
}
