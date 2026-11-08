enum BackgroundMode { white, mica, bingMica, catgirl }

enum AppLanguageMode { system, chinese, english }

enum AppThemeMode { system, light, dark }

class AppSettings {
  const AppSettings({
    this.backgroundMode = BackgroundMode.white,
    this.catgirlWallpaperIndex = 0,
    this.downloadDirectory = '',
    this.concurrentDownloads = 5,
    this.proxy = '',
    this.defaultUserAgent = '',
    this.defaultReferer = '',
    this.defaultCookie = '',
    this.defaultHeaders = '',
    this.aria2RpcUrl = 'http://127.0.0.1:6800/jsonrpc',
    this.aria2RpcSecret = '',
    this.animationsEnabled = true,
    this.languageMode = AppLanguageMode.system,
    this.themeMode = AppThemeMode.system,
    this.downloadDirectoryPrompted = false,
    this.minimizeToTrayOnClose = false,
    this.suppressCloseConfirmation = false,
    this.launchAtStartup = false,
  });

  final BackgroundMode backgroundMode;
  final int catgirlWallpaperIndex;
  final String downloadDirectory;
  final int concurrentDownloads;
  final String proxy;
  final String defaultUserAgent;
  final String defaultReferer;
  final String defaultCookie;
  final String defaultHeaders;
  final String aria2RpcUrl;
  final String aria2RpcSecret;
  final bool animationsEnabled;
  final AppLanguageMode languageMode;
  final AppThemeMode themeMode;
  final bool downloadDirectoryPrompted;
  final bool minimizeToTrayOnClose;
  final bool suppressCloseConfirmation;
  final bool launchAtStartup;

  AppSettings copyWith({
    BackgroundMode? backgroundMode,
    int? catgirlWallpaperIndex,
    String? downloadDirectory,
    int? concurrentDownloads,
    String? proxy,
    String? defaultUserAgent,
    String? defaultReferer,
    String? defaultCookie,
    String? defaultHeaders,
    String? aria2RpcUrl,
    String? aria2RpcSecret,
    bool? animationsEnabled,
    AppLanguageMode? languageMode,
    AppThemeMode? themeMode,
    bool? downloadDirectoryPrompted,
    bool? minimizeToTrayOnClose,
    bool? suppressCloseConfirmation,
    bool? launchAtStartup,
  }) {
    return AppSettings(
      backgroundMode: backgroundMode ?? this.backgroundMode,
      catgirlWallpaperIndex: catgirlWallpaperIndex ?? this.catgirlWallpaperIndex,
      downloadDirectory: downloadDirectory ?? this.downloadDirectory,
      concurrentDownloads: concurrentDownloads ?? this.concurrentDownloads,
      proxy: proxy ?? this.proxy,
      defaultUserAgent: defaultUserAgent ?? this.defaultUserAgent,
      defaultReferer: defaultReferer ?? this.defaultReferer,
      defaultCookie: defaultCookie ?? this.defaultCookie,
      defaultHeaders: defaultHeaders ?? this.defaultHeaders,
      aria2RpcUrl: aria2RpcUrl ?? this.aria2RpcUrl,
      aria2RpcSecret: aria2RpcSecret ?? this.aria2RpcSecret,
      animationsEnabled: animationsEnabled ?? this.animationsEnabled,
      languageMode: languageMode ?? this.languageMode,
      themeMode: themeMode ?? this.themeMode,
      downloadDirectoryPrompted:
          downloadDirectoryPrompted ?? this.downloadDirectoryPrompted,
      minimizeToTrayOnClose:
          minimizeToTrayOnClose ?? this.minimizeToTrayOnClose,
      suppressCloseConfirmation:
          suppressCloseConfirmation ?? this.suppressCloseConfirmation,
      launchAtStartup: launchAtStartup ?? this.launchAtStartup,
    );
  }
}
