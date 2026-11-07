import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_acrylic/flutter_acrylic.dart';
import 'package:window_manager/window_manager.dart';

import 'config/app_constants.dart';
import 'models/app_settings.dart';
import 'pages/app_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Platform.isWindows) {
    await windowManager.ensureInitialized();
    await windowManager.setPreventClose(true);
    await Window.initialize();
    const options = WindowOptions(
      size: Size(1180, 760),
      // Keep enough room for the full navigation while allowing compact
      // layouts on smaller laptop screens. The Flutter tree adapts below.
      minimumSize: Size(760, 520),
      center: true,
      backgroundColor: Colors.transparent,
      titleBarStyle: TitleBarStyle.hidden,
      windowButtonVisibility: false,
      title: AppConstants.appName,
    );
    await windowManager.waitUntilReadyToShow(options, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  AppSettings _settings = const AppSettings();

  void _updateSettings(AppSettings settings) {
    if (mounted) setState(() => _settings = settings);
  }

  @override
  Widget build(BuildContext context) {
    final locale = switch (_settings.languageMode) {
      AppLanguageMode.system => null,
      AppLanguageMode.chinese => const Locale('zh'),
      AppLanguageMode.english => const Locale('en'),
    };
    final bingWallpaperEnabled =
        _settings.backgroundMode == BackgroundMode.bingMica;
    return MaterialApp(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      // Avoid a full-surface color tween that looks like a flash on Windows.
      themeAnimationDuration: Duration.zero,
      theme: _buildTheme(Brightness.light, bingWallpaper: bingWallpaperEnabled),
      darkTheme: _buildTheme(Brightness.dark, bingWallpaper: bingWallpaperEnabled),
      themeMode: switch (_settings.themeMode) {
        AppThemeMode.system => ThemeMode.system,
        AppThemeMode.light => ThemeMode.light,
        AppThemeMode.dark => ThemeMode.dark,
      },
      locale: locale,
      supportedLocales: const [Locale('zh'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      localeResolutionCallback: (deviceLocale, supportedLocales) {
        final requested =
            deviceLocale ?? WidgetsBinding.instance.platformDispatcher.locale;
        return requested.languageCode == 'zh'
            ? const Locale('zh')
            : const Locale('en');
      },
      home: AppShell(onSettingsChanged: _updateSettings),
    );
  }

  ThemeData _buildTheme(
    Brightness brightness, {
    required bool bingWallpaper,
  }) {
    final dark = brightness == Brightness.dark;
    const ink = Color(0xFF282B30);
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      fontFamily: 'Microsoft YaHei',
      fontFamilyFallback: const ['Microsoft YaHei UI', 'Segoe UI'],
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF6D8F7A),
        brightness: brightness,
        surface: bingWallpaper
            ? (dark ? const Color(0xD5202521) : const Color(0xDDFCFDFC))
            : (dark ? const Color(0xFF202421) : const Color(0xFFFCFCFB)),
      ),
      scaffoldBackgroundColor: Colors.transparent,
      textTheme: (dark ? ThemeData.dark() : ThemeData.light()).textTheme.apply(
        fontFamily: 'Microsoft YaHei',
        bodyColor: dark ? const Color(0xFFE8ECE8) : ink,
        displayColor: dark ? const Color(0xFFE8ECE8) : ink,
      ),
      cardTheme: CardThemeData(
        // Translucent cards let the Bing image remain visible inside the
        // content area instead of only around the window edges.
        color: bingWallpaper
            ? (dark ? const Color(0xD5222925) : const Color(0xDFFDFEFC))
            : (dark ? const Color(0xF5282D29) : const Color(0xF5FFFFFF)),
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: const BorderRadius.all(Radius.circular(12)),
          side: BorderSide(
            color: dark ? const Color(0xFF3B433D) : const Color(0xFFE9EAE7),
          ),
        ),
      ),
      dividerColor: dark ? const Color(0xFF3B433D) : const Color(0xFFE7E8E5),
      visualDensity: VisualDensity.standard,
    );
  }
}
