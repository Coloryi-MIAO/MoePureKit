import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_settings.dart';

class SettingsService {
  static const _prefix = 'moepurekit.';

  Future<AppSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    final rawMode = prefs.getString('${_prefix}background') ?? 'white';
    final mode = BackgroundMode.values.firstWhere(
      (value) => value.name == rawMode,
      orElse: () => BackgroundMode.white,
    );
    final languageMode = AppLanguageMode.values.firstWhere(
      (value) =>
          value.name == (prefs.getString('${_prefix}language') ?? 'system'),
      orElse: () => AppLanguageMode.system,
    );
    final themeMode = AppThemeMode.values.firstWhere(
      (value) => value.name == (prefs.getString('${_prefix}theme') ?? 'system'),
      orElse: () => AppThemeMode.system,
    );
    final aria2RpcUrl =
        prefs.getString('${_prefix}aria2RpcUrl') ??
        'http://127.0.0.1:6800/jsonrpc';
    var aria2RpcSecret = prefs.getString('${_prefix}aria2RpcSecret') ?? '';
    if (aria2RpcSecret.isEmpty && _isLocalRpcUrl(aria2RpcUrl)) {
      aria2RpcSecret = _newRpcSecret();
      if (!await prefs.setString('${_prefix}aria2RpcSecret', aria2RpcSecret)) {
        throw StateError('无法保存本机 aria2 RPC 密钥');
      }
    }
    return AppSettings(
      backgroundMode: mode,
      downloadDirectory: prefs.getString('${_prefix}downloadDirectory') ?? '',
      concurrentDownloads: prefs.getInt('${_prefix}concurrentDownloads') ?? 5,
      proxy: prefs.getString('${_prefix}proxy') ?? '',
      defaultUserAgent: prefs.getString('${_prefix}userAgent') ?? '',
      defaultReferer: prefs.getString('${_prefix}referer') ?? '',
      defaultCookie: prefs.getString('${_prefix}cookie') ?? '',
      defaultHeaders: prefs.getString('${_prefix}headers') ?? '',
      aria2RpcUrl: aria2RpcUrl,
      aria2RpcSecret: aria2RpcSecret,
      animationsEnabled: prefs.getBool('${_prefix}animations') ?? true,
      languageMode: languageMode,
      themeMode: themeMode,
      downloadDirectoryPrompted:
          prefs.getBool('${_prefix}downloadDirectoryPrompted') ?? false,
      minimizeToTrayOnClose:
          prefs.getBool('${_prefix}minimizeToTrayOnCloseBeta15') ?? false,
      suppressCloseConfirmation:
          prefs.getBool('${_prefix}suppressCloseConfirmationBeta19') ?? false,
      launchAtStartup: prefs.getBool('${_prefix}launchAtStartup') ?? false,
    );
  }

  bool _isLocalRpcUrl(String value) {
    final uri = Uri.tryParse(value);
    return uri != null &&
        uri.scheme == 'http' &&
        const {'127.0.0.1', 'localhost', '::1'}.contains(uri.host);
  }

  String _newRpcSecret() {
    final random = Random.secure();
    return List.generate(
      32,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }

  Future<void> save(AppSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await Future.wait([
      prefs.setString('${_prefix}background', settings.backgroundMode.name),
      prefs.setString(
        '${_prefix}downloadDirectory',
        settings.downloadDirectory,
      ),
      prefs.setInt(
        '${_prefix}concurrentDownloads',
        settings.concurrentDownloads,
      ),
      prefs.setString('${_prefix}proxy', settings.proxy),
      prefs.setString('${_prefix}userAgent', settings.defaultUserAgent),
      prefs.setString('${_prefix}referer', settings.defaultReferer),
      prefs.setString('${_prefix}cookie', settings.defaultCookie),
      prefs.setString('${_prefix}headers', settings.defaultHeaders),
      prefs.setString('${_prefix}aria2RpcUrl', settings.aria2RpcUrl),
      prefs.setString('${_prefix}aria2RpcSecret', settings.aria2RpcSecret),
      prefs.setBool('${_prefix}animations', settings.animationsEnabled),
      prefs.setString('${_prefix}language', settings.languageMode.name),
      prefs.setString('${_prefix}theme', settings.themeMode.name),
      prefs.setBool(
        '${_prefix}downloadDirectoryPrompted',
        settings.downloadDirectoryPrompted,
      ),
      prefs.setBool(
        '${_prefix}minimizeToTrayOnCloseBeta15',
        settings.minimizeToTrayOnClose,
      ),
      prefs.setBool(
        '${_prefix}suppressCloseConfirmationBeta19',
        settings.suppressCloseConfirmation,
      ),
      prefs.setBool('${_prefix}launchAtStartup', settings.launchAtStartup),
    ]);
  }
}
