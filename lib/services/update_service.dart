import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:http/http.dart' as http;

/// The kind of Windows package advertised by a GitHub Release asset.
enum ReleasePackageKind { portable, installer, other }

class ReleaseAsset {
  const ReleaseAsset({
    required this.name,
    required this.downloadUrl,
    required this.size,
    required this.kind,
    this.contentType,
    this.digest,
  });

  final String name;
  final String downloadUrl;
  final int size;
  final ReleasePackageKind kind;
  final String? contentType;
  final String? digest;

  String get kindLabel => switch (kind) {
        ReleasePackageKind.portable => '便携版',
        ReleasePackageKind.installer => '安装版',
        ReleasePackageKind.other => '其他格式',
      };

  static ReleasePackageKind classify(String name) {
    final value = name.toLowerCase();
    if (RegExp(r'(^|[._ -])(portable|no[-_ ]?install|standalone|便携)([._ -]|$)')
        .hasMatch(value)) {
      return ReleasePackageKind.portable;
    }
    if (value.endsWith('.zip') || value.endsWith('.7z') || value.endsWith('.rar')) {
      return ReleasePackageKind.portable;
    }
    if (value.endsWith('.msi') ||
        RegExp(r'(setup|installer|install|安装)').hasMatch(value)) {
      return ReleasePackageKind.installer;
    }
    if (value.endsWith('.exe')) return ReleasePackageKind.portable;
    return ReleasePackageKind.other;
  }

  bool get isWindowsPackage {
    final value = name.toLowerCase();
    if (value.contains('source code') || value.endsWith('.sha256') ||
        value.endsWith('.sha256sum') || value.endsWith('.txt') ||
        value.endsWith('.json')) return false;
    final knownPackage = value.endsWith('.exe') || value.endsWith('.msi') ||
        value.endsWith('.zip') || value.endsWith('.7z') || value.endsWith('.rar');
    if (!knownPackage) return false;
    // Exclude explicitly non-Windows builds while accepting generic assets
    // whose names do not declare a target platform.
    final nonWindows = RegExp(r'(^|[._ -])(linux|macos|mac|darwin|android|ios)([._ -]|$)')
        .hasMatch(value);
    return !nonWindows;
  }
}

class AppRelease {
  const AppRelease({
    required this.tag,
    required this.name,
    required this.notes,
    required this.url,
    required this.assets,
  });

  final String tag;
  final String name;
  final String notes;
  final String url;
  final List<ReleaseAsset> assets;

  String get version => tag.replaceFirst(RegExp(r'^v'), '');

  List<ReleaseAsset> get downloadableAssets => assets
      .where((asset) => asset.isWindowsPackage && asset.kind != ReleasePackageKind.other)
      .toList(growable: false);
}

class UpdateService {
  static const repository = 'Coloryi-MIAO/MoePureKit';
  static const releasesUrl = 'https://github.com/$repository/releases/latest';
  static const apiUrl = 'https://api.github.com/repos/$repository/releases/latest';

