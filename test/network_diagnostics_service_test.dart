import 'package:flutter_test/flutter_test.dart';
import 'package:moepurekit/services/network_diagnostics_service.dart';

void main() {
  group('parsePingOutput', () {
    test('parses Windows English responses and computes packet loss', () {
      final summary = parsePingOutput('''
Reply from 1.1.1.1: bytes=32 time=10ms TTL=58
Reply from 1.1.1.1: bytes=32 time=12ms TTL=58
Request timed out.
Reply from 1.1.1.1: bytes=32 time=14ms TTL=58
Reply from 1.1.1.1: bytes=32 time=12ms TTL=58
''', sent: 5);

      expect(summary.sent, 5);
      expect(summary.received, 4);
      expect(summary.packetLossPercent, 20);
      expect(summary.minMs, 10);
      expect(summary.maxMs, 14);
      expect(summary.averageMs, 12);
      expect(summary.jitterMs, 2);
    });

    test('parses Chinese output and sub-millisecond responses', () {
      final summary = parsePingOutput('''
来自 1.1.1.1 的回复: 字节=32 时间=8ms TTL=58
来自 1.1.1.1 的回复: 字节=32 时间<1ms TTL=58
''', sent: 2);

      expect(summary.received, 2);
      expect(summary.samplesMs, [8, 0.5]);
      expect(summary.packetLossPercent, 0);
    });

    test('reports all packets lost when no response rows are present', () {
      final summary = parsePingOutput('Request timed out.\n', sent: 5);
      expect(summary.received, 0);
      expect(summary.packetLossPercent, 100);
      expect(summary.averageMs, isNull);
      expect(summary.jitterMs, isNull);
    });
  });
}
