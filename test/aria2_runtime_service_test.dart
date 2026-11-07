import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:moepurekit/models/app_settings.dart';
import 'package:moepurekit/services/aria2_runtime_service.dart';
import 'package:moepurekit/services/aria2_service.dart';

void main() {
  test(
    'bundled aria2 starts with authenticated loopback RPC and shuts down cleanly',
    () async {
      final portProbe = await ServerSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      final port = portProbe.port;
      await portProbe.close();
      final temporaryDirectory = await Directory.systemTemp.createTemp(
        'moepurekit-aria2-test-',
      );
      final runtime = Aria2RuntimeService(
        executablePath: File('assets/aria2/windows-x64/aria2c.exe')
            .absolute
            .path,
        dataDirectory:
            '${temporaryDirectory.path}${Platform.pathSeparator}state',
        acquireRuntimeMutex: () async => true,
        releaseRuntimeMutex: () async {},
        attachAria2Process: (processId) async {},
      );
      final settings = AppSettings(
        aria2RpcUrl: 'http://127.0.0.1:$port/jsonrpc',
        aria2RpcSecret: 'runtime-test-secret',
        downloadDirectory:
            '${temporaryDirectory.path}${Platform.pathSeparator}downloads',
      );
      final service = Aria2Service(settings);
      final downloadServer = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      final receivedRequest = Completer<HttpRequest>();
      final serverSubscription = downloadServer.listen((request) async {
        if (!receivedRequest.isCompleted) receivedRequest.complete(request);
        request.response
          ..statusCode = HttpStatus.ok
          ..write('aria2 test payload');
        await request.response.close();
      });

      try {
        final starts = await Future.wait([
          runtime.start(settings),
          runtime.start(settings),
        ]);
        expect(starts, everyElement('内置 aria2 已启动'));
        expect(runtime.isRunning, isTrue);
        final stat = await service.globalStat();
        expect(stat['numActive'], isNotNull);
        expect(stat['numWaiting'], isNotNull);
        await service.addUri(
          'http://127.0.0.1:${downloadServer.port}/sample.bin',
          userAgent: 'MoePureKit integration test',
          referer: 'https://example.test/source',
          cookie: 'session=integration',
          headers: 'X-Integration: yes',
        );
        final request = await receivedRequest.future.timeout(
          const Duration(seconds: 10),
        );
        expect(
          request.headers.value(HttpHeaders.userAgentHeader),
          'MoePureKit integration test',
        );
        expect(
          request.headers.value(HttpHeaders.refererHeader),
          'https://example.test/source',
        );
        expect(
          request.headers.value(HttpHeaders.cookieHeader),
          'session=integration',
        );
        expect(request.headers.value('X-Integration'), 'yes');
        await runtime.stop();
        expect(runtime.isRunning, isFalse);
      } finally {
        await serverSubscription.cancel();
        await downloadServer.close(force: true);
        service.close();
        await runtime.stop();
        await temporaryDirectory.delete(recursive: true);
      }
    },
    skip: !Platform.isWindows,
    timeout: const Timeout(Duration(seconds: 30)),
  );
}
