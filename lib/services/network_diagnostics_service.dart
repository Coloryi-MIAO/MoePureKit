import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

class PingSummary {
  const PingSummary({required this.sent, required this.samplesMs});

  final int sent;
  final List<double> samplesMs;

  int get received => samplesMs.length;
  double get packetLossPercent => sent == 0
      ? 0.0
      : ((sent - received).clamp(0, sent) / sent) * 100.0;
  double? get minMs => samplesMs.isEmpty
      ? null
      : samplesMs.reduce((a, b) => a < b ? a : b);
  double? get maxMs => samplesMs.isEmpty
      ? null
      : samplesMs.reduce((a, b) => a > b ? a : b);
  double? get averageMs => samplesMs.isEmpty
      ? null
      : samplesMs.reduce((a, b) => a + b) / samplesMs.length;

  /// Mean absolute difference between consecutive successful samples.
  double? get jitterMs {
    if (samplesMs.length < 2) return null;
    var total = 0.0;
    for (var index = 1; index < samplesMs.length; index++) {
      total += (samplesMs[index] - samplesMs[index - 1]).abs();
    }
    return total / (samplesMs.length - 1);
  }
}

class NetworkDiagnosticsResult {
  const NetworkDiagnosticsResult({
    required this.localIpv4,
    required this.interfaceAlias,
    required this.defaultGateway,
    required this.configuredDnsServers,
    required this.gatewayPing,
    required this.gatewayPingError,
    required this.dnsAddress,
    required this.dnsLatencyMs,
    required this.ping,
    required this.pingTarget,
    required this.httpsLatencyMs,
    required this.httpStatusCode,
    required this.downloadMbps,
    required this.downloadBytes,
    required this.uploadMbps,
    required this.uploadBytes,
    required this.includeUpload,
    required this.dnsError,
    required this.pingError,
    required this.httpsError,
    required this.downloadError,
    required this.uploadError,
    required this.elapsed,
    required this.measuredAt,
  });

  final String? localIpv4;
  final String? interfaceAlias;
  final String? defaultGateway;
  final List<String> configuredDnsServers;
  final PingSummary? gatewayPing;
  final String? gatewayPingError;
  final String? dnsAddress;
  final double? dnsLatencyMs;
  final PingSummary ping;
  final String pingTarget;
  final double? httpsLatencyMs;
  final int? httpStatusCode;
  final double? downloadMbps;
  final int downloadBytes;
  final double? uploadMbps;
  final int uploadBytes;
  final bool includeUpload;
  final String? dnsError;
  final String? pingError;
  final String? httpsError;
  final String? downloadError;
  final String? uploadError;
  final Duration elapsed;
  final DateTime measuredAt;
}

/// Parses the response rows of Windows/macOS/Linux ping output.
/// A line such as `time<1ms` is represented as 0.5 ms.
PingSummary parsePingOutput(String output, {int sent = 5}) {
  final samples = <double>[];
  final expression = RegExp(
    r'(?:time|时间)\s*([=<])\s*([0-9]+(?:[.,][0-9]+)?)\s*ms',
    caseSensitive: false,
  );
  for (final match in expression.allMatches(output)) {
    final operator = match.group(1);
    final raw = match.group(2)?.replaceAll(',', '.') ?? '';
    final value = double.tryParse(raw);
    if (value == null || !value.isFinite) continue;
    final sample = operator == '<'
        ? (value / 2 < 0.5 ? 0.5 : value / 2)
        : value;
    samples.add(sample);
  }
  return PingSummary(sent: sent, samplesMs: List.unmodifiable(samples));
}

class _WindowsNetworkConfig {
  const _WindowsNetworkConfig({
    this.interfaceAlias,
    this.ipv4,
    this.defaultGateway,
    this.dnsServers = const [],
  });

  final String? interfaceAlias;
  final String? ipv4;
  final String? defaultGateway;
  final List<String> dnsServers;
}

class NetworkDiagnosticsService {
  static const String speedTestHost = 'speed.cloudflare.com';
  static const int pingCount = 5;
  static const int downloadTestBytes = 8 * 1024 * 1024;
  static const int uploadTestBytes = 2 * 1024 * 1024;

