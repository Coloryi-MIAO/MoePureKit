import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:moepurekit/models/app_settings.dart';
import 'package:moepurekit/services/aria2_service.dart';

void main() {
  test('passes rpc secret and per-task HTTP credentials to aria2', () async {
    http.Request? request;
    final service = Aria2Service(
      const AppSettings(
        aria2RpcSecret: 'local-secret',
        defaultUserAgent: 'MoePureKit Test',
        defaultCookie: 'session=local',
        defaultHeaders: 'X-Test: yes',
      ),
      client: MockClient((value) async {
        request = value;
        return http.Response('{"jsonrpc":"2.0","id":"1","result":"gid"}', 200);
      }),
    );

    final gid = await service.addUri('https://example.com/archive.zip');
    final payload = jsonDecode(request!.body) as Map<String, dynamic>;
    final params = payload['params'] as List<dynamic>;
    final options = params.last as Map<String, dynamic>;
    expect(gid, 'gid');
    expect(params.first, 'token:local-secret');
    expect(options['header'], contains('Cookie: session=local'));
    expect(options['header'], contains('User-Agent: MoePureKit Test'));
    expect(options['follow-torrent'], 'true');
    service.close();
  });

  test('rejects unsupported download URLs before making an RPC call', () async {
    var requests = 0;
    final service = Aria2Service(
      const AppSettings(),
      client: MockClient((_) async {
        requests++;
        return http.Response('{}', 200);
      }),
    );

    await expectLater(
      service.addUri('file:///private/file'),
      throwsA(isA<FormatException>()),
    );
    expect(requests, 0);
    service.close();
  });

  test(
    'uses login headers when fetching a remote Metalink descriptor',
    () async {
      final requests = <http.BaseRequest>[];
      final service = Aria2Service(
        const AppSettings(),
        client: MockClient((request) async {
          requests.add(request);
          if (request.method == 'GET') {
            return http.Response('<metalink/>', 200);
          }
          return http.Response(
            '{"jsonrpc":"2.0","id":"1","result":["metalink-gid"]}',
            200,
          );
        }),
      );

      final gids = await service.addMetalink(
        'https://downloads.example.test/file.meta4',
        userAgent: 'MoePureKit test client',
        referer: 'https://example.test/account',
        cookie: 'session=metalink',
        headers: 'X-Source: catalog',
      );

      expect(gids, ['metalink-gid']);
      expect(requests, hasLength(2));
      expect(requests.first.headers['user-agent'], 'MoePureKit test client');
      expect(requests.first.headers['referer'], 'https://example.test/account');
      expect(requests.first.headers['cookie'], 'session=metalink');
      expect(requests.first.headers['X-Source'], 'catalog');
      service.close();
    },
  );

  test(
    'rejects malformed custom HTTP headers before making an RPC call',
    () async {
      var requests = 0;
      final service = Aria2Service(
        const AppSettings(),
        client: MockClient((_) async {
          requests++;
          return http.Response('{}', 200);
        }),
      );

      await expectLater(
        service.addUri(
          'https://example.test/file.zip',
          headers: 'missing-colon',
        ),
        throwsA(isA<FormatException>()),
      );
      expect(requests, 0);
      service.close();
    },
  );
}
