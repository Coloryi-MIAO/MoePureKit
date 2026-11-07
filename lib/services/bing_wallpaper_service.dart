import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

class BingWallpaperInfo {
  const BingWallpaperInfo({
    required this.localPath,
    required this.imageUrl,
    required this.title,
    required this.copyright,
    required this.copyrightLink,
    required this.startDate,
    required this.cacheDate,
    this.isStale = false,
    this.isCached = false,
  });

  final String localPath;
  final String imageUrl;
  final String title;
  final String copyright;
  final String copyrightLink;
  final String startDate;
  final String cacheDate;
  final bool isStale;
  final bool isCached;

  BingWallpaperInfo copyWith({bool? isStale, bool? isCached}) {
    return BingWallpaperInfo(
      localPath: localPath,
      imageUrl: imageUrl,
      title: title,
      copyright: copyright,
      copyrightLink: copyrightLink,
      startDate: startDate,
      cacheDate: cacheDate,
      isStale: isStale ?? this.isStale,
      isCached: isCached ?? this.isCached,
    );
  }

  Map<String, Object?> toJson() => {
    'localPath': localPath,
    'imageUrl': imageUrl,
    'title': title,
    'copyright': copyright,
    'copyrightLink': copyrightLink,
    'startDate': startDate,
    'cacheDate': cacheDate,
  };

  static BingWallpaperInfo? fromJson(Map<String, dynamic> json) {
    final localPath = json['localPath'] as String?;
    final imageUrl = json['imageUrl'] as String?;
    if (localPath == null || imageUrl == null) return null;
    return BingWallpaperInfo(
      localPath: localPath,
      imageUrl: imageUrl,
      title: json['title'] as String? ?? 'Bing 每日壁纸',
      copyright: json['copyright'] as String? ?? '',
      copyrightLink: json['copyrightLink'] as String? ?? '',
      startDate: json['startDate'] as String? ?? '',
      cacheDate: json['cacheDate'] as String? ?? '',
      isCached: true,
    );
  }
}

/// Fetches Bing's daily image and keeps a local copy so the app can render it
/// without depending on a live image URL every time it starts.
class BingWallpaperService {
  BingWallpaperService({http.Client? client, Directory? cacheDirectory})
    : _client = client ?? http.Client(),
      _cacheDirectory = cacheDirectory;

  final http.Client _client;
  final Directory? _cacheDirectory;
  static const _metadataFileName = 'bing-wallpaper.json';
  static const _maxImageBytes = 20 * 1024 * 1024;

  Future<BingWallpaperInfo> loadToday({bool forceRefresh = false}) async {
    final localAppData = Platform.environment['LOCALAPPDATA'];
    final cacheRoot = localAppData != null && localAppData.isNotEmpty
        ? localAppData
        : Directory.systemTemp.path;
    final cacheDirectory = _cacheDirectory ??
        Directory(
          '$cacheRoot${Platform.pathSeparator}MoePureKit${Platform.pathSeparator}Cache${Platform.pathSeparator}BingWallpaper',
        );
    final cached = await _readCache(cacheDirectory);
    final today = _dateKey(DateTime.now());

    if (!forceRefresh && cached != null && cached.cacheDate == today) {
      return cached.copyWith(isCached: true);
    }

    try {
      return await _downloadToday(cacheDirectory);
    } catch (_) {
      if (cached != null) return cached.copyWith(isStale: true, isCached: true);
      rethrow;
    }
  }

  Future<BingWallpaperInfo?> _readCache(Directory directory) async {
    try {
      final metadataFile = File(
        '${directory.path}${Platform.pathSeparator}$_metadataFileName',
      );
      if (!await metadataFile.exists()) return null;
      final decoded = jsonDecode(await metadataFile.readAsString());
      if (decoded is! Map<String, dynamic>) return null;
      final info = BingWallpaperInfo.fromJson(decoded);
      if (info == null || !await File(info.localPath).exists()) return null;
      return info;
    } catch (_) {
      return null;
    }
  }

