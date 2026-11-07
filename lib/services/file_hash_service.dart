import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';

class FileHashResult {
  const FileHashResult({
    required this.digest,
    required this.algorithm,
    required this.bytesProcessed,
    required this.modified,
    required this.elapsed,
  });

  final String digest;
  final String algorithm;
  final int bytesProcessed;
  final DateTime modified;
  final Duration elapsed;
}

/// Computes a file digest in a worker isolate so large files do not block UI
/// frames. Progress is sent back in coarse intervals to avoid excessive rebuilds.
Future<FileHashResult> computeFileHash(
  String path, {
  String algorithm = 'SHA-256',
  void Function(int processed, int total)? onProgress,
}) async {
  final messages = ReceivePort();
  final errors = ReceivePort();
  final completer = Completer<FileHashResult>();

  final messageSubscription = messages.listen((message) {
    if (message == null) {
      if (!completer.isCompleted) {
        completer.completeError(StateError('哈希工作线程提前退出'));
      }
      return;
    }
    if (message is! Map) return;
    final type = message['type'];
    if (type == 'progress') {
      onProgress?.call(
        (message['processed'] as num).toInt(),
        (message['total'] as num).toInt(),
      );
      return;
    }
    if (type == 'result') {
      if (completer.isCompleted) return;
      completer.complete(
        FileHashResult(
          digest: message['digest'] as String,
          algorithm: message['algorithm'] as String,
          bytesProcessed: (message['bytesProcessed'] as num).toInt(),
          modified: DateTime.fromMillisecondsSinceEpoch(
            (message['modifiedMillis'] as num).toInt(),
          ),
          elapsed: Duration(
            microseconds: (message['elapsedMicros'] as num).toInt(),
          ),
        ),
      );
      return;
    }
    if (type == 'error' && !completer.isCompleted) {
      completer.completeError(
        FileSystemException(message['message'] as String? ?? '哈希计算失败', path),
      );
    }
  });
  final errorSubscription = errors.listen((message) {
    if (completer.isCompleted) return;
    final details = message is List && message.isNotEmpty
        ? message.first.toString()
        : message.toString();
    completer.completeError(StateError('哈希工作线程异常：$details'));
  });
  Isolate? worker;
  try {
    worker = await Isolate.spawn<Map<String, Object?>>(
      _fileHashWorker,
      <String, Object?>{
        'path': path,
        'algorithm': algorithm,
        'sendPort': messages.sendPort,
      },
      onError: errors.sendPort,
      onExit: messages.sendPort,
      errorsAreFatal: true,
    );
    return await completer.future;
  } finally {
    worker?.kill(priority: Isolate.immediate);
    await messageSubscription.cancel();
    await errorSubscription.cancel();
    messages.close();
    errors.close();
  }
}

void _fileHashWorker(Map<String, Object?> message) {
  unawaited(_runFileHashWorker(message));
}

Future<void> _runFileHashWorker(Map<String, Object?> message) async {
  final sendPort = message['sendPort'] as SendPort;
  final path = message['path'] as String;
  final algorithm = message['algorithm'] as String;
  try {
    final file = File(path);
    if (!await file.exists()) {
      throw FileSystemException('文件不存在', path);
    }

    final stat = await file.stat();
    final hash = _hashFor(algorithm);
    var processed = 0;
    var lastReportedBytes = 0;
    var lastReportedAt = 0;
    final stopwatch = Stopwatch()..start();
    final progressStream = file.openRead().transform(
      StreamTransformer<List<int>, List<int>>.fromHandlers(
        handleData: (chunk, sink) {
          processed += chunk.length;
          final elapsedMs = stopwatch.elapsedMilliseconds;
          if (processed - lastReportedBytes >= 16 * 1024 * 1024 ||
              elapsedMs - lastReportedAt >= 400) {
            sendPort.send(<String, Object?>{
              'type': 'progress',
              'processed': processed,
              'total': stat.size,
            });
            lastReportedBytes = processed;
            lastReportedAt = elapsedMs;
          }
          sink.add(chunk);
        },
      ),
    );
    final digest = await hash.bind(progressStream).first;
    stopwatch.stop();
    // Always deliver a final progress event, including for very small files.
    sendPort.send(<String, Object?>{
      'type': 'progress',
      'processed': processed,
      'total': stat.size,
    });
    sendPort.send(<String, Object?>{
      'type': 'result',
      'digest': digest.toString(),
      'algorithm': _normalizeAlgorithm(algorithm),
      'bytesProcessed': processed,
      'modifiedMillis': stat.modified.millisecondsSinceEpoch,
      'elapsedMicros': stopwatch.elapsedMicroseconds,
    });
  } on Object catch (error) {
    sendPort.send(<String, Object?>{
      'type': 'error',
      'message': error.toString(),
    });
  }
}

/// Backwards-compatible SHA-256 helper used by existing callers and tests.
Future<String> computeFileSha256(String path) async =>
    (await computeFileHash(path)).digest;

Hash _hashFor(String algorithm) {
  switch (_normalizeAlgorithm(algorithm)) {
    case 'MD5':
      return md5;
    case 'SHA-1':
      return sha1;
    case 'SHA-256':
      return sha256;
    case 'SHA-384':
      return sha384;
    case 'SHA-512':
      return sha512;
    default:
      throw ArgumentError.value(algorithm, 'algorithm', '不支持的哈希算法');
  }
}

String _normalizeAlgorithm(String algorithm) =>
    algorithm.trim().toUpperCase().replaceAll('_', '-');
