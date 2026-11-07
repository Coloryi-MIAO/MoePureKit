import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:moepurekit/services/file_hash_service.dart';

void main() {
  test(
    'computes SHA-256 without loading the complete file into memory',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'moepurekit-hash-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}${Platform.pathSeparator}sample.txt');
      await file.writeAsString('hello');

      expect(
        await computeFileSha256(file.path),
        '2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824',
      );
    },
  );

  test('reports missing files instead of returning an empty hash', () async {
    final missingPath = [
      Directory.systemTemp.path,
      'moepurekit-missing-${DateTime.now().microsecondsSinceEpoch}',
    ].join(Platform.pathSeparator);

    expect(computeFileSha256(missingPath), throwsA(isA<FileSystemException>()));
  });
  test('supports MD5 for compatibility checks', () async {
    final directory = await Directory.systemTemp.createTemp(
      'moepurekit-hash-md5-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}${Platform.pathSeparator}sample.txt');
    await file.writeAsString('hello');

    final result = await computeFileHash(file.path, algorithm: 'MD5');
    expect(result.digest, '5d41402abc4b2a76b9719d911017c592');
    expect(result.algorithm, 'MD5');
  });

  test('supports additional algorithms and reports streamed progress', () async {
    final directory = await Directory.systemTemp.createTemp(
      'moepurekit-hash-algorithms-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}${Platform.pathSeparator}sample.txt');
    await file.writeAsString('hello');

    var lastProcessed = 0;
    final result = await computeFileHash(
      file.path,
      algorithm: 'SHA-512',
      onProgress: (processed, total) {
        expect(total, 5);
        expect(processed, greaterThanOrEqualTo(lastProcessed));
        lastProcessed = processed;
      },
    );

    expect(result.algorithm, 'SHA-512');
    expect(result.bytesProcessed, 5);
    expect(
      result.digest,
      '9b71d224bd62f3785d96d46ad3ea3d73319bfbc2890caadae2dff72519673ca72323c3d99ba5c11d7c7acc6e14b8c5da0c4663475c2e5c3adef46f73bcdec043',
    );
    expect(lastProcessed, 5);
  });

}
