enum DownloadSourceKind { link, torrentFile, metalinkFile }

DownloadSourceKind classifyDownloadSource(String source) {
  final value = source.trim().toLowerCase();
  if (value.startsWith('magnet:')) return DownloadSourceKind.link;
  final path = value.split('?').first;
  if (path.endsWith('.torrent')) return DownloadSourceKind.torrentFile;
  if (path.endsWith('.metalink') || path.endsWith('.meta4')) {
    return DownloadSourceKind.metalinkFile;
  }
  return DownloadSourceKind.link;
}
