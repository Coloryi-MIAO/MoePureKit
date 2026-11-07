class CatalogItem {
  const CatalogItem({
    required this.title,
    required this.url,
    this.version = '',
    this.size = '',
    this.sha256 = '',
    this.category = '',
    this.description = '',
    this.tags = const [],
    this.source = '',
  });

  final String title;
  final String url;
  final String version;
  final String size;
  final String sha256;
  final String category;
  final String description;
  final List<String> tags;
  final String source;

  factory CatalogItem.fromJson(Map<String, dynamic> json) {
    final title = (json['title'] as String? ?? json['name'] as String? ?? '')
        .trim();
    final url =
        (json['url'] as String? ?? json['download_url'] as String? ?? '')
            .trim();
    if (title.isEmpty) throw const FormatException('条目缺少 title');
    final uri = Uri.tryParse(url);
    if (uri == null ||
        !const {
          'http',
          'https',
          'ftp',
          'magnet',
          'ed2k',
        }.contains(uri.scheme.toLowerCase()) ||
        (!const {'magnet', 'ed2k'}.contains(uri.scheme.toLowerCase()) &&
            uri.host.isEmpty) ||
        (uri.scheme.toLowerCase() == 'magnet' &&
            uri.queryParametersAll['xt']?.any(
                  (value) =>
                      value.startsWith('urn:btih:') ||
                      value.startsWith('urn:btmh:'),
                ) !=
                true) ||
        (uri.scheme.toLowerCase() == 'ed2k' &&
            !url.startsWith('ed2k://|file|'))) {
      throw FormatException('“$title”需要有效的 HTTP、FTP、磁力或 ed2k 下载地址');
    }
    final sha256 = json['sha256'] as String? ?? '';
    if (sha256.isNotEmpty && !RegExp(r'^[A-Fa-f0-9]{64}$').hasMatch(sha256)) {
      throw FormatException('“$title”的 SHA-256 必须是 64 位十六进制字符串');
    }
    final rawTags = json['tags'];
    final tags = rawTags is List
        ? rawTags.whereType<String>().toList()
        : const <String>[];
    return CatalogItem(
      title: title,
      url: url,
      version: json['version'] as String? ?? '',
      size: json['size'] as String? ?? '',
      sha256: sha256,
      category: json['category'] as String? ?? '',
      description: json['description'] as String? ?? '',
      tags: tags,
      source: json['source'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    'title': title,
    'url': url,
    'version': version,
    'size': size,
    'sha256': sha256,
    'category': category,
    'description': description,
    if (tags.isNotEmpty) 'tags': tags,
    if (source.isNotEmpty) 'source': source,
  };
}
