import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../models/app_settings.dart';

/// Owns the aria2 endpoint used by this MoePureKit instance.
/// A native named mutex and an in-flight Future prevent duplicate launches.
class Aria2RuntimeService {
  Aria2RuntimeService({
    this.executablePath,
    this.dataDirectory,
    Future<bool> Function()? acquireRuntimeMutex,
    Future<void> Function()? releaseRuntimeMutex,
    Future<void> Function(int processId)? attachAria2Process,
  }) : _acquireRuntimeMutex = acquireRuntimeMutex ?? _acquireNativeMutex,
       _releaseRuntimeMutexCallback =
           releaseRuntimeMutex ?? _releaseNativeMutex,
       _attachAria2Process = attachAria2Process ?? _attachNativeProcess;

  static const MethodChannel _systemChannel = MethodChannel('moepurekit/system');

  final String? executablePath;
  final String? dataDirectory;
  final Future<bool> Function() _acquireRuntimeMutex;
  final Future<void> Function() _releaseRuntimeMutexCallback;
  final Future<void> Function(int processId) _attachAria2Process;

  static Future<void> _attachNativeProcess(int processId) async {
    final attached = await _systemChannel.invokeMethod<bool>(
      'attachAria2Process',
      processId,
    );
    if (attached != true) {
      throw StateError('Windows 未确认 aria2 进程托管');
    }
  }

  static Future<bool> _acquireNativeMutex() async =>
      await _systemChannel.invokeMethod<bool>('acquireAria2Mutex') ?? false;

  static Future<void> _releaseNativeMutex() =>
      _systemChannel.invokeMethod<void>('releaseAria2Mutex');
  Process? _process;
  Uri? _rpcUri;
  String _rpcSecret = '';
  Future<String>? _startFuture;
  Future<void>? _stopFuture;
  bool _ownsRuntimeMutex = false;
  bool _adoptedRpc = false;
  bool _stopRequested = false;

  bool get isRunning => _process != null || _adoptedRpc;

  Future<String> start(AppSettings settings) {
    if (!Platform.isWindows) return Future.value('内置 aria2 仅支持 Windows');
    if (_stopRequested) return Future.value('aria2 正在关闭，请稍后重试');
    if (_process != null || _adoptedRpc) {
      return Future.value('内置 aria2 已启动');
    }
    final pending = _startFuture;
    if (pending != null) return pending;

    final operation = _startInternal(settings);
    _startFuture = operation;
    return operation.whenComplete(() {
      if (identical(_startFuture, operation)) _startFuture = null;
    });
  }

