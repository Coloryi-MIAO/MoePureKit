import 'dart:io';

import 'package:flutter/services.dart';

class StartupService {
  static const _channel = MethodChannel('moepurekit/system');

  Future<bool> isEnabled() async {
    if (!Platform.isWindows) return false;
    return await _channel.invokeMethod<bool>('getAutostart') ?? false;
  }

  Future<void> setEnabled(bool enabled) async {
    if (!Platform.isWindows) {
      throw UnsupportedError('开机自启仅支持 Windows');
    }
    await _channel.invokeMethod<void>('setAutostart', enabled);
  }
}
