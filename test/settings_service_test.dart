import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:moepurekit/services/settings_service.dart';

void main() {
  test(
    'generates and persists a secret for the bundled local RPC engine',
    () async {
      SharedPreferences.setMockInitialValues({});
      final service = SettingsService();

      final settings = await service.load();
      final reloaded = await service.load();

      expect(settings.aria2RpcSecret, hasLength(64));
      expect(settings.aria2RpcSecret, matches(RegExp(r'^[a-f0-9]{64}$')));
      expect(reloaded.aria2RpcSecret, settings.aria2RpcSecret);
    },
  );

  test(
    'does not inject a local RPC secret for a remote configured endpoint',
    () async {
      SharedPreferences.setMockInitialValues({
        'moepurekit.aria2RpcUrl': 'https://downloads.example.com/jsonrpc',
      });

      final settings = await SettingsService().load();

      expect(settings.aria2RpcSecret, isEmpty);
    },
  );

  test('persists startup and close-confirmation preferences', () async {
    SharedPreferences.setMockInitialValues({});
    final service = SettingsService();

    final defaults = await service.load();
    expect(defaults.launchAtStartup, isFalse);
    expect(defaults.suppressCloseConfirmation, isFalse);

    await service.save(
      defaults.copyWith(launchAtStartup: true, suppressCloseConfirmation: true),
    );
    final reloaded = await service.load();
    expect(reloaded.launchAtStartup, isTrue);
    expect(reloaded.suppressCloseConfirmation, isTrue);
  });
}