  Future<NetworkDiagnosticsResult> runFullTest({
    String pingTarget = '1.1.1.1',
    bool includeUpload = true,
    void Function(String stage)? onProgress,
  }) async {
    final totalWatch = Stopwatch()..start();
    onProgress?.call('正在读取网络适配器信息…');
    final adapter = await _readWindowsNetworkConfig();
    final localIpv4 = adapter.ipv4 ?? await _findLocalIpv4();
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 8)
      ..idleTimeout = const Duration(seconds: 8)
      ..findProxy = HttpClient.findProxyFromEnvironment;

    PingSummary? gatewayPing;
    String? gatewayPingError;
    String? dnsAddress;
    double? dnsLatencyMs;
    String? dnsError;
    PingSummary ping = const PingSummary(sent: pingCount, samplesMs: []);
    String? pingError;
    double? httpsLatencyMs;
    int? httpStatusCode;
    String? httpsError;
    double? downloadMbps;
    var downloadBytes = 0;
    String? downloadError;
    double? uploadMbps;
    var uploadBytes = 0;
    String? uploadError;

    try {
      if (adapter.defaultGateway != null) {
        onProgress?.call('正在测试默认网关 Ping…');
        try {
          gatewayPing = await _runPing(
            adapter.defaultGateway!,
            count: 3,
            timeoutMillis: 800,
          );
          if (gatewayPing.received == 0) {
            gatewayPingError = '默认网关未响应 ICMP';
          }
        } on Object catch (error) {
          gatewayPingError = _shortError(error);
        }
      }

      onProgress?.call('正在解析测速节点 DNS…');
      final dnsWatch = Stopwatch()..start();
      try {
        final addresses = await InternetAddress.lookup(speedTestHost).timeout(
          const Duration(seconds: 8),
        );
        dnsWatch.stop();
        if (addresses.isEmpty) {
          dnsError = 'DNS 查询未返回 IP 地址';
        } else {
          dnsAddress = addresses.first.address;
          dnsLatencyMs = dnsWatch.elapsedMicroseconds / 1000;
        }
      } on Object catch (error) {
        dnsWatch.stop();
        dnsError = _shortError(error);
      }

      onProgress?.call('正在测试 ICMP Ping、抖动和丢包…');
      try {
        ping = await _runPing(pingTarget.trim(), count: pingCount);
        if (ping.received == 0) {
          pingError = '未收到 ICMP 响应；目标或本机防火墙可能屏蔽 Ping';
        }
      } on Object catch (error) {
        pingError = _shortError(error);
      }

      onProgress?.call('正在测量 HTTPS 往返延迟…');
      try {
        final latency = await _measureHttpsLatency(client);
        httpsLatencyMs = latency.$1;
        httpStatusCode = latency.$2;
      } on Object catch (error) {
        httpsError = _shortError(error);
      }

      onProgress?.call('正在测试下载速度（最多接收 8 MiB）…');
      try {
        final download = await _measureDownload(client, downloadTestBytes);
        downloadMbps = download.$1;
        downloadBytes = download.$2;
      } on Object catch (error) {
        downloadError = _shortError(error);
      }

      if (includeUpload) {
        onProgress?.call('正在测试上传速度（发送 2 MiB 自动生成测试数据）…');
        try {
          final upload = await _measureUpload(client, uploadTestBytes);
          uploadMbps = upload.$1;
          uploadBytes = upload.$2;
        } on Object catch (error) {
          uploadError = _shortError(error);
        }
      }
    } finally {
      totalWatch.stop();
      client.close(force: true);
    }