  Future<String> _startInternal(AppSettings settings) async {
    final rpcUri = Uri.tryParse(settings.aria2RpcUrl);
    if (rpcUri == null ||
        rpcUri.scheme != 'http' ||
        !const {'127.0.0.1', 'localhost', '::1'}.contains(rpcUri.host) ||
        rpcUri.userInfo.isNotEmpty ||
        rpcUri.port < 1 ||
        rpcUri.port > 65535) {
      return 'JSON-RPC 地址必须是有效的本机 HTTP 地址；不会启动内置 aria2';
    }

    final resolvedExecutablePath =
        executablePath ??
        [
          File(Platform.resolvedExecutable).parent.path,
          'data',
          'aria2',
          'aria2c.exe',
        ].join(Platform.pathSeparator);
    final executable = File(resolvedExecutablePath);
    if (!await executable.exists()) {
      return '未找到内置引擎：${executable.path}';
    }

    final dataPath = dataDirectory ?? _defaultDataDirectory();
    if (dataPath == null) {
      return '无法确定 aria2 数据目录；请检查 Windows 用户配置目录';
    }
    final downloadDirectory = settings.downloadDirectory.trim().isNotEmpty
        ? settings.downloadDirectory.trim()
        : _defaultDownloadDirectory();
    if (downloadDirectory == null) {
      return '无法确定下载目录；请检查 Windows 用户配置目录';
    }

    try {
      // A second app/process cannot launch another bundled daemon. The mutex
      // is independent from the window's single-instance mutex.
      final acquired = await _acquireRuntimeMutex();
      if (!acquired) {
        if (await _isRpcReady(rpcUri, settings.aria2RpcSecret)) {
          return '检测到另一个实例已启动 aria2，当前复用本机服务';
        }
        return '另一个 MoePureKit 实例正在管理 aria2，本次不会重复启动';
      }
      _ownsRuntimeMutex = true;

      // A previous orphan or a user-managed local aria2 may still own the
      // configured port. Never spawn a second process over a live RPC server.
      if (await _isRpcReady(rpcUri, settings.aria2RpcSecret)) {
        // This RPC server may be an orphan left behind by an earlier app
        // version. Adopt its authenticated local endpoint so normal app exit
        // can send aria2.shutdown instead of leaving it in the background.
        _rpcUri = rpcUri;
        _rpcSecret = settings.aria2RpcSecret;
        _adoptedRpc = true;
        return '检测到已有本机 aria2 服务，已接管并避免重复启动';
      }
      if (_stopRequested) {
        await _releaseRuntimeMutex();
        return 'aria2 启动已取消';
      }

      final data = Directory(dataPath);
      await data.create(recursive: true);
      await Directory(downloadDirectory).create(recursive: true);
      final sessionFile = File(
        '${data.path}${Platform.pathSeparator}session.txt',
      );
      if (!await sessionFile.exists()) {
        await sessionFile.create(recursive: true);
      }

      final arguments = <String>[
        '--enable-rpc=true',
        '--rpc-listen-all=false',
        '--rpc-allow-origin-all=false',
        '--rpc-listen-port=${rpcUri.port}',
        '--rpc-secret=${settings.aria2RpcSecret}',
        '--max-concurrent-downloads=${settings.concurrentDownloads.clamp(1, 64)}',
        '--max-connection-per-server=8',
        '--continue=true',
        '--input-file=${sessionFile.path}',
        '--save-session=${sessionFile.path}',
        '--save-session-interval=60',
        '--dir=$downloadDirectory',
      ];
      if (settings.proxy.trim().isNotEmpty) {
        arguments.add('--all-proxy=${settings.proxy.trim()}');
      }

      final process = await Process.start(
        executable.path,
        arguments,
        workingDirectory: executable.parent.path,
        runInShell: false,
        mode: ProcessStartMode.normal,
      );
      _process = process;
      _rpcUri = rpcUri;
      _rpcSecret = settings.aria2RpcSecret;
      process.stdout.transform(SystemEncoding().decoder).listen((_) {});
      process.stderr.transform(SystemEncoding().decoder).listen((_) {});
      unawaited(
        process.exitCode.then((_) async {
          if (identical(_process, process)) {
            _process = null;
            _rpcUri = null;
            _rpcSecret = '';
            _adoptedRpc = false;
            await _releaseRuntimeMutex();
          }
        }),
      );

      // Attach the exact child PID to a Windows Job Object with
      // KILL_ON_JOB_CLOSE. Graceful exit still uses aria2.shutdown; this is
      // the fallback for crashes, forced window destruction, or task kills.
      try {
        await _attachAria2Process(process.pid);
      } on Object catch (attachError) {
        try {
          await _terminateOwnedProcess(process, sendRpcShutdown: false);
          return 'Windows 无法托管 aria2 子进程，已终止本次启动以避免后台残留：$attachError';
        } on Object catch (terminationError) {
          return 'aria2 无法纳入系统进程托管，且未能确认终止；已保留运行锁避免重复启动：$terminationError';
        }
      }

      if (!await _waitForRpc(rpcUri, settings.aria2RpcSecret)) {
        try {
          await _terminateOwnedProcess(process, sendRpcShutdown: false);
          return '内置 aria2 未能在本机端口 ${rpcUri.port} 建立 JSON-RPC 连接';
        } on Object catch (terminationError) {
          // Do not release the named mutex when we cannot prove the child has
          // exited. The job object remains the final cleanup guard.
          return 'aria2 RPC 未能连接，且未能确认子进程已退出；已保留运行锁避免重复启动：$terminationError';
        }
      }
      return '内置 aria2 已启动';
    } on ProcessException catch (error) {
      await _releaseRuntimeMutex();
      return '无法启动内置 aria2：${error.message}';
    } on FileSystemException catch (error) {
      await _releaseRuntimeMutex();
      return '无法准备 aria2 数据或下载目录：${error.message}';
    } on PlatformException catch (error) {
      await _releaseRuntimeMutex();
      return '无法锁定 aria2 运行实例：${error.message ?? error.code}';
    } catch (error) {
      await _releaseRuntimeMutex();
      return 'aria2 初始化失败：$error';
    }
  }

  String? _defaultDataDirectory() {
    final appData = Platform.environment['APPDATA'];
    if (appData == null || appData.trim().isEmpty) return null;
    return [appData, 'Coloryi-MIAO', 'MoePureKit', 'aria2']
        .join(Platform.pathSeparator);
  }

  String? _defaultDownloadDirectory() {
    final profile = Platform.environment['USERPROFILE'];
    if (profile == null || profile.trim().isEmpty) return null;
    return [profile, 'Downloads', 'MoePureKit'].join(Platform.pathSeparator);
  }

