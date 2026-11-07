import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_acrylic/flutter_acrylic.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:window_manager/window_manager.dart';

import '../config/app_constants.dart';
import '../config/app_translations.dart';
import '../models/app_settings.dart';
import '../models/catalog_item.dart';
import '../models/download_source.dart';
import '../models/download_task.dart';
import '../services/aria2_service.dart';
import '../services/aria2_runtime_service.dart';
import '../services/bing_wallpaper_service.dart';
import '../services/catalog_service.dart';
import '../services/file_hash_service.dart';
import '../services/settings_service.dart';
import '../services/startup_service.dart';
import '../services/system_status_service.dart';
import '../services/network_diagnostics_service.dart';
import '../services/system_metrics_service.dart';
import '../services/update_service.dart';
import 'maintenance_pages.dart';
import '../widgets/motion_settings.dart';

enum AppPage {
  home('首页', Icons.home_outlined),
  downloads('下载', Icons.download_outlined),
  fileManager('文件管理', Icons.folder_open_outlined),
  cleanup('C 盘清理', Icons.cleaning_services_outlined),
  security('病毒查杀', Icons.shield_outlined),
  drivers('驱动管理', Icons.memory_outlined),
  system('系统', Icons.computer_outlined),
  office('Office', Icons.description_outlined),
  software('实用软件', Icons.widgets_outlined),
  activation('激活', Icons.verified_user_outlined),
  quickTools('快捷工具', Icons.dashboard_customize_outlined),
  fileHash('文件校验', Icons.fingerprint_outlined),
  textTools('文本工具', Icons.text_fields),
  jsonTools('JSON 格式化', Icons.data_object),
  encodingTools('编码转换', Icons.code),
  network('网络诊断', Icons.wifi_tethering_outlined),
  settings('设置', Icons.settings_outlined),
  about('关于', Icons.info_outline);

  const AppPage(this.label, this.icon);
  final String label;
  final IconData icon;
}

