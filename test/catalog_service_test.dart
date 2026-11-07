import 'package:flutter_test/flutter_test.dart';
import 'package:moepurekit/services/catalog_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('stores and loads a configurable resource catalog', () async {
    SharedPreferences.setMockInitialValues({});
    final service = CatalogService();
    await service.saveSystem('''
      [
        {
          "title": "Sample OS",
          "version": "1.0",
          "size": "2 GB",
          "sha256": "${List.filled(64, 'a').join()}",
          "url": "https://example.com/image.iso",
          "category": "System",
          "description": "Example entry"
        }
      ]
    ''');

    final items = await service.loadSystem();
    expect(items, hasLength(1));
    expect(items.single.title, 'Sample OS');
    expect(items.single.version, '1.0');
    expect(items.single.sha256, hasLength(64));
  });

  test('rejects invalid URLs and checksums', () async {
    SharedPreferences.setMockInitialValues({});
    final service = CatalogService();

    await expectLater(
      service.saveSoftware('[{"title":"Bad URL","url":"file:///tmp/app.exe"}]'),
      throwsA(isA<FormatException>()),
    );
    await expectLater(
      service.saveSoftware(
        '[{"title":"Bad hash","url":"https://example.com/app.exe","sha256":"abc"}]',
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test('loads the configured bundled app catalog', () async {
    SharedPreferences.setMockInitialValues({});
    final items = await CatalogService().loadSoftware();
    expect(items, isNotEmpty);
    expect(items.any((item) => item.title == 'Notepad++'), isTrue);
    expect(items.any((item) => item.category == '通讯与社交'), isTrue);
  });

  test('loads ISO resources from assets/iso.json', () async {
    SharedPreferences.setMockInitialValues({});
    final items = await CatalogService().loadSystem();

    expect(items, isNotEmpty);
    expect(items.any((item) => item.category == 'Windows 11 23H2'), isTrue);
    expect(items.any((item) => item.url.startsWith('magnet:')), isTrue);
    expect(items.any((item) => item.url.startsWith('ed2k:')), isTrue);
    expect(
      items
          .where((item) => item.sha256.isNotEmpty)
          .every((item) => item.sha256.length == 64),
      isTrue,
    );
  });
}
