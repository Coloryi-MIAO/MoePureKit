import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';

class SignatureMatch {
  const SignatureMatch({required this.path, required this.name, required this.sha256});
  final String path;
  final String name;
  final String sha256;
}

class SignatureScanSummary {
  const SignatureScanSummary({required this.scannedFiles, required this.skippedFiles, required this.matches});
  final int scannedFiles;
  final int skippedFiles;
  final List<SignatureMatch> matches;
}

/// Scans a directory in one worker isolate; each file is streamed through
/// SHA-256 so neither file contents nor hashing work block the UI isolate.
Future<SignatureScanSummary> scanDirectoryForSignatures(
  String directoryPath,
  Map<String, String> signatures, {
  void Function(int scanned, int skipped)? onProgress,
}) async {
  final messages = ReceivePort();
  final errors = ReceivePort();
  final completer = Completer<SignatureScanSummary>();
  final messageSubscription = messages.listen((message) {
    if (message is! Map) return;
    switch (message['type']) {
      case 'progress':
        onProgress?.call((message['scanned'] as num).toInt(), (message['skipped'] as num).toInt());
        break;
      case 'result':
        if (!completer.isCompleted) {
          final rawMatches = (message['matches'] as List).cast<Map>();
          completer.complete(SignatureScanSummary(
            scannedFiles: (message['scanned'] as num).toInt(),
            skippedFiles: (message['skipped'] as num).toInt(),
            matches: rawMatches.map((item) => SignatureMatch(
              path: item['path'] as String,
              name: item['name'] as String,
              sha256: item['sha256'] as String,
            )).toList(growable: false),
          ));
        }
        break;
      case 'error':
        if (!completer.isCompleted) {
          completer.completeError(StateError(message['message']?.toString() ?? '指纹扫描失败'));
        }
        break;
    }
  });
  final errorSubscription = errors.listen((message) {
    if (!completer.isCompleted) {
      completer.completeError(StateError('扫描线程异常：$message'));
    }
  });
  Isolate? worker;
  try {
    worker = await Isolate.spawn<Map<String, Object?>>(
      _signatureScanWorker,
      <String, Object?>{
        'directory': directoryPath,
        'signatures': signatures,
        'sendPort': messages.sendPort,
      },
      onError: errors.sendPort,
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

void _signatureScanWorker(Map<String, Object?> message) {
  unawaited(_runSignatureScan(message));
}

Future<void> _runSignatureScan(Map<String, Object?> message) async {
  final sendPort = message['sendPort'] as SendPort;
  final root = Directory(message['directory'] as String);
  final signatures = (message['signatures'] as Map).cast<String, String>();
  var scanned = 0;
  var skipped = 0;
  var lastReport = DateTime.now();
  final matches = <Map<String, String>>[];
  try {
    if (!await root.exists()) throw FileSystemException('目录不存在', root.path);
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (await FileSystemEntity.type(entity.path, followLinks: false) != FileSystemEntityType.file) continue;
      try {
        final digest = (await sha256.bind(File(entity.path).openRead()).first).toString();
        scanned++;
        final name = signatures[digest.toLowerCase()];
        if (name != null && matches.length < 500) {
          matches.add({'path': entity.path, 'name': name, 'sha256': digest});
        }
      } catch (_) {
        skipped++;
      }
      final now = DateTime.now();
      if (scanned % 16 == 0 || now.difference(lastReport).inMilliseconds >= 500) {
        sendPort.send({'type': 'progress', 'scanned': scanned, 'skipped': skipped});
        lastReport = now;
      }
    }
    sendPort.send({'type': 'result', 'scanned': scanned, 'skipped': skipped, 'matches': matches});
  } catch (error) {
    sendPort.send({'type': 'error', 'message': error.toString()});
  }
}