class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.onSettingsChanged});

  final ValueChanged<AppSettings> onSettingsChanged;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell>
    with WidgetsBindingObserver, WindowListener, TrayListener {
  final _settingsService = SettingsService();
  final _wallpaperService = BingWallpaperService();
  final _aria2Runtime = Aria2RuntimeService();
  late AppSettings _settings;
  late AppSettings _savedSettings;
  late Aria2Service _aria2;
  final GlobalKey<_SettingsPageState> _settingsPageKey =
      GlobalKey<_SettingsPageState>();
  final ValueNotifier<AppPage> _currentPage = ValueNotifier<AppPage>(AppPage.home);
  bool _settingsLoaded = false;
  bool _splashVisible = true;
  bool _splashOpaque = false;
  String? _pendingDownloadUri;
  BingWallpaperInfo? _wallpaper;
  bool _wallpaperLoading = false;
  String? _wallpaperError;
  final ValueNotifier<Set<AppPage>> _activePages =
      ValueNotifier<Set<AppPage>>(<AppPage>{});
  final Set<AppPage> _visitedPages = <AppPage>{AppPage.home};
  String? _persistenceError;
  String _aria2RuntimeStatus = '正在准备内置 aria2';
  bool _officeDeploymentInProgress = false;
  bool _closePromptVisible = false;
  bool _allowClose = false;
  bool _exitInProgress = false;
  bool _trayInitialized = false;
  final Set<Aria2Service> _retiredServices = {};
  final Set<Timer> _serviceRetirementTimers = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (Platform.isWindows) {
      windowManager.addListener(this);
      trayManager.addListener(this);
    }
    _settings = const AppSettings();
    _savedSettings = _settings;
    _aria2 = Aria2Service(_settings);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _splashOpaque = true);
    });
    unawaited(_finishSplash());
    unawaited(_loadSettings());
  }

  Future<void> _finishSplash() async {
    await Future<void>.delayed(const Duration(milliseconds: 2700));
    if (!mounted) return;
    setState(() => _splashOpaque = false);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    if (mounted) setState(() => _splashVisible = false);
  }

  Future<void> _loadSettings() async {
    try {
      var loaded = await _settingsService.load();
      String? startupStatusError;
      try {
        loaded = loaded.copyWith(
          launchAtStartup: await StartupService().isEnabled(),
        );
      } catch (error) {
        startupStatusError = '开机自启状态读取失败：${_shortError(error)}';
      }
      if (!mounted) return;
      setState(() {
        _settings = loaded;
        _savedSettings = loaded;
        _settingsLoaded = true;
        _persistenceError = startupStatusError;
        _retireService(_aria2);
        _aria2 = Aria2Service(loaded);
      });
      widget.onSettingsChanged(loaded);
      if (!loaded.downloadDirectoryPrompted) {
        unawaited(_promptForDownloadDirectory());
      }
      final runtimeStatus = await _aria2Runtime.start(loaded);
      if (mounted) setState(() => _aria2RuntimeStatus = runtimeStatus);
      await _applyBackgroundEffect(
        loaded.backgroundMode,
        dark: _isDarkMode(loaded.themeMode),
      );
      if (loaded.backgroundMode == BackgroundMode.bingMica) {
        await _loadWallpaper();
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _settingsLoaded = true;
          _persistenceError = '设置加载失败：$error';
        });
      }
    }
  }

  Future<void> _applySettings(AppSettings settings) async {
    final oldSettings = _savedSettings;
    final aria2RuntimeChanged =
        oldSettings.aria2RpcUrl != settings.aria2RpcUrl ||
        oldSettings.aria2RpcSecret != settings.aria2RpcSecret ||
        oldSettings.downloadDirectory != settings.downloadDirectory ||
        oldSettings.proxy != settings.proxy ||
        oldSettings.concurrentDownloads != settings.concurrentDownloads;
    final aria2Changed = aria2RuntimeChanged ||
        oldSettings.defaultUserAgent != settings.defaultUserAgent ||
        oldSettings.defaultReferer != settings.defaultReferer ||
        oldSettings.defaultCookie != settings.defaultCookie ||
        oldSettings.defaultHeaders != settings.defaultHeaders;
    final themeChanged = oldSettings.themeMode != settings.themeMode;
    final languageChanged = oldSettings.languageMode != settings.languageMode;
    final backgroundChanged =
        oldSettings.backgroundMode != settings.backgroundMode;
    final startupChanged = oldSettings.launchAtStartup != settings.launchAtStartup;

    final oldService = _aria2;
    void updateLocalSettings() {
      _settings = settings;
      if (aria2Changed) _aria2 = Aria2Service(settings);
      _persistenceError = null;
    }

    final needsInheritedRebuild =
        themeChanged || languageChanged || backgroundChanged;
    if (needsInheritedRebuild) {
      updateLocalSettings();
      widget.onSettingsChanged(settings);
    } else {
      setState(updateLocalSettings);
    }
    if (aria2Changed) _retireService(oldService);

    try {
      if (startupChanged) {
        await StartupService().setEnabled(settings.launchAtStartup);
      }
      await _settingsService.save(settings);
      _savedSettings = settings;
      if (aria2RuntimeChanged) {
        await _aria2Runtime.stop();
        final runtimeStatus = await _aria2Runtime.start(settings);
        if (mounted) setState(() => _aria2RuntimeStatus = runtimeStatus);
      }
      if (backgroundChanged || themeChanged) {
        await _applyBackgroundEffect(
          settings.backgroundMode,
          dark: _isDarkMode(settings.themeMode),
        );
      }
      if (settings.backgroundMode == BackgroundMode.bingMica &&
          (backgroundChanged || _wallpaper == null)) {
        await _loadWallpaper();
      } else if (backgroundChanged &&
          settings.backgroundMode != BackgroundMode.bingMica) {
        if (mounted) {
          setState(() {
            _wallpaperError = null;
            _wallpaperLoading = false;
          });
        }
      }
    } catch (error) {
      // Do not leave an unsaved preview applied after a failed save.
      _settings = oldSettings;
      _savedSettings = oldSettings;
      if (aria2Changed) {
        _retireService(_aria2);
        _aria2 = Aria2Service(oldSettings);
      }
      widget.onSettingsChanged(oldSettings);
      try {
        await _applyBackgroundEffect(
          oldSettings.backgroundMode,
          dark: _isDarkMode(oldSettings.themeMode),
        );
      } catch (_) {}
      if (startupChanged) {
        try {
          await StartupService().setEnabled(oldSettings.launchAtStartup);
        } catch (_) {}
      }
      if (mounted) setState(() => _persistenceError = '设置保存失败：$error');
      rethrow;
    }
  }

  /// Applies only theme/background to the live shell; nothing is persisted
  /// until the user explicitly presses Save in the settings page.
  void _previewAppearance(AppSettings draft) {
    final preview = _settings.copyWith(
      themeMode: draft.themeMode,
      backgroundMode: draft.backgroundMode,
    );
    if (preview.themeMode == _settings.themeMode &&
        preview.backgroundMode == _settings.backgroundMode) {
      return;
    }
    setState(() => _settings = preview);
    widget.onSettingsChanged(preview);
    unawaited(
      _applyBackgroundEffect(
        preview.backgroundMode,
        dark: _isDarkMode(preview.themeMode),
      ).catchError((Object error) {
        if (mounted) {
          setState(() => _wallpaperError = '外观预览失败：${_shortError(error)}');
        }
      }),
    );
    if (preview.backgroundMode == BackgroundMode.bingMica &&
        _wallpaper == null &&
        !_wallpaperLoading) {
      unawaited(_loadWallpaper());
    }
  }

  bool _isDarkMode(AppThemeMode mode) {
    return switch (mode) {
      AppThemeMode.dark => true,
      AppThemeMode.light => false,
      AppThemeMode.system =>
        WidgetsBinding.instance.platformDispatcher.platformBrightness ==
            Brightness.dark,
    };
  }

  void _retireService(Aria2Service service) {
    late final Timer timer;
    timer = Timer(const Duration(seconds: 4), () {
      _serviceRetirementTimers.remove(timer);
      _retiredServices.remove(service);
      service.close();
    });
    _retiredServices.add(service);
    _serviceRetirementTimers.add(timer);
  }

  Future<void> _applyBackgroundEffect(
    BackgroundMode mode, {
    required bool dark,
  }) async {
    if (!Platform.isWindows) return;
    switch (mode) {
      case BackgroundMode.white:
        await Window.setEffect(
          effect: WindowEffect.disabled,
          color: const Color(0xFFFFFFFF),
          dark: dark,
        );
      case BackgroundMode.mica:
        await Window.setEffect(
          effect: WindowEffect.mica,
          color: const Color(0xFFF5F6F4),
          dark: dark,
        );
      case BackgroundMode.bingMica:
        await Window.setEffect(
          effect: WindowEffect.acrylic,
          color: const Color(0xBFFFFFFF),
          dark: dark,
        );
    }
  }

  Future<void> _loadWallpaper({bool forceRefresh = false}) async {
    if (_wallpaperLoading) return;
    setState(() {
      _wallpaperLoading = true;
      _wallpaperError = null;
    });
    _setPageActivity(AppPage.settings, true);
    try {
      final wallpaper = await _wallpaperService.loadToday(
        forceRefresh: forceRefresh,
      );
      if (!mounted) return;
      setState(() {
        _wallpaper = wallpaper;
        _wallpaperError = wallpaper.isStale
            ? 'Bing 暂时不可用，正在使用上次缓存的壁纸'
            : null;
      });
    } catch (error) {
      if (mounted) {
        setState(() => _wallpaperError = 'Bing 壁纸载入失败：${_shortError(error)}');
      }
    } finally {
      if (mounted) {
        setState(() => _wallpaperLoading = false);
        _setPageActivity(AppPage.settings, false);
      }
    }
  }

  void _setPageActivity(AppPage page, bool active) {
    if (!mounted) return;
    final current = _activePages.value;
    if (current.contains(page) == active) return;
    final updated = Set<AppPage>.of(current);
    if (active) {
      updated.add(page);
    } else {
      updated.remove(page);
    }
    // Updating the indicator no longer rebuilds the entire tool workspace.
    _activePages.value = Set<AppPage>.unmodifiable(updated);
  }

  void _navigateTo(AppPage page) {
    unawaited(_navigateToGuarded(page));
  }

  Future<void> _navigateToGuarded(
    AppPage page, {
    VoidCallback? beforeNavigate,
  }) async {
    if (!mounted) return;
    if (_currentPage.value == AppPage.settings && page != AppPage.settings) {
      final canLeave =
          await _settingsPageKey.currentState?.confirmLeave() ?? true;
      if (!canLeave || !mounted) return;
    }
    beforeNavigate?.call();
    _visitedPages.add(page);
    _currentPage.value = page;
  }

  void _openResourceDownload(String uri) {
    unawaited(
      _navigateToGuarded(
        AppPage.downloads,
        beforeNavigate: () => _pendingDownloadUri = uri,
      ),
    );
  }

  void _consumePendingDownload(String uri) {
    if (_pendingDownloadUri == uri) {
      setState(() => _pendingDownloadUri = null);
    }
  }

  Future<void> _promptForDownloadDirectory() async {
    if (!mounted || !_settingsLoaded || _splashVisible) {
      await Future<void>.delayed(const Duration(milliseconds: 350));
      if (!mounted) return;
      return _promptForDownloadDirectory();
    }
    final defaultPath = [
      Platform.environment['USERPROFILE'] ?? '',
      'Downloads',
      'MoePureKit',
    ].where((part) => part.isNotEmpty).join(Platform.pathSeparator);
    final selectedPath = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const LocalizedText('设置下载目录'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const LocalizedText('请选择下载文件的保存位置。之后也可以在“设置”中修改。'),
            const SizedBox(height: 12),
            SelectableText(defaultPath),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, ''),
            child: const LocalizedText('暂不设置'),
          ),
          TextButton(
            onPressed: () async {
              final path = await getDirectoryPath(
                initialDirectory: Directory(defaultPath).parent.path,
                confirmButtonText: '选择此文件夹',
              );
              if (path != null && context.mounted) {
                Navigator.pop(context, path);
              }
            },
            child: const LocalizedText('选择文件夹'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, defaultPath),
            child: const LocalizedText('使用默认目录'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    await _applySettings(
      _settings.copyWith(
        downloadDirectory: selectedPath?.trim().isNotEmpty == true
            ? selectedPath!.trim()
            : _settings.downloadDirectory,
        downloadDirectoryPrompted: true,
      ),
    );
  }

  Future<void> _ensureTray() async {
    if (_trayInitialized) return;
    final iconPath = [
      File(Platform.resolvedExecutable).parent.path,
      'tray_icon.ico',
    ].join(Platform.pathSeparator);
    await trayManager.setIcon(iconPath);
    await trayManager.setToolTip('MoePureKit 萌净工具箱');
    await trayManager.setContextMenu(
      Menu(
        items: [
          MenuItem(key: 'show', label: '打开萌净工具箱'),
          MenuItem.separator(),
          MenuItem(key: 'exit', label: '退出萌净工具箱'),
        ],
      ),
    );
    _trayInitialized = true;
  }

  Future<void> _showWindow() async {
    await windowManager.show();
    await windowManager.focus();
  }

  Future<void> _exitApplication({bool settingsAlreadyConfirmed = false}) async {
    if (_allowClose || _exitInProgress) return;
    _exitInProgress = true;
    try {
      // Tray-menu exit is also a navigation away from the settings workspace.
      // Apply the same unsaved-changes guard used by tab navigation/window close.
      if (!settingsAlreadyConfirmed && _currentPage.value == AppPage.settings) {
        final canLeave =
            await _settingsPageKey.currentState?.confirmLeave() ?? true;
        if (!canLeave || !mounted) {
          _exitInProgress = false;
          return;
        }
      }

      // The runtime is an independently running child process on Windows.
      // Wait for aria2.shutdown and, if needed, terminate only the exact PID
      // started by this app before allowing the native window to close.
      await _aria2Runtime.stop();
      if (_trayInitialized) {
        await trayManager.destroy();
        _trayInitialized = false;
      }
      _allowClose = true;
      await windowManager.setPreventClose(false);
      await windowManager.close();
    } catch (error) {
      _exitInProgress = false;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: LocalizedText('退出前关闭 aria2 失败：$error')),
        );
      }
    }
  }

  @override
  void onWindowClose() {
    if (_allowClose) return;
    unawaited(_confirmWindowClose());
  }

  Future<void> _confirmWindowClose() async {
    if (!mounted || _closePromptVisible || _exitInProgress) return;
    // Lock immediately, before any async settings/download lookup, so both the
    // title-bar button and WM_CLOSE event share exactly one dialog.
    _closePromptVisible = true;
    try {
      if (_currentPage.value == AppPage.settings) {
        final canLeave =
            await _settingsPageKey.currentState?.confirmLeave() ?? true;
        if (!canLeave || !mounted) return;
      }

      if (_settings.suppressCloseConfirmation) {
        await _closeUsingPreference(settingsAlreadyConfirmed: true);
        return;
      }

      var activeDownloads = 0;
      var waitingDownloads = 0;
      String? downloadStatusError;
      try {
        final stat = await _aria2.globalStat().timeout(
          const Duration(seconds: 2),
        );
        activeDownloads = int.tryParse('${stat['numActive']}') ?? 0;
        waitingDownloads = int.tryParse('${stat['numWaiting']}') ?? 0;
      } catch (error) {
        downloadStatusError = _shortError(error);
      }
      if (!mounted) return;

      final activities = <String>[
        if (activeDownloads > 0) '正在下载：$activeDownloads 个',
        if (waitingDownloads > 0) '排队任务：$waitingDownloads 个',
        if (_officeDeploymentInProgress) 'Office 部署仍在运行',
        if (downloadStatusError != null)
          '无法读取下载状态：$downloadStatusError',
      ];
      var suppressFuturePrompts = false;
      final choice = await showDialog<({String action, bool suppressPrompts})>(
        context: context,
        barrierDismissible: false,
        builder: (context) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: const LocalizedText('关闭 MoePureKit？'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LocalizedText(
                  activities.isEmpty
                      ? '选择隐藏到系统托盘继续运行，或退出应用。'
                      : '${activities.join('\n')}。\n隐藏到系统托盘可继续后台运行；退出会停止 aria2，并中断进行中的任务。',
                ),
                const SizedBox(height: 8),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: const LocalizedText('不再询问关闭确认（可在设置中重新开启）'),
                  value: suppressFuturePrompts,
                  onChanged: (value) => setDialogState(
                    () => suppressFuturePrompts = value ?? false,
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const LocalizedText('取消'),
              ),
              OutlinedButton(
                autofocus: !_settings.minimizeToTrayOnClose,
                onPressed: () => Navigator.pop(context, (
                  action: 'exit',
                  suppressPrompts: suppressFuturePrompts,
                )),
                child: const LocalizedText('退出应用'),
              ),
              FilledButton(
                autofocus: _settings.minimizeToTrayOnClose,
                onPressed: () => Navigator.pop(context, (
                  action: 'tray',
                  suppressPrompts: suppressFuturePrompts,
                )),
                child: const LocalizedText('最小化到托盘'),
              ),
            ],
          ),
        ),
      );
      if (!mounted || choice == null) return;
      if (choice.suppressPrompts) {
        await _applySettings(
          _settings.copyWith(suppressCloseConfirmation: true),
        );
      }
      if (choice.action == 'tray') {
        await _minimizeToTray();
      } else if (choice.action == 'exit') {
        await _exitApplication(settingsAlreadyConfirmed: true);
      }
    } finally {
      _closePromptVisible = false;
    }
  }

  Future<void> _closeUsingPreference({bool settingsAlreadyConfirmed = false}) async {
    if (_settings.minimizeToTrayOnClose) {
      await _minimizeToTray();
    } else {
      await _exitApplication(settingsAlreadyConfirmed: settingsAlreadyConfirmed);
    }
  }

  Future<void> _minimizeToTray() async {
    try {
      await _ensureTray();
      await windowManager.hide();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: LocalizedText('无法创建系统托盘图标：$error')));
      }
    }
  }

  @override
  void onTrayIconMouseDown() {
    unawaited(_showWindow());
  }

  @override
  void onTrayIconRightMouseDown() {
    unawaited(trayManager.popUpContextMenu());
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case 'show':
        unawaited(_showWindow());
      case 'exit':
        unawaited(_exitApplication());
    }
  }

  @override
  void dispose() {
    if (Platform.isWindows) {
      windowManager.removeListener(this);
      trayManager.removeListener(this);
    }
    _aria2.close();
    _wallpaperService.close();
    _activePages.dispose();
    _currentPage.dispose();
    for (final timer in _serviceRetirementTimers) {
      timer.cancel();
    }
    for (final service in _retiredServices) {
      service.close();
    }
    _serviceRetirementTimers.clear();
    _retiredServices.clear();
    unawaited(_aria2Runtime.stop().catchError((Object _) {}));
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangePlatformBrightness() {
    super.didChangePlatformBrightness();
    if (_settings.themeMode == AppThemeMode.system) {
      unawaited(
        _applyBackgroundEffect(
          _settings.backgroundMode,
          dark: _isDarkMode(_settings.themeMode),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final animationsEnabled = _settings.animationsEnabled && !reduceMotion;
    return MotionSettings(
      enabled: animationsEnabled,
      child: Stack(
      fit: StackFit.expand,
      children: [
        _buildBackground(),
        Scaffold(
          backgroundColor: Colors.transparent,
          body: Column(
            children: [
              _WindowTitleBar(
                status: _settingsLoaded ? '已就绪' : '正在加载设置',
                onClose: () => unawaited(_confirmWindowClose()),
              ),
              Expanded(
                child: Row(
                  children: [
                    ValueListenableBuilder<AppPage>(
                      valueListenable: _currentPage,
                      builder: (context, selectedPage, child) =>
                          ValueListenableBuilder<Set<AppPage>>(
                        valueListenable: _activePages,
                        builder: (context, activePages, child) => _Sidebar(
                          selected: selectedPage,
                          activePages: activePages,
                          compact: MediaQuery.sizeOf(context).width < 1020,
                          animationsEnabled: animationsEnabled,
                          bingWallpaper: _settings.backgroundMode ==
                              BackgroundMode.bingMica,
                          onSelected: _navigateTo,
                        ),
                      ),
                    ),
                    Expanded(
                      child: ValueListenableBuilder<AppPage>(
                        valueListenable: _currentPage,
                        builder: (context, selectedPage, child) => Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _PageHeader(
                              title: selectedPage.label,
                              status: _persistenceError ??
                                  _wallpaperError ?? 'Windows 桌面工具',
                            ),
                            Expanded(
                              child: ValueListenableBuilder<Set<AppPage>>(
                                valueListenable: _activePages,
                                builder: (context, activePages, child) =>
                                    _PersistentPageSwitcher(
                                  index: AppPage.values.indexOf(selectedPage),
                                  enabled: animationsEnabled,
                                  children: [
                                    for (final page in AppPage.values)
                                      if (_visitedPages.contains(page))
                                        TickerMode(
                                          key: ValueKey('page-ticker-${page.name}'),
                                          // A hidden page is muted only while
                                          // idle. Long-running tasks keep their
                                          // tickers alive and continue in the
                                          // background, while idle pages save
                                          // frames and CPU time.
                                          enabled: selectedPage == page ||
                                              activePages.contains(page),
                                          child: RepaintBoundary(
                                            key: ValueKey('page-${page.name}'),
                                            child: _pageBody(page),
                                          ),
                                        )
                                      else
                                        SizedBox.shrink(
                                          key: ValueKey('page-${page.name}'),
                                        ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (_splashVisible)
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedOpacity(
                opacity: _splashOpaque ? 1 : 0,
                duration: const Duration(milliseconds: 300),
                child: ColoredBox(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? const Color(0xFF171B18)
                      : const Color(0xFFF9FAF8),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.spa_outlined,
                          size: 34,
                          color: Color(0xFF698674),
                        ),
                        const SizedBox(height: 22),
                        LocalizedText(
                          AppConstants.splashText,
                          style: TextStyle(
                            fontSize: 17,
                            letterSpacing: 1.2,
                            color:
                                Theme.of(context).brightness == Brightness.dark
                                ? const Color(0xFFE5E9E5)
                                : const Color(0xFF383D39),
                          ),
                        ),
                        const SizedBox(height: 14),
                        const LocalizedText(
                          AppConstants.appName,
                          style: TextStyle(
                            fontSize: 12,
                            color: Color(0xFF8A908B),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    ),
    );
  }

  Widget _buildBackground() {
    final mode = _settings.backgroundMode;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final useBingImage = mode == BackgroundMode.bingMica && _wallpaper != null;

    return SizedBox.expand(
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (useBingImage)
            Opacity(
              // Keep the photo clearly visible, while a tint layer below
              // preserves contrast for translucent cards and sidebar labels.
              opacity: dark ? 0.70 : 0.78,
              child: Image.file(
                File(_wallpaper!.localPath),
                key: ValueKey(_wallpaper!.localPath),
                fit: BoxFit.cover,
                cacheWidth: 1920,
                cacheHeight: 1080,
                filterQuality: FilterQuality.low,
                gaplessPlayback: true,
                errorBuilder: (context, error, stackTrace) =>
                    ColoredBox(
                      color: dark
                          ? const Color(0xFF191D1A)
                          : const Color(0xFFFAFBF9),
                    ),
              ),
            )
          else
            ColoredBox(
              color: dark
                  ? (mode == BackgroundMode.white
                        ? const Color(0xFF191D1A)
                        : const Color(0xD5202521))
                  : (mode == BackgroundMode.white
                        ? const Color(0xFFFAFBF9)
                        : const Color(0xDDF7F8F6)),
            ),
          if (useBingImage)
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: dark
                      ? const [Color(0x660B110D), Color(0x390B110D)]
                      : const [Color(0x49FFFFFF), Color(0x23FFFFFF)],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _pageBody(AppPage page) {
    switch (page) {
      case AppPage.home:
        return _HomePage(
          key: const ValueKey(AppPage.home),
          onNavigate: _navigateTo,
          runtimeStatus: _aria2RuntimeStatus,
        );
      case AppPage.downloads:
        return _DownloadsPage(
          key: const ValueKey(AppPage.downloads),
          service: _aria2,
          runtimeStatus: _aria2RuntimeStatus,
          initialUri: _pendingDownloadUri,
          onInitialUriConsumed: _consumePendingDownload,
          onActivityChanged: (active) =>
              _setPageActivity(AppPage.downloads, active),
        );
      case AppPage.system:
        return _SystemPage(
          key: const ValueKey(AppPage.system),
          onSelectResource: _openResourceDownload,
        );
      case AppPage.fileManager:
        return const FileManagerPage(key: ValueKey(AppPage.fileManager));
      case AppPage.cleanup:
        return CleanupPage(
          key: const ValueKey(AppPage.cleanup),
          onActivityChanged: (active) => _setPageActivity(AppPage.cleanup, active),
        );
      case AppPage.security:
        return SecurityPage(
          key: const ValueKey(AppPage.security),
          onActivityChanged: (active) => _setPageActivity(AppPage.security, active),
        );
      case AppPage.drivers:
        return DriversPage(
          key: const ValueKey(AppPage.drivers),
          onActivityChanged: (active) => _setPageActivity(AppPage.drivers, active),
        );
      case AppPage.office:
        return _OfficePage(
          key: const ValueKey(AppPage.office),
          onDeploymentChanged: (active) {
            if (mounted) setState(() => _officeDeploymentInProgress = active);
          },
          onActivityChanged: (active) =>
              _setPageActivity(AppPage.office, active),
        );
      case AppPage.software:
        return _SoftwarePage(
          key: const ValueKey(AppPage.software),
          onSelectResource: _openResourceDownload,
        );
      case AppPage.activation:
        return _ActivationPage(
          key: const ValueKey(AppPage.activation),
          onActivityChanged: (active) =>
              _setPageActivity(AppPage.activation, active),
        );
      case AppPage.quickTools:
        return const _QuickToolsPage(key: ValueKey(AppPage.quickTools));
      case AppPage.fileHash:
        return _FileHashPage(
          key: const ValueKey(AppPage.fileHash),
          onActivityChanged: (active) =>
              _setPageActivity(AppPage.fileHash, active),
        );
      case AppPage.textTools:
        return const _TextToolsPage(key: ValueKey(AppPage.textTools));
      case AppPage.jsonTools:
        return const _JsonToolsPage(key: ValueKey(AppPage.jsonTools));
      case AppPage.encodingTools:
        return const _EncodingToolsPage(key: ValueKey(AppPage.encodingTools));
      case AppPage.network:
        return _NetworkPage(
          key: const ValueKey(AppPage.network),
          onActivityChanged: (active) =>
              _setPageActivity(AppPage.network, active),
        );
      case AppPage.settings:
        return _SettingsPage(
          key: _settingsPageKey,
          settings: _savedSettings,
          onSave: _applySettings,
          onPreview: _previewAppearance,
          wallpaper: _wallpaper,
          wallpaperLoading: _wallpaperLoading,
          wallpaperError: _wallpaperError,
          onRefreshWallpaper: () => _loadWallpaper(forceRefresh: true),
        );
      case AppPage.about:
        return const _AboutPage(key: ValueKey(AppPage.about));
    }
  }
}




/// Keeps every visited page mounted while animating only the visible surface.
/// TickerMode is controlled per page by the host: selected pages and pages
/// with an active long-running task keep ticking while idle background pages
/// are muted to save CPU. This switcher itself never destroys page State.
class _PersistentPageSwitcher extends StatefulWidget {
  const _PersistentPageSwitcher({
    required this.index,
    required this.enabled,
    required this.children,
  });

  final int index;
  final bool enabled;
  final List<Widget> children;

  @override
  State<_PersistentPageSwitcher> createState() =>
      _PersistentPageSwitcherState();
}

class _PersistentPageSwitcherState extends State<_PersistentPageSwitcher>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late int _displayedIndex;
  int _transitionToken = 0;

  @override
  void initState() {
    super.initState();
    _displayedIndex = widget.index;
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
      value: 1,
    );
  }

  @override
  void didUpdateWidget(covariant _PersistentPageSwitcher oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.enabled != widget.enabled && !widget.enabled) {
      _transitionToken++;
      _controller.stop();
      _controller.value = 1;
      _displayedIndex = widget.index;
      return;
    }
    if (oldWidget.index != widget.index) {
      if (!widget.enabled) {
        _transitionToken++;
        _controller.stop();
        _controller.value = 1;
        _displayedIndex = widget.index;
      } else {
        _transitionTo(widget.index);
      }
    }
  }

  Future<void> _transitionTo(int targetIndex) async {
    // Invalidate an older transition even when the user navigates back to the
    // page that is still displayed during the fade-out half.
    final token = ++_transitionToken;
    _controller.stop();
    if (targetIndex == _displayedIndex) {
      try {
        await _controller.animateTo(
          1,
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeOutCubic,
        );
      } catch (_) {}
      return;
    }
    try {
      await _controller.animateTo(
        0,
        duration: const Duration(milliseconds: 105),
        curve: Curves.easeInCubic,
      );
      if (!mounted || token != _transitionToken) return;
      setState(() => _displayedIndex = targetIndex);
      await _controller.animateTo(
        1,
        duration: const Duration(milliseconds: 175),
        curve: Curves.easeOutCubic,
      );
    } catch (_) {
      // A newer navigation request may interrupt the previous transition.
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      child: IndexedStack(
        index: _displayedIndex,
        sizing: StackFit.expand,
        children: widget.children,
      ),
      builder: (context, child) {
        final opacity = Curves.easeOutCubic.transform(_controller.value);
        return Opacity(
          opacity: opacity,
          child: Transform.translate(
            offset: Offset(0, (1 - opacity) * 5),
            child: child,
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _transitionToken++;
    _controller.dispose();
    super.dispose();
  }
}

class _WindowTitleBar extends StatelessWidget {
  const _WindowTitleBar({required this.status, required this.onClose});

  final String status;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: Row(
        children: [
          Expanded(
            child: DragToMoveArea(
              child: Padding(
                padding: const EdgeInsets.only(left: 20),
                child: Row(
                  children: [
                    const Icon(
                      Icons.spa_outlined,
                      size: 17,
                      color: Color(0xFF688272),
                    ),
                    const SizedBox(width: 9),
                    const LocalizedText(
                      AppConstants.appName,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 14),
                    LocalizedText(
                      status,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF969C97),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          _WindowButton(
            icon: Icons.minimize,
            tooltip: '最小化',
            onPressed: () => windowManager.minimize(),
          ),
          _WindowButton(
            icon: Icons.crop_square,
            tooltip: '最大化 / 还原',
            onPressed: () async {
              if (await windowManager.isMaximized()) {
                await windowManager.unmaximize();
              } else {
                await windowManager.maximize();
              }
            },
          ),
          _WindowButton(
            icon: Icons.close,
            tooltip: '关闭',
            onPressed: onClose,
            close: true,
          ),
        ],
      ),
    );
  }
}

class _WindowButton extends StatelessWidget {
  const _WindowButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.close = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final bool close;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Tooltip(
      message: translateText(context, tooltip),
      child: SizedBox(
        width: 46,
        height: 44,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            hoverColor: close
                ? const Color(0xFFE86B66)
                : dark
                ? const Color(0xFF3B433D)
                : const Color(0xFFE9EBE8),
            onTap: onPressed,
            child: Icon(
              icon,
              size: 15,
              color: dark ? const Color(0xFFE5E9E5) : const Color(0xFF424743),
            ),
          ),
        ),
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.selected,
    required this.activePages,
    required this.compact,
    required this.animationsEnabled,
    required this.bingWallpaper,
    required this.onSelected,
  });

  final AppPage selected;
  final Set<AppPage> activePages;
  final bool compact;
  final bool animationsEnabled;
  final bool bingWallpaper;
  final ValueChanged<AppPage> onSelected;

  static const _groups = <(String, List<AppPage>)>[
    ('概览', [AppPage.home]),
    ('下载与资源', [AppPage.downloads, AppPage.system, AppPage.software, AppPage.office]),
    ('系统维护', [AppPage.fileManager, AppPage.cleanup, AppPage.security, AppPage.drivers, AppPage.activation, AppPage.quickTools, AppPage.network]),
    ('效率工具', [AppPage.fileHash, AppPage.textTools, AppPage.jsonTools, AppPage.encodingTools]),
    ('其他', [AppPage.settings, AppPage.about]),
  ];

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final duration = animationsEnabled
        ? const Duration(milliseconds: 220)
        : Duration.zero;
    return LayoutBuilder(
      builder: (context, _) {
        final width = compact ? 62.0 : 210.0;
        return AnimatedContainer(
          duration: animationsEnabled
              ? const Duration(milliseconds: 180)
              : Duration.zero,
          curve: Curves.easeOutCubic,
          width: width,
          decoration: BoxDecoration(
            color: dark
                ? (bingWallpaper ? const Color(0xD5202521) : const Color(0xEF202521))
                : (bingWallpaper ? const Color(0xDDFDFEFC) : const Color(0xEFFFFFFF)),
            border: Border(
              right: BorderSide(color: dark ? const Color(0xFF3B433D) : const Color(0xFFE8EAE6)),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!compact)
                const Padding(
                  padding: EdgeInsets.fromLTRB(18, 19, 12, 12),
                  child: LocalizedText(
                    '工具箱',
                    style: TextStyle(color: Color(0xFF8D948E), fontSize: 11, letterSpacing: 1),
                  ),
                ),
              Expanded(
                child: ListView(
                  padding: EdgeInsets.fromLTRB(compact ? 5 : 8, 0, compact ? 5 : 8, 8),
                  children: [
                    for (final group in _groups) ...[
                      if (!compact)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(10, 14, 8, 6),
                          child: LocalizedText(
                            group.$1,
                            style: const TextStyle(fontSize: 10, color: Color(0xFF969D97), fontWeight: FontWeight.w600),
                          ),
                        ),
                      for (final page in group.$2)
                        _NavigationItem(
                          page: page,
                          selected: selected == page,
                          active: activePages.contains(page),
                          compact: compact,
                          animationDuration: duration,
                          onTap: () => onSelected(page),
                        ),
                    ],
                  ],
                ),
              ),
              if (!compact)
                const Padding(
                  padding: EdgeInsets.fromLTRB(18, 8, 10, 14),
                  child: LocalizedText('朴素 · 轻便 · 常用', style: TextStyle(fontSize: 10, color: Color(0xFFA0A59F))),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _NavigationItem extends StatelessWidget {
  const _NavigationItem({
    required this.page,
    required this.selected,
    required this.active,
    required this.compact,
    required this.animationDuration,
    required this.onTap,
  });

  final AppPage page;
  final bool selected;
  final bool active;
  final bool compact;
  final Duration animationDuration;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final accent = dark ? const Color(0xFFB4CCBA) : const Color(0xFF42604D);
    final item = Padding(
      padding: EdgeInsets.symmetric(horizontal: compact ? 1 : 2, vertical: 2),
      child: AnimatedContainer(
        duration: animationDuration,
        curve: Curves.easeOutCubic,
        height: 40,
        decoration: BoxDecoration(
          color: selected
              ? (dark ? const Color(0xFF344239) : const Color(0xFFE9F0EA))
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: onTap,
            child: Row(
              mainAxisAlignment: compact
                  ? MainAxisAlignment.center
                  : MainAxisAlignment.start,
              children: [
                if (!compact) const SizedBox(width: 7),
                if (!compact)
                  AnimatedContainer(
                    duration: animationDuration,
                    curve: Curves.easeOutCubic,
                    width: selected ? 3 : 0,
                    height: selected ? 20 : 0,
                    decoration: BoxDecoration(
                      color: accent,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                if (!compact) SizedBox(width: selected ? 7 : 10),
                SizedBox(
                  width: 20,
                  height: 20,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Center(
                        child: AnimatedSwitcher(
                          duration: animationDuration,
                          switchInCurve: Curves.easeOut,
                          switchOutCurve: Curves.easeIn,
                          child: Icon(
                            page.icon,
                            key: ValueKey('${page.name}-$selected'),
                            size: 18,
                            color: selected ? accent : const Color(0xFF737A74),
                          ),
                        ),
                      ),
                      Positioned(
                        right: -2,
                        top: -2,
                        child: AnimatedOpacity(
                          opacity: active ? 1 : 0,
                          duration: animationDuration,
                          child: Tooltip(
                            message: translateText(context, '任务运行中'),
                            child: Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: const Color(0xFF36B76A),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: dark
                                      ? const Color(0xEF202521)
                                      : const Color(0xEFFFFFFF),
                                  width: 1.4,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (!compact) const SizedBox(width: 10),
                if (!compact)
                  Expanded(
                    child: AnimatedDefaultTextStyle(
                      duration: animationDuration,
                      curve: Curves.easeOut,
                      style: TextStyle(
                        fontFamily: 'Microsoft YaHei',
                        fontSize: 12.5,
                        fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                        color: selected ? accent : const Color(0xFF424743),
                      ),
                      child: LocalizedText(
                        page.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                if (!compact) const SizedBox(width: 8),
              ],
            ),
          ),
        ),
      ),
    );
    return compact
        ? Tooltip(message: translateText(context, page.label), child: item)
        : item;
  }

}

class _PageHeader extends StatelessWidget {
  const _PageHeader({required this.title, required this.status});

  final String title;
  final String status;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final compact = MediaQuery.sizeOf(context).width < 1020;
    return Container(
      height: compact ? 58 : 70,
      padding: EdgeInsets.symmetric(horizontal: compact ? 14 : 28),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: dark ? const Color(0xFF3B433D) : const Color(0xFFE8EAE6),
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: AnimatedSwitcher(
              duration: MotionSettings.enabledOf(context)
                  ? const Duration(milliseconds: 240)
                  : Duration.zero,
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween<Offset>(begin: const Offset(0, .04), end: Offset.zero).animate(animation),
                  child: child,
                ),
              ),
              child: LocalizedText(
                title,
                key: ValueKey(title),
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Flexible(
            child: LocalizedText(
              status,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, color: Color(0xFF8A918B)),
            ),
          ),
        ],
      ),
    );
  }
}

class _HomePage extends StatelessWidget {
  const _HomePage({
    super.key,
    required this.onNavigate,
    required this.runtimeStatus,
  });

  final ValueChanged<AppPage> onNavigate;
  final String runtimeStatus;

  @override
  Widget build(BuildContext context) {
    return _PageScroll(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionIntro(
            eyebrow: 'OVERVIEW',
            title: '设备状态一览',
            subtitle: '把常用维护工具和当前系统状态放在一起。',
          ),
          const SizedBox(height: 18),
          const _SystemPerformancePanel(),
          const SizedBox(height: 12),
          const _SystemSummaryCard(),
          const SizedBox(height: 24),
          const _SectionIntro(
            eyebrow: 'QUICK ACCESS',
            title: '常用入口',
            subtitle: '常用功能保持精简，完整工具分类见左侧导航。',
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _HomeCard(
                icon: Icons.folder_open_outlined,
                title: '文件管理',
                subtitle: '浏览、整理和管理文件',
                onTap: () => onNavigate(AppPage.fileManager),
              ),
              _HomeCard(
                icon: Icons.cleaning_services_outlined,
                title: 'C 盘清理',
                subtitle: '扫描临时文件并预览空间',
                onTap: () => onNavigate(AppPage.cleanup),
              ),
              _HomeCard(
                icon: Icons.shield_outlined,
                title: '病毒查杀',
                subtitle: '本地 SHA-256 与 Defender',
                onTap: () => onNavigate(AppPage.security),
              ),
              _HomeCard(
                icon: Icons.memory_outlined,
                title: '驱动管理',
                subtitle: '驱动信息、扫描与 INF 安装',
                onTap: () => onNavigate(AppPage.drivers),
              ),
              _HomeCard(
                icon: Icons.download_outlined,
                title: '下载任务',
                subtitle: '查看和管理 aria2 下载',
                onTap: () => onNavigate(AppPage.downloads),
              ),
              _HomeCard(
                icon: Icons.computer_outlined,
                title: '系统资源',
                subtitle: '查看已配置的系统资源',
                onTap: () => onNavigate(AppPage.system),
              ),
              _HomeCard(
                icon: Icons.dashboard_customize_outlined,
                title: '快捷工具',
                subtitle: '任务管理器、系统设置等',
                onTap: () => onNavigate(AppPage.quickTools),
              ),
              _HomeCard(
                icon: Icons.fingerprint_outlined,
                title: '文件校验',
                subtitle: '计算 SHA-256 等哈希',
                onTap: () => onNavigate(AppPage.fileHash),
              ),
            ],
          ),
          const SizedBox(height: 18),
          _InfoCard(
            child: Row(
              children: [
                const Icon(Icons.cloud_done_outlined, color: Color(0xFF6D8574), size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: LocalizedText(
                    runtimeStatus,
                    style: const TextStyle(fontSize: 12, color: Color(0xFF646B65)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          const _InfoCard(
            child: Row(
              children: [
                _AppMark(),
                SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      LocalizedText(AppConstants.appName, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                      SizedBox(height: 5),
                      LocalizedText('版本 ${AppConstants.version}  ·  ${AppConstants.author}', style: TextStyle(fontSize: 11, color: Color(0xFF858C86))),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SystemPerformancePanel extends StatefulWidget {
  const _SystemPerformancePanel();

  @override
  State<_SystemPerformancePanel> createState() => _SystemPerformancePanelState();
}

class _SystemPerformancePanelState extends State<_SystemPerformancePanel> {
  final SystemMetricsService _service = SystemMetricsService();
  StreamSubscription<SystemMetrics>? _subscription;
  SystemMetrics? _metrics;
  final List<double> _cpuHistory = <double>[];
  final List<double> _memoryHistory = <double>[];
  final List<double> _diskHistory = <double>[];
  String? _error;

  @override
  void initState() {
    super.initState();
    _subscription = _service.stream.listen(
      (sample) {
        if (!mounted) return;
        setState(() {
          _metrics = sample;
          _error = null;
          _appendHistory(_cpuHistory, sample.cpuPercent);
          _appendHistory(_memoryHistory, sample.memoryPercent);
          // This chart represents system-volume occupancy. Disk activity is
          // shown independently as the small detail line below it.
          _appendHistory(_diskHistory, sample.diskUsedPercent);
        });
      },
      onError: (Object error) {
        if (mounted) setState(() => _error = error.toString());
      },
    );
  }

  bool? _samplerActive;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final active = TickerMode.of(context);
    if (_samplerActive == active) return;
    _samplerActive = active;
    if (active) {
      unawaited(_startSampler());
    } else {
      unawaited(_service.stop());
    }
  }

  Future<void> _startSampler() async {
    if (mounted) setState(() => _error = null);
    try {
      await _service.start();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  void _appendHistory(List<double> values, double value) {
    values.add(value.clamp(0, 100).toDouble());
    if (values.length > 48) values.removeAt(0);
  }

  @override
  void dispose() {
    _subscription?.cancel();
    unawaited(_service.close());
    super.dispose();
  }

  String _bytes(int value) {
    if (value >= 1024 * 1024 * 1024) return '${(value / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    if (value >= 1024 * 1024) return '${(value / (1024 * 1024)).toStringAsFixed(0)} MB';
    if (value >= 1024) return '${(value / 1024).toStringAsFixed(0)} KB';
    return '$value B';
  }

  String _rate(int value) => '${_bytes(value)}/s';

  @override
  Widget build(BuildContext context) {
    final metrics = _metrics;
    return _InfoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: LocalizedText('性能', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              ),
              Icon(Icons.monitor_heart_outlined, size: 16, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 6),
              LocalizedText(
                metrics == null ? (_error == null ? '正在读取 Windows 原生性能数据' : '读取失败') : 'Windows API 直读 · 约 1.5 秒更新',
                style: const TextStyle(fontSize: 10, color: Color(0xFF858C86)),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (metrics == null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 18),
              child: Row(
                children: [
                  if (_error == null)
                    const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  else
                    const Icon(Icons.info_outline, size: 17, color: Color(0xFF9A805E)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: LocalizedText(
                      _error ?? '正在读取 CPU、内存与磁盘状态…',
                      style: const TextStyle(fontSize: 11, color: Color(0xFF858C86)),
                    ),
                  ),
                  if (_error != null)
                    TextButton.icon(
                      onPressed: _startSampler,
                      icon: const Icon(Icons.refresh, size: 15),
                      label: const LocalizedText('重试'),
                    ),
                ],
              ),
            )
          else ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _PerformanceMetric(label: 'CPU', value: metrics.cpuPercent, history: _cpuHistory, color: const Color(0xFF6E9279))),
                const SizedBox(width: 14),
                Expanded(child: _PerformanceMetric(label: '内存', value: metrics.memoryPercent, history: _memoryHistory, color: const Color(0xFF8195B1), detail: '${_bytes(metrics.memoryUsedBytes)} / ${_bytes(metrics.memoryTotalBytes)}')),
                const SizedBox(width: 14),
                Expanded(
                  child: _PerformanceMetric(
                    label: 'C 盘占用',
                    value: metrics.diskUsedPercent,
                    history: _diskHistory,
                    color: const Color(0xFFC39A68),
                    detail: metrics.diskActivePercent >= 0
                        ? '磁盘活动 ${metrics.diskActivePercent.toStringAsFixed(0)}%'
                        : '磁盘活动暂不可用',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 10),
            Wrap(
              spacing: 18,
              runSpacing: 8,
              children: [
                _PerformanceFootnote(label: '磁盘读取', value: metrics.diskReadBytesPerSecond < 0 ? '--' : _rate(metrics.diskReadBytesPerSecond)),
                _PerformanceFootnote(label: '磁盘写入', value: metrics.diskWriteBytesPerSecond < 0 ? '--' : _rate(metrics.diskWriteBytesPerSecond)),
                _PerformanceFootnote(label: 'C 盘剩余', value: '${_bytes(metrics.driveFreeBytes)} / ${_bytes(metrics.driveTotalBytes)}'),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _PerformanceMetric extends StatelessWidget {
  const _PerformanceMetric({required this.label, required this.value, required this.history, required this.color, this.detail});
  final String label;
  final double value;
  final List<double> history;
  final Color color;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final motionEnabled = MotionSettings.enabledOf(context) && !reduceMotion;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LocalizedText(label, style: const TextStyle(fontSize: 11, color: Color(0xFF858C86))),
        const SizedBox(height: 5),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            AnimatedSwitcher(
              duration: motionEnabled ? const Duration(milliseconds: 180) : Duration.zero,
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween<Offset>(begin: const Offset(0, .12), end: Offset.zero).animate(animation),
                  child: child,
                ),
              ),
              child: LocalizedText(
                value.toStringAsFixed(0),
                key: ValueKey(value.toStringAsFixed(0)),
                style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w600, height: 1),
              ),
            ),
            const Padding(padding: EdgeInsets.only(left: 3, bottom: 2), child: LocalizedText('%', style: TextStyle(fontSize: 11, color: Color(0xFF858C86)))),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0, end: value.clamp(0, 100) / 100),
            duration: motionEnabled ? const Duration(milliseconds: 260) : Duration.zero,
            curve: Curves.easeOutCubic,
            builder: (context, animatedValue, _) => LinearProgressIndicator(
              value: animatedValue,
              minHeight: 4,
              backgroundColor: color.withValues(alpha: .12),
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(height: 34, width: double.infinity, child: CustomPaint(painter: _SparklinePainter(List<double>.of(history), color))),
        if (detail != null) ...[
          const SizedBox(height: 6),
          LocalizedText(detail!, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10, color: Color(0xFF858C86))),
        ],
      ],
    );
  }
}

class _SparklinePainter extends CustomPainter {
  const _SparklinePainter(this.values, this.color);
  final List<double> values;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final baseline = Paint()..color = color.withValues(alpha: .12)..strokeWidth = 1;
    canvas.drawLine(Offset(0, size.height - 1), Offset(size.width, size.height - 1), baseline);
    if (values.length < 2) return;
    final path = Path();
    for (var i = 0; i < values.length; i++) {
      final x = i / (values.length - 1) * size.width;
      final y = size.height - (values[i].clamp(0, 100) / 100 * (size.height - 3)) - 1;
      if (i == 0) { path.moveTo(x, y); } else { path.lineTo(x, y); }
    }
    canvas.drawPath(path, Paint()..color = color..style = PaintingStyle.stroke..strokeWidth = 1.8..strokeCap = StrokeCap.round..strokeJoin = StrokeJoin.round);
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter oldDelegate) => oldDelegate.values != values || oldDelegate.color != color;
}

class _PerformanceFootnote extends StatelessWidget {
  const _PerformanceFootnote({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      LocalizedText('$label ', style: const TextStyle(fontSize: 10, color: Color(0xFF858C86))),
      LocalizedText(value, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600)),
    ],
  );
}

class _SystemSummaryCard extends StatefulWidget {
  const _SystemSummaryCard();

  @override
  State<_SystemSummaryCard> createState() => _SystemSummaryCardState();
}

class _SystemSummaryCardState extends State<_SystemSummaryCard> {
  final _service = SystemStatusService();
  late Future<Map<String, String>> _overview;

  @override
  void initState() {
    super.initState();
    _overview = _service.getSystemOverview();
  }

  void _refresh() {
    setState(() => _overview = _service.getSystemOverview());
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, String>>(
      future: _overview,
      builder: (context, snapshot) {
        return _InfoCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: LocalizedText(
                      '本机系统信息',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: _refresh,
                    tooltip: translateText(context, '刷新系统信息'),
                    icon: const Icon(Icons.refresh, size: 18),
                  ),
                ],
              ),
              if (snapshot.connectionState == ConnectionState.waiting)
                const LinearProgressIndicator(minHeight: 2)
              else if (snapshot.hasError)
                LocalizedText(
                  '系统信息读取失败：${snapshot.error}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF9A514A),
                  ),
                )
              else
                Wrap(
                  spacing: 26,
                  runSpacing: 12,
                  children: [
                    _SystemFact(
                      label: '设备',
                      value: snapshot.data?['computerName'] ?? '--',
                    ),
                    _SystemFact(
                      label: 'Windows',
                      value:
                          '${snapshot.data?['os'] ?? '--'} '
                          '${snapshot.data?['version'] ?? ''} '
                          '(build ${snapshot.data?['build'] ?? '--'})',
                    ),
                    _SystemFact(
                      label: '处理器',
                      value: snapshot.data?['cpu'] ?? '--',
                    ),
                    _SystemFact(
                      label: '内存',
                      value: '${snapshot.data?['memoryGB'] ?? '--'} GB',
                    ),
                    _SystemFact(
                      label: '系统架构',
                      value: snapshot.data?['architecture'] ?? '--',
                    ),
                    _SystemFact(
                      label: '制造商 / 型号',
                      value: [
                        snapshot.data?['manufacturer'],
                        snapshot.data?['model'],
                      ].where((value) => value != null && value.toString().trim().isNotEmpty).join(' '),
                    ),
                    _SystemFact(
                      label: '主板 / BIOS',
                      value: [snapshot.data?['board'], snapshot.data?['bios']]
                          .where((value) => value != null && value.toString().trim().isNotEmpty)
                          .join(' / '),
                    ),
                    _SystemFact(
                      label: '运行时间',
                      value: '${snapshot.data?['uptimeDays'] ?? '--'} 天 ${snapshot.data?['uptimeHours'] ?? '--'} 小时',
                    ),
                  ],
                ),
            ],
          ),
        );
      },
    );
  }
}

class _SystemFact extends StatelessWidget {
  const _SystemFact({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 250,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LocalizedText(
          label,
          style: const TextStyle(fontSize: 10, color: Color(0xFF858C86)),
        ),
        const SizedBox(height: 3),
        LocalizedText(
          value,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 12),
        ),
      ],
    ),
  );
}

class _AppMark extends StatelessWidget {
  const _AppMark();

  @override
  Widget build(BuildContext context) => Container(
    width: 42,
    height: 42,
    decoration: BoxDecoration(
      color: const Color(0xFFEAF1EB),
      borderRadius: BorderRadius.circular(10),
    ),
    child: const Icon(Icons.spa_outlined, color: Color(0xFF63816D)),
  );
}

class _HomeCard extends StatelessWidget {
  const _HomeCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 226,
      child: _InfoCard(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 20, color: const Color(0xFF66806D)),
              const SizedBox(height: 22),
              LocalizedText(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              LocalizedText(
                subtitle,
                style: const TextStyle(fontSize: 11, color: Color(0xFF858C86)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DownloadsPage extends StatefulWidget {
  const _DownloadsPage({
    super.key,
    required this.service,
    required this.runtimeStatus,
    required this.initialUri,
    required this.onInitialUriConsumed,
    required this.onActivityChanged,
  });

  final Aria2Service service;
  final String runtimeStatus;
  final String? initialUri;
  final ValueChanged<String> onInitialUriConsumed;
  final ValueChanged<bool> onActivityChanged;

  @override
  State<_DownloadsPage> createState() => _DownloadsPageState();
}

class _DownloadsPageState extends State<_DownloadsPage> {
  Timer? _timer;
  List<DownloadTask> _tasks = const [];
  String _engineStatus = '连接 aria2 中…';
  Aria2Service? _refreshingService;
  bool _configurationAttempted = false;

  @override
  void initState() {
    super.initState();
    _engineStatus = widget.runtimeStatus;
    unawaited(_refreshTasks());
    if (widget.initialUri != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final uri = widget.initialUri;
        if (mounted && uri != null) unawaited(_addUri(uri));
      });
    }
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => _refreshTasks());
  }

  @override
  void didUpdateWidget(covariant _DownloadsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.runtimeStatus != widget.runtimeStatus) {
      if (!_engineStatus.startsWith('aria2 已连接')) {
        _engineStatus = widget.runtimeStatus;
      }
      unawaited(_refreshTasks());
    }
    if (oldWidget.service != widget.service) {
      _configurationAttempted = false;
      unawaited(_refreshTasks());
    }
    if (oldWidget.initialUri != widget.initialUri &&
        widget.initialUri != null) {
      unawaited(_addUri(widget.initialUri!));
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _refreshTasks() async {
    final service = widget.service;
    if (identical(_refreshingService, service)) return;
    _refreshingService = service;
    String? configurationError;
    try {
      if (!_configurationAttempted) {
        _configurationAttempted = true;
        try {
          await service.configure();
        } catch (error) {
          configurationError = _shortError(error);
        }
      }
      final tasks = await service.listTasks();
      if (mounted && service == widget.service) {
        setState(() {
          _tasks = tasks;
          _engineStatus = configurationError == null
              ? 'aria2 已连接 · ${tasks.length} 个任务'
              : 'aria2 已连接，但设置同步失败：$configurationError';
        });
        widget.onActivityChanged(
          tasks.any((task) =>
              task.status == 'active' || task.status == 'waiting'),
        );
      }
    } catch (error) {
      if (mounted && service == widget.service) {
        setState(() {
          _engineStatus = widget.runtimeStatus.startsWith('未找到内置引擎')
              ? widget.runtimeStatus
              : 'aria2 未连接：${_shortError(error)}';
        });
        widget.onActivityChanged(false);
      }
    } finally {
      if (identical(_refreshingService, service)) {
        _refreshingService = null;
      }
    }
  }

  Future<void> _addTask() async {
    final input = await showDialog<DownloadTaskInput>(
      context: context,
      builder: (context) => const _DownloadTaskDialog(),
    );
    if (input == null || !mounted) return;
    try {
      if (input.isTorrent && !_isHttpUrl(input.address)) {
        await widget.service.addTorrent(
          input.address,
          userAgent: input.userAgent,
          referer: input.referer,
          cookie: input.cookie,
          headers: input.headers,
        );
      } else if (input.isMetalink) {
        await widget.service.addMetalink(
          input.address,
          userAgent: input.userAgent,
          referer: input.referer,
          cookie: input.cookie,
          headers: input.headers,
        );
      } else {
        await widget.service.addUri(
          input.address,
          userAgent: input.userAgent,
          referer: input.referer,
          cookie: input.cookie,
          headers: input.headers,
        );
      }
      await _refreshTasks();
      _notify('任务已添加');
    } catch (error) {
      _notify('添加失败：${_shortError(error)}');
    }
  }

  Future<void> _addUri(String uri) async {
    widget.onInitialUriConsumed(uri);
    try {
      await widget.service.addUri(uri);
      await _refreshTasks();
      _notify('任务已添加');
    } catch (error) {
      _notify('添加失败：${_shortError(error)}');
    }
  }

  Future<void> _taskAction(
    DownloadTask task,
    Future<void> Function(String) action,
  ) async {
    try {
      await action(task.gid);
      await _refreshTasks();
    } catch (error) {
      _notify('操作失败：${_shortError(error)}');
    }
  }

  void _notify(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: LocalizedText(message),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final active = _tasks.where((task) => task.status == 'active').length;
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(28, 24, 28, 0),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              _SectionIntro(
                eyebrow: 'ARIA2 JSON-RPC',
                title: '下载任务',
                subtitle: _engineStatus,
                trailing: FilledButton.tonalIcon(
                  onPressed: _addTask,
                  icon: const Icon(Icons.add, size: 18),
                  label: const LocalizedText('添加任务'),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  _MetricCard(label: '任务总数', value: '${_tasks.length}'),
                  const SizedBox(width: 12),
                  _MetricCard(label: '正在下载', value: '$active'),
                  const SizedBox(width: 12),
                  const _MetricCard(
                    label: '下载目录',
                    value: '由 aria2 / 设置管理',
                    compact: true,
                  ),
                ],
              ),
              const SizedBox(height: 18),
              if (_tasks.isEmpty)
                _InfoCard(
                  child: _EmptyState(
                    icon: Icons.cloud_download_outlined,
                    title: '还没有下载任务',
                    subtitle: _engineStatus.contains('未连接')
                        ? '请先在设置中配置 aria2 JSON-RPC 服务，再添加 HTTP、磁力或种子任务。'
                        : '添加链接后，任务进度和速度会显示在这里。',
                    action: TextButton.icon(
                      onPressed: _addTask,
                      icon: const Icon(Icons.add),
                      label: const LocalizedText('添加任务'),
                    ),
                  ),
                ),
            ]),
          ),
        ),
        if (_tasks.isNotEmpty)
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(28, 0, 28, 28),
            sliver: SliverList.builder(
              itemCount: _tasks.length,
              itemBuilder: (context, index) {
                final task = _tasks[index];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _DownloadTaskTile(
                    task: task,
                    onPause: () => _taskAction(task, widget.service.pause),
                    onResume: () => _taskAction(task, widget.service.resume),
                    onRemove: () => _taskAction(task, widget.service.remove),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}

class DownloadTaskInput {
  const DownloadTaskInput({
    required this.address,
    required this.isTorrent,
    required this.isMetalink,
    required this.userAgent,
    required this.referer,
    required this.cookie,
    required this.headers,
  });

  final String address;
  final bool isTorrent;
  final bool isMetalink;
  final String userAgent;
  final String referer;
  final String cookie;
  final String headers;
}

class _DownloadTaskDialog extends StatefulWidget {
  const _DownloadTaskDialog();

  @override
  State<_DownloadTaskDialog> createState() => _DownloadTaskDialogState();
}

class _DownloadTaskDialogState extends State<_DownloadTaskDialog> {
  final _address = TextEditingController();
  final _userAgent = TextEditingController();
  final _referer = TextEditingController();
  final _cookie = TextEditingController();
  final _headers = TextEditingController();
  bool _advanced = false;
  String? _error;

  DownloadSourceKind get _sourceKind => classifyDownloadSource(_address.text);
  bool get _isTorrent => _sourceKind == DownloadSourceKind.torrentFile;
  bool get _isMetalink => _sourceKind == DownloadSourceKind.metalinkFile;

  @override
  void dispose() {
    _address.dispose();
    _userAgent.dispose();
    _referer.dispose();
    _cookie.dispose();
    _headers.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const LocalizedText('添加下载任务'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _address,
                autofocus: true,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: translateText(
                    context,
                    _isTorrent
                        ? _isHttpUrl(_address.text)
                              ? '种子文件链接'
                              : '种子文件路径'
                        : _isMetalink
                        ? 'Metalink 文件路径或下载地址'
                        : 'HTTP / HTTPS / 磁力链接',
                  ),
                  hintText: translateText(
                    context,
                    _isTorrent
                        ? _isHttpUrl(_address.text)
                              ? 'https://example.com/file.torrent'
                              : r'C:\Downloads\sample.torrent'
                        : _isMetalink
                        ? r'C:\Downloads\sample.metalink 或 https://…'
                        : 'https://… 或 magnet:?xt=…',
                  ),
                  border: const OutlineInputBorder(),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: LocalizedText(
                    _error!,
                    style: const TextStyle(color: Colors.red, fontSize: 12),
                  ),
                ),
              ],
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => setState(() => _advanced = !_advanced),
                  icon: Icon(_advanced ? Icons.expand_less : Icons.expand_more),
                  label: LocalizedText(_advanced ? '收起登录信息' : '登录信息与请求头'),
                ),
              ),
              if (_advanced) ...[
                _DialogField(controller: _cookie, label: 'Cookie'),
                _DialogField(controller: _userAgent, label: 'User-Agent'),
                _DialogField(controller: _referer, label: 'Referer'),
                _DialogField(
                  controller: _headers,
                  label: '额外 Header（每行一个）',
                  maxLines: 3,
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const LocalizedText('取消'),
        ),
        FilledButton(
          onPressed: () {
            final value = _address.text.trim();
            if (value.isEmpty) {
              setState(() => _error = '请输入链接或本地种子文件路径');
              return;
            }
            Navigator.pop(
              context,
              DownloadTaskInput(
                address: value,
                isTorrent: _isTorrent,
                isMetalink: _isMetalink,
                userAgent: _userAgent.text,
                referer: _referer.text,
                cookie: _cookie.text,
                headers: _headers.text,
              ),
            );
          },
          child: const LocalizedText('开始下载'),
        ),
      ],
    );
  }
}

class _DialogField extends StatelessWidget {
  const _DialogField({
    required this.controller,
    required this.label,
    this.maxLines = 1,
  });

  final TextEditingController controller;
  final String label;
  final int maxLines;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: TextField(
      controller: controller,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: translateText(context, label),
        border: const OutlineInputBorder(),
        isDense: true,
      ),
    ),
  );
}

class _DownloadTaskTile extends StatelessWidget {
  const _DownloadTaskTile({
    required this.task,
    required this.onPause,
    required this.onResume,
    required this.onRemove,
  });

  final DownloadTask task;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final percent = (task.progress * 100).clamp(0, 100).toStringAsFixed(1);
    return _InfoCard(
      child: Row(
        children: [
          const Icon(
            Icons.insert_drive_file_outlined,
            color: Color(0xFF708675),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LocalizedText(
                  task.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: LinearProgressIndicator(
                    value: task.totalLength > 0 ? task.progress : null,
                    minHeight: 5,
                    backgroundColor: const Color(0xFFE9ECE9),
                    color: const Color(0xFF789481),
                  ),
                ),
                const SizedBox(height: 7),
                LocalizedText(
                  '${_taskStatus(context, task.status)}  ·  $percent%  ·  ${_formatBytes(task.downloadSpeed)}/s  ·  ${translateText(context, '剩余')} ${_formatDuration(context, task.remainingSeconds)}',
                  style: const TextStyle(
                    fontSize: 10,
                    color: Color(0xFF818982),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (task.status == 'active')
            IconButton(
              tooltip: '暂停',
              onPressed: onPause,
              icon: const Icon(Icons.pause),
            )
          else if (task.status == 'paused' || task.status == 'waiting')
            IconButton(
              tooltip: '继续',
              onPressed: onResume,
              icon: const Icon(Icons.play_arrow),
            ),
          IconButton(
            tooltip: '删除任务',
            onPressed: onRemove,
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
    );
  }
}

class _SystemPage extends StatefulWidget {
  const _SystemPage({super.key, required this.onSelectResource});

  final ValueChanged<String> onSelectResource;

  @override
  State<_SystemPage> createState() => _SystemPageState();
}

class _SystemPageState extends State<_SystemPage> {
  final _catalogService = CatalogService();
  List<CatalogItem> _items = const [];
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final items = await _catalogService.loadSystem();
      if (mounted) setState(() => _items = items);
    } catch (error) {
      if (mounted) setState(() => _error = '资源清单读取失败：$error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _editCatalog() async {
    final initial = _items.isEmpty
        ? ''
        : const JsonEncoder.withIndent('  ')
              .convert(_items.map((item) => item.toJson()).toList());
    final source = await showDialog<String>(
      context: context,
      builder: (context) =>
          _CatalogEditorDialog(title: '编辑系统资源 JSON', initialValue: initial),
    );
    if (source == null) return;
    try {
      await _catalogService.saveSystem(source);
      final items = await _catalogService.loadSystem();
      if (mounted) {
        setState(() {
          _items = items;
          _error = null;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = '保存清单失败：$error');
    }
  }

  Future<void> _openMicrosoftWindowsDownloads() async {
    try {
      await _launchExternalUrl(
        'https://www.microsoft.com/software-download/windows11',
      );
    } catch (error) {
      if (mounted) {
        setState(() => _error = '无法打开微软官方下载页：${_shortError(error)}');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return _PageScroll(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionIntro(
            eyebrow: 'RESOURCE CATALOG',
            title: '系统资源',
            subtitle: '资源清单可由维护者配置；应用不内置来源不明的系统镜像。',
            trailing: OutlinedButton.icon(
              onPressed: _editCatalog,
              icon: const Icon(Icons.edit_outlined, size: 16),
              label: const LocalizedText('编辑清单'),
            ),
          ),
          const SizedBox(height: 18),
          _InfoCard(
            child: Row(
              children: [
                const Icon(Icons.verified_outlined, color: Color(0xFF708675)),
                const SizedBox(width: 12),
                const Expanded(
                  child: LocalizedText(
                    'Windows 11 官方镜像',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                OutlinedButton(
                  onPressed: _openMicrosoftWindowsDownloads,
                  child: const LocalizedText('打开微软官方下载页'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (_error != null)
            _InfoCard(
              child: LocalizedText(
                _error!,
                style: const TextStyle(color: Color(0xFF9A514A)),
              ),
            )
          else if (_loading)
            const Center(child: CircularProgressIndicator())
          else if (_items.isEmpty)
            const _InfoCard(
              child: _EmptyState(
                icon: Icons.inventory_2_outlined,
                title: '尚未配置资源',
                subtitle: '配置资源时可填写名称、版本、文件大小、校验值与下载地址；选择后可交由 aria2 下载。',
              ),
            )
          else
            ..._items.map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _CatalogItemTile(
                  item: item,
                  actionLabel: '添加到下载',
                  onAction: () => widget.onSelectResource(item.url),
                ),
              ),
            ),
          const SizedBox(height: 14),
          _InfoCard(
            child: LocalizedText(
              '资源接口建议：维护独立 JSON 清单，字段包括 title、version、size、sha256、url。由可信维护者提供链接并验证哈希后再导入。',
              style: TextStyle(
                fontSize: 12,
                height: 1.7,
                color: Theme.of(context).brightness == Brightness.dark
                    ? const Color(0xFFB7C0B8)
                    : const Color(0xFF737B74),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CatalogEditorDialog extends StatefulWidget {
  const _CatalogEditorDialog({required this.title, required this.initialValue});

  final String title;
  final String initialValue;

  @override
  State<_CatalogEditorDialog> createState() => _CatalogEditorDialogState();
}

class _CatalogEditorDialogState extends State<_CatalogEditorDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: LocalizedText(widget.title),
      content: SizedBox(
        width: 660,
        child: SingleChildScrollView(
          child: TextField(
            controller: _controller,
            minLines: 14,
            maxLines: 22,
            decoration: InputDecoration(
              hintText: translateText(
                context,
                '[{"title":"资源名称","version":"版本","size":"大小","sha256":"校验值","url":"https://...","category":"分类","description":"说明"}]',
              ),
              border: const OutlineInputBorder(),
              alignLabelWithHint: true,
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const LocalizedText('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _controller.text),
          child: const LocalizedText('保存清单'),
        ),
      ],
    );
  }
}

class _CatalogItemTile extends StatelessWidget {
  const _CatalogItemTile({
    required this.item,
    required this.actionLabel,
    required this.onAction,
  });

  final CatalogItem item;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final metadata = <String>[
      if (item.category.isNotEmpty) item.category,
      if (item.version.isNotEmpty) '版本 ${item.version}',
      if (item.size.isNotEmpty) '大小 ${item.size}',
    ];
    return _InfoCard(
      child: Row(
        children: [
          const Icon(Icons.inventory_2_outlined, color: Color(0xFF708675)),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LocalizedText(
                  item.title,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (metadata.isNotEmpty) ...[
                  const SizedBox(height: 5),
                  LocalizedText(
                    metadata.join(' · '),
                    style: const TextStyle(
                      fontSize: 10,
                      color: Color(0xFF858C86),
                    ),
                  ),
                ],
                if (item.description.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  LocalizedText(
                    item.description,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF858C86),
                    ),
                  ),
                ],
                if (item.sha256.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  LocalizedText(
                    'SHA-256: ${item.sha256}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 9,
                      color: Color(0xFF858C86),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          OutlinedButton(
            onPressed: onAction,
            child: LocalizedText(actionLabel),
          ),
        ],
      ),
    );
  }
}

class _OfficePage extends StatefulWidget {
  const _OfficePage({
    super.key,
    required this.onDeploymentChanged,
    required this.onActivityChanged,
  });

  final ValueChanged<bool> onDeploymentChanged;
  final ValueChanged<bool> onActivityChanged;

  @override
  State<_OfficePage> createState() => _OfficePageState();
}

class _OfficePageState extends State<_OfficePage> {
  final _statusService = SystemStatusService();
  final _setupPathController = TextEditingController();
  String _status = '尚未检测';
  String _deploymentStatus = '等待配置官方 Office Deployment Tool';
  bool _checking = false;
  bool _verifying = false;
  bool _deploying = false;
  String _version = 'Microsoft 365 Apps';
  String _language = 'zh-CN';
  String _channel = 'Current';
  final Set<String> _components = {'Word', 'Excel', 'PowerPoint', 'Outlook'};

  void _notifyActivity() {
    widget.onActivityChanged(_checking || _verifying || _deploying);
  }

  @override
  void dispose() {
    _setupPathController.dispose();
    super.dispose();
  }

  Future<void> _detect() async {
    setState(() {
      _checking = true;
      _status = '正在读取系统安装信息…';
    });
    _notifyActivity();
    try {
      final status = await _statusService.detectOffice();
      if (mounted) setState(() => _status = status);
    } catch (error) {
      if (mounted) setState(() => _status = '检测失败：$error');
    } finally {
      if (mounted) {
        setState(() => _checking = false);
        _notifyActivity();
      }
    }
  }

  /// Launch a verified Microsoft ODT executable through ShellExecute's RunAs
  /// verb. Calling Process.start directly fails with Win32 error 740 because
  /// Dart does not automatically display a UAC consent prompt.
  Future<int> _runOdtElevated({
    required String executable,
    required List<String> arguments,
    required String workingDirectory,
  }) async {
    final payload = base64Encode(
      utf8.encode(jsonEncode({
        'executable': executable,
        'arguments': arguments,
        'workingDirectory': workingDirectory,
      })),
    );
    final script = r'''
$ErrorActionPreference = 'Stop'
try {
  $data = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('PAYLOAD_PLACEHOLDER')) | ConvertFrom-Json
  function ConvertTo-WindowsArgument([string]$value) {
    if ($value.Length -eq 0) { return '""' }
    if ($value -notmatch '[\s"]') { return $value }
    $builder = New-Object System.Text.StringBuilder
    [void]$builder.Append('"')
    $slashes = 0
    foreach ($character in $value.ToCharArray()) {
      if ($character -eq [char]92) { $slashes++; continue }
      if ($character -eq [char]34) {
        [void]$builder.Append(('\' * (2 * $slashes + 1)))
        [void]$builder.Append('"')
        $slashes = 0
        continue
      }
      if ($slashes -gt 0) { [void]$builder.Append(('\' * $slashes)); $slashes = 0 }
      [void]$builder.Append($character)
    }
    if ($slashes -gt 0) { [void]$builder.Append(('\' * (2 * $slashes))) }
    [void]$builder.Append('"')
    return $builder.ToString()
  }
  $argumentLine = (@($data.arguments) | ForEach-Object { ConvertTo-WindowsArgument ([string]$_) }) -join ' '
  $parameters = @{
    FilePath = [string]$data.executable
    WorkingDirectory = [string]$data.workingDirectory
    Verb = 'RunAs'
    Wait = $true
    PassThru = $true
    ErrorAction = 'Stop'
  }
  if (-not [string]::IsNullOrWhiteSpace($argumentLine)) { $parameters.ArgumentList = $argumentLine }
  $child = Start-Process @parameters
  [Console]::Out.WriteLine(('ODT_CHILD_EXIT=' + [int]$child.ExitCode))
  exit 0
} catch {
  [Console]::Error.WriteLine($_.Exception.Message)
  $nativeCode = 0
  try { $nativeCode = [int]$_.Exception.NativeErrorCode } catch { }
  if ($nativeCode -eq 1223) { exit 1223 }
  exit 1
}
''';
    final command = script.replaceFirst('PAYLOAD_PLACEHOLDER', payload);
    final encoded = base64Encode(
      command.codeUnits.expand((unit) => [unit & 0xff, unit >> 8]).toList(),
    );
    final result = await Process.run(
      'powershell.exe',
      [
        '-NoLogo',
        '-NoProfile',
        '-NonInteractive',
        '-ExecutionPolicy',
        'Bypass',
        '-EncodedCommand',
        encoded,
      ],
      runInShell: false,
    );
    if (result.exitCode == 1223) {
      throw ProcessException(
        'powershell.exe',
        const ['Start-Process', '-Verb', 'RunAs'],
        '用户取消了 Windows UAC 管理员授权',
        result.exitCode,
      );
    }
    if (result.exitCode != 0) {
      final details = result.stderr.toString().trim();
      throw ProcessException(
        executable,
        arguments,
        details.isEmpty ? '管理员程序启动失败（退出码 ${result.exitCode}）' : details,
        result.exitCode,
      );
    }
    final childExit = RegExp(r'ODT_CHILD_EXIT=(-?\d+)')
        .firstMatch(result.stdout.toString());
    if (childExit == null) {
      throw ProcessException(
        executable,
        arguments,
        '管理员启动器未返回 ODT 退出码：${result.stderr.toString().trim()}',
      );
    }
    return int.parse(childExit.group(1)!);
  }

  Future<void> _openOdtDownloadPage() async {
    try {
      await _launchExternalUrl(
        'https://www.microsoft.com/download/details.aspx?id=49117',
      );
    } catch (error) {
      if (mounted) {
        setState(
          () => _deploymentStatus = '无法打开微软 ODT 下载页：${_shortError(error)}',
        );
      }
    }
  }

  Future<void> _selectOdtInstaller() async {
    final selected = await openFile(
      confirmButtonText: '选择官方 ODT 安装包',
      acceptedTypeGroups: const [
        XTypeGroup(label: 'Windows executable', extensions: ['exe']),
      ],
    );
    if (selected == null || !mounted) return;
    final installer = File(selected.path);
    setState(() {
      _verifying = true;
      _deploymentStatus = '正在验证微软 ODT 安装包签名…';
    });
    _notifyActivity();
    try {
      final signer = await _statusService.verifyMicrosoftSignedExecutable(
        installer.absolute.path,
      );
      if (!mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const LocalizedText('解压官方 ODT'),
          content: LocalizedText(
            '已验证发布者：$signer。接下来会请求 Windows UAC 管理员授权并启动微软官方 ODT 自解压程序，请在它的窗口中接受许可并选择解压目录。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const LocalizedText('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const LocalizedText('启动解压程序'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      widget.onDeploymentChanged(true);
      setState(() => _deploymentStatus = '正在运行 ODT 解压程序…');
      final exitCode = await _runOdtElevated(
        executable: installer.absolute.path,
        arguments: const [],
        workingDirectory: installer.parent.path,
      );
      if (mounted) {
        setState(
          () => _deploymentStatus = exitCode == 0
              ? 'ODT 解压程序已退出。请选择解压目录中的 setup.exe。'
              : 'ODT 解压程序退出码：$exitCode',
        );
      }
    } on ProcessException catch (error) {
      if (mounted) {
        setState(() => _deploymentStatus = '无法启动 ODT：${error.message}');
      }
    } on FileSystemException catch (error) {
      if (mounted) {
        setState(() => _deploymentStatus = '无法读取 ODT：${error.message}');
      }
    } on FormatException catch (error) {
      if (mounted) setState(() => _deploymentStatus = '拒绝运行：${error.message}');
    } on PowerShellUnavailableException catch (error) {
      if (mounted) setState(() => _deploymentStatus = error.toString());
    } finally {
      widget.onDeploymentChanged(false);
      if (mounted) {
        setState(() => _verifying = false);
        _notifyActivity();
      }
    }
  }

  Future<void> _selectSetupFile() async {
    final selected = await openFile(
      confirmButtonText: '选择 ODT setup.exe',
      acceptedTypeGroups: const [
        XTypeGroup(label: 'Windows executable', extensions: ['exe']),
      ],
    );
    if (selected != null && mounted) {
      _setupPathController.text = selected.path;
    }
  }

  String _buildDeploymentXml() {
    const productIds = {
      'Microsoft 365 Apps': 'O365ProPlusRetail',
      'Office LTSC 2024': 'ProPlus2024Volume',
      'Office LTSC 2021': 'ProPlus2021Volume',
    };
    const appIds = {
      'Word': 'Word',
      'Excel': 'Excel',
      'PowerPoint': 'PowerPoint',
      'Outlook': 'Outlook',
      'OneNote': 'OneNote',
    };
    final exclusions = appIds.entries
        .where((entry) => !_components.contains(entry.key))
        .map((entry) => '    <ExcludeApp ID="${entry.value}" />')
        .join('\n');
    final productId = productIds[_version]!;
    return '''<Configuration>
  <Add OfficeClientEdition="64" Channel="$_channel">
    <Product ID="$productId">
      <Language ID="$_language" />
$exclusions
    </Product>
  </Add>
  <Display Level="Full" AcceptEULA="TRUE" />
  <Updates Enabled="TRUE" />
</Configuration>
''';
  }

  Future<void> _deployOffice() async {
    final path = _setupPathController.text.trim();
    final setup = File(path);
    final exists = path.isNotEmpty && await setup.exists();
    if (!mounted) return;
    if (!exists || setup.uri.pathSegments.last.toLowerCase() != 'setup.exe') {
      setState(
        () => _deploymentStatus = '请选择微软官方 Office Deployment Tool 中的 setup.exe',
      );
      return;
    }

    setState(() {
      _verifying = true;
      _deploymentStatus = '正在验证微软数字签名…';
    });
    _notifyActivity();
    late final String signer;
    try {
      signer = await _statusService.verifyMicrosoftSignedExecutable(
        setup.absolute.path,
      );
    } on PowerShellUnavailableException catch (error) {
      if (mounted) setState(() => _deploymentStatus = error.toString());
      return;
    } on ProcessException catch (error) {
      if (mounted) {
        setState(() => _deploymentStatus = '无法验证 ODT 签名：${error.message}');
      }
      return;
    } on FormatException catch (error) {
      if (mounted) {
        setState(() => _deploymentStatus = '拒绝运行：${error.message}');
      }
      return;
    } on UnsupportedError catch (error) {
      if (mounted) {
        setState(() => _deploymentStatus = error.message ?? '$error');
      }
      return;
    } finally {
      if (mounted) {
        setState(() => _verifying = false);
        _notifyActivity();
      }
    }
    if (!mounted) return;
    setState(() => _deploymentStatus = '已验证微软签名，等待确认');

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const LocalizedText('确认部署'),
        content: LocalizedText(
          '已验证发布者：$signer。将请求 Windows UAC 管理员授权，通过 $path 执行 Office 部署；请确认你拥有所选版本的合法许可证。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const LocalizedText('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const LocalizedText('确认并运行'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    Directory? configDirectory;
    widget.onDeploymentChanged(true);
    setState(() {
      _deploying = true;
      _deploymentStatus = '正在准备 ODT 部署配置…';
    });
    _notifyActivity();
    try {
      configDirectory = await Directory.systemTemp.createTemp(
        'moepurekit-office-',
      );
      final configFile = File(
        '${configDirectory.path}${Platform.pathSeparator}configuration.xml',
      );
      await configFile.writeAsString(_buildDeploymentXml(), flush: true);
      if (mounted) setState(() => _deploymentStatus = '正在运行 ODT…');
      final exitCode = await _runOdtElevated(
        executable: setup.absolute.path,
        arguments: ['/configure', configFile.path],
        workingDirectory: setup.parent.path,
      );
      if (mounted) {
        setState(() {
          _deploymentStatus = exitCode == 0
              ? 'ODT 已完成（退出码 0）。详细安装结果请查看 Office 安装日志。'
              : 'ODT 退出码 $exitCode';
        });
      }
    } on ProcessException catch (error) {
      if (mounted) {
        setState(() => _deploymentStatus = '无法启动 ODT：${error.message}');
      }
    } on FileSystemException catch (error) {
      if (mounted) {
        setState(() => _deploymentStatus = '无法写入部署配置：${error.message}');
      }
    } finally {
      if (configDirectory != null && await configDirectory.exists()) {
        await configDirectory.delete(recursive: true);
      }
      widget.onDeploymentChanged(false);
      if (mounted) {
        setState(() => _deploying = false);
        _notifyActivity();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return _PageScroll(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionIntro(
            eyebrow: 'OFFICE DEPLOYMENT',
            title: 'Office 部署',
            subtitle: '下载微软官方 ODT，自行解压后选择 setup.exe；根据授权选择版本、语言和组件。',
          ),
          const SizedBox(height: 18),
          _InfoCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const LocalizedText(
                  '安装状态检测',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                LocalizedText(
                  _status,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF727A73),
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _checking ? null : _detect,
                      icon: _checking
                          ? const SizedBox(
                              width: 15,
                              height: 15,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.search),
                      label: const LocalizedText('检测已安装 Office'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _InfoCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const LocalizedText(
                  '部署配置',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                const LocalizedText(
                  '1. 从微软下载并运行 ODT 自解压程序。  2. 选择解压目录中的 setup.exe。  3. 生成官方 configuration.xml 并运行部署。',
                  style: TextStyle(fontSize: 11, height: 1.6),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _openOdtDownloadPage,
                      icon: const Icon(Icons.open_in_new),
                      label: const LocalizedText('微软官方 ODT 下载页'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _verifying || _deploying
                          ? null
                          : _selectOdtInstaller,
                      icon: const Icon(Icons.folder_open_outlined),
                      label: const LocalizedText('选择并运行 ODT 解压包'),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 16,
                  runSpacing: 8,
                  children: [
                    _DropdownField<String>(
                      label: '版本',
                      value: _version,
                      values: const [
                        'Microsoft 365 Apps',
                        'Office LTSC 2024',
                        'Office LTSC 2021',
                      ],
                      onChanged: (value) => setState(() => _version = value),
                    ),
                    _DropdownField<String>(
                      label: '语言',
                      value: _language,
                      values: const ['zh-CN', 'en-US', 'ja-JP'],
                      onChanged: (value) => setState(() => _language = value),
                    ),
                    _DropdownField<String>(
                      label: '更新通道',
                      value: _channel,
                      values: const [
                        'Current',
                        'MonthlyEnterprise',
                        'SemiAnnual',
                      ],
                      onChanged: (value) => setState(() => _channel = value),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                const LocalizedText(
                  '安装组件',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children:
                      ['Word', 'Excel', 'PowerPoint', 'Outlook', 'OneNote']
                          .map(
                            (component) => FilterChip(
                              label: LocalizedText(component),
                              selected: _components.contains(component),
                              onSelected: (selected) {
                                setState(() {
                                  if (selected) {
                                    _components.add(component);
                                  } else {
                                    _components.remove(component);
                                  }
                                });
                              },
                            ),
                          )
                          .toList(),
                ),
                const SizedBox(height: 14),
                _SettingsField(
                  label: '解压后的 ODT setup.exe 路径',
                  controller: _setupPathController,
                  hint: r'C:\OfficeDeploymentTool\setup.exe',
                  onTrailing: _selectSetupFile,
                ),
                LocalizedText(
                  _deploymentStatus,
                  style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 10),
                FilledButton.icon(
                  onPressed: _deploying || _verifying ? null : _deployOffice,
                  icon: _deploying || _verifying
                      ? const SizedBox(
                          width: 15,
                          height: 15,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.install_desktop_outlined),
                  label: LocalizedText(
                    _verifying
                        ? '验证签名中'
                        : _deploying
                        ? '部署进行中'
                        : '验证签名、生成配置并运行 ODT',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SoftwarePage extends StatefulWidget {
  const _SoftwarePage({super.key, required this.onSelectResource});

  final ValueChanged<String> onSelectResource;

  @override
  State<_SoftwarePage> createState() => _SoftwarePageState();
}

class _SoftwarePageState extends State<_SoftwarePage> {
  final _catalogService = CatalogService();
  final _search = TextEditingController();
  String _category = '全部';
  List<CatalogItem> _items = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final items = await _catalogService.loadSoftware();
      if (mounted) setState(() => _items = items);
    } catch (error) {
      if (mounted) setState(() => _error = '软件清单读取失败：$error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _editCatalog() async {
    final initial = _items.isEmpty
        ? ''
        : const JsonEncoder.withIndent('  ')
              .convert(_items.map((item) => item.toJson()).toList());
    final source = await showDialog<String>(
      context: context,
      builder: (context) =>
          _CatalogEditorDialog(title: '编辑软件清单 JSON', initialValue: initial),
    );
    if (source == null) return;
    try {
      await _catalogService.saveSoftware(source);
      final items = await _catalogService.loadSoftware();
      if (mounted) {
        setState(() {
          _items = items;
          _error = null;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = '保存清单失败：$error');
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final categories = <String>{
      '全部',
      ..._items
          .map((item) => item.category)
          .where((category) => category.isNotEmpty),
    }.toList();
    final query = _search.text.trim().toLowerCase();
    final filteredItems = _items.where((item) {
      final categoryMatches = _category == '全部' || item.category == _category;
      final searchMatches =
          query.isEmpty ||
          '${item.title} ${item.category} ${item.description} ${item.tags.join(' ')}'
              .toLowerCase()
              .contains(query);
      return categoryMatches && searchMatches;
    }).toList();
    return _PageScroll(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionIntro(
            eyebrow: 'SOFTWARE CATALOG',
            title: '实用软件',
            subtitle: '按分类整理可信软件资源，清单与下载地址应由用户或维护者配置。',
            trailing: OutlinedButton.icon(
              onPressed: _editCatalog,
              icon: const Icon(Icons.edit_outlined, size: 16),
              label: const LocalizedText('编辑清单'),
            ),
          ),
          const SizedBox(height: 18),
          TextField(
            controller: _search,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: translateText(context, '搜索软件名称'),
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            children: categories
                .map(
                  (item) => ChoiceChip(
                    label: LocalizedText(item),
                    selected: _category == item,
                    onSelected: (_) => setState(() => _category = item),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 16),
          if (_error != null)
            _InfoCard(
              child: LocalizedText(
                _error!,
                style: const TextStyle(color: Color(0xFF9A514A)),
              ),
            )
          else if (_loading)
            const Center(child: CircularProgressIndicator())
          else if (filteredItems.isEmpty)
            const _InfoCard(
              child: _EmptyState(
                icon: Icons.widgets_outlined,
                title: '未找到已配置的软件',
                subtitle: '软件数据源为空。配置后可按分类和关键词筛选，并在核对发布者与来源后跳转下载。',
              ),
            )
          else
            ...filteredItems.map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _CatalogItemTile(
                  item: item,
                  actionLabel: '添加到下载',
                  onAction: () => widget.onSelectResource(item.url),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _QuickToolsPage extends StatelessWidget {
  const _QuickToolsPage({super.key});

  static const _shortcuts = <(String, IconData, String, List<String>)>[
    ('控制面板', Icons.tune, 'control.exe', []),
    ('任务管理器', Icons.monitor_heart_outlined, 'taskmgr.exe', []),
    ('设备管理器', Icons.devices_outlined, 'mmc.exe', ['devmgmt.msc']),
    ('磁盘管理', Icons.storage, 'mmc.exe', ['diskmgmt.msc']),
    ('程序和功能', Icons.apps_outlined, 'control.exe', ['appwiz.cpl']),
    (
      'Windows 更新',
      Icons.system_update_alt,
      'explorer.exe',
      ['ms-settings:windowsupdate'],
    ),
    (
      '网络设置',
      Icons.settings_ethernet,
      'explorer.exe',
      ['ms-settings:network-status'],
    ),
    ('声音设置', Icons.volume_up_outlined, 'control.exe', ['mmsys.cpl']),
    ('服务管理', Icons.settings_suggest_outlined, 'mmc.exe', ['services.msc']),
    (
      '启动应用',
      Icons.rocket_launch_outlined,
      'explorer.exe',
      ['ms-settings:startupapps'],
    ),
  ];

  Future<void> _launch(
    BuildContext context,
    String executable,
    List<String> args,
  ) async {
    final isDeviceManager = executable.toLowerCase() == 'mmc.exe' && args.any((arg) => arg.toLowerCase() == 'devmgmt.msc');
    if (isDeviceManager) {
      final approved = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const LocalizedText('需要管理员权限'),
          content: const LocalizedText('设备管理器将以管理员身份启动，以便执行驱动和设备更改。Windows 将显示 UAC 确认窗口。'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const LocalizedText('取消')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const LocalizedText('继续并请求权限')),
          ],
        ),
      );
      if (approved != true || !context.mounted) return;
      try {
        await _startElevated(executable, args);
      } catch (error) {
        if (context.mounted) _showLaunchError(context, '$error');
      }
      return;
    }
    try {
      await Process.start(executable, args, runInShell: false);
    } on ProcessException catch (error) {
      if (!context.mounted) return;
      if (!_requiresElevation(error)) {
        _showLaunchError(context, error.message);
        return;
      }

      final approved = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const LocalizedText('需要管理员权限'),
          content: const LocalizedText(
            '此 Windows 系统工具要求提升权限。是否继续并响应 Windows 用户账户控制（UAC）提示？',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const LocalizedText('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const LocalizedText('继续并请求权限'),
            ),
          ],
        ),
      );
      if (approved != true || !context.mounted) return;

      try {
        await _startElevated(executable, args);
      } catch (elevatedError) {
        if (context.mounted) _showLaunchError(context, '$elevatedError');
      }
    }
  }

  bool _requiresElevation(ProcessException error) {
    final message = error.message.toLowerCase();
    return error.errorCode == 740 ||
        message.contains('requires elevation') ||
        message.contains('operation requires elevation');
  }

  Future<void> _startElevated(String executable, List<String> args) async {
    final payload = base64Encode(
      utf8.encode(jsonEncode({'executable': executable, 'arguments': args})),
    );
    final script =
        r"$data=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('" +
        payload +
        r"')) | ConvertFrom-Json; try { Start-Process -FilePath $data.executable -ArgumentList $data.arguments -Verb RunAs -ErrorAction Stop | Out-Null } catch { [Console]::Error.WriteLine($_.Exception.Message); exit 1 }";
    final command = Uint8List(script.length * 2);
    for (var index = 0; index < script.length; index++) {
      final codeUnit = script.codeUnitAt(index);
      command[index * 2] = codeUnit & 0xFF;
      command[index * 2 + 1] = codeUnit >> 8;
    }
    final result = await Process.run('powershell.exe', [
      '-NoProfile',
      '-NonInteractive',
      '-EncodedCommand',
      base64Encode(command),
    ], runInShell: false);
    if (result.exitCode != 0) {
      final error = result.stderr.toString().trim();
      throw ProcessException(
        'powershell.exe',
        const ['-Verb', 'RunAs'],
        error.isEmpty ? 'UAC 已取消或系统工具启动失败' : error,
        result.exitCode,
      );
    }
  }

  void _showLaunchError(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: LocalizedText('无法打开系统工具：$message')));
  }

  @override
  Widget build(BuildContext context) => _PageScroll(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionIntro(
          eyebrow: 'QUICK TOOLS',
          title: '快捷工具',
          subtitle: '需要管理员权限的工具会先征求同意，再显示 Windows UAC 确认。',
        ),
        const SizedBox(height: 18),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = (constraints.maxWidth / 220).floor().clamp(1, 4);
            return GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                mainAxisExtent: 92,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
              ),
              itemCount: _shortcuts.length,
              itemBuilder: (context, index) {
                final shortcut = _shortcuts[index];
                return _InfoCard(
                  onTap: () => _launch(context, shortcut.$3, shortcut.$4),
                  child: Row(
                    children: [
                      Icon(shortcut.$2, color: const Color(0xFF66806D)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: LocalizedText(
                          shortcut.$1,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const Icon(Icons.open_in_new, size: 15),
                    ],
                  ),
                );
              },
            );
          },
        ),
      ],
    ),
  );
}

class _FileHashPage extends StatefulWidget {
  const _FileHashPage({
    super.key,
    required this.onActivityChanged,
  });

  final ValueChanged<bool> onActivityChanged;

  @override
  State<_FileHashPage> createState() => _FileHashPageState();
}

class _FileHashPageState extends State<_FileHashPage> {
  static const _algorithms = <String>[
    'SHA-256',
    'SHA-512',
    'SHA-384',
    'SHA-1',
    'MD5',
  ];

  final _expectedHashController = TextEditingController();
  String? _path;
  String? _fileName;
  String? _digest;
  String? _error;
  String _algorithm = 'SHA-256';
  int _processed = 0;
  int _total = 0;
  DateTime? _modified;
  Duration? _elapsed;
  bool _calculating = false;
  DateTime _lastProgressUiUpdate = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void dispose() {
    _expectedHashController.dispose();
    super.dispose();
  }

  Future<void> _selectFile() async {
    final selected = await openFile(confirmButtonText: '选择文件');
    if (selected == null || !mounted) return;
    setState(() {
      _path = selected.path;
      _fileName = selected.name;
      _digest = null;
      _error = null;
      _processed = 0;
      _total = 0;
      _modified = null;
      _elapsed = null;
      _expectedHashController.clear();
    });
    await _calculate();
  }

  Future<void> _calculate() async {
    final path = _path;
    if (path == null || _calculating) return;
    setState(() {
      _calculating = true;
      _digest = null;
      _error = null;
      _processed = 0;
      _total = 0;
      _elapsed = null;
    });
    widget.onActivityChanged(true);
    try {
      final result = await computeFileHash(
        path,
        algorithm: _algorithm,
        onProgress: (processed, total) {
          if (!mounted) return;
          // Limit rebuilds for very large files while keeping the progress bar live.
          final now = DateTime.now();
          if (processed == total ||
              processed - _processed >= 16 * 1024 * 1024 ||
              now.difference(_lastProgressUiUpdate).inMilliseconds >= 400) {
            _lastProgressUiUpdate = now;
            setState(() {
              _processed = processed;
              _total = total;
            });
          }
        },
      );
      if (mounted) {
        setState(() {
          _digest = result.digest;
          _processed = result.bytesProcessed;
          _total = result.bytesProcessed;
          _modified = result.modified;
          _elapsed = result.elapsed;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = '文件哈希计算失败：${_shortError(error)}');
      }
    } finally {
      if (mounted) {
        setState(() => _calculating = false);
        widget.onActivityChanged(false);
      }
    }
  }

  Future<void> _copyHash() async {
    final digest = _digest;
    if (digest == null) return;
    await Clipboard.setData(ClipboardData(text: digest));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: LocalizedText('${_algorithm} 已复制')),
      );
    }
  }

  String _formatModified(DateTime value) {
    final local = value.toLocal();
    String two(int number) => number.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}';
  }

  String get _normalizedExpected => _expectedHashController.text
      .replaceAll(RegExp(r'\s+'), '')
      .toLowerCase();

  @override
  Widget build(BuildContext context) {
    final progress = _total <= 0
        ? (_digest == null ? 0.0 : 1.0)
        : (_processed / _total).clamp(0.0, 1.0).toDouble();
    final expected = _normalizedExpected;
    final comparison = _digest != null && expected.isNotEmpty
        ? expected == _digest!.toLowerCase()
        : null;

    return _PageScroll(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionIntro(
            eyebrow: 'FILE INTEGRITY',
            title: '文件校验',
            subtitle: '支持多种常见哈希算法，流式读取文件并显示实时进度。',
          ),
          const SizedBox(height: 18),
          _InfoCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.insert_drive_file_outlined,
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                      ),
                    ),
                    const SizedBox(width: 13),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          LocalizedText(
                            '选择要校验的文件',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                          SizedBox(height: 3),
                          LocalizedText(
                            '文件只在本机读取，不会上传。',
                            style: TextStyle(
                              color: Color(0xFF858C86),
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: _calculating ? null : _selectFile,
                      icon: const Icon(Icons.folder_open_outlined, size: 17),
                      label: const LocalizedText('选择文件'),
                    ),
                  ],
                ),
                if (_path != null) ...[
                  const SizedBox(height: 16),
                  const Divider(height: 1),
                  const SizedBox(height: 12),
                  LocalizedText(
                    _fileName ?? '已选择文件',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  SelectableText(
                    _path!,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF858C86),
                    ),
                  ),
                  const SizedBox(height: 9),
                  Wrap(
                    spacing: 16,
                    runSpacing: 6,
                    children: [
                      if (_total > 0 || _digest != null)
                        _HashMeta(
                          icon: Icons.storage,
                          label: _formatBytes(_total),
                        ),
                      if (_modified != null)
                        _HashMeta(
                          icon: Icons.schedule_outlined,
                          label: _formatModified(_modified!),
                        ),
                      if (_elapsed != null)
                        _HashMeta(
                          icon: Icons.speed,
                          label: '${_elapsed!.inMilliseconds} ms',
                        ),
                    ],
                  ),
                ] else ...[
                  const SizedBox(height: 13),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    decoration: BoxDecoration(
                      color: Theme.of(context).brightness == Brightness.dark
                          ? const Color(0x332F3832)
                          : const Color(0xFFF7F9F6),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: Theme.of(context).dividerColor,
                      ),
                    ),
                    child: const Column(
                      children: [
                        Icon(
                          Icons.file_upload_outlined,
                          size: 25,
                          color: Color(0xFF87958A),
                        ),
                        SizedBox(height: 7),
                        LocalizedText(
                          '尚未选择文件',
                          style: TextStyle(fontWeight: FontWeight.w500),
                        ),
                        SizedBox(height: 3),
                        LocalizedText(
                          '点击右上方按钮浏览本地文件',
                          style: TextStyle(
                            fontSize: 11,
                            color: Color(0xFF858C86),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          _InfoCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const LocalizedText(
                  '哈希算法',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 9),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: _algorithm,
                        decoration: const InputDecoration(
                          isDense: true,
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 12,
                          ),
                        ),
                        items: _algorithms
                            .map(
                              (item) => DropdownMenuItem(
                                value: item,
                                child: LocalizedText(item),
                              ),
                            )
                            .toList(),
                        onChanged: _calculating
                            ? null
                            : (value) {
                                if (value == null) return;
                                setState(() => _algorithm = value);
                                if (_path != null) unawaited(_calculate());
                              },
                      ),
                    ),
                    const SizedBox(width: 10),
                    FilledButton.icon(
                      onPressed: _path == null || _calculating
                          ? null
                          : _calculate,
                      icon: _calculating
                          ? const SizedBox(
                              width: 15,
                              height: 15,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                              ),
                            )
                          : const Icon(Icons.play_arrow_rounded, size: 18),
                      label: const LocalizedText('重新计算'),
                    ),
                  ],
                ),
                if (_calculating) ...[
                  const SizedBox(height: 15),
                  LinearProgressIndicator(value: _total > 0 ? progress : null),
                  const SizedBox(height: 7),
                  Row(
                    children: [
                      const LocalizedText(
                        '正在计算…',
                        style: TextStyle(fontSize: 11),
                      ),
                      const Spacer(),
                      LocalizedText(
                        _total > 0
                            ? '${(progress * 100).toStringAsFixed(1)}%  ·  ${_formatBytes(_processed)} / ${_formatBytes(_total)}'
                            : _formatBytes(_processed),
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF858C86),
                        ),
                      ),
                    ],
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  LocalizedText(
                    _error!,
                    style: const TextStyle(color: Color(0xFFB45D55)),
                  ),
                ],
              ],
            ),
          ),
          if (_digest != null) ...[
            const SizedBox(height: 12),
            _InfoCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: LocalizedText(
                          '计算结果',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: Theme.of(context).brightness == Brightness.dark
                              ? const Color(0xFF334239)
                              : const Color(0xFFEAF1EB),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: LocalizedText(
                          _algorithm,
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Theme.of(context).brightness == Brightness.dark
                          ? const Color(0xFF171B18)
                          : const Color(0xFFF5F7F4),
                      borderRadius: BorderRadius.circular(9),
                      border: Border.all(color: Theme.of(context).dividerColor),
                    ),
                    child: SelectableText(
                      _digest!,
                      style: const TextStyle(
                        fontFamily: 'Consolas',
                        fontSize: 13,
                        height: 1.5,
                        letterSpacing: 0.35,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      const Expanded(
                        child: LocalizedText(
                          '可选择并复制完整校验值',
                          style: TextStyle(
                            color: Color(0xFF858C86),
                            fontSize: 11,
                          ),
                        ),
                      ),
                      FilledButton.tonalIcon(
                        onPressed: _copyHash,
                        icon: const Icon(Icons.copy_outlined, size: 16),
                        label: const LocalizedText('复制哈希'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          _InfoCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const LocalizedText(
                  '对比已有校验值',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 5),
                const LocalizedText(
                  '粘贴发布者提供的哈希，自动比较当前计算结果。',
                  style: TextStyle(
                    fontSize: 11,
                    color: Color(0xFF858C86),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _expectedHashController,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: '粘贴 MD5 / SHA 哈希值',
                    isDense: true,
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      tooltip: '清空',
                      onPressed: () {
                        _expectedHashController.clear();
                        setState(() {});
                      },
                      icon: const Icon(Icons.clear),
                    ),
                  ),
                ),
                if (comparison != null) ...[
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Icon(
                        comparison ? Icons.verified_outlined : Icons.error_outline,
                        color: comparison
                            ? const Color(0xFF548B65)
                            : const Color(0xFFB45D55),
                      ),
                      const SizedBox(width: 8),
                      LocalizedText(
                        comparison ? '校验值匹配' : '校验值不匹配',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: comparison
                              ? const Color(0xFF548B65)
                              : const Color(0xFFB45D55),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 9),
                const LocalizedText(
                  '提示：MD5 和 SHA-1 仅用于兼容性核对；安全完整性校验建议优先使用 SHA-256 或 SHA-512。',
                  style: TextStyle(
                    color: Color(0xFF858C86),
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HashMeta extends StatelessWidget {
  const _HashMeta({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 13, color: const Color(0xFF879189)),
      const SizedBox(width: 5),
      LocalizedText(
        label,
        style: const TextStyle(fontSize: 10, color: Color(0xFF858C86)),
      ),
    ],
  );
}

class _TextToolsPage extends StatefulWidget {
  const _TextToolsPage({super.key});

  @override
  State<_TextToolsPage> createState() => _TextToolsPageState();
}

class _TextToolsPageState extends State<_TextToolsPage> {
  final _controller = TextEditingController();
  Timer? _statsTimer;
  int _characters = 0;
  int _lines = 0;
  int _words = 0;
  int _utf8Bytes = 0;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_scheduleStatsUpdate);
  }

  void _scheduleStatsUpdate() {
    _statsTimer?.cancel();
    // Computing Unicode/word/UTF-8 statistics on every keystroke can be costly
    // for large pasted text. Update once the user pauses typing.
    _statsTimer = Timer(const Duration(milliseconds: 180), () {
      if (!mounted) return;
      final value = _controller.text;
      setState(() {
        _characters = value.runes.length;
        _lines = value.isEmpty ? 0 : '\n'.allMatches(value).length + 1;
        _words = value.trim().isEmpty
            ? 0
            : RegExp(r'\S+').allMatches(value).length;
        _utf8Bytes = utf8.encode(value).length;
      });
    });
  }

  @override
  void dispose() {
    _statsTimer?.cancel();
    _controller.removeListener(_scheduleStatsUpdate);
    _controller.dispose();
    super.dispose();
  }

  void _apply(String Function(String value) transform) {
    final value = transform(_controller.text);
    setState(() {
      _controller.value = TextEditingValue(
        text: value,
        selection: TextSelection.collapsed(offset: value.length),
      );
    });
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: _controller.text));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: LocalizedText('文本已复制')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return _PageScroll(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionIntro(
            eyebrow: 'TEXT UTILITIES',
            title: '文本工具',
            subtitle: '常用文本清理和批量处理，所有操作均在本机完成。',
          ),
          const SizedBox(height: 18),
          _InfoCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: LocalizedText(
                        '输入文本',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: _controller.text.isEmpty
                          ? null
                          : _controller.clear,
                      icon: const Icon(Icons.delete_outline, size: 16),
                      label: const LocalizedText('清空'),
                    ),
                    TextButton.icon(
                      onPressed: _controller.text.isEmpty ? null : _copy,
                      icon: const Icon(Icons.copy_outlined, size: 16),
                      label: const LocalizedText('复制'),
                    ),
                  ],
                ),
                const SizedBox(height: 7),
                TextField(
                  controller: _controller,
                  minLines: 10,
                  maxLines: 16,
                  decoration: const InputDecoration(
                    hintText: '在此粘贴或输入文本…',
                    alignLabelWithHint: true,
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 14,
                  runSpacing: 6,
                  children: [
                    _HashMeta(icon: Icons.text_fields, label: '$_characters 字符'),
                    _HashMeta(icon: Icons.notes_outlined, label: '$_lines 行'),
                    _HashMeta(icon: Icons.short_text, label: '$_words 个词'),
                    _HashMeta(
                      icon: Icons.data_usage_outlined,
                      label: '$_utf8Bytes 字节 (UTF-8)',
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _InfoCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const LocalizedText(
                  '文本处理',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 11),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _TextAction('去除首尾空白', Icons.format_clear, () => _apply((v) => v.trim())),
                    _TextAction('合并多余空行', Icons.vertical_align_center, () => _apply((v) => v.replaceAll(RegExp(r'\n{3,}'), '\n\n'))),
                    _TextAction('删除空白行', Icons.format_line_spacing, () => _apply((v) => v.split('\n').where((line) => line.trim().isNotEmpty).join('\n'))),
                    _TextAction('行去重', Icons.filter_1, () => _apply((v) => v.split('\n').toSet().join('\n'))),
                    _TextAction('按行排序', Icons.sort_by_alpha, () => _apply((v) { final rows = v.split('\n'); rows.sort(); return rows.join('\n'); })),
                    _TextAction('转为大写', Icons.text_increase, () => _apply((v) => v.toUpperCase())),
                    _TextAction('转为小写', Icons.text_decrease, () => _apply((v) => v.toLowerCase())),
                    _TextAction('反转文本', Icons.swap_horiz, () => _apply((v) => String.fromCharCodes(v.runes.toList().reversed))),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TextAction extends StatelessWidget {
  const _TextAction(this.label, this.icon, this.onPressed);

  final String label;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
    onPressed: onPressed,
    icon: Icon(icon, size: 15),
    label: LocalizedText(label),
  );
}

class _JsonToolsPage extends StatefulWidget {
  const _JsonToolsPage({super.key});

  @override
  State<_JsonToolsPage> createState() => _JsonToolsPageState();
}

class _JsonToolsPageState extends State<_JsonToolsPage> {
  final _inputController = TextEditingController();
  final _outputController = TextEditingController();
  Timer? _editTimer;
  String _status = '粘贴 JSON 后选择格式化、压缩或校验。';
  bool? _valid;

  void _onInputChanged(String _) {
    _editTimer?.cancel();
    _editTimer = Timer(const Duration(milliseconds: 130), () {
      if (!mounted) return;
      setState(() {
        _valid = null;
        _status = '内容已修改，请重新校验。';
      });
    });
  }

  @override
  void dispose() {
    _editTimer?.cancel();
    _inputController.dispose();
    _outputController.dispose();
    super.dispose();
  }

  void _process({required bool pretty}) {
    try {
      final decoded = jsonDecode(_inputController.text);
      final output = pretty
          ? const JsonEncoder.withIndent('  ').convert(decoded)
          : jsonEncode(decoded);
      setState(() {
        _outputController.text = output;
        _valid = true;
        _status = pretty ? 'JSON 格式有效，已完成格式化。' : 'JSON 格式有效，已压缩输出。';
      });
    } on FormatException catch (error) {
      setState(() {
        _valid = false;
        _status = 'JSON 格式错误：${error.message}（位置 ${error.offset}）';
        _outputController.clear();
      });
    } catch (error) {
      setState(() {
        _valid = false;
        _status = '处理失败：${_shortError(error)}';
        _outputController.clear();
      });
    }
  }

  void _validate() {
    try {
      jsonDecode(_inputController.text);
      setState(() {
        _valid = true;
        _status = 'JSON 格式有效。';
      });
    } on FormatException catch (error) {
      setState(() {
        _valid = false;
        _status = 'JSON 格式错误：${error.message}（位置 ${error.offset}）';
        _outputController.clear();
      });
    }
  }

  Future<void> _copyOutput() async {
    if (_outputController.text.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: _outputController.text));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: LocalizedText('JSON 结果已复制')),
      );
    }
  }

  @override
  Widget build(BuildContext context) => _PageScroll(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionIntro(
          eyebrow: 'JSON WORKBENCH',
          title: 'JSON 格式化',
          subtitle: '格式化、压缩并校验 JSON 数据，不会上传输入内容。',
        ),
        const SizedBox(height: 18),
        _InfoCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const LocalizedText('输入 JSON', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              TextField(
                controller: _inputController,
                minLines: 9,
                maxLines: 14,
                decoration: const InputDecoration(
                  hintText: '{\n  "name": "MoePureKit",\n  "enabled": true\n}',
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
                onChanged: _onInputChanged,
              ),
              const SizedBox(height: 11),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: () => _process(pretty: true),
                    icon: const Icon(Icons.format_align_left, size: 17),
                    label: const LocalizedText('格式化'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _process(pretty: false),
                    icon: const Icon(Icons.compress, size: 17),
                    label: const LocalizedText('压缩'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _validate,
                    icon: const Icon(Icons.fact_check_outlined, size: 17),
                    label: const LocalizedText('校验 JSON'),
                  ),
                  TextButton.icon(
                    onPressed: () => setState(() {
                      _editTimer?.cancel();
                      _inputController.clear();
                      _outputController.clear();
                      _valid = null;
                      _status = '粘贴 JSON 后选择格式化、压缩或校验。';
                    }),
                    icon: const Icon(Icons.clear, size: 16),
                    label: const LocalizedText('清空'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(
                    _valid == null
                        ? Icons.info_outline
                        : _valid!
                            ? Icons.check_circle_outline
                            : Icons.error_outline,
                    size: 17,
                    color: _valid == null
                        ? const Color(0xFF89918A)
                        : _valid!
                            ? const Color(0xFF548B65)
                            : const Color(0xFFB45D55),
                  ),
                  const SizedBox(width: 7),
                  Expanded(child: LocalizedText(_status)),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _InfoCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: LocalizedText('输出结果', style: TextStyle(fontWeight: FontWeight.w600)),
                  ),
                  TextButton.icon(
                    onPressed: _outputController.text.isEmpty ? null : _copyOutput,
                    icon: const Icon(Icons.copy_outlined, size: 16),
                    label: const LocalizedText('复制结果'),
                  ),
                ],
              ),
              TextField(
                controller: _outputController,
                readOnly: true,
                minLines: 8,
                maxLines: 14,
                style: const TextStyle(fontFamily: 'Consolas', fontSize: 12),
                decoration: const InputDecoration(
                  hintText: '格式化或压缩后的 JSON 会显示在这里。',
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _EncodingToolsPage extends StatefulWidget {
  const _EncodingToolsPage({super.key});

  @override
  State<_EncodingToolsPage> createState() => _EncodingToolsPageState();
}

class _EncodingToolsPageState extends State<_EncodingToolsPage> {
  static const _modes = <String>[
    'Base64 编码',
    'Base64 解码',
    'URL 编码',
    'URL 解码',
  ];

  final _inputController = TextEditingController();
  final _outputController = TextEditingController();
  Timer? _byteCountTimer;
  int _inputByteCount = 0;
  String _mode = _modes.first;
  String? _error;

  void _scheduleByteCount() {
    _byteCountTimer?.cancel();
    _byteCountTimer = Timer(const Duration(milliseconds: 160), () {
      if (!mounted) return;
      final count = utf8.encode(_inputController.text).length;
      setState(() => _inputByteCount = count);
    });
  }

  @override
  void dispose() {
    _byteCountTimer?.cancel();
    _inputController.dispose();
    _outputController.dispose();
    super.dispose();
  }

  void _convert() {
    try {
      final input = _inputController.text;
      final output = switch (_mode) {
        'Base64 编码' => base64Encode(utf8.encode(input)),
        'Base64 解码' => utf8.decode(base64.decode(input.trim())),
        'URL 编码' => Uri.encodeComponent(input),
        'URL 解码' => Uri.decodeComponent(input),
        _ => throw StateError('不支持的编码方式'),
      };
      setState(() {
        _outputController.text = output;
        _inputByteCount = utf8.encode(input).length;
        _error = null;
      });
    } catch (error) {
      setState(() {
        _outputController.clear();
        _error = '转换失败：${_shortError(error)}';
      });
    }
  }

  Future<void> _copyOutput() async {
    if (_outputController.text.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: _outputController.text));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: LocalizedText('转换结果已复制')),
      );
    }
  }

  @override
  Widget build(BuildContext context) => _PageScroll(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionIntro(
          eyebrow: 'ENCODING CONVERTER',
          title: '编码转换',
          subtitle: '在本机进行 UTF-8、Base64 和 URL 编码转换。',
        ),
        const SizedBox(height: 18),
        _InfoCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const LocalizedText('转换模式', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: _mode,
                decoration: const InputDecoration(
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                items: _modes
                    .map((mode) => DropdownMenuItem(value: mode, child: LocalizedText(mode)))
                    .toList(),
                onChanged: (value) {
                  if (value != null) setState(() { _mode = value; _error = null; });
                },
              ),
              const SizedBox(height: 13),
              const LocalizedText('输入内容', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 7),
              TextField(
                controller: _inputController,
                minLines: 5,
                maxLines: 9,
                decoration: const InputDecoration(
                  hintText: '输入要转换的文本…',
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
                onChanged: (_) => _scheduleByteCount(),
              ),
              const SizedBox(height: 8),
              LocalizedText(
                'UTF-8 字节数：$_inputByteCount',
                style: const TextStyle(color: Color(0xFF858C86), fontSize: 11),
              ),
              const SizedBox(height: 11),
              Row(
                children: [
                  FilledButton.icon(
                    onPressed: _convert,
                    icon: const Icon(Icons.transform, size: 17),
                    label: const LocalizedText('开始转换'),
                  ),
                  const SizedBox(width: 8),
                  TextButton.icon(
                    onPressed: () => setState(() {
                      _byteCountTimer?.cancel();
                      _inputController.clear();
                      _outputController.clear();
                      _inputByteCount = 0;
                      _error = null;
                    }),
                    icon: const Icon(Icons.clear, size: 16),
                    label: const LocalizedText('清空'),
                  ),
                ],
              ),
              if (_error != null) ...[
                const SizedBox(height: 9),
                LocalizedText(_error!, style: const TextStyle(color: Color(0xFFB45D55))),
              ],
              const SizedBox(height: 17),
              Row(
                children: [
                  const Expanded(
                    child: LocalizedText('转换结果', style: TextStyle(fontWeight: FontWeight.w600)),
                  ),
                  TextButton.icon(
                    onPressed: _outputController.text.isEmpty ? null : _copyOutput,
                    icon: const Icon(Icons.copy_outlined, size: 16),
                    label: const LocalizedText('复制结果'),
                  ),
                ],
              ),
              TextField(
                controller: _outputController,
                readOnly: true,
                minLines: 5,
                maxLines: 9,
                style: const TextStyle(fontFamily: 'Consolas', fontSize: 12),
                decoration: const InputDecoration(
                  hintText: '转换结果会显示在这里。',
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}


class _NetworkPage extends StatefulWidget {
  const _NetworkPage({
    super.key,
    required this.onActivityChanged,
  });

  final ValueChanged<bool> onActivityChanged;

  @override
  State<_NetworkPage> createState() => _NetworkPageState();
}

class _NetworkPageState extends State<_NetworkPage> {
  final _service = NetworkDiagnosticsService();
  final _pingTargetController = TextEditingController(text: '1.1.1.1');
  NetworkDiagnosticsResult? _result;
  bool _checking = false;
  bool _includeUpload = true;
  String _stage = '尚未检测';
  String? _error;

  @override
  void dispose() {
    _pingTargetController.dispose();
    super.dispose();
  }

  Future<void> _check() async {
    if (_checking) return;
    final target = _pingTargetController.text.trim();
    if (target.isEmpty) {
      setState(() => _error = '请输入 Ping 目标，例如 1.1.1.1');
      return;
    }
    setState(() {
      _checking = true;
      _error = null;
      _result = null;
      _stage = '正在准备检测…';
    });
    widget.onActivityChanged(true);
    try {
      final result = await _service.runFullTest(
        pingTarget: target,
        includeUpload: _includeUpload,
        onProgress: (stage) {
          if (mounted) setState(() => _stage = stage);
        },
      );
      if (mounted) setState(() => _result = result);
    } on Object catch (error) {
      if (mounted) setState(() => _error = '网络检测失败：${_shortError(error)}');
    } finally {
      if (mounted) {
        setState(() => _checking = false);
        widget.onActivityChanged(false);
      }
    }
  }

  Future<void> _copyReport() async {
    final result = _result;
    if (result == null) return;
    final ping = result.ping;
    final lines = <String>[
      'MoePureKit 网络检测报告',
      '检测时间：${result.measuredAt.toLocal()}',
      '网络适配器：${result.interfaceAlias ?? '未获取'}',
      '本机 IPv4：${result.localIpv4 ?? '未获取'}',
      '默认网关：${result.defaultGateway ?? '未获取'}',
      '网关 Ping：${_formatMs(result.gatewayPing?.averageMs)}；丢包：${result.gatewayPing == null ? '未测试' : result.gatewayPing!.packetLossPercent.toStringAsFixed(1) + '%'}',
      '系统 DNS：${result.configuredDnsServers.isEmpty ? '未获取' : result.configuredDnsServers.join(', ')}',
      '测速域名解析 IP：${result.dnsAddress ?? result.dnsError ?? '失败'}',
      'DNS 延迟：${_formatMs(result.dnsLatencyMs)}',
      'Ping 目标：${result.pingTarget}',
      'Ping：${_formatMs(ping.averageMs)}；抖动：${_formatMs(ping.jitterMs)}；丢包：${ping.packetLossPercent.toStringAsFixed(1)}%',
      'Ping 最低/最高：${_formatMs(ping.minMs)} / ${_formatMs(ping.maxMs)}',
      'HTTPS 延迟：${_formatMs(result.httpsLatencyMs)}；HTTP：${result.httpStatusCode ?? '失败'}',
      '下载速度：${_formatSpeed(result.downloadMbps)}',
      '上传速度：${_formatSpeed(result.uploadMbps)}',
      '检测耗时：${(result.elapsed.inMilliseconds / 1000).toStringAsFixed(1)} 秒',
      '测速节点：https://${NetworkDiagnosticsService.speedTestHost}',
      '说明：速度为本机到测速节点的近似结果；上传测试只发送自动生成的测试数据。',
    ];
    await Clipboard.setData(ClipboardData(text: lines.join('\n')));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: LocalizedText('网络检测报告已复制')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    return _PageScroll(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionIntro(
            eyebrow: 'NETWORK DIAGNOSTICS',
            title: '网络诊断',
            subtitle: '检测 Ping、抖动、丢包、DNS、HTTPS 延迟和实际传输速度。',
          ),
          const SizedBox(height: 18),
          _InfoCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: LocalizedText(
                        '完整网络检测',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    if (result != null)
                      TextButton.icon(
                        onPressed: _copyReport,
                        icon: const Icon(Icons.copy_outlined, size: 16),
                        label: const LocalizedText('复制报告'),
                      ),
                  ],
                ),
                const SizedBox(height: 9),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _pingTargetController,
                        enabled: !_checking,
                        decoration: const InputDecoration(
                          labelText: 'Ping 目标',
                          hintText: '1.1.1.1',
                          isDense: true,
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.network_check),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    FilledButton.icon(
                      onPressed: _checking ? null : _check,
                      icon: _checking
                          ? const SizedBox(
                              width: 15,
                              height: 15,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.play_arrow_rounded, size: 18),
                      label: LocalizedText(_checking ? '检测中' : '开始检测'),
                    ),
                  ],
                ),
                const SizedBox(height: 7),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: _includeUpload,
                  onChanged: _checking
                      ? null
                      : (value) => setState(() => _includeUpload = value ?? true),
                  title: const LocalizedText(
                    '同时测试上传速度（发送约 2 MiB 自动生成数据）',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
                if (_checking) ...[
                  const SizedBox(height: 6),
                  const LinearProgressIndicator(),
                  const SizedBox(height: 8),
                  LocalizedText(
                    _stage,
                    style: const TextStyle(fontSize: 11, color: Color(0xFF858C86)),
                  ),
                ] else if (result != null) ...[
                  const SizedBox(height: 6),
                  LocalizedText(
                    '检测完成 · ${(result.elapsed.inMilliseconds / 1000).toStringAsFixed(1)} 秒',
                    style: const TextStyle(fontSize: 11, color: Color(0xFF548B65)),
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  LocalizedText(
                    _error!,
                    style: const TextStyle(color: Color(0xFFB45D55), fontSize: 12),
                  ),
                ],
                const SizedBox(height: 7),
                const LocalizedText(
                  '测速会连接 Cloudflare 公共测速节点。下载最多接收 8 MiB；上传仅发送自动生成的数据，不会上传本地文件。结果反映本机到该节点的路径，不等同于运营商线路保证值。',
                  style: TextStyle(fontSize: 10, height: 1.5, color: Color(0xFF858C86)),
                ),
              ],
            ),
          ),
          if (result != null) ...[
            const SizedBox(height: 13),
            _buildMetrics(result),
            const SizedBox(height: 12),
            _buildDetails(result),
          ],
        ],
      ),
    );
  }

  Widget _buildMetrics(NetworkDiagnosticsResult result) {
    final ping = result.ping;
    final metrics = <(String, String, String, IconData)>[
      ('Ping 平均', _formatMs(ping.averageMs), '目标 ${result.pingTarget}', Icons.network_check),
      ('网关 Ping', _formatMs(result.gatewayPing?.averageMs), result.gatewayPing == null ? '未获取默认网关' : '${result.gatewayPing!.received}/${result.gatewayPing!.sent} 个响应', Icons.router_outlined),
      ('抖动 Jitter', _formatMs(ping.jitterMs), '连续 Ping 延迟变化均值', Icons.waves_outlined),
      ('丢包率', '${ping.packetLossPercent.toStringAsFixed(1)}%', '${ping.received}/${ping.sent} 个响应', Icons.network_check),
      ('下载速度', _formatSpeed(result.downloadMbps), '${_formatBytes(result.downloadBytes)} 已接收', Icons.download_rounded),
      ('上传速度', result.includeUpload ? _formatSpeed(result.uploadMbps) : '未测试', result.includeUpload ? '${_formatBytes(result.uploadBytes)} 已发送' : '已关闭上传测试', Icons.upload_rounded),
      ('HTTPS 延迟', _formatMs(result.httpsLatencyMs), 'HTTP ${result.httpStatusCode ?? '不可用'} · 3 次中位数', Icons.lock_outline),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 760
            ? 3
            : constraints.maxWidth >= 480
                ? 2
                : 1;
        final gap = 10.0;
        final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final item in metrics)
              _NetworkMetricCard(
                width: width,
                label: item.$1,
                value: item.$2,
                detail: item.$3,
                icon: item.$4,
              ),
          ],
        );
      },
    );
  }

  Widget _buildDetails(NetworkDiagnosticsResult result) {
    final ping = result.ping;
    final issues = <String>[
      if (result.gatewayPingError != null) '网关 Ping：${result.gatewayPingError}',
      if (result.dnsError != null) 'DNS：${result.dnsError}',
      if (result.pingError != null) 'Ping：${result.pingError}',
      if (result.httpsError != null) 'HTTPS：${result.httpsError}',
      if (result.downloadError != null) '下载：${result.downloadError}',
      if (result.uploadError != null) '上传：${result.uploadError}',
    ];
    return _InfoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const LocalizedText('检测详情', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          _NetworkDetailRow('网络适配器', result.interfaceAlias ?? '未获取'),
          _NetworkDetailRow('本机 IPv4', result.localIpv4 ?? '未获取'),
          _NetworkDetailRow('默认网关', result.defaultGateway ?? '未获取'),
          _NetworkDetailRow('网关 Ping', result.gatewayPing == null ? (result.gatewayPingError ?? '未测试') : '${_formatMs(result.gatewayPing!.averageMs)} · 丢包 ${result.gatewayPing!.packetLossPercent.toStringAsFixed(1)}%'),
          _NetworkDetailRow('网关 Ping 样本', result.gatewayPing == null || result.gatewayPing!.samplesMs.isEmpty ? '无响应' : result.gatewayPing!.samplesMs.map((value) => '${value.toStringAsFixed(1)} ms').join('、')),
          _NetworkDetailRow('系统 DNS 服务器', result.configuredDnsServers.isEmpty ? '未获取' : result.configuredDnsServers.join('、')),
          _NetworkDetailRow('测速域名解析 IP', result.dnsAddress ?? '解析失败'),
          _NetworkDetailRow('DNS 查询耗时', _formatMs(result.dnsLatencyMs)),
          _NetworkDetailRow('Ping 最低 / 最高', '${_formatMs(ping.minMs)} / ${_formatMs(ping.maxMs)}'),
          _NetworkDetailRow('Ping 样本', ping.samplesMs.isEmpty ? '无响应' : ping.samplesMs.map((value) => '${value.toStringAsFixed(1)} ms').join('、')),
          _NetworkDetailRow('下载数据量', _formatBytes(result.downloadBytes)),
          _NetworkDetailRow('上传数据量', _formatBytes(result.uploadBytes)),
          _NetworkDetailRow('检测节点', 'https://${NetworkDiagnosticsService.speedTestHost}'),
          if (issues.isNotEmpty) ...[
            const SizedBox(height: 10),
            const Divider(height: 1),
            const SizedBox(height: 10),
            const LocalizedText('未完成项目', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
            const SizedBox(height: 6),
            for (final issue in issues)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: LocalizedText(
                  '• $issue',
                  style: const TextStyle(fontSize: 11, color: Color(0xFFB27A45)),
                ),
              ),
          ],
          const SizedBox(height: 8),
          const LocalizedText(
            '网络适配器、默认网关和系统 DNS 来自 Windows 网络配置。Ping 使用系统 ICMP 命令；部分网络或防火墙会屏蔽 ICMP。此时 HTTPS 延迟仍可反映应用层连通性。抖动按成功样本的相邻延迟差绝对值计算。',
            style: TextStyle(fontSize: 10, height: 1.5, color: Color(0xFF858C86)),
          ),
        ],
      ),
    );
  }

  String _formatMs(double? value) =>
      value == null ? '—' : '${value.toStringAsFixed(1)} ms';

  String _formatSpeed(double? value) =>
      value == null ? '—' : '${value.toStringAsFixed(2)} Mbps';

  String _formatBytes(int value) {
    if (value >= 1024 * 1024) return '${(value / (1024 * 1024)).toStringAsFixed(2)} MiB';
    if (value >= 1024) return '${(value / 1024).toStringAsFixed(1)} KiB';
    return '$value B';
  }
}

class _NetworkMetricCard extends StatelessWidget {
  const _NetworkMetricCard({
    required this.width,
    required this.label,
    required this.value,
    required this.detail,
    required this.icon,
  });

  final double width;
  final String label;
  final String value;
  final String detail;
  final IconData icon;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    child: _InfoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: const Color(0xFF738A79)),
              const SizedBox(width: 7),
              Expanded(
                child: LocalizedText(
                  label,
                  style: const TextStyle(fontSize: 11, color: Color(0xFF858C86)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          LocalizedText(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 5),
          LocalizedText(
            detail,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 10, color: Color(0xFF858C86)),
          ),
        ],
      ),
    ),
  );
}

class _NetworkDetailRow extends StatelessWidget {
  const _NetworkDetailRow(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 118,
          child: LocalizedText(
            label,
            style: const TextStyle(fontSize: 11, color: Color(0xFF858C86)),
          ),
        ),
        Expanded(
          child: SelectableText(value, style: const TextStyle(fontSize: 11)),
        ),
      ],
    ),
  );
}

Future<void> _launchExternalUrl(String value) async {
  final uri = Uri.parse(value);
  if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
    throw StateError('未能交给系统默认浏览器打开 $value');
  }
}

class _ActivationPage extends StatefulWidget {
  const _ActivationPage({
    super.key,
    required this.onActivityChanged,
  });

  final ValueChanged<bool> onActivityChanged;

  @override
  State<_ActivationPage> createState() => _ActivationPageState();
}

class _ActivationPageState extends State<_ActivationPage> {
  final _statusService = SystemStatusService();
  final _productKeyController = TextEditingController();
  String _status = '许可状态尚未读取';
  bool _checking = false;
  bool _activating = false;
  bool _checkingTicket = false;
  bool _diagnosingKms = false;
  String _ticketStatus = '尚未检查 XML 文件';
  String _kmsStatus = '尚未读取 KMS 客户端信息';
  String? _ticketPath;

  void _notifyActivity() {
    widget.onActivityChanged(
      _checking || _activating || _checkingTicket || _diagnosingKms,
    );
  }

  @override
  void dispose() {
    _productKeyController.dispose();
    super.dispose();
  }

  Future<void> _checkStatus() async {
    setState(() {
      _checking = true;
      _status = '正在读取 Windows 许可状态…';
    });
    _notifyActivity();
    try {
      final result = await _statusService.detectWindowsLicense();
      if (mounted) setState(() => _status = result);
    } catch (error) {
      if (mounted) setState(() => _status = '状态读取失败：$error');
    } finally {
      if (mounted) {
        setState(() => _checking = false);
        _notifyActivity();
      }
    }
  }

  Future<void> _inspectTicket() async {
    final selected = await openFile(
      confirmButtonText: '选择 XML 文件',
      acceptedTypeGroups: const [
        XTypeGroup(label: 'XML 文件', extensions: ['xml']),
      ],
    );
    if (selected == null || !mounted) return;
    setState(() {
      _checkingTicket = true;
      _ticketPath = selected.path;
      _ticketStatus = '正在安全解析 XML…';
    });
    _notifyActivity();
    try {
      final result = await _statusService.inspectLicenseTicketXml(
        selected.path,
      );
      if (mounted) setState(() => _ticketStatus = result);
    } on Object catch (error) {
      if (mounted) setState(() => _ticketStatus = 'XML 检查失败：$error');
    } finally {
      if (mounted) {
        setState(() => _checkingTicket = false);
        _notifyActivity();
      }
    }
  }

  Future<void> _diagnoseKms() async {
    setState(() {
      _diagnosingKms = true;
      _kmsStatus = '正在读取当前 KMS 客户端配置并测试网络…';
    });
    _notifyActivity();
    try {
      final result = await _statusService.diagnoseKmsClient();
      if (mounted) setState(() => _kmsStatus = result);
    } on Object catch (error) {
      if (mounted) setState(() => _kmsStatus = 'KMS 诊断失败：$error');
    } finally {
      if (mounted) {
        setState(() => _diagnosingKms = false);
        _notifyActivity();
      }
    }
  }

  Future<void> _openWindowsActivationSettings() async {
    try {
      await _statusService.openWindowsActivationSettings();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: LocalizedText('已打开 Windows 官方激活设置'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } on ProcessException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: LocalizedText('无法打开 Windows 激活设置：${error.message}'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } on UnsupportedError catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: LocalizedText(error.message ?? '$error'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _installProductKey() async {
    final key = _productKeyController.text.trim();
    if (!RegExp(r'^[A-Za-z0-9]{5}(?:-?[A-Za-z0-9]{5}){4}$').hasMatch(key)) {
      setState(() => _status = '请输入格式正确的 25 位 Windows 正版产品密钥');
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const LocalizedText('安装正版 Windows 密钥'),
        content: const LocalizedText(
          '此操作将通过 Windows 用户账户控制请求管理员确认，把你提供的密钥提交给 Windows 授权服务并尝试在线激活。密钥不会保存在本应用设置中。请只使用你有权使用的正版密钥。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const LocalizedText('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const LocalizedText('确认并请求管理员权限'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _activating = true;
      _status = '正在请求管理员确认并提交正版密钥…';
    });
    _notifyActivity();
    _productKeyController.clear();
    try {
      final result = await _statusService.installGenuineWindowsProductKey(key);
      if (mounted) setState(() => _status = result);
    } on FormatException catch (error) {
      if (mounted) setState(() => _status = '密钥格式错误：${error.message}');
    } on ProcessException catch (error) {
      if (mounted) {
        setState(() => _status = 'Windows 未完成密钥安装：${error.message}');
      }
    } on TimeoutException catch (error) {
      if (mounted) setState(() => _status = '激活流程超时：${error.message}');
    } on StateError catch (error) {
      if (mounted) setState(() => _status = 'Windows 拒绝此密钥：$error');
    } on FileSystemException catch (error) {
      if (mounted) setState(() => _status = '无法准备激活请求：${error.message}');
    } on UnsupportedError catch (error) {
      if (mounted) setState(() => _status = error.message ?? '$error');
    } finally {
      if (mounted) {
        setState(() => _activating = false);
        _notifyActivity();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return _PageScroll(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionIntro(
            eyebrow: 'GENUINE WINDOWS ACTIVATION',
            title: 'Windows 正版激活',
            subtitle: '输入你拥有的正版产品密钥，通过 Windows 授权服务安装并尝试激活。',
          ),
          const SizedBox(height: 18),
          _InfoCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const LocalizedText(
                  'Windows 许可状态',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                LocalizedText(
                  _status,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF707870),
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _checking ? null : _checkStatus,
                      icon: _checking
                          ? const SizedBox(
                              width: 15,
                              height: 15,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.fact_check_outlined),
                      label: const LocalizedText('检查许可状态'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _openWindowsActivationSettings,
                      icon: const Icon(Icons.open_in_new),
                      label: const LocalizedText('打开 Windows 官方激活设置'),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _productKeyController,
                  obscureText: true,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: const InputDecoration(
                    labelText: 'Windows 产品密钥',
                    hintText: 'XXXXX-XXXXX-XXXXX-XXXXX-XXXXX',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 10),
                FilledButton.icon(
                  onPressed: _activating ? null : _installProductKey,
                  icon: _activating
                      ? const SizedBox(
                          width: 15,
                          height: 15,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.key_outlined),
                  label: LocalizedText(_activating ? '正在安装并激活…' : '安装密钥并尝试激活'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _InfoCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const LocalizedText(
                  'XML 票据安全检查',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                const LocalizedText(
                  '选择本地 XML 文件，检查 XML 语法、结构摘要与 SHA-256。此操作不会将票据导入 Windows，也不会判定票据是否真实或具备授权资格。',
                  style: TextStyle(fontSize: 12, height: 1.6, color: Color(0xFF72766F)),
                ),
                const SizedBox(height: 10),
                if (_ticketPath != null)
                  SelectableText(
                    _ticketPath!,
                    style: const TextStyle(fontSize: 11, color: Color(0xFF707870)),
                  ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _checkingTicket ? null : _inspectTicket,
                  icon: _checkingTicket
                      ? const SizedBox(width: 15, height: 15, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.document_scanner_outlined),
                  label: LocalizedText(_checkingTicket ? '正在检查 XML…' : '选择并检查 XML 票据'),
                ),
                const SizedBox(height: 10),
                SelectableText(
                  _ticketStatus,
                  style: const TextStyle(fontSize: 12, height: 1.65, color: Color(0xFF707870)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _InfoCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const LocalizedText(
                  '企业 KMS 客户端诊断',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                const LocalizedText(
                  '只读检查本机现有的批量授权客户端状态、已配置或 DNS 发现的 KMS 主机，以及 TCP 端口连通性。不会修改主机配置或发起激活。',
                  style: TextStyle(fontSize: 12, height: 1.6, color: Color(0xFF72766F)),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: _diagnosingKms ? null : _diagnoseKms,
                  icon: _diagnosingKms
                      ? const SizedBox(width: 15, height: 15, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.hub_outlined),
                  label: LocalizedText(_diagnosingKms ? '正在诊断…' : '检查 KMS 客户端'),
                ),
                const SizedBox(height: 10),
                SelectableText(
                  _kmsStatus,
                  style: const TextStyle(fontSize: 12, height: 1.65, color: Color(0xFF707870)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          const _InfoCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LocalizedText(
                  '重要风险提示',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF7E5D37),
                  ),
                ),
                SizedBox(height: 8),
                LocalizedText(
                  '仅输入你依法获得的 Windows 产品密钥。提交密钥需要通过 Windows UAC 明确确认；本应用不存储该密钥，不含激活绕过或伪造许可证功能。无效、过期或不适用于当前版本的密钥会由 Windows 拒绝。',
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.7,
                    color: Color(0xFF72766F),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
        ],
      ),
    );
  }
}

class _SettingsPage extends StatefulWidget {
  const _SettingsPage({
    super.key,
    required this.settings,
    required this.onSave,
    required this.onPreview,
    required this.wallpaper,
    required this.wallpaperLoading,
    required this.wallpaperError,
    required this.onRefreshWallpaper,
  });

  final AppSettings settings;
  final Future<void> Function(AppSettings) onSave;
  final ValueChanged<AppSettings> onPreview;
  final BingWallpaperInfo? wallpaper;
  final bool wallpaperLoading;
  final String? wallpaperError;
  final VoidCallback onRefreshWallpaper;

  @override
  State<_SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<_SettingsPage> {
  late AppSettings _draft;
  late AppSettings _baseline;
  late final Map<String, TextEditingController> _controllers;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _draft = widget.settings;
    _baseline = widget.settings;
    _controllers = {
      'downloadDirectory': TextEditingController(
        text: _draft.downloadDirectory,
      ),
      'aria2RpcUrl': TextEditingController(text: _draft.aria2RpcUrl),
      'aria2RpcSecret': TextEditingController(text: _draft.aria2RpcSecret),
      'proxy': TextEditingController(text: _draft.proxy),
      'defaultUserAgent': TextEditingController(text: _draft.defaultUserAgent),
      'defaultReferer': TextEditingController(text: _draft.defaultReferer),
      'defaultCookie': TextEditingController(text: _draft.defaultCookie),
      'defaultHeaders': TextEditingController(text: _draft.defaultHeaders),
      'concurrentDownloads': TextEditingController(
        text: '${_draft.concurrentDownloads}',
      ),
    };
    for (final controller in _controllers.values) {
      controller.addListener(_onControllerChanged);
    }
  }

  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.removeListener(_onControllerChanged);
      controller.dispose();
    }
    super.dispose();
  }

  bool get _hasUnsavedChanges =>
      !_settingsEqual(_collectSettings(_draft), _baseline);

  bool _settingsEqual(AppSettings a, AppSettings b) =>
      a.backgroundMode == b.backgroundMode &&
      a.downloadDirectory == b.downloadDirectory &&
      a.concurrentDownloads == b.concurrentDownloads &&
      a.proxy == b.proxy &&
      a.defaultUserAgent == b.defaultUserAgent &&
      a.defaultReferer == b.defaultReferer &&
      a.defaultCookie == b.defaultCookie &&
      a.defaultHeaders == b.defaultHeaders &&
      a.aria2RpcUrl == b.aria2RpcUrl &&
      a.aria2RpcSecret == b.aria2RpcSecret &&
      a.animationsEnabled == b.animationsEnabled &&
      a.languageMode == b.languageMode &&
      a.themeMode == b.themeMode &&
      a.downloadDirectoryPrompted == b.downloadDirectoryPrompted &&
      a.minimizeToTrayOnClose == b.minimizeToTrayOnClose &&
      a.suppressCloseConfirmation == b.suppressCloseConfirmation &&
      a.launchAtStartup == b.launchAtStartup;

  Future<bool> _save({bool showSuccess = true}) async {
    if (_saving) return false;
    final settings = _collectSettings(_draft);
    setState(() => _saving = true);
    try {
      await widget.onSave(settings);
      if (!mounted) return false;
      setState(() {
        _draft = settings;
        _baseline = settings;
      });
      widget.onPreview(settings);
      if (showSuccess) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: LocalizedText('设置已保存'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return true;
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: LocalizedText('保存失败：${_shortError(error)}'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return false;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<bool> confirmLeave() async {
    if (!_hasUnsavedChanges) return true;
    final choice = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const LocalizedText('设置尚未保存'),
        content: const LocalizedText('当前设置有未保存的更改。离开前要如何处理？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, 'stay'),
            child: const LocalizedText('继续编辑'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, 'discard'),
            child: const LocalizedText('放弃修改'),
          ),
          FilledButton(
            onPressed: _saving
                ? null
                : () => Navigator.pop(dialogContext, 'save'),
            child: const LocalizedText('保存并离开'),
          ),
        ],
      ),
    );
    if (choice == 'save') return _save(showSuccess: false);
    if (choice == 'discard') {
      _restoreBaseline();
      return true;
    }
    return false;
  }

  void _restoreBaseline() {
    final saved = _baseline;
    _controllers['downloadDirectory']!.text = saved.downloadDirectory;
    _controllers['aria2RpcUrl']!.text = saved.aria2RpcUrl;
    _controllers['aria2RpcSecret']!.text = saved.aria2RpcSecret;
    _controllers['proxy']!.text = saved.proxy;
    _controllers['defaultUserAgent']!.text = saved.defaultUserAgent;
    _controllers['defaultReferer']!.text = saved.defaultReferer;
    _controllers['defaultCookie']!.text = saved.defaultCookie;
    _controllers['defaultHeaders']!.text = saved.defaultHeaders;
    _controllers['concurrentDownloads']!.text = '${saved.concurrentDownloads}';
    setState(() => _draft = saved);
    widget.onPreview(saved);
  }

  void _updateDraft(AppSettings settings, {bool previewAppearance = false}) {
    final collected = _collectSettings(settings);
    setState(() => _draft = collected);
    if (previewAppearance) widget.onPreview(collected);
  }

  AppSettings _collectSettings(AppSettings settings) {
    final parallel =
        int.tryParse(_controllers['concurrentDownloads']!.text) ?? 5;
    return settings.copyWith(
      downloadDirectory: _controllers['downloadDirectory']!.text.trim(),
      aria2RpcUrl: _controllers['aria2RpcUrl']!.text.trim(),
      aria2RpcSecret: _controllers['aria2RpcSecret']!.text,
      proxy: _controllers['proxy']!.text.trim(),
      defaultUserAgent: _controllers['defaultUserAgent']!.text,
      defaultReferer: _controllers['defaultReferer']!.text,
      defaultCookie: _controllers['defaultCookie']!.text,
      defaultHeaders: _controllers['defaultHeaders']!.text,
      concurrentDownloads: parallel.clamp(1, 64),
    );
  }

  void _applyLanguage(AppLanguageMode value) {
    _updateDraft(_draft.copyWith(languageMode: value));
  }

  Future<void> _chooseDownloadDirectory() async {
    final path = await getDirectoryPath(
      initialDirectory: _controllers['downloadDirectory']!.text.trim().isEmpty
          ? null
          : _controllers['downloadDirectory']!.text.trim(),
      confirmButtonText: '选择此文件夹',
    );
    if (path != null) {
      _controllers['downloadDirectory']!.text = path;
    }
  }

  void _applyTheme(AppThemeMode value) {
    _updateDraft(_draft.copyWith(themeMode: value), previewAppearance: true);
  }

  void _applyBackground(BackgroundMode value) {
    _updateDraft(_draft.copyWith(backgroundMode: value), previewAppearance: true);
  }

  void _applyAutostart(bool value) {
    _updateDraft(_draft.copyWith(launchAtStartup: value));
  }

  @override
  Widget build(BuildContext context) {
    final bingWallpaper = widget.wallpaper;
    final bingCaption = bingWallpaper == null
        ? widget.wallpaperError ?? '启动时自动更新；网络不可用时使用本地缓存'
        : '${bingWallpaper.isStale ? '离线缓存 · ' : ''}${bingWallpaper.copyright}';
    return _PageScroll(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionIntro(
            eyebrow: 'PREFERENCES',
            title: '设置',
            subtitle: '偏好信息保存在本机；全局字体固定为微软雅黑。',
          ),
          const SizedBox(height: 16),
          _InfoCard(
            child: Row(
              children: [
                Icon(Icons.visibility_outlined, size: 18, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 9),
                const Expanded(
                  child: LocalizedText(
                    '主题和背景会立即预览，但不会自动保存；离开本页时会询问保存或放弃。',
                    style: TextStyle(fontSize: 11, color: Color(0xFF858C86)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          _InfoCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _SettingsTitle('外观'),
                const SizedBox(height: 12),
                DropdownButtonFormField<AppLanguageMode>(
                  isExpanded: true,
                  initialValue: _draft.languageMode,
                  decoration: InputDecoration(
                    labelText: translateText(context, '界面语言'),
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: [
                    DropdownMenuItem(
                      value: AppLanguageMode.system,
                      child: LocalizedText('跟随系统'),
                    ),
                    DropdownMenuItem(
                      value: AppLanguageMode.chinese,
                      child: LocalizedText('简体中文'),
                    ),
                    DropdownMenuItem(
                      value: AppLanguageMode.english,
                      child: LocalizedText('English'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      _applyLanguage(value);
                    }
                  },
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<AppThemeMode>(
                  isExpanded: true,
                  initialValue: _draft.themeMode,
                  decoration: InputDecoration(
                    labelText: translateText(context, '主题模式'),
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: [
                    DropdownMenuItem(
                      value: AppThemeMode.system,
                      child: LocalizedText('跟随系统'),
                    ),
                    DropdownMenuItem(
                      value: AppThemeMode.light,
                      child: LocalizedText('浅色模式'),
                    ),
                    DropdownMenuItem(
                      value: AppThemeMode.dark,
                      child: LocalizedText('深色模式'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      _applyTheme(value);
                    }
                  },
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<BackgroundMode>(
                  isExpanded: true,
                  initialValue: _draft.backgroundMode,
                  decoration: InputDecoration(
                    labelText: translateText(context, '背景模式'),
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: BackgroundMode.white,
                      child: LocalizedText('纯白背景'),
                    ),
                    DropdownMenuItem(
                      value: BackgroundMode.mica,
                      child: LocalizedText('毛玻璃（Mica / Acrylic）'),
                    ),
                    DropdownMenuItem(
                      value: BackgroundMode.bingMica,
                      child: LocalizedText('Bing 每日壁纸 + 毛玻璃'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      _applyBackground(value);
                    }
                  },
                ),
                if (_draft.backgroundMode == BackgroundMode.bingMica) ...[
                  const SizedBox(height: 10),
                  Container(
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Theme.of(context).dividerColor),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(
                          height: 132,
                          child: widget.wallpaper == null
                              ? Center(
                                  child: widget.wallpaperLoading
                                      ? const CircularProgressIndicator()
                                      : const Icon(Icons.wallpaper_outlined, size: 34),
                                )
                              : Image.file(
                                  File(widget.wallpaper!.localPath),
                                  fit: BoxFit.cover,
                                  cacheWidth: 960,
                                  errorBuilder: (context, error, stackTrace) =>
                                      const Center(child: Icon(Icons.broken_image_outlined)),
                                ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(11, 9, 11, 10),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    LocalizedText(
                                      bingWallpaper?.title ?? 'Bing 每日壁纸',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                                    ),
                                    const SizedBox(height: 3),
                                    LocalizedText(
                                      bingCaption,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 10,
                                        color: Color(0xFF858C86),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              if (bingWallpaper != null &&
                                  bingWallpaper.copyrightLink.isNotEmpty)
                                IconButton(
                                  tooltip: translateText(context, '查看图片来源'),
                                  onPressed: () async {
                                    try {
                                      await _launchExternalUrl(
                                        bingWallpaper.copyrightLink,
                                      );
                                    } catch (error) {
                                      if (mounted) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(
                                            content: LocalizedText(
                                              '无法打开图片来源：${_shortError(error)}',
                                            ),
                                          ),
                                        );
                                      }
                                    }
                                  },
                                  icon: const Icon(Icons.open_in_new_rounded),
                                ),
                              IconButton(
                                tooltip: translateText(context, '刷新 Bing 壁纸'),
                                onPressed: widget.wallpaperLoading ? null : widget.onRefreshWallpaper,
                                icon: widget.wallpaperLoading
                                    ? const SizedBox(width: 17, height: 17, child: CircularProgressIndicator(strokeWidth: 2))
                                    : const Icon(Icons.refresh_rounded),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const LocalizedText('开机时自动启动'),
                  subtitle: const LocalizedText(
                    '仅为当前 Windows 用户创建启动项，不需要管理员权限',
                  ),
                  value: _draft.launchAtStartup,
                  onChanged: _applyAutostart,
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const LocalizedText('关闭时最小化到系统托盘（保留后台下载）'),
                  subtitle: const LocalizedText('默认关闭窗口会退出应用并关闭 aria2；启用后会隐藏到托盘并继续下载'),
                  value: _draft.minimizeToTrayOnClose,
                  onChanged: (value) => setState(
                    () =>
                        _draft = _draft.copyWith(minimizeToTrayOnClose: value),
                  ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const LocalizedText('关闭时不再询问'),
                  subtitle: const LocalizedText('直接执行上方选择的默认操作；可随时重新开启'),
                  value: _draft.suppressCloseConfirmation,
                  onChanged: (value) => setState(
                    () => _draft = _draft.copyWith(
                      suppressCloseConfirmation: value,
                    ),
                  ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const LocalizedText('启用界面轻量动画'),
                  subtitle: const LocalizedText('控制页面、卡片与导航的淡入淡出；不会暂停后台任务'),
                  value: _draft.animationsEnabled,
                  onChanged: (value) => setState(
                    () => _draft = _draft.copyWith(animationsEnabled: value),
                  ),
                ),
                const LocalizedText(
                  '字体：Microsoft YaHei（固定）',
                  style: TextStyle(fontSize: 11, color: Color(0xFF858C86)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _InfoCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _SettingsTitle('下载与 aria2'),
                const SizedBox(height: 12),
                _SettingsField(
                  label: '下载目录',
                  controller: _controllers['downloadDirectory']!,
                  onTrailing: _chooseDownloadDirectory,
                ),
                _SettingsField(
                  label: 'aria2 JSON-RPC 地址',
                  controller: _controllers['aria2RpcUrl']!,
                  hint: 'http://127.0.0.1:6800/jsonrpc',
                ),
                _SettingsField(
                  label: 'RPC 密钥',
                  controller: _controllers['aria2RpcSecret']!,
                  obscureText: true,
                ),
                _SettingsField(
                  label: '并发数（1–64）',
                  controller: _controllers['concurrentDownloads']!,
                  keyboardType: TextInputType.number,
                ),
                _SettingsField(
                  label: '代理地址',
                  controller: _controllers['proxy']!,
                  hint: '例如 http://127.0.0.1:7890',
                ),
                const SizedBox(height: 8),
                const _SettingsTitle('默认登录信息'),
                const SizedBox(height: 10),
                _SettingsField(
                  label: 'User-Agent',
                  controller: _controllers['defaultUserAgent']!,
                ),
                _SettingsField(
                  label: 'Referer',
                  controller: _controllers['defaultReferer']!,
                ),
                _SettingsField(
                  label: 'Cookie',
                  controller: _controllers['defaultCookie']!,
                  obscureText: true,
                ),
                _SettingsField(
                  label: '额外 Header（每行一个）',
                  controller: _controllers['defaultHeaders']!,
                  maxLines: 3,
                ),
                const LocalizedText(
                  'Cookie 与 RPC 密钥保存在本机 SharedPreferences 中，当前版本未加密；请勿在共享账户中保存敏感信息。',
                  style: TextStyle(
                    fontSize: 10,
                    height: 1.5,
                    color: Color(0xFF858C86),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          const _InfoCard(
            child: LocalizedText(
              '启动遮罩按需求每次启动固定显示约 3 秒；当前版本不提供关闭开关。',
              style: TextStyle(fontSize: 11, color: Color(0xFF858C86)),
            ),
          ),
          const SizedBox(height: 14),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: _saving ? null : () => _save(),
              icon: _saving
                  ? const SizedBox(width: 15, height: 15, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.save_outlined),
              label: const LocalizedText('保存设置'),
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsTitle extends StatelessWidget {
  const _SettingsTitle(this.title);

  final String title;

  @override
  Widget build(BuildContext context) => LocalizedText(
    title,
    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
  );
}

class _SettingsField extends StatelessWidget {
  const _SettingsField({
    required this.label,
    required this.controller,
    this.hint,
    this.obscureText = false,
    this.maxLines = 1,
    this.keyboardType,
    this.onTrailing,
  });

  final String label;
  final TextEditingController controller;
  final String? hint;
  final bool obscureText;
  final int maxLines;
  final TextInputType? keyboardType;
  final VoidCallback? onTrailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: controller,
        obscureText: obscureText,
        maxLines: maxLines,
        keyboardType: keyboardType,
        decoration: InputDecoration(
          labelText: translateText(context, label),
          hintText: hint == null ? null : translateText(context, hint!),
          border: const OutlineInputBorder(),
          isDense: true,
          suffixIcon: onTrailing == null
              ? null
              : IconButton(
                  onPressed: onTrailing,
                  tooltip: translateText(context, '浏览文件夹'),
                  icon: const Icon(Icons.folder_open_outlined),
                ),
        ),
      ),
    );
  }
}

class _AboutPage extends StatefulWidget {
  const _AboutPage({super.key});

  @override
  State<_AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<_AboutPage> {
  final _updater = UpdateService();
  AppRelease? _release;
  String _status = '尚未检查';
  bool _checking = false;
  Timer? _timer;
  UpdateDownload? _activeDownload;
  ReleaseAsset? _downloadedAsset;
  String? _downloadedPath;
  String? _downloadStatus;
  String? _downloadError;
  int _downloadReceived = 0;
  int _downloadTotal = 0;
  bool _downloading = false;
  String? _promptedReleaseTag;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _check(silent: true));
    _timer = Timer.periodic(
      const Duration(hours: 6),
      (_) => _check(silent: true, promptForUpdate: false),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    _activeDownload?.cancel();
    super.dispose();
  }

  Future<void> _check({bool silent = false, bool promptForUpdate = true}) async {
    if (_checking) return;
    var shouldPromptForPackage = false;
    setState(() {
      _checking = true;
      if (!silent) _status = '正在检查更新…';
    });
    try {
      final release = await _updater.checkLatest();
      if (!mounted) return;
      final newer = _updater.isNewer(release.version, AppConstants.version);
      shouldPromptForPackage = promptForUpdate &&
          newer &&
          release.downloadableAssets.isNotEmpty &&
          _promptedReleaseTag != release.tag;
      setState(() {
        _release = release;
        _status = newer
            ? '发现新版本：${release.version}'
            : (_updater.isNewer(AppConstants.version, release.version)
                ? '本地版本高于 GitHub 最新发布版本'
                : '当前已是最新版本');
      });
    } catch (error) {
      if (mounted && !silent) setState(() => _status = '检查失败：$error');
    } finally {
      if (mounted) setState(() => _checking = false);
    }
    // Ask once when the About page is opened or the user checks manually.
    // Background polling updates the status without interrupting another page.
    if (mounted && shouldPromptForPackage && _release != null) {
      _promptedReleaseTag = _release!.tag;
      await _chooseAndDownload();
    }
  }

  String _formatSize(int bytes) {
    if (bytes >= 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
    if (bytes >= 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '$bytes B';
  }

  Future<void> _chooseAndDownload() async {
    final release = _release;
    if (release == null || _downloading) return;
    final candidates = release.downloadableAssets;
    if (candidates.isEmpty) {
      setState(() => _downloadStatus = '此 Release 没有可识别的 Windows 安装包或便携包。');
      return;
    }

    final selected = await showDialog<ReleaseAsset>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const LocalizedText('选择下载版本'),
        content: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const LocalizedText('请选择要下载的版本。便携版通常解压后运行；安装版会启动 Windows 安装向导。',
                  style: TextStyle(fontSize: 12, height: 1.45)),
              const SizedBox(height: 10),
              for (final asset in candidates)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(asset.kind == ReleasePackageKind.portable
                      ? Icons.folder_zip_outlined
                      : Icons.install_desktop_outlined),
                  title: LocalizedText(asset.kindLabel, style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: LocalizedText('${asset.name}\n${_formatSize(asset.size)}', maxLines: 2,
                      overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11)),
                  isThreeLine: true,
                  onTap: () => Navigator.of(dialogContext).pop(asset),
                ),
            ],
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(dialogContext), child: const LocalizedText('取消'))],
      ),
    );
    if (selected == null || !mounted) return;

    final saveLocation = await getSaveLocation(suggestedName: selected.name);
    if (saveLocation == null || !mounted) return;

    final downloader = UpdateDownload();
    setState(() {
      _activeDownload = downloader;
      _downloadedAsset = selected;
      _downloadedPath = null;
      _downloadError = null;
      _downloadStatus = '正在准备下载…';
      _downloadReceived = 0;
      _downloadTotal = selected.size;
      _downloading = true;
    });
    try {
      final file = await downloader.download(
        selected,
        saveLocation.path,
        onProgress: (received, total) {
          if (!mounted) return;
          setState(() {
            _downloadReceived = received;
            _downloadTotal = total;
            _downloadStatus = '正在下载…';
          });
        },
      );
      if (!mounted) return;
      setState(() {
        _downloadedPath = file.path;
        _downloadStatus = selected.digest == null
            ? '下载完成。该 Release 未提供 API SHA-256，请按发布说明自行核对。'
            : '下载完成，SHA-256 校验通过。';
      });
    } on UpdateDownloadCancelled {
      if (mounted) setState(() => _downloadStatus = '下载已取消。');
    } on UpdateIntegrityException {
      if (mounted) setState(() {
        _downloadError = '文件 SHA-256 校验失败，已删除下载文件。';
        _downloadStatus = _downloadError!;
      });
    } catch (error) {
      if (mounted) setState(() {
        _downloadError = '下载失败：$error';
        _downloadStatus = _downloadError!;
      });
    } finally {
      if (mounted) setState(() {
        _downloading = false;
        _activeDownload = null;
      });
    }
  }

  void _cancelDownload() {
    _activeDownload?.cancel();
  }

  Future<void> _openDownloadedFile() async {
    final path = _downloadedPath;
    final asset = _downloadedAsset;
    if (path == null || asset == null) return;
    if (asset.kind == ReleasePackageKind.portable) {
      await Process.start('explorer.exe', ['/select,$path'], mode: ProcessStartMode.detached);
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const LocalizedText('运行安装程序？'),
        content: const LocalizedText('即将启动你刚下载的安装包。请确认文件来自 MoePureKit 官方 GitHub Release；Windows 可能会显示 UAC 或 SmartScreen 提示。',
            style: TextStyle(height: 1.45)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const LocalizedText('取消')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const LocalizedText('运行安装程序')),
        ],
      ),
    );
    if (confirmed != true) return;
    if (path.toLowerCase().endsWith('.msi')) {
      await Process.start('msiexec.exe', ['/i', path], mode: ProcessStartMode.detached);
    } else {
      await Process.start(path, [], mode: ProcessStartMode.detached);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasUpdate = _release != null && _updater.isNewer(_release!.version, AppConstants.version);
    final hasPackages = _release?.downloadableAssets.isNotEmpty ?? false;
    final progress = _downloadTotal > 0
        ? (_downloadReceived / _downloadTotal).clamp(0.0, 1.0)
        : null;
    return _PageScroll(child: Center(child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 560), child: _InfoCard(child: Column(mainAxisSize: MainAxisSize.min, children: [
        const _AppMark(), const SizedBox(height: 16),
        const LocalizedText(AppConstants.appName, textAlign: TextAlign.center, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8), const LocalizedText('轻量、朴素的 Windows 常用工具箱。', style: TextStyle(fontSize: 12, color: Color(0xFF7F877F))),
        const SizedBox(height: 20),
        const _AboutLine(label: '作者', value: AppConstants.author),
        const _AboutLine(label: '版本', value: AppConstants.version),
        const _AboutLine(label: '平台', value: 'Windows 桌面'),
        const _AboutLine(label: '许可', value: 'GNU GPL-3.0-only'),
        const _AboutLine(label: '版权', value: '© 2026 Coloryi-MIAO'),
        const SizedBox(height: 16),
        Container(width: double.infinity, padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(.45), borderRadius: BorderRadius.circular(12)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [const Icon(Icons.system_update_alt, size: 18), const SizedBox(width: 8), const Expanded(child: LocalizedText('更新监测', style: TextStyle(fontWeight: FontWeight.w600))), if (hasUpdate) const Chip(label: LocalizedText('有更新', style: TextStyle(fontSize: 11)), visualDensity: VisualDensity.compact)]),
          const SizedBox(height: 8), LocalizedText(_status, style: Theme.of(context).textTheme.bodySmall),
          if (hasUpdate) ...[const SizedBox(height: 6), LocalizedText(_release!.name, style: const TextStyle(fontWeight: FontWeight.w600)), if (_release!.notes.isNotEmpty) LocalizedText(_release!.notes, maxLines: 4, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall)],
          const SizedBox(height: 10), Wrap(spacing: 8, runSpacing: 8, children: [
            OutlinedButton.icon(onPressed: _checking ? null : () => _check(), icon: _checking ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.refresh, size: 16), label: const LocalizedText('检查更新')),
            if (hasPackages) FilledButton.icon(onPressed: _downloading ? null : _chooseAndDownload, icon: const Icon(Icons.download, size: 16), label: LocalizedText(hasUpdate ? '下载更新' : '下载此发布版')),
            TextButton(onPressed: () => launchUrl(Uri.parse(UpdateService.releasesUrl)), child: const LocalizedText('GitHub 发布页')),
          ]),
          if (_downloadStatus != null) ...[
            const SizedBox(height: 12),
            LocalizedText(_downloadStatus!, style: TextStyle(fontSize: 11, color: _downloadError == null ? null : Theme.of(context).colorScheme.error, height: 1.4)),
            if (_downloading) ...[
              const SizedBox(height: 7),
              LinearProgressIndicator(value: progress),
              const SizedBox(height: 4),
              Row(children: [
                Expanded(child: LocalizedText(_downloadTotal > 0 ? '${(progress! * 100).toStringAsFixed(1)}% · ${_formatSize(_downloadReceived)} / ${_formatSize(_downloadTotal)}' : _formatSize(_downloadReceived), style: const TextStyle(fontSize: 10))),
                TextButton(onPressed: _cancelDownload, child: const LocalizedText('取消下载')),
              ]),
            ],
            if (_downloadedPath != null && !_downloading)
              Align(alignment: Alignment.centerLeft, child: Wrap(spacing: 8, children: [
                FilledButton.tonalIcon(onPressed: _openDownloadedFile, icon: Icon(_downloadedAsset?.kind == ReleasePackageKind.portable ? Icons.folder_open : Icons.play_arrow), label: LocalizedText(_downloadedAsset?.kind == ReleasePackageKind.portable ? '在文件夹中显示' : '运行安装程序')),
                TextButton(onPressed: () => Clipboard.setData(ClipboardData(text: _downloadedPath!)), child: const LocalizedText('复制文件路径')),
              ])),
          ],
          const SizedBox(height: 8), const LocalizedText('进入关于页面时自动检查，应用运行期间每 6 小时检查一次。支持在应用内流式下载 Windows 便携版或安装版；不会自动运行安装程序。', style: TextStyle(fontSize: 10, height: 1.4)),
        ])),
        const SizedBox(height: 14), const LocalizedText('下载资源由用户配置并自行校验。第三方依赖与资源遵循各自许可。', textAlign: TextAlign.center, style: TextStyle(fontSize: 11, height: 1.6, color: Color(0xFF858C86))),
      ])),
    )));
  }
}

class _AboutLine extends StatelessWidget {
  const _AboutLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 7),
    child: Row(
      children: [
        SizedBox(
          width: 92,
          child: LocalizedText(
            label,
            style: const TextStyle(fontSize: 12, color: Color(0xFF8A908A)),
          ),
        ),
        Expanded(
          child: LocalizedText(value, style: const TextStyle(fontSize: 12)),
        ),
      ],
    ),
  );
}

class _PageScroll extends StatelessWidget {
  const _PageScroll({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      key: const ValueKey('page-scroll'),
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 28),
      child: child,
    );
  }
}

class _SectionIntro extends StatelessWidget {
  const _SectionIntro({
    required this.eyebrow,
    required this.title,
    required this.subtitle,
    this.trailing,
  });

  final String eyebrow;
  final String title;
  final String subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return FadeIn(
      duration: const Duration(milliseconds: 190),
      offset: 3,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LocalizedText(
                  eyebrow,
                  style: const TextStyle(
                    fontSize: 9,
                    letterSpacing: 1.4,
                    color: Color(0xFF8B938C),
                  ),
                ),
                const SizedBox(height: 7),
                LocalizedText(
                  title,
                  style: const TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 7),
                LocalizedText(
                  subtitle,
                  style: const TextStyle(fontSize: 11, color: Color(0xFF838A84)),
                ),
              ],
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 12), trailing!],
        ],
      ),
    );
  }
}

class _InfoCard extends StatefulWidget {
  const _InfoCard({required this.child, this.onTap});

  final Widget child;
  final VoidCallback? onTap;

  @override
  State<_InfoCard> createState() => _InfoCardState();
}

class _InfoCardState extends State<_InfoCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final motionEnabled = MotionSettings.enabledOf(context) && !reduceMotion;
    return FadeIn(
      duration: const Duration(milliseconds: 210),
      offset: 5,
      child: MouseRegion(
        onEnter: (_) {
          if (!_hovered) setState(() => _hovered = true);
        },
        onExit: (_) {
          if (_hovered) setState(() => _hovered = false);
        },
        child: AnimatedContainer(
          duration: motionEnabled
              ? const Duration(milliseconds: 180)
              : Duration.zero,
          curve: Curves.easeOutCubic,
          transform: Matrix4.translationValues(0, _hovered ? -1.5 : 0, 0),
          child: Card(
            elevation: _hovered ? 2 : null,
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: widget.onTap,
              hoverColor: Theme.of(context).colorScheme.primary.withValues(alpha: .035),
              splashColor: Theme.of(context).colorScheme.primary.withValues(alpha: .07),
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: widget.child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.label,
    required this.value,
    this.compact = false,
  });

  final String label;
  final String value;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: _InfoCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LocalizedText(
              label,
              style: const TextStyle(fontSize: 10, color: Color(0xFF858C86)),
            ),
            const SizedBox(height: 8),
            LocalizedText(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: compact ? 12 : 21,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.action,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: const Color(0xFF819385), size: 24),
        const SizedBox(height: 12),
        LocalizedText(
          title,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        LocalizedText(
          subtitle,
          style: const TextStyle(
            fontSize: 11,
            height: 1.6,
            color: Color(0xFF838A84),
          ),
        ),
        if (action != null) ...[const SizedBox(height: 8), action!],
      ],
    );
  }
}

class _DropdownField<T> extends StatelessWidget {
  const _DropdownField({
    required this.label,
    required this.value,
    required this.values,
    required this.onChanged,
  });

  final String label;
  final T value;
  final List<T> values;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 190,
      child: DropdownButtonFormField<T>(
        initialValue: value,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: translateText(context, label),
          border: const OutlineInputBorder(),
          isDense: true,
        ),
        items: values
            .map(
              (item) => DropdownMenuItem<T>(
                value: item,
                child: LocalizedText(item.toString()),
              ),
            )
            .toList(),
        onChanged: (value) {
          if (value != null) onChanged(value);
        },
      ),
    );
  }
}

String _shortError(Object error) {
  final text = error.toString();
  return text.length > 130 ? '${text.substring(0, 127)}…' : text;
}

bool _isHttpUrl(String value) {
  final uri = Uri.tryParse(value.trim());
  return uri != null &&
      const {'http', 'https'}.contains(uri.scheme.toLowerCase());
}

String _taskStatus(BuildContext context, String status) {
  final isEnglish = Localizations.localeOf(context).languageCode == 'en';
  switch (status) {
    case 'active':
      return isEnglish ? 'Downloading' : '下载中';
    case 'waiting':
      return isEnglish ? 'Waiting' : '等待中';
    case 'paused':
      return isEnglish ? 'Paused' : '已暂停';
    case 'complete':
      return isEnglish ? 'Complete' : '已完成';
    case 'error':
      return isEnglish ? 'Failed' : '失败';
    case 'removed':
      return isEnglish ? 'Removed' : '已移除';
    default:
      return status;
  }
}

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
}

String _formatDuration(BuildContext context, int seconds) {
  if (seconds <= 0) return '--';
  final duration = Duration(seconds: seconds);
  final isEnglish = Localizations.localeOf(context).languageCode == 'en';
  if (duration.inHours > 0) {
    return isEnglish
        ? '${duration.inHours}h ${duration.inMinutes.remainder(60)}m'
        : '${duration.inHours}小时${duration.inMinutes.remainder(60)}分';
  }
  if (duration.inMinutes > 0) {
    return isEnglish
        ? '${duration.inMinutes}m ${duration.inSeconds.remainder(60)}s'
        : '${duration.inMinutes}分${duration.inSeconds.remainder(60)}秒';
  }
  return isEnglish ? '${duration.inSeconds}s' : '${duration.inSeconds}秒';
}