  Future<AppRelease> checkLatest() async {
    final response = await http.get(
      Uri.parse(apiUrl),
      headers: const {
        'Accept': 'application/vnd.github+json',
        'User-Agent': 'MoePureKit-Updater',
      },
    ).timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) {
      throw HttpException('GitHub HTTP ${response.statusCode}');
    }
    final data = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    final tag = data['tag_name'] as String?;
    final url = data['html_url'] as String?;
    if (tag == null || url == null) {
      throw const FormatException('Release 信息不完整');
    }
    final rawAssets = data['assets'] as List<dynamic>? ?? const <dynamic>[];
    final assets = rawAssets.map((raw) {
      final item = raw as Map<String, dynamic>;
      final name = item['name'] as String? ?? '';
      return ReleaseAsset(
        name: name,
        downloadUrl: item['browser_download_url'] as String? ?? '',
        size: item['size'] as int? ?? 0,
        kind: ReleaseAsset.classify(name),
        contentType: item['content_type'] as String?,
        digest: item['digest'] as String?,
      );
    }).where((asset) => asset.name.isNotEmpty && asset.downloadUrl.isNotEmpty)
        .toList(growable: false);
    return AppRelease(
      tag: tag,
      name: data['name'] as String? ?? tag,
      notes: data['body'] as String? ?? '',
      url: url,
      assets: assets,
    );
  }

  bool isNewer(String latest, String current) {
    List<int> nums(String value) => RegExp(r'\d+')
        .allMatches(value)
        .take(3)
        .map((match) => int.parse(match.group(0)!))
        .toList();
    final a = nums(latest), b = nums(current);
    for (var i = 0; i < 3; i++) {
      final x = i < a.length ? a[i] : 0;
      final y = i < b.length ? b[i] : 0;
      if (x != y) return x > y;
    }
    final ap = RegExp(r'(?:beta|rc)[.-]?(\d+)', caseSensitive: false).firstMatch(latest);
    final bp = RegExp(r'(?:beta|rc)[.-]?(\d+)', caseSensitive: false).firstMatch(current);
    if (ap == null && bp != null) return true;
    if (ap != null && bp == null) return false;
    return (int.tryParse(ap?.group(1) ?? '') ?? 0) >
        (int.tryParse(bp?.group(1) ?? '') ?? 0);
  }
}

/// One cancellable, disk-streamed update transfer. It never buffers the whole
/// installer/archive in memory and writes to a .part file until verified.
class UpdateDownload {
  final http.Client _client = http.Client();
  bool _cancelled = false;

  void cancel() {
    _cancelled = true;
    _client.close();
  }

  Future<File> download(
    ReleaseAsset asset,
    String destinationPath, {
    required void Function(int received, int total) onProgress,
  }) async {
    final destination = File(destinationPath);
    final partial = File('$destinationPath.part');
    IOSink? sink;
    try {
      if (await destination.exists()) {
        throw FileSystemException('目标文件已存在', destination.path);
      }
      if (await partial.exists()) await partial.delete();

      final request = http.Request('GET', Uri.parse(asset.downloadUrl));
      request.headers['User-Agent'] = 'MoePureKit-Updater';
      request.headers['Accept'] = 'application/octet-stream';
      final response = await _client.send(request).timeout(const Duration(seconds: 30));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException('Download HTTP ${response.statusCode}');
      }

      final total = response.contentLength ?? asset.size;
      var received = 0;
      sink = partial.openWrite();
      onProgress(0, total);
      await for (final chunk in response.stream.timeout(const Duration(minutes: 2))) {
        if (_cancelled) throw const UpdateDownloadCancelled();
        sink.add(chunk);
        received += chunk.length;
        onProgress(received, total);
      }
      if (_cancelled) throw const UpdateDownloadCancelled();
      await sink.flush();
      await sink.close();
      sink = null;
      final actualDigest = (await crypto.sha256.bind(partial.openRead()).first).toString();
      final expectedDigest = asset.digest?.replaceFirst(RegExp(r'^sha256:'), '').toLowerCase();
      if (expectedDigest != null && expectedDigest.isNotEmpty &&
          expectedDigest != actualDigest) {
        throw const UpdateIntegrityException();
      }
      await partial.rename(destination.path);
      return destination;
    } catch (error) {
      try {
        await sink?.close();
      } catch (_) {}
      try {
        if (await partial.exists()) await partial.delete();
      } catch (_) {}
      if (_cancelled && error is! UpdateDownloadCancelled) {
        throw const UpdateDownloadCancelled();
      }
      rethrow;
    } finally {
      _client.close();
    }
  }
}

class UpdateDownloadCancelled implements Exception {
  const UpdateDownloadCancelled();
  @override
  String toString() => 'Download cancelled';
}

class UpdateIntegrityException implements Exception {
  const UpdateIntegrityException();
  @override
  String toString() => 'SHA-256 verification failed';
}
