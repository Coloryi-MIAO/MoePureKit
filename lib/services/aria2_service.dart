import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../models/app_settings.dart';
import '../models/download_task.dart';

class Aria2Service {
  Aria2Service(this.settings, {http.Client? client})
    : _client = client ?? http.Client();

  final AppSettings settings;
  final http.Client _client;
  int _requestId = 0;

  Future<dynamic> _rpc(String method, [List<dynamic> params = const []]) async {
    final args = <dynamic>[];
    if (settings.aria2RpcSecret.isNotEmpty) {
      args.add('token:${settings.aria2RpcSecret}');
    }
    args.addAll(params);
    final response = await _client
        .post(
          Uri.parse(settings.aria2RpcUrl),
          headers: const {'content-type': 'application/json'},
          body: jsonEncode({
            'jsonrpc': '2.0',
            'id': '${DateTime.now().microsecondsSinceEpoch}-${_requestId++}',
            'method': method,
            'params': args,
          }),
        )
        .timeout(const Duration(seconds: 8));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException('aria2 RPC HTTP ${response.statusCode}');
    }
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    if (payload['error'] case final Map<String, dynamic> error) {
      throw StateError('aria2: ${error['message'] ?? '未知 RPC 错误'}');
    }
    return payload['result'];
  }

  Map<String, String> _downloadOptions({
    required String directory,
    required String userAgent,
    required String referer,
    required String cookie,
    required String headers,
    required String proxy,
  }) {
    final options = <String, String>{};
    final selectedDirectory = directory.trim().isNotEmpty
        ? directory.trim()
        : settings.downloadDirectory;
    if (selectedDirectory.isNotEmpty) options['dir'] = selectedDirectory;

    final allHeaders = _requestHeaders(
      userAgent: userAgent,
      referer: referer,
      cookie: cookie,
      headers: headers,
    );
    if (allHeaders.isNotEmpty) {
      options['header'] = allHeaders.entries
          .map((entry) => '${entry.key}: ${entry.value}')
          .join('\n');
    }

    final selectedProxy = proxy.trim().isNotEmpty
        ? proxy.trim()
        : settings.proxy.trim();
    if (selectedProxy.isNotEmpty) options['all-proxy'] = selectedProxy;
    options['follow-torrent'] = 'true';
    options['max-connection-per-server'] = '8';
    return options;
  }

  Map<String, String> _requestHeaders({
    required String userAgent,
    required String referer,
    required String cookie,
    required String headers,
  }) {
    final result = <String, String>{};
    final selectedUserAgent = userAgent.trim().isNotEmpty
        ? userAgent.trim()
        : settings.defaultUserAgent.trim();
    final selectedReferer = referer.trim().isNotEmpty
        ? referer.trim()
        : settings.defaultReferer.trim();
    final selectedCookie = cookie.trim().isNotEmpty
        ? cookie.trim()
        : settings.defaultCookie.trim();
    if (selectedUserAgent.isNotEmpty) {
      result['User-Agent'] = selectedUserAgent;
    }
    if (selectedReferer.isNotEmpty) {
      result['Referer'] = selectedReferer;
    }
    if (selectedCookie.isNotEmpty) result['Cookie'] = selectedCookie;

    final rawHeaders = headers.trim().isNotEmpty
        ? headers
        : settings.defaultHeaders;
    for (final line in rawHeaders.split(RegExp(r'[\r\n]+'))) {
      final separator = line.indexOf(':');
      if (separator <= 0) {
        if (line.trim().isNotEmpty) {
          throw const FormatException('自定义 Header 必须使用“名称: 值”格式，每行一项');
        }
        continue;
      }
      final name = line.substring(0, separator).trim();
      final value = line.substring(separator + 1).trim();
      if (name.isEmpty || name.contains(RegExp(r'[\r\n]'))) {
        throw const FormatException('自定义 Header 名称无效');
      }
      result[name] = value;
    }
    if (result.values.any((value) => value.contains(RegExp(r'[\r\n]')))) {
      throw const FormatException('HTTP Header 值不能包含换行符');
    }
    return result;
  }

  Future<String> addUri(
    String uri, {
    String directory = '',
    String userAgent = '',
    String referer = '',
    String cookie = '',
    String headers = '',
    String proxy = '',
  }) async {
    final value = uri.trim();
    final parsed = Uri.tryParse(value);
    if (parsed == null ||
        !parsed.hasScheme ||
        !const {
          'http',
          'https',
          'magnet',
          'ftp',
          'ed2k',
        }.contains(parsed.scheme) ||
        (!const {'magnet', 'ed2k'}.contains(parsed.scheme) &&
            parsed.host.isEmpty) ||
        (parsed.scheme == 'ed2k' &&
            !value.toLowerCase().startsWith('ed2k://|file|')) ||
        (parsed.scheme == 'magnet' &&
            parsed.queryParametersAll['xt']?.any(
                  (value) =>
                      value.startsWith('urn:btih:') ||
                      value.startsWith('urn:btmh:'),
                ) !=
                true)) {
      throw const FormatException('请输入有效的 HTTP、HTTPS、FTP、ed2k 或磁力链接');
    }
    final result = await _rpc('aria2.addUri', [
      [value],
      _downloadOptions(
        directory: directory,
        userAgent: userAgent,
        referer: referer,
        cookie: cookie,
        headers: headers,
        proxy: proxy,
      ),
    ]);
    return result as String;
  }

  Future<String> addTorrent(
    String torrentPath, {
    String directory = '',
    String userAgent = '',
    String referer = '',
    String cookie = '',
    String headers = '',
    String proxy = '',
  }) async {
    final torrentFile = File(torrentPath);
    if (await torrentFile.length() > 10 * 1024 * 1024) {
      throw const FormatException('种子文件超过 10 MB 限制');
    }
    final torrent = await torrentFile.readAsBytes();
    final result = await _rpc('aria2.addTorrent', [
      base64Encode(torrent),
      <String>[],
      _downloadOptions(
        directory: directory,
        userAgent: userAgent,
        referer: referer,
        cookie: cookie,
        headers: headers,
        proxy: proxy,
      ),
    ]);
    return result as String;
  }

  Future<List<String>> addMetalink(
    String source, {
    String directory = '',
    String userAgent = '',
    String referer = '',
    String cookie = '',
    String headers = '',
    String proxy = '',
  }) async {
    final parsed = Uri.tryParse(source.trim());
    final List<int> bytes;
    if (parsed != null &&
        const {'http', 'https'}.contains(parsed.scheme.toLowerCase())) {
      final request = http.Request('GET', parsed)
        ..headers.addAll(
          _requestHeaders(
            userAgent: userAgent,
            referer: referer,
            cookie: cookie,
            headers: headers,
          ),
        );
      final response = await _client
          .send(request)
          .timeout(const Duration(seconds: 30));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException('Metalink 下载失败：HTTP ${response.statusCode}');
      }
      const maxMetalinkSize = 10 * 1024 * 1024;
      if ((response.contentLength ?? 0) > maxMetalinkSize) {
        throw const FormatException('Metalink 文件超过 10 MB 限制');
      }
      final data = BytesBuilder(copy: false);
      await for (final chunk in response.stream.timeout(
        const Duration(seconds: 30),
      )) {
        if (data.length + chunk.length > maxMetalinkSize) {
          throw const FormatException('Metalink 文件超过 10 MB 限制');
        }
        data.add(chunk);
      }
      bytes = data.takeBytes();
    } else {
      final metalinkFile = File(source);
      if (await metalinkFile.length() > 10 * 1024 * 1024) {
        throw const FormatException('Metalink 文件超过 10 MB 限制');
      }
      bytes = await metalinkFile.readAsBytes();
    }
    final result = await _rpc('aria2.addMetalink', [
      base64Encode(bytes),
      _downloadOptions(
        directory: directory,
        userAgent: userAgent,
        referer: referer,
        cookie: cookie,
        headers: headers,
        proxy: proxy,
      ),
    ]) as List<dynamic>;
    return result.cast<String>();
  }

  Future<void> configure() async {
    final options = <String, String>{
      'max-concurrent-downloads': settings.concurrentDownloads
          .clamp(1, 64)
          .toString(),
    };
    if (settings.downloadDirectory.trim().isNotEmpty) {
      options['dir'] = settings.downloadDirectory.trim();
    }
    if (settings.proxy.trim().isNotEmpty) {
      options['all-proxy'] = settings.proxy.trim();
    }
    await _rpc('aria2.changeGlobalOption', [options]);
  }

  Future<List<DownloadTask>> listTasks() async {
    const keys = [
      'gid',
      'status',
      'totalLength',
      'completedLength',
      'downloadSpeed',
      'files',
    ];
    final results = await Future.wait([
      _rpc('aria2.tellActive', [keys]),
      _rpc('aria2.tellWaiting', [0, 100, keys]),
      _rpc('aria2.tellStopped', [0, 100, keys]),
    ]);
    final active = results[0] as List<dynamic>;
    final waiting = results[1] as List<dynamic>;
    final stopped = results[2] as List<dynamic>;
    return [...active, ...waiting, ...stopped]
        .map((task) => DownloadTask.fromAria2(task as Map<String, dynamic>))
        .toList();
  }

  Future<void> pause(String gid) async {
    await _rpc('aria2.pause', [gid]);
  }

  Future<void> resume(String gid) async {
    await _rpc('aria2.unpause', [gid]);
  }

  Future<void> remove(String gid) async {
    final tasks = await listTasks();
    DownloadTask? task;
    for (final candidate in tasks) {
      if (candidate.gid == gid) {
        task = candidate;
        break;
      }
    }
    if (task?.status == 'complete' ||
        task?.status == 'error' ||
        task?.status == 'removed') {
      await _rpc('aria2.removeDownloadResult', [gid]);
      return;
    }
    await _rpc('aria2.remove', [gid]);
  }

  Future<Map<String, dynamic>> globalStat() async {
    return await _rpc('aria2.getGlobalStat') as Map<String, dynamic>;
  }

  void close() => _client.close();
}
