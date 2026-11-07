class DownloadTask {
  const DownloadTask({
    required this.gid,
    required this.name,
    required this.status,
    required this.completedLength,
    required this.totalLength,
    required this.downloadSpeed,
    required this.remainingSeconds,
  });

  final String gid;
  final String name;
  final String status;
  final int completedLength;
  final int totalLength;
  final int downloadSpeed;
  final int remainingSeconds;

  double get progress => totalLength <= 0 ? 0 : completedLength / totalLength;

  factory DownloadTask.fromAria2(Map<String, dynamic> json) {
    final files = json['files'] as List<dynamic>? ?? const [];
    final firstFile = files.isEmpty
        ? const <String, dynamic>{}
        : files.first as Map<String, dynamic>;
    final rawPath = firstFile['path'] as String? ?? '';
    final name = rawPath.isEmpty
        ? (json['gid'] as String? ?? '未知任务')
        : rawPath.split(RegExp(r'[/\\]')).last;
    final total = int.tryParse(json['totalLength']?.toString() ?? '') ?? 0;
    final completed =
        int.tryParse(json['completedLength']?.toString() ?? '') ?? 0;
    final speed = int.tryParse(json['downloadSpeed']?.toString() ?? '') ?? 0;
    final remaining = speed <= 0 ? 0 : ((total - completed) / speed).ceil();

    return DownloadTask(
      gid: json['gid'] as String? ?? '',
      name: name,
      status: json['status'] as String? ?? 'unknown',
      completedLength: completed,
      totalLength: total,
      downloadSpeed: speed,
      remainingSeconds: remaining,
    );
  }
}