    onProgress?.call('检测完成');
    return NetworkDiagnosticsResult(
      localIpv4: localIpv4,
      interfaceAlias: adapter.interfaceAlias,
      defaultGateway: adapter.defaultGateway,
      configuredDnsServers: adapter.dnsServers,
      gatewayPing: gatewayPing,
      gatewayPingError: gatewayPingError,
      dnsAddress: dnsAddress,
      dnsLatencyMs: dnsLatencyMs,
      ping: ping,
      pingTarget: pingTarget,
      httpsLatencyMs: httpsLatencyMs,
      httpStatusCode: httpStatusCode,
      downloadMbps: downloadMbps,
      downloadBytes: downloadBytes,
      uploadMbps: uploadMbps,
      uploadBytes: uploadBytes,
      includeUpload: includeUpload,
      dnsError: dnsError,
      pingError: pingError,
      httpsError: httpsError,
      downloadError: downloadError,
      uploadError: uploadError,
      elapsed: totalWatch.elapsed,
      measuredAt: DateTime.now(),
    );
  }

  Future<_WindowsNetworkConfig> _readWindowsNetworkConfig() async {
    if (!Platform.isWindows) return const _WindowsNetworkConfig();
    const script = r'''
$cfg = Get-NetIPConfiguration | Where-Object { $_.IPv4DefaultGateway -ne $null } | Select-Object -First 1
if ($null -eq $cfg) {
  $cfg = Get-NetIPConfiguration | Where-Object { $_.IPv4Address -ne $null } | Select-Object -First 1
}
if ($null -eq $cfg) { throw 'No active network adapter found' }
$ipv4 = @($cfg.IPv4Address | ForEach-Object { $_.IPAddress })
$dns = @($cfg.DnsServer.ServerAddresses)
$gateway = $null
if ($cfg.IPv4DefaultGateway) { $gateway = [string]$cfg.IPv4DefaultGateway.NextHop }
[pscustomobject]@{
  interfaceAlias = [string]$cfg.InterfaceAlias
  ipv4 = $ipv4
  gateway = $gateway
  dnsServers = $dns
} | ConvertTo-Json -Compress -Depth 3
''';
    try {
      final result = await Process.run(
        'powershell.exe',
        ['-NoProfile', '-NonInteractive', '-Command', script],
        runInShell: false,
      ).timeout(const Duration(seconds: 6));
      if (result.exitCode != 0) return const _WindowsNetworkConfig();
      final output = result.stdout.toString().trim();
      if (output.isEmpty) return const _WindowsNetworkConfig();
      final data = jsonDecode(output) as Map<String, dynamic>;
      final ipv4Values = data['ipv4'] is List
          ? (data['ipv4'] as List).whereType<String>().toList()
          : data['ipv4'] is String
              ? <String>[data['ipv4'] as String]
              : <String>[];
      final dnsValues = data['dnsServers'] is List
          ? (data['dnsServers'] as List).whereType<String>().toList()
          : data['dnsServers'] is String
              ? <String>[data['dnsServers'] as String]
              : <String>[];
      String? ipv4;
      for (final value in ipv4Values) {
        if (value.isNotEmpty && !value.startsWith('169.254.')) {
          ipv4 = value;
          break;
        }
      }
      final gateway = data['gateway']?.toString();
      return _WindowsNetworkConfig(
        interfaceAlias: data['interfaceAlias']?.toString(),
        ipv4: ipv4,
        defaultGateway: gateway == null || gateway.isEmpty ? null : gateway,
        dnsServers: List.unmodifiable(dnsValues),
      );
    } on Object {
      return const _WindowsNetworkConfig();
    }
  }

  Future<String?> _findLocalIpv4() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
        includeLinkLocal: false,
      );
      for (final interface in interfaces) {
        for (final address in interface.addresses) {
          if (address.type == InternetAddressType.IPv4 &&
              !address.isLoopback &&
              !address.address.startsWith('169.254.')) {
            return address.address;
          }
        }
      }
    } on Object {
      // The network test remains useful even if interface enumeration fails.
    }
    return null;
  }

  Future<PingSummary> _runPing(
    String target, {
    required int count,
    int timeoutMillis = 1200,
  }) async {
    if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9._:-]*$').hasMatch(target)) {
      throw const FormatException('Ping 目标只能包含主机名或 IP 地址字符');
    }
    final executable = Platform.isWindows ? 'ping.exe' : 'ping';
    final timeoutSeconds = (timeoutMillis / 1000).ceil().clamp(1, 10);
    final arguments = Platform.isWindows
        ? ['-n', '$count', '-w', '$timeoutMillis', '-l', '32', target]
        : ['-c', '$count', '-W', '$timeoutSeconds', '-s', '32', target];
    final result = await Process.run(
      executable,
      arguments,
      runInShell: false,
    ).timeout(Duration(milliseconds: count * timeoutMillis + 5000));
    final output = '${result.stdout}\n${result.stderr}';
    return parsePingOutput(output, sent: count);
  }

  Future<(double, int)> _measureHttpsLatency(HttpClient client) async {
    final values = <double>[];
    var lastStatus = 0;
    for (var index = 0; index < 3; index++) {
      final uri = Uri.https(speedTestHost, '/__down', {
        'bytes': '1',
        'probe': DateTime.now().microsecondsSinceEpoch.toString(),
      });
      final watch = Stopwatch()..start();
      final request = await client.getUrl(uri).timeout(
        const Duration(seconds: 10),
      );
      request.headers.set(HttpHeaders.cacheControlHeader, 'no-cache');
      request.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
      final response = await request.close().timeout(
        const Duration(seconds: 10),
      );
      await response.drain<void>().timeout(const Duration(seconds: 10));
      watch.stop();
      lastStatus = response.statusCode;
      if (lastStatus < 200 || lastStatus >= 400) {
        throw HttpException('测速节点返回 HTTP $lastStatus', uri: uri);
      }
      values.add(watch.elapsedMicroseconds / 1000);
    }
    values.sort();
    return (values[values.length ~/ 2], lastStatus);
  }

  Future<(double, int)> _measureDownload(
    HttpClient client,
    int requestedBytes,
  ) async {
    final uri = Uri.https(speedTestHost, '/__down', {
      'bytes': '$requestedBytes',
      'probe': DateTime.now().microsecondsSinceEpoch.toString(),
    });
    final watch = Stopwatch()..start();
    final request = await client.getUrl(uri).timeout(
      const Duration(seconds: 12),
    );
    request.headers.set(HttpHeaders.cacheControlHeader, 'no-cache');
    request.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
    final response = await request.close().timeout(
      const Duration(seconds: 20),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      await response.drain<void>();
      throw HttpException('下载测速节点返回 HTTP ${response.statusCode}', uri: uri);
    }
    var received = 0;
    await for (final chunk in response.timeout(const Duration(seconds: 20))) {
      received += chunk.length;
    }
    watch.stop();
    if (received <= 0 || watch.elapsedMicroseconds <= 0) {
      throw const HttpException('下载测速未收到有效数据');
    }
    final seconds = watch.elapsedMicroseconds / 1000000;
    return ((received * 8 / seconds) / 1000000, received);
  }

  Future<(double, int)> _measureUpload(
    HttpClient client,
    int requestedBytes,
  ) async {
    final uri = Uri.https(speedTestHost, '/__up', {
      'probe': DateTime.now().microsecondsSinceEpoch.toString(),
    });
    final payload = Uint8List(requestedBytes);
    // The zero-filled buffer is synthetic; no local file or user content is sent.

    final watch = Stopwatch()..start();
    final request = await client.postUrl(uri).timeout(
      const Duration(seconds: 12),
    );
    request.contentLength = payload.length;
    request.headers.set(
      HttpHeaders.contentTypeHeader,
      'application/octet-stream',
    );
    request.headers.set(HttpHeaders.cacheControlHeader, 'no-cache');
    request.add(payload);
    final response = await request.close().timeout(
      const Duration(seconds: 25),
    );
    await response.drain<void>().timeout(const Duration(seconds: 15));
    watch.stop();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException('上传测速节点返回 HTTP ${response.statusCode}', uri: uri);
    }
    if (watch.elapsedMicroseconds <= 0) {
      throw const HttpException('上传测速耗时无效');
    }
    final seconds = watch.elapsedMicroseconds / 1000000;
    return ((payload.length * 8 / seconds) / 1000000, payload.length);
  }

  String _shortError(Object error) {
    if (error is TimeoutException) return '连接超时';
    if (error is SocketException) return '网络不可达：${error.message}';
    if (error is HandshakeException) return 'TLS 握手失败：${error.message}';
    return error.toString().replaceFirst('Exception: ', '');
  }
}
