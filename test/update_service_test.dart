import 'package:flutter_test/flutter_test.dart';
import 'package:moepurekit/services/update_service.dart';

void main() {
  group('ReleaseAsset.classify', () {
    test('recognizes portable archives', () {
      expect(ReleaseAsset.classify('MoePureKit-win-x64-portable.zip'),
          ReleasePackageKind.portable);
    });

    test('recognizes installer packages', () {
      expect(ReleaseAsset.classify('MoePureKit-Setup-x64.exe'),
          ReleasePackageKind.installer);
      expect(ReleaseAsset.classify('MoePureKit-x64.msi'),
          ReleasePackageKind.installer);
    });

    test('treats an unlabelled standalone exe as portable', () {
      expect(ReleaseAsset.classify('MoePureKit.exe'),
          ReleasePackageKind.portable);
    });

    test('does not classify GitHub source archives as Windows packages', () {
      final source = ReleaseAsset(
        name: 'Source code (zip)',
        downloadUrl: 'https://example.invalid/source.zip',
        size: 1,
        kind: ReleaseAsset.classify('Source code (zip)'),
      );
      expect(source.isWindowsPackage, isFalse);
    });

    test('filters explicitly non-Windows assets', () {
      final linux = ReleaseAsset(
        name: 'MoePureKit-linux-x64.zip',
        downloadUrl: 'https://example.invalid/linux.zip',
        size: 1,
        kind: ReleaseAsset.classify('MoePureKit-linux-x64.zip'),
      );
      expect(linux.isWindowsPackage, isFalse);
    });
  });

  group('UpdateService.isNewer', () {
    final service = UpdateService();

    test('compares beta numbers', () {
      expect(service.isNewer('0.3.5-beta.22', '0.3.5-beta.21'), isTrue);
      expect(service.isNewer('0.3.5-beta.19', '0.3.5-beta.20'), isFalse);
    });

    test('stable is newer than a beta with the same numeric version', () {
      expect(service.isNewer('0.3.5', '0.3.5-beta.21'), isTrue);
    });
  });
}
