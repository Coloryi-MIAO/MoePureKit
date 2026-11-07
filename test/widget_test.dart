import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:moepurekit/config/app_constants.dart';
import 'package:moepurekit/main.dart';
import 'package:moepurekit/models/app_settings.dart';
import 'package:moepurekit/pages/app_shell.dart';

void main() {
  const systemChannel = MethodChannel('moepurekit/system');
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(systemChannel, (call) async {
          if (call.method == 'getAutostart') return false;
          if (call.method == 'setAutostart') return null;
          return null;
        });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(systemChannel, null);
  });

  testWidgets('shows the startup overlay and all sidebar pages', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'moepurekit.downloadDirectoryPrompted': true,
    });
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.localeTestValue = const Locale('zh');
    addTearDown(() => tester.view.resetPhysicalSize());
    addTearDown(() => tester.view.resetDevicePixelRatio());
    addTearDown(() => tester.platformDispatcher.clearLocaleTestValue());

    await tester.pumpWidget(const MyApp());
    expect(
      find.text(AppConstants.splashText).evaluate().isNotEmpty ||
          find
              .text('Your next choice, without another web search.')
              .evaluate()
              .isNotEmpty,
      isTrue,
    );

    await tester.pump(const Duration(milliseconds: 3400));
    await tester.pump(const Duration(milliseconds: 350));

    final isEnglish = find.text('Home').evaluate().isNotEmpty;
    for (final label
        in isEnglish
            ? [
                'Home',
                'Downloads',
                'System',
                'Office',
                'Utilities',
                'Licensing',
                'Quick tools',
                'File checksum',
                'Text tools',
                'JSON formatter',
                'Encoding converter',
                'Network diagnostics',
                'Settings',
                'About',
              ]
            : [
                '首页',
                '下载',
                '系统',
                'Office',
                '实用软件',
                '激活',
                '快捷工具',
                '文件校验',
                '文本工具',
                'JSON 格式化',
                '编码转换',
                '网络诊断',
                '设置',
                '关于',
              ]) {
      expect(find.text(label), findsWidgets);
    }

    await tester.tap(find.text(isEnglish ? 'Licensing' : '激活').first);
    await tester.pump(const Duration(milliseconds: 250));
    expect(
      find.text(isEnglish ? 'XML ticket safety inspection' : 'XML 票据安全检查'),
      findsOneWidget,
    );
    expect(
      find.text(isEnglish ? 'Enterprise KMS client diagnostics' : '企业 KMS 客户端诊断'),
      findsOneWidget,
    );

    await tester.tap(find.text(isEnglish ? 'File checksum' : '文件校验').first);
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('FILE INTEGRITY'), findsOneWidget);
    expect(
      find.text(isEnglish ? 'Choose a file to verify' : '选择要校验的文件'),
      findsOneWidget,
    );

    await tester.tap(find.text(isEnglish ? 'Text tools' : '文本工具').first);
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('TEXT UTILITIES'), findsOneWidget);

    await tester.tap(find.text(isEnglish ? 'JSON formatter' : 'JSON 格式化').first);
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text(isEnglish ? 'JSON WORKBENCH' : 'JSON WORKBENCH'), findsOneWidget);

    await tester.tap(find.text(isEnglish ? 'Encoding converter' : '编码转换').first);
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text(isEnglish ? 'ENCODING CONVERTER' : 'ENCODING CONVERTER'), findsOneWidget);

    await tester.tap(find.text(isEnglish ? 'Network diagnostics' : '网络诊断').first);
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text(isEnglish ? 'Full network test' : '完整网络检测'), findsOneWidget);
    expect(find.text(isEnglish ? 'Ping target' : 'Ping 目标'), findsOneWidget);
    expect(find.text(isEnglish ? 'Start check' : '开始检测'), findsOneWidget);

    await tester.tap(find.text(isEnglish ? 'About' : '关于').first);
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('Coloryi-MIAO'), findsOneWidget);
    expect(find.text('0.3.5-beta.7'), findsOneWidget);
  });

  testWidgets('localizes the startup overlay and uses Microsoft YaHei', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'moepurekit.downloadDirectoryPrompted': true,
      'moepurekit.language': 'english',
    });
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.localeTestValue = const Locale('en');
    addTearDown(() => tester.view.resetPhysicalSize());
    addTearDown(() => tester.view.resetDevicePixelRatio());
    addTearDown(() => tester.platformDispatcher.clearLocaleTestValue());

    await tester.pumpWidget(const MyApp());
    await tester.pump();

    expect(
      find.text('Your next choice, without another web search.'),
      findsOneWidget,
    );
    expect(find.text('MoePureKit Utility Toolkit'), findsWidgets);
    expect(
      Theme.of(tester.element(find.byType(AppShell)))
          .textTheme
          .bodyMedium
          ?.fontFamily,
      'Microsoft YaHei',
    );
    await tester.pump(const Duration(milliseconds: 3100));
    await tester.pump(const Duration(milliseconds: 350));
  });

  testWidgets('applies manually selected language and dark theme', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'moepurekit.downloadDirectoryPrompted': true,
    });
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(() => tester.view.resetPhysicalSize());
    addTearDown(() => tester.view.resetDevicePixelRatio());

    await tester.pumpWidget(const MyApp());
    await tester.pump(const Duration(milliseconds: 3400));
    await tester.pump(const Duration(milliseconds: 350));

    final settingsLabel = find.text('Settings').evaluate().isNotEmpty
        ? 'Settings'
        : '设置';
    await tester.tap(find.text(settingsLabel).first);
    await tester.pump(const Duration(milliseconds: 250));

    await tester.tap(find.byType(DropdownButtonFormField<AppLanguageMode>));
    await tester.pumpAndSettle();
    final chineseOption = find.text('简体中文').evaluate().isNotEmpty
        ? '简体中文'
        : 'Simplified Chinese';
    await tester.tap(find.text(chineseOption).last);
    await tester.pump(const Duration(milliseconds: 250));

    await tester.tap(find.byType(DropdownButtonFormField<AppThemeMode>));
    await tester.pumpAndSettle();
    final darkOption = find.text('深色模式').evaluate().isNotEmpty
        ? '深色模式'
        : 'Dark';
    await tester.tap(find.text(darkOption).last);
    await tester.pumpAndSettle();
    expect(find.text('首页'), findsWidgets);
    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
      ThemeMode.dark,
    );
    expect(
      Theme.of(tester.element(find.byType(Scaffold).first)).brightness,
      Brightness.dark,
    );

    final saveLabel = find.text('保存设置').evaluate().isNotEmpty
        ? '保存设置'
        : 'Save settings';
    await tester.ensureVisible(find.text(saveLabel).last);
    await tester.tap(find.text(saveLabel).last);
    await tester.pumpAndSettle();

    expect(find.text('首页'), findsWidgets);
    expect(
      Theme.of(tester.element(find.byType(AppShell))).brightness,
      Brightness.dark,
    );
  });

  testWidgets('settings controls do not overflow at minimum window size', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'moepurekit.downloadDirectoryPrompted': true,
    });
    tester.view.physicalSize = const Size(900, 600);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.localeTestValue = const Locale('en');
    addTearDown(() => tester.view.resetPhysicalSize());
    addTearDown(() => tester.view.resetDevicePixelRatio());
    addTearDown(() => tester.platformDispatcher.clearLocaleTestValue());

    await tester.pumpWidget(const MyApp());
    await tester.pump(const Duration(milliseconds: 3400));
    await tester.pump(const Duration(milliseconds: 350));
    await tester.tap(find.text('Settings').first);
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
  });

  testWidgets('asks for a download folder once on the first launch', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(() => tester.view.resetPhysicalSize());
    addTearDown(() => tester.view.resetDevicePixelRatio());

    await tester.pumpWidget(const MyApp());
    await tester.pump(const Duration(milliseconds: 3400));
    for (
      var attempt = 0;
      attempt < 8 &&
          find.text('Set download folder').evaluate().isEmpty &&
          find.text('设置下载目录').evaluate().isEmpty;
      attempt++
    ) {
      await tester.pump(const Duration(milliseconds: 350));
    }

    final title = find.text('Set download folder').evaluate().isNotEmpty
        ? 'Set download folder'
        : '设置下载目录';
    final defaultFolder = find.text('Use default folder').evaluate().isNotEmpty
        ? 'Use default folder'
        : '使用默认目录';
    expect(find.text(title), findsOneWidget);
    await tester.tap(find.text(defaultFolder));
    await tester.pump(const Duration(milliseconds: 600));
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getBool('moepurekit.downloadDirectoryPrompted'), isTrue);
    expect(
      preferences.getString('moepurekit.downloadDirectory'),
      contains('Downloads'),
    );
  });
  testWidgets('keeps a visited tool page alive when switching tabs', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'moepurekit.downloadDirectoryPrompted': true,
    });
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(() => tester.view.resetPhysicalSize());
    addTearDown(() => tester.view.resetDevicePixelRatio());

    await tester.pumpWidget(const MyApp());
    await tester.pump(const Duration(milliseconds: 3400));
    await tester.pump(const Duration(milliseconds: 350));

    final textToolsLabel = find.text('文本工具').evaluate().isNotEmpty
        ? '文本工具'
        : 'Text tools';
    final aboutLabel = find.text('关于').evaluate().isNotEmpty ? '关于' : 'About';
    await tester.tap(find.text(textToolsLabel).first);
    await tester.pump();
    final editor = find.byType(TextField).first;
    await tester.enterText(editor, 'this content must survive tab changes');
    await tester.pump(const Duration(milliseconds: 220));

    await tester.tap(find.text(aboutLabel).first);
    await tester.pump();
    await tester.tap(find.text(textToolsLabel).first);
    await tester.pump();

    final restoredEditor = tester.widget<TextField>(find.byType(TextField).first);
    expect(
      restoredEditor.controller!.text,
      'this content must survive tab changes',
    );
  });

}
