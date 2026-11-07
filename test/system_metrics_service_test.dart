import 'package:flutter_test/flutter_test.dart';
import 'package:moepurekit/services/system_metrics_service.dart';

void main() {
  test('keeps CPU and memory metrics when disk activity is unavailable', () {
    final metrics = SystemMetrics.fromJson({
      'cpu': 37.5,
      'memory': 62.0,
      'diskActive': -1,
      'diskUsed': 48.0,
      'memoryUsedBytes': 8 * 1024 * 1024 * 1024,
      'memoryTotalBytes': 16 * 1024 * 1024 * 1024,
      'readBytesPerSec': -1,
      'writeBytesPerSec': -1,
      'driveFreeBytes': 200,
      'driveTotalBytes': 400,
    });

    expect(metrics.cpuPercent, 37.5);
    expect(metrics.memoryPercent, 62.0);
    expect(metrics.diskActivePercent, -1);
    expect(metrics.diskUsedPercent, 48.0);
    expect(metrics.diskReadBytesPerSecond, -1);
    expect(metrics.diskWriteBytesPerSecond, -1);
  });
  test('keeps disk occupancy and disk activity as independent values', () {
    final metrics = SystemMetrics.fromJson({
      'cpu': 12.0,
      'memory': 44.0,
      'diskActive': 31.0,
      'diskUsed': 78.0,
      'memoryUsedBytes': 4 * 1024 * 1024 * 1024,
      'memoryTotalBytes': 8 * 1024 * 1024 * 1024,
      'readBytesPerSec': 2 * 1024 * 1024,
      'writeBytesPerSec': 512 * 1024,
      'driveFreeBytes': 88,
      'driveTotalBytes': 400,
    });

    expect(metrics.diskUsedPercent, 78.0);
    expect(metrics.diskActivePercent, 31.0);
    expect(metrics.diskReadBytesPerSecond, 2 * 1024 * 1024);
    expect(metrics.diskWriteBytesPerSecond, 512 * 1024);
  });

}
