import 'package:flutter_test/flutter_test.dart';
import 'package:moepurekit/models/download_source.dart';

void main() {
  test('magnet display names are never treated as local files', () {
    expect(
      classifyDownloadSource('magnet:?xt=urn:btih:abc&dn=file.torrent'),
      DownloadSourceKind.link,
    );
    expect(
      classifyDownloadSource('magnet:?xt=urn:btih:abc&dn=file.metalink'),
      DownloadSourceKind.link,
    );
  });

  test('local and remote torrent descriptors are classified by URL path', () {
    expect(
      classifyDownloadSource(r'C:\Downloads\seed.torrent'),
      DownloadSourceKind.torrentFile,
    );
    expect(
      classifyDownloadSource('https://example.com/seed.torrent?token=abc'),
      DownloadSourceKind.torrentFile,
    );
    expect(
      classifyDownloadSource('https://example.com/seed.meta4'),
      DownloadSourceKind.metalinkFile,
    );
  });
}