  Future<bool> _isRpcReady(Uri uri, String secret) async {
    final client = http.Client();
    try {
      final params = <String>[];
      if (secret.isNotEmpty) params.add('token:$secret');
      final response = await client
          .post(
            uri,
            headers: const {'content-type': 'application/json'},
            body: jsonEncode({
              'jsonrpc': '2.0',
              'id': 'moepurekit-probe',
              'method': 'aria2.getVersion',
              'params': params,
            }),
          )
          .timeout(const Duration(milliseconds: 450));
      if (response.statusCode != 200) return false;
      final payload = jsonDecode(response.body);
      return payload is Map<String, dynamic> && payload.containsKey('result');
    } on Object {
      return false;
    } finally {
      client.close();
    }
  }

  Future<bool> _waitForRpc(Uri uri, String secret) async {
    for (var attempt = 0; attempt < 20; attempt++) {
      if (await _isRpcReady(uri, secret)) return true;
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    return false;
  }

  Future<void> stop() {
    final pending = _stopFuture;
    if (pending != null) return pending;
    final operation = _stopInternal();
    _stopFuture = operation;
    return operation.whenComplete(() {
      if (identical(_stopFuture, operation)) _stopFuture = null;
    });
  }

  Future<void> _stopInternal() async {
    _stopRequested = true;
    try {
      final pendingStart = _startFuture;
      if (pendingStart != null) {
        try {
          await pendingStart;
        } catch (_) {
          // Startup reports its own error; shutdown still releases the lock.
        }
      }

      final process = _process;
      if (process == null) {
        if (_adoptedRpc && _rpcUri != null) {
          final uri = _rpcUri!;
          final secret = _rpcSecret;
          await _requestRpcShutdown(uri, secret);
          var stopped = false;
          for (var attempt = 0; attempt < 20; attempt++) {
            if (!await _isRpcReady(uri, secret)) {
              stopped = true;
              break;
            }
            await Future<void>.delayed(const Duration(milliseconds: 150));
          }
          if (!stopped) {
            throw StateError('aria2 RPC 未确认退出；为避免重复启动，保留运行锁并阻止关闭');
          }
          _adoptedRpc = false;
          _rpcUri = null;
          _rpcSecret = '';
        }
        await _releaseRuntimeMutex();
        return;
      }
      await _terminateOwnedProcess(process, sendRpcShutdown: true);
    } finally {
      _stopRequested = false;
    }
  }

  Future<void> _terminateOwnedProcess(
    Process process, {
    required bool sendRpcShutdown,
  }) async {
    if (sendRpcShutdown && _rpcUri != null) {
      await _requestRpcShutdown(_rpcUri!, _rpcSecret);
    }

    var exited = false;
    try {
      await process.exitCode.timeout(const Duration(seconds: 3));
      exited = true;
    } on TimeoutException {
      // aria2 did not honor its RPC shutdown request in time.
    } on Object {
      exited = true;
    }

    if (!exited) {
      process.kill();
      try {
        await process.exitCode.timeout(const Duration(seconds: 3));
        exited = true;
      } on Object {
        // Keep both the process reference and mutex: a new aria2 must not be
        // launched while the previous owned process may still be alive.
      }
    }
    if (!exited) {
      throw StateError('aria2 进程未能确认退出；已保留运行锁以防止重复启动');
    }

    if (identical(_process, process)) {
      _process = null;
      _rpcUri = null;
      _rpcSecret = '';
    }
    _adoptedRpc = false;
    await _releaseRuntimeMutex();
  }

  Future<void> _requestRpcShutdown(Uri uri, String secret) async {
    final client = HttpClient();
    try {
      final request = await client
          .postUrl(uri)
          .timeout(const Duration(seconds: 2));
      request.headers.contentType = ContentType.json;
      final params = <String>[];
      if (secret.isNotEmpty) params.add('token:$secret');
      request.write(
        jsonEncode({
          'jsonrpc': '2.0',
          'id': 'moepurekit-shutdown',
          'method': 'aria2.shutdown',
          'params': params,
        }),
      );
      final response = await request.close().timeout(
        const Duration(seconds: 2),
      );
      await response.drain<void>().timeout(const Duration(seconds: 2));
    } on Object {
      // The process may already be exiting or the RPC endpoint may be stale.
    } finally {
      client.close(force: true);
    }
  }

  Future<void> _releaseRuntimeMutex() async {
    if (!_ownsRuntimeMutex) return;
    try {
      await _releaseRuntimeMutexCallback();
      _ownsRuntimeMutex = false;
    } on Object {
      // Keep the ownership flag so a later stop can retry. The OS also
      // abandons the native mutex automatically if the owning thread exits.
    }
  }
}
