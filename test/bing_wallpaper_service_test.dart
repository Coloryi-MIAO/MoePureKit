import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:moepurekit/services/bing_wallpaper_service.dart';

void main() {
  late Directory cacheDirectory;
  late BingWallpaperService service;
  var requestCount = 0;

  setUp(() async {
    cacheDirectory = await Directory.systemTemp.createTemp(
      'moepurekit-bing-test-',
    );
    requestCount = 0;
    final client = MockClient((request) async {
      requestCount++;
      if (request.url.path.endsWith('/HPImageArchive.aspx')) {
        return http.Response(
          jsonEncode({
            'images': [
              {
                'url': '/wallpaper.jpg',
                'startdate': '20261101',
                'title': 'Test landscape',
                'copyright': 'Test photographer',
                'copyrightlink': 'https://www.bing.com/',
              },
            ],
          }),
          HttpStatus.ok,
          headers: const {'content-type': 'application/json'},
        );
      }
      return http.Response.bytes(
        [0xFF, 0xD8, 0xFF, 0xD9],
        HttpStatus.ok,
        headers: const {'content-type': 'image/jpeg'},
      );
    });
    service = BingWallpaperService(
      client: client,
      cacheDirectory: cacheDirectory,
    );
  });

  tearDown(() async {
    service.close();
    if (await cacheDirectory.exists()) {
      await cacheDirectory.delete(recursive: true);
    }
  });

  test('downloads Bing image and reuses local cache', () async {
    final first = await service.loadToday(forceRefresh: true);
    expect(await File(first.localPath).exists(), isTrue);
    expect(first.title, 'Test landscape');
    expect(first.copyright, 'Test photographer');
    expect(requestCount, 2);

    final cached = await service.loadToday();
    expect(cached.localPath, first.localPath);
    expect(cached.isCached, isTrue);
    expect(requestCount, 2);
  });

  test('uses last saved wallpaper when refresh fails', () async {
    final first = await service.loadToday(forceRefresh: true);
    service.close();
    service = BingWallpaperService(
      client: MockClient((request) async => http.Response('offline', 503)),
      cacheDirectory: cacheDirectory,
    );

    final fallback = await service.loadToday(forceRefresh: true);
    expect(fallback.localPath, first.localPath);
    expect(fallback.isStale, isTrue);
    expect(await File(fallback.localPath).exists(), isTrue);
  });
}
