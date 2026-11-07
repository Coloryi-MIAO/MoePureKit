import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

class SystemMetrics {
  const SystemMetrics({
    required this.cpuPercent,
    required this.memoryPercent,
    required this.diskActivePercent,
    required this.diskUsedPercent,
    required this.memoryUsedBytes,
    required this.memoryTotalBytes,
    required this.diskReadBytesPerSecond,
    required this.diskWriteBytesPerSecond,
    required this.driveFreeBytes,
    required this.driveTotalBytes,
    required this.sampledAt,
  });

  final double cpuPercent;
  final double memoryPercent;
  /// -1 means Windows did not expose physical-disk activity for this sample.
  final double diskActivePercent;
  final double diskUsedPercent;
  final int memoryUsedBytes;
  final int memoryTotalBytes;
  /// -1 means Windows did not expose physical-disk throughput for this sample.
  final int diskReadBytesPerSecond;
  final int diskWriteBytesPerSecond;
  final int driveFreeBytes;
  final int driveTotalBytes;
  final DateTime sampledAt;

  factory SystemMetrics.fromJson(Map<String, dynamic> json) =>
      SystemMetrics.fromMap(json);

  factory SystemMetrics.fromMap(Map<dynamic, dynamic> values) {
    num number(String key, [num fallback = 0]) =>
        values[key] is num ? values[key] as num : fallback;
    final cpu = number('cpu', -1).toDouble();
    final memory = number('memory', -1).toDouble();
    final memoryTotal = number('memoryTotalBytes').toInt();
    if (cpu < 0 || memory < 0 || memoryTotal <= 0) {
      throw StateError('GetSystemTimes / GlobalMemoryStatusEx 未返回有效数据');
    }
    final diskActive = number('diskActive', -1).toDouble();
    return SystemMetrics(
      cpuPercent: cpu.clamp(0, 100).toDouble(),
      memoryPercent: memory.clamp(0, 100).toDouble(),
      diskActivePercent: diskActive < 0
          ? -1
          : diskActive.clamp(0, 100).toDouble(),
      diskUsedPercent: number('diskUsed').toDouble().clamp(0, 100).toDouble(),
      memoryUsedBytes: number('memoryUsedBytes').toInt(),
      memoryTotalBytes: memoryTotal,
      diskReadBytesPerSecond: number('readBytesPerSec', -1).toInt(),
      diskWriteBytesPerSecond: number('writeBytesPerSec', -1).toInt(),
      driveFreeBytes: number('driveFreeBytes').toInt(),
      driveTotalBytes: number('driveTotalBytes').toInt(),
      sampledAt: DateTime.now(),
    );
  }
}

/// Reads metrics through Win32 APIs registered by the Windows runner.
/// No PowerShell, WMI or Windows Performance Counter process is started.
class SystemMetricsService {
  static const MethodChannel _channel = MethodChannel('moepurekit/system');
  static const Duration _sampleInterval = Duration(milliseconds: 1500);

  final StreamController<SystemMetrics> _controller =
      StreamController<SystemMetrics>.broadcast();
  Timer? _timer;
  bool _closed = false;
  bool _started = false;
  bool _sampling = false;
  Completer<void>? _sampleCompleted;

  Stream<SystemMetrics> get stream => _controller.stream;

  Future<void> start() async {
    if (_closed || _started) return;
    if (!Platform.isWindows) {
      throw UnsupportedError('实时性能采样仅支持 Windows');
    }
    _started = true;
    await _sample();
    if (!_closed && _started) {
      _timer = Timer.periodic(_sampleInterval, (_) => unawaited(_sample()));
    }
  }

  Future<void> _sample() async {
    if (_closed || !_started || _sampling) return;
    _sampling = true;
    final completed = Completer<void>();
    _sampleCompleted = completed;
    try {
      final values = await _channel.invokeMapMethod<Object?, Object?>(
        'getSystemMetrics',
      );
      if (values == null) {
        throw PlatformException(
          code: 'empty_metrics',
          message: 'Windows runner 未返回性能数据',
        );
      }
      if (!_closed && _started) {
        _controller.add(SystemMetrics.fromMap(values));
      }
    } on PlatformException catch (error) {
      if (!_closed && _started) {
        _controller.addError(
          StateError('Windows 原生性能 API 读取失败：${error.message ?? error.code}'),
        );
      }
    } catch (error) {
      if (!_closed && _started) _controller.addError(error);
    } finally {
      _sampling = false;
      if (!completed.isCompleted) completed.complete();
      if (identical(_sampleCompleted, completed)) _sampleCompleted = null;
    }
  }

  Future<void> stop() async {
    _started = false;
    _timer?.cancel();
    _timer = null;
    final inFlight = _sampleCompleted;
    if (inFlight != null) await inFlight.future;
    if (Platform.isWindows) {
      try {
        await _channel.invokeMethod<void>('stopSystemMetrics');
      } on Object {
        // The runner may already be tearing down; its process handle cleanup
        // remains the final fallback.
      }
    }
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await stop();
    await _controller.close();
  }
}