  Future<BingWallpaperInfo> _downloadToday(Directory directory) async {
    await directory.create(recursive: true);
    final archiveUri = Uri.https('www.bing.com', '/HPImageArchive.aspx', {
      'format': 'js',
      'idx': '0',
      'n': '1',
      'mkt': 'zh-CN',
    });
    final archiveResponse = await _client
        .get(
          archiveUri,
          headers: const {'User-Agent': 'MoePureKit/0.3.5'},
        )
        .timeout(const Duration(seconds: 12));
    if (archiveResponse.statusCode != HttpStatus.ok) {
      throw HttpException('Bing 图片信息请求失败：HTTP ${archiveResponse.statusCode}');
    }

    final payload = jsonDecode(archiveResponse.body);
    if (payload is! Map<String, dynamic>) {
      throw const FormatException('Bing 图片信息格式无效');
    }
    final images = payload['images'];
    if (images is! List || images.isEmpty || images.first is! Map) {
      throw const FormatException('Bing 未返回每日壁纸');
    }
    final image = Map<String, dynamic>.from(images.first as Map);
    final rawUrl = image['url'] as String?;
    if (rawUrl == null || rawUrl.trim().isEmpty) {
      throw const FormatException('Bing 壁纸地址为空');
    }
    final imageUri = _normalizeImageUri(rawUrl);
    final imageResponse = await _client
        .get(
          imageUri,
          headers: const {'User-Agent': 'MoePureKit/0.3.5'},
        )
        .timeout(const Duration(seconds: 25));
    if (imageResponse.statusCode != HttpStatus.ok) {
      throw HttpException('Bing 壁纸下载失败：HTTP ${imageResponse.statusCode}');
    }
    final contentType = imageResponse.headers['content-type'] ?? '';
    if (!contentType.toLowerCase().startsWith('image/')) {
      throw const FormatException('Bing 返回内容不是图片');
    }
    final bytes = imageResponse.bodyBytes;
    if (bytes.isEmpty || bytes.length > _maxImageBytes) {
      throw const FormatException('Bing 图片大小无效');
    }

    final startDate = image['startdate'] as String? ?? _dateKey(DateTime.now());
    final target = File(
      '${directory.path}${Platform.pathSeparator}bing-$startDate-${DateTime.now().microsecondsSinceEpoch}.img',
    );
    final temporary = File('${target.path}.download');
    await temporary.writeAsBytes(bytes, flush: true);
    await temporary.rename(target.path);

    final result = BingWallpaperInfo(
      localPath: target.path,
      imageUrl: imageUri.toString(),
      title: image['title'] as String? ?? 'Bing 每日壁纸',
      copyright: image['copyright'] as String? ?? '',
      copyrightLink: image['copyrightlink'] as String? ?? '',
      startDate: startDate,
      cacheDate: _dateKey(DateTime.now()),
    );
    final metadataFile = File(
      '${directory.path}${Platform.pathSeparator}$_metadataFileName',
    );
    final metadataTemporary = File('${metadataFile.path}.new');
    await metadataTemporary.writeAsString(
      jsonEncode(result.toJson()),
      flush: true,
    );
    if (await metadataFile.exists()) await metadataFile.delete();
    await metadataTemporary.rename(metadataFile.path);

    // Keep only the image referenced by the committed metadata so the cache
    // does not grow by one full-resolution wallpaper every day.
    await for (final entry in directory.list(followLinks: false)) {
      if (entry is File &&
          entry.path != target.path &&
          (entry.path.endsWith('.img') || entry.path.endsWith('.download'))) {
        try {
          await entry.delete();
        } catch (_) {
          // A stale cache file must not make the newly downloaded wallpaper fail.
        }
      }
    }
    return result;
  }

  Uri _normalizeImageUri(String value) {
    final uri = Uri.parse(
      value.startsWith('//')
          ? 'https:$value'
          : value.startsWith('http')
          ? value
          : 'https://www.bing.com${value.startsWith('/') ? value : '/$value'}',
    );
    final host = uri.host.toLowerCase();
    final trustedHost = host == 'bing.com' ||
        host.endsWith('.bing.com') ||
        host.endsWith('.bing.net');
    if (uri.scheme != 'https' || !trustedHost) {
      throw const FormatException('Bing 返回了不受信任的图片地址');
    }
    return uri;
  }

  String _dateKey(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}'
      '${date.month.toString().padLeft(2, '0')}'
      '${date.day.toString().padLeft(2, '0')}';

  void close() => _client.close();
}
