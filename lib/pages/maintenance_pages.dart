import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/signature_scan_service.dart';
import '../config/app_translations.dart';
import '../widgets/motion_settings.dart';

class FileManagerPage extends StatefulWidget {
  const FileManagerPage({super.key});

  @override
  State<FileManagerPage> createState() => _FileManagerPageState();
}

class _FileManagerEntry {
  const _FileManagerEntry({required this.entity, required this.name, required this.isDirectory, required this.size, required this.modified});
  final FileSystemEntity entity;
  final String name;
  final bool isDirectory;
  final int size;
  final DateTime modified;
}

class _FileManagerPageState extends State<FileManagerPage> {
  late String _path;
  final TextEditingController _searchController = TextEditingController();
  List<_FileManagerEntry> _entries = <_FileManagerEntry>[];
  bool _loading = false;
  bool _limitReached = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _path = Platform.environment['USERPROFILE'] ?? Directory.current.path;
    unawaited(_load());
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final result = <_FileManagerEntry>[];
      var limitReached = false;
      var seen = 0;
      await for (final entity in Directory(_path).list(followLinks: false)) {
        if (seen++ >= 1200) {
          limitReached = true;
          break;
        }
        try {
          final type = await FileSystemEntity.type(entity.path, followLinks: false);
          if (type == FileSystemEntityType.link) continue;
          final stat = await entity.stat();
          final isDirectory = type == FileSystemEntityType.directory;
          result.add(_FileManagerEntry(
            entity: entity,
            name: entity.path.split(RegExp(r'[\\/]')).where((part) => part.isNotEmpty).last,
            isDirectory: isDirectory,
            size: isDirectory ? 0 : stat.size,
            modified: stat.modified,
          ));
        } catch (_) {
          // Skip entries that disappear or are inaccessible during enumeration.
        }
      }
      result.sort((a, b) {
        if (a.isDirectory != b.isDirectory) return a.isDirectory ? -1 : 1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
      if (mounted) setState(() { _entries = result; _limitReached = limitReached; });
    } catch (error) {
      if (mounted) setState(() => _error = '无法读取此目录：$error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _chooseDirectory() async {
    final path = await getDirectoryPath(initialDirectory: _path, confirmButtonText: '打开此文件夹');
    if (path != null && mounted) {
      setState(() { _path = path; _searchController.clear(); });
      await _load();
    }
  }

  Future<void> _goParent() async {
    final parent = Directory(_path).parent.path;
    if (parent == _path) return;
    setState(() => _path = parent);
    await _load();
  }

  Future<void> _openEntry(_FileManagerEntry entry) async {
    if (entry.isDirectory) {
      setState(() => _path = entry.entity.path);
      await _load();
      return;
    }
    try {
      if (Platform.isWindows) {
        await Process.start('explorer.exe', [entry.entity.path], runInShell: false);
      } else if (Platform.isMacOS) {
        await Process.start('open', [entry.entity.path]);
      } else {
        await Process.start('xdg-open', [entry.entity.path]);
      }
    } catch (error) {
      _notify('打开失败：$error');
    }
  }

  Future<void> _copyPath(_FileManagerEntry entry) async {
    await Clipboard.setData(ClipboardData(text: entry.entity.path));
    _notify('路径已复制');
  }

  Future<void> _rename(_FileManagerEntry entry) async {
    final controller = TextEditingController(text: entry.name);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const LocalizedText('重命名'),
        content: TextField(controller: controller, autofocus: true, decoration: const InputDecoration(labelText: '新名称')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const LocalizedText('取消')),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: const LocalizedText('确定')),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.isEmpty || name == entry.name) return;
    if (!_isSafeLeafName(name)) { _notify('名称包含无效字符，或不能是 . / ..'); return; }
    final destination = '${Directory(_path).path}${Platform.pathSeparator}$name';
    if (await FileSystemEntity.type(destination, followLinks: false) != FileSystemEntityType.notFound) { _notify('目标名称已存在，未执行重命名。'); return; }
    try {
      await entry.entity.rename(destination);
      await _load();
    } catch (error) {
      _notify('重命名失败：$error');
    }
  }

  Future<void> _delete(_FileManagerEntry entry) async {
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const LocalizedText('确认删除？'),
        content: LocalizedText(entry.isDirectory
            ? '将永久删除文件夹“${entry.name}”及其内容。此操作无法撤销。'
            : '将永久删除文件“${entry.name}”。此操作无法撤销。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const LocalizedText('取消')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const LocalizedText('删除')),
        ],
      ),
    );
    if (approved != true) return;
    try {
      if (entry.isDirectory) {
        await Directory(entry.entity.path).delete(recursive: true);
      } else {
        await File(entry.entity.path).delete();
      }
      await _load();
    } catch (error) {
      _notify('删除失败（可能被占用或需要权限）：$error');
    }
  }

  Future<void> _copyFile(_FileManagerEntry entry, {required bool move}) async {
    final target = await getDirectoryPath(confirmButtonText: '选择目标文件夹');
    if (target == null) return;
    final sourcePath = entry.entity.path;
    final destination = '$target${Platform.pathSeparator}${entry.name}';
    final normalizedSource = sourcePath.toLowerCase().replaceAll('/', '\\');
    final normalizedTarget = target.toLowerCase().replaceAll('/', '\\');
    if (entry.isDirectory && (normalizedTarget == normalizedSource || normalizedTarget.startsWith('$normalizedSource\\'))) {
      _notify('不能将文件夹复制或移动到自身内部。');
      return;
    }
    if (await FileSystemEntity.type(destination, followLinks: false) != FileSystemEntityType.notFound) {
      _notify('目标位置已存在同名项目，为避免覆盖已取消操作。');
      return;
    }
    try {
      if (!entry.isDirectory) {
        if (move) {
          try {
            await File(sourcePath).rename(destination);
          } on FileSystemException {
            await File(sourcePath).copy(destination);
            await File(sourcePath).delete();
          }
        } else {
          await File(sourcePath).copy(destination);
        }
      } else {
        if (move) {
          try {
            await Directory(sourcePath).rename(destination);
          } on FileSystemException {
            await _copyDirectoryTree(Directory(sourcePath), Directory(destination));
            await Directory(sourcePath).delete(recursive: true);
          }
        } else {
          await _copyDirectoryTree(Directory(sourcePath), Directory(destination));
        }
      }
      await _load();
      _notify(move ? '项目已移动' : '项目已复制');
    } catch (error) {
      _notify('操作失败：$error');
    }
  }

  Future<void> _copyDirectoryTree(Directory source, Directory destination) async {
    await destination.create(recursive: true);
    await for (final entity in source.list(followLinks: false)) {
      final type = await FileSystemEntity.type(entity.path, followLinks: false);
      final leafName = entity.path.split(RegExp(r'[\\/]')).where((part) => part.isNotEmpty).last;
      final target = '${destination.path}${Platform.pathSeparator}$leafName';
      if (type == FileSystemEntityType.directory) {
        await _copyDirectoryTree(Directory(entity.path), Directory(target));
      } else if (type == FileSystemEntityType.file) {
        await File(entity.path).copy(target);
      }
    }
  }

  Future<void> _createFolder() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const LocalizedText('新建文件夹'),
        content: TextField(controller: controller, autofocus: true, decoration: const InputDecoration(labelText: '文件夹名称')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const LocalizedText('取消')),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: const LocalizedText('创建')),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.isEmpty) return;
    if (!_isSafeLeafName(name)) { _notify('名称包含无效字符，或不能是 . / ..'); return; }
    try {
      await Directory('$_path${Platform.pathSeparator}$name').create();
      await _load();
    } catch (error) {
      _notify('创建失败：$error');
    }
  }

  bool _isSafeLeafName(String value) {
    if (value == '.' || value == '..' || value.trim() != value || value.isEmpty) return false;
    if (value.contains('/') || value.contains('\\') || RegExp(r'[<>:"|?*\x00-\x1F]').hasMatch(value)) return false;
    if (value.endsWith('.') || value.endsWith(' ')) return false;
    return true;
  }

  void _notify(String message) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: LocalizedText(message)));
  }

  String _date(DateTime value) {
    final d = value.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final query = _searchController.text.trim().toLowerCase();
    final filtered = _entries.where((entry) => entry.name.toLowerCase().contains(query)).toList(growable: false);
    return Padding(
      padding: const EdgeInsets.fromLTRB(26, 22, 26, 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _MaintenanceHeader(eyebrow: 'FILES', title: '文件管理', subtitle: '浏览本机目录，进行常用文件整理操作。'),
          const SizedBox(height: 16),
          Row(children: [
            OutlinedButton.icon(onPressed: _goParent, icon: const Icon(Icons.arrow_upward, size: 16), label: const LocalizedText('上一级')),
            const SizedBox(width: 8),
            OutlinedButton.icon(onPressed: _chooseDirectory, icon: const Icon(Icons.folder_open_outlined, size: 16), label: const LocalizedText('选择目录')),
            const SizedBox(width: 8),
            OutlinedButton.icon(onPressed: _createFolder, icon: const Icon(Icons.create_new_folder_outlined, size: 16), label: const LocalizedText('新建文件夹')),
            const Spacer(),
            IconButton(tooltip: '刷新', onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh)),
          ]),
          const SizedBox(height: 8),
          TextField(
            controller: _searchController,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: '搜索当前目录', isDense: true, border: OutlineInputBorder()),
          ),
          const SizedBox(height: 8),
          _MaintenanceCard(child: Row(children: [const Icon(Icons.folder_outlined, size: 17, color: Color(0xFF718A78)), const SizedBox(width: 8), Expanded(child: LocalizedText(_path, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11)))])),
          const SizedBox(height: 10),
          if (_limitReached) const Padding(padding: EdgeInsets.only(bottom: 6), child: LocalizedText('当前目录项目较多，仅显示前 1,200 项；可使用搜索缩小范围。', style: TextStyle(fontSize: 10, color: Color(0xFF9A805E)))),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(child: LocalizedText(_error!, style: const TextStyle(color: Color(0xFFB65F56))))
                    : filtered.isEmpty
                        ? const Center(child: LocalizedText('此目录为空，或没有匹配的文件。', style: TextStyle(color: Color(0xFF858C86))))
                        : ListView.separated(
                            itemCount: filtered.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 6),
                            itemBuilder: (context, index) {
                              final entry = filtered[index];
                              return _MaintenanceCard(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                child: Row(children: [
                                  Icon(entry.isDirectory ? Icons.folder_outlined : Icons.insert_drive_file_outlined, color: entry.isDirectory ? const Color(0xFFB18E55) : const Color(0xFF718A78), size: 20),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: InkWell(
                                      onTap: () => _openEntry(entry),
                                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                        LocalizedText(entry.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                                        const SizedBox(height: 3),
                                        LocalizedText(entry.isDirectory ? '文件夹 · ${_date(entry.modified)}' : '${_formatBytes(entry.size)} · ${_date(entry.modified)}', style: const TextStyle(fontSize: 10, color: Color(0xFF858C86))),
                                      ]),
                                    ),
                                  ),
                                  IconButton(tooltip: '复制路径', visualDensity: VisualDensity.compact, onPressed: () => _copyPath(entry), icon: const Icon(Icons.content_copy_outlined, size: 16)),
                                  PopupMenuButton<String>(
                                    tooltip: '更多操作',
                                    onSelected: (action) {
                                      switch (action) {
                                        case 'rename':
                                          _rename(entry);
                                          break;
                                        case 'delete':
                                          _delete(entry);
                                          break;
                                        case 'copy':
                                          _copyFile(entry, move: false);
                                          break;
                                        case 'move':
                                          _copyFile(entry, move: true);
                                          break;
                                      }
                                    },
                                    itemBuilder: (_) => [
                                      const PopupMenuItem(value: 'rename', child: LocalizedText('重命名')),
                                      const PopupMenuItem(value: 'copy', child: LocalizedText('复制到…')),
                                      const PopupMenuItem(value: 'move', child: LocalizedText('移动到…')),
                                      const PopupMenuItem(value: 'delete', child: LocalizedText('删除')),
                                    ],
                                  ),
                                ]),
                              );
                            },
                          ),
          ),
        ],
      ),
    );
  }
}

class CleanupPage extends StatefulWidget {
  const CleanupPage({super.key, required this.onActivityChanged});
  final ValueChanged<bool> onActivityChanged;
  @override
  State<CleanupPage> createState() => _CleanupPageState();
}

class _CleanupFile {
  const _CleanupFile(this.path, this.size);
  final String path;
  final int size;
}

class _CleanupPageState extends State<CleanupPage> {
  List<_CleanupFile> _files = <_CleanupFile>[];
  bool _scanning = false;
  bool _cleaning = false;
  int _skipped = 0;
  String _status = '仅扫描 Windows 临时目录中的旧文件；不会自动清理下载、桌面或文档。';

  List<String> get _roots {
    final candidates = <String>[
      Platform.environment['TEMP'] ?? '',
      Platform.environment['TMP'] ?? '',
      if (Platform.isWindows && (Platform.environment['WINDIR'] ?? '').isNotEmpty)
        '${Platform.environment['WINDIR']}\\Temp',
    ];
    final systemDrive = (Platform.environment['SystemDrive'] ?? 'C:').toLowerCase();
    return candidates
        .where((path) => path.isNotEmpty && path.length >= 2 && path.substring(0, 2).toLowerCase() == systemDrive)
        .toSet()
        .toList(growable: false);
  }

  Future<void> _scan() async {
    if (!Platform.isWindows) {
      setState(() => _status = 'C 盘临时目录清理仅支持 Windows。');
      return;
    }
    setState(() { _scanning = true; _files = <_CleanupFile>[]; _skipped = 0; _status = '正在扫描临时文件…'; });
    widget.onActivityChanged(true);
    final found = <_CleanupFile>[];
    final threshold = DateTime.now().subtract(const Duration(hours: 24));
    var skipped = 0;
    for (final rootPath in _roots) {
      if (found.length >= 50000) break;
      final root = Directory(rootPath);
      if (!await root.exists()) continue;
      try {
        await for (final entity in root.list(recursive: true, followLinks: false)) {
          if (found.length >= 50000) break;
          try {
            final type = await FileSystemEntity.type(entity.path, followLinks: false);
            if (type != FileSystemEntityType.file) continue;
            final stat = await entity.stat();
            if (stat.modified.isBefore(threshold)) found.add(_CleanupFile(entity.path, stat.size));
          } catch (_) {
            skipped++;
          }
        }
      } catch (_) {
        skipped++;
      }
    }
    if (mounted) {
      setState(() {
        _files = found;
        _skipped = skipped;
        _scanning = false;
        final bytes = found.fold<int>(0, (sum, file) => sum + file.size);
        _status = '扫描完成：${found.length} 个超过 24 小时的临时文件，约 ${_formatBytes(bytes)}。${found.length >= 50000 ? '已达到 50,000 项安全上限，请分批处理。' : ''}';
      });
    }
    widget.onActivityChanged(false);
  }

  Future<void> _clean() async {
    if (_files.isEmpty || _cleaning) return;
    final count = _files.length;
    final bytes = _files.fold<int>(0, (sum, file) => sum + file.size);
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const LocalizedText('确认清理临时文件？'),
        content: LocalizedText('将尝试删除 $count 个超过 24 小时的临时文件，预计释放 ${_formatBytes(bytes)}。被系统占用或权限不足的文件会自动跳过。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const LocalizedText('取消')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const LocalizedText('确认清理')),
        ],
      ),
    );
    if (approved != true) return;
    setState(() { _cleaning = true; _status = '正在清理…'; });
    widget.onActivityChanged(true);
    var deleted = 0;
    var failed = 0;
    var freed = 0;
    for (final item in _files) {
      try {
        await File(item.path).delete();
        deleted++;
        freed += item.size;
      } catch (_) {
        failed++;
      }
    }
    if (mounted) {
      setState(() {
        _cleaning = false;
        _files = <_CleanupFile>[];
        _status = '已删除 $deleted 个文件，释放 ${_formatBytes(freed)}；跳过 $failed 个占用或无权限文件。';
      });
    }
    widget.onActivityChanged(false);
  }

  Future<void> _openStorageSettings() async {
    try {
      await Process.start('explorer.exe', ['ms-settings:storage'], runInShell: false);
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: LocalizedText('无法打开存储设置：$error')));
    }
  }

  @override
  Widget build(BuildContext context) => _MaintenanceScroll(
    children: [
      const _MaintenanceHeader(eyebrow: 'STORAGE CARE', title: 'C 盘清理', subtitle: '先扫描与预览，再由你确认删除。'),
      const SizedBox(height: 18),
      _MaintenanceCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Row(children: [Icon(Icons.cleaning_services_outlined, color: Color(0xFF718A78)), SizedBox(width: 9), LocalizedText('安全临时文件清理', style: TextStyle(fontWeight: FontWeight.w600))]),
        const SizedBox(height: 8),
        const LocalizedText('扫描当前用户 TEMP/TMP 与 Windows Temp 目录，只列出 24 小时以前的普通文件。不会触碰个人文档、下载目录、注册表或系统组件存储。', style: TextStyle(fontSize: 11, color: Color(0xFF858C86), height: 1.5)),
        const SizedBox(height: 14),
        Wrap(spacing: 8, runSpacing: 8, children: [
          FilledButton.icon(onPressed: _scanning || _cleaning ? null : _scan, icon: const Icon(Icons.search, size: 17), label: const LocalizedText('扫描临时文件')),
          OutlinedButton.icon(onPressed: _cleaning || _files.isEmpty ? null : _clean, icon: const Icon(Icons.delete_outline, size: 17), label: LocalizedText(_cleaning ? '正在清理…' : '确认清理 (${_files.length})')),
          TextButton.icon(onPressed: _openStorageSettings, icon: const Icon(Icons.settings_outlined, size: 17), label: const LocalizedText('Windows 存储设置')),
        ]),
      ])),
      const SizedBox(height: 12),
      _MaintenanceCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const LocalizedText('扫描状态', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        LocalizedText(_status, style: const TextStyle(fontSize: 11, color: Color(0xFF737B74), height: 1.45)),
        if (_skipped > 0) ...[const SizedBox(height: 5), LocalizedText('读取失败或无权限：$_skipped 项', style: const TextStyle(fontSize: 10, color: Color(0xFF9A805E)))],
        if (_scanning || _cleaning) ...[const SizedBox(height: 10), const LinearProgressIndicator(minHeight: 3)],
      ])),
      if (_files.isNotEmpty) ...[
        const SizedBox(height: 12),
        _MaintenanceCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const LocalizedText('待清理项目预览', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          for (final item in _files.take(12)) Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(children: [const Icon(Icons.description_outlined, size: 14, color: Color(0xFF8A928B)), const SizedBox(width: 8), Expanded(child: LocalizedText(item.path, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10))), LocalizedText(_formatBytes(item.size), style: const TextStyle(fontSize: 10, color: Color(0xFF858C86)))]),
          ),
          if (_files.length > 12) LocalizedText('另有 ${_files.length - 12} 项未展开', style: const TextStyle(fontSize: 10, color: Color(0xFF858C86))),
        ])),
      ],
    ],
  );
}

class SecurityPage extends StatefulWidget {
  const SecurityPage({super.key, required this.onActivityChanged});
  final ValueChanged<bool> onActivityChanged;
  @override
  State<SecurityPage> createState() => _SecurityPageState();
}

class _SecurityPageState extends State<SecurityPage> {
  final Map<String, String> _signatures = <String, String>{};
  String? _directory;
  String _status = '载入本地 SHA-256 指纹库…';
  bool _loadingDatabase = true;
  bool _scanning = false;
  bool _defenderScanning = false;
  int _scanned = 0;
  int _skipped = 0;
  List<SignatureMatch> _matches = <SignatureMatch>[];
  String? _defenderResult;

  @override
  void initState() {
    super.initState();
    unawaited(_loadDatabase());
  }

  Future<File> get _localDatabase async {
    final base = Platform.environment['LOCALAPPDATA'] ?? Directory.systemTemp.path;
    final folder = Directory('$base${Platform.pathSeparator}MoePureKit');
    if (!await folder.exists()) await folder.create(recursive: true);
    return File('${folder.path}${Platform.pathSeparator}sha256_signatures.local.json');
  }

  Future<void> _loadDatabase() async {
    try {
      final raw = await rootBundle.loadString('assets/sha256_signatures.json');
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      for (final item in (decoded['entries'] as List? ?? const [])) {
        if (item is Map) {
          final hash = item['sha256']?.toString().toLowerCase() ?? '';
          if (RegExp(r'^[a-f0-9]{64}$').hasMatch(hash)) {
            _signatures[hash] = item['name']?.toString() ?? '本地特征';
          }
        }
      }
      final local = await _localDatabase;
      if (await local.exists()) {
        final localData = jsonDecode(await local.readAsString());
        if (localData is Map) {
          for (final entry in localData.entries) {
            final hash = entry.key.toString().toLowerCase();
            if (RegExp(r'^[a-f0-9]{64}$').hasMatch(hash)) {
              _signatures[hash] = entry.value.toString();
            }
          }
        }
      }
      if (mounted) setState(() { _loadingDatabase = false; _status = '本地库已载入 ${_signatures.length} 条指纹。'; });
    } catch (error) {
      if (mounted) setState(() { _loadingDatabase = false; _status = '本地指纹库载入失败：$error'; });
    }
  }

  Future<void> _importSignatures() async {
    final file = await openFile(acceptedTypeGroups: [const XTypeGroup(label: 'SHA-256 指纹文本', extensions: ['txt', 'csv'])], confirmButtonText: '导入指纹');
    if (file == null) return;
    final imported = <String, String>{};
    for (final line in await File(file.path).readAsLines()) {
      final text = line.trim();
      if (text.isEmpty || text.startsWith('#')) continue;
      final match = RegExp(r'^([a-fA-F0-9]{64})(?:[\s,;]+(.+))?$').firstMatch(text);
      if (match != null) imported[match.group(1)!.toLowerCase()] = (match.group(2) ?? '导入的本地特征').trim();
    }
    if (imported.isEmpty) {
      if (mounted) setState(() => _status = '没有找到有效的 SHA-256 指纹。每行格式：64 位哈希 空格 名称');
      return;
    }
    _signatures.addAll(imported);
    final local = await _localDatabase;
    await local.writeAsString(jsonEncode(_signatures), flush: true);
    if (mounted) setState(() => _status = '已导入并保存 ${imported.length} 条指纹；当前共 ${_signatures.length} 条。');
  }

  Future<void> _chooseDirectory() async {
    final path = await getDirectoryPath(confirmButtonText: '扫描此文件夹');
    if (path != null && mounted) setState(() { _directory = path; _matches = <SignatureMatch>[]; _scanned = 0; _skipped = 0; });
  }

  Future<void> _scanLocal() async {
    final directory = _directory;
    if (directory == null || _scanning || _signatures.isEmpty) return;
    setState(() { _scanning = true; _matches = <SignatureMatch>[]; _scanned = 0; _skipped = 0; _status = '正在逐文件计算 SHA-256…'; });
    widget.onActivityChanged(true);
    try {
      final summary = await scanDirectoryForSignatures(directory, Map<String, String>.of(_signatures), onProgress: (scanned, skipped) {
        if (mounted) setState(() { _scanned = scanned; _skipped = skipped; });
      });
      if (mounted) setState(() {
        _matches = summary.matches;
        _scanned = summary.scannedFiles;
        _skipped = summary.skippedFiles;
        _status = summary.matches.isEmpty
            ? '本地指纹匹配完成：扫描 ${summary.scannedFiles} 个文件，未命中已知指纹。'
            : '发现 ${summary.matches.length} 个指纹匹配项。请勿直接运行文件，进一步使用 Defender 复核。';
      });
    } catch (error) {
      if (mounted) setState(() => _status = '本地扫描失败：$error');
    } finally {
      if (mounted) setState(() => _scanning = false);
      widget.onActivityChanged(false);
    }
  }

  Future<void> _runDefender() async {
    final directory = _directory;
    if (directory == null || _defenderScanning) return;
    if (!Platform.isWindows) {
      setState(() => _defenderResult = 'Microsoft Defender 扫描仅支持 Windows。');
      return;
    }
    setState(() { _defenderScanning = true; _defenderResult = '正在请求管理员权限并调用 Microsoft Defender…'; });
    widget.onActivityChanged(true);
    File? scriptFile;
    File? resultFile;
    try {
      final temp = Directory.systemTemp;
      final token = '${pid}_${DateTime.now().microsecondsSinceEpoch}';
      scriptFile = File('${temp.path}${Platform.pathSeparator}moepurekit_defender_$token.ps1');
      resultFile = File('${temp.path}${Platform.pathSeparator}moepurekit_defender_$token.json');
      final path64 = base64Encode(utf8.encode(directory));
      final resultPath64 = base64Encode(utf8.encode(resultFile.path));
      final inner = r'''
$ErrorActionPreference = 'Stop'
$target = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('PATH_BASE64'))
$resultPath = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('RESULT_BASE64'))
try {
  Import-Module Defender -ErrorAction Stop
  Start-MpScan -ScanType CustomScan -ScanPath $target -ErrorAction Stop
  $payload = @{ success = $true; message = 'Windows Defender 已接受自定义扫描请求。扫描可能在后台继续；请在 Windows 安全中心的保护历史记录中查看检测与处置结果。' } | ConvertTo-Json -Compress
  [IO.File]::WriteAllText($resultPath, $payload, [Text.UTF8Encoding]::new($false))
} catch {
  $payload = @{ success = $false; error = $_.Exception.Message } | ConvertTo-Json -Compress
  [IO.File]::WriteAllText($resultPath, $payload, [Text.UTF8Encoding]::new($false))
  exit 1
}
'''.replaceAll('PATH_BASE64', path64).replaceAll('RESULT_BASE64', resultPath64);
      await scriptFile.writeAsString(inner, encoding: utf8, flush: true);
      final script64 = base64Encode(utf8.encode(scriptFile.path));
      final result64 = base64Encode(utf8.encode(resultFile.path));
      final launcher = r'''
$scriptPath = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('SCRIPT_BASE64'))
$resultPath = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('RESULT_BASE64'))
try {
  $p = Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList ('-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' + $scriptPath + '"') -Wait -PassThru -ErrorAction Stop
  if (Test-Path $resultPath) { [Console]::Out.Write([IO.File]::ReadAllText($resultPath)); Remove-Item $resultPath -Force -ErrorAction SilentlyContinue }
  exit $p.ExitCode
} catch { [Console]::Error.WriteLine($_.Exception.Message); exit 1 }
'''.replaceAll('SCRIPT_BASE64', script64).replaceAll('RESULT_BASE64', result64);
      final result = await Process.run('powershell.exe', ['-NoProfile', '-NonInteractive', '-EncodedCommand', base64Encode(utf16le(launcher))], runInShell: false).timeout(const Duration(minutes: 30));
      final raw = result.stdout.toString().trim();
      if (raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map && decoded['success'] == true) {
          if (mounted) setState(() => _defenderResult = decoded['message']?.toString() ?? 'Defender 扫描命令已完成。');
        } else {
          throw StateError(decoded is Map ? (decoded['error']?.toString() ?? 'Defender 扫描失败') : 'Defender 返回格式异常');
        }
      } else if (result.exitCode != 0) {
        throw ProcessException('powershell.exe', const [], result.stderr.toString().trim().isEmpty ? 'UAC 已取消或 Defender 扫描启动失败' : result.stderr.toString(), result.exitCode);
      } else {
        throw const FormatException('未收到 Defender 扫描结果');
      }
    } catch (error) {
      if (mounted) setState(() => _defenderResult = 'Defender 扫描未能确认完成：$error');
    } finally {
      try { if (scriptFile != null && await scriptFile.exists()) await scriptFile.delete(); } catch (_) {}
      try { if (resultFile != null && await resultFile.exists()) await resultFile.delete(); } catch (_) {}
      if (mounted) setState(() => _defenderScanning = false);
      widget.onActivityChanged(false);
    }
  }

  @override
  Widget build(BuildContext context) => _MaintenanceScroll(
    children: [
      const _MaintenanceHeader(eyebrow: 'SECURITY', title: '病毒查杀', subtitle: '本地 SHA-256 指纹核对 + Microsoft Defender 深度扫描。'),
      const SizedBox(height: 16),
      _MaintenanceCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Row(children: [Icon(Icons.fingerprint_outlined, color: Color(0xFF718A78)), SizedBox(width: 9), LocalizedText('本地 SHA-256 指纹库', style: TextStyle(fontWeight: FontWeight.w600))]),
        const SizedBox(height: 8),
        LocalizedText(_loadingDatabase ? '正在载入…' : '已载入 ${_signatures.length} 条指纹。支持导入本地 TXT/CSV（每行 64 位 SHA-256，可在后面附名称）。', style: const TextStyle(fontSize: 11, color: Color(0xFF858C86), height: 1.5)),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: [
          OutlinedButton.icon(onPressed: _loadingDatabase ? null : _importSignatures, icon: const Icon(Icons.file_upload_outlined, size: 17), label: const LocalizedText('导入指纹库')),
          OutlinedButton.icon(onPressed: _chooseDirectory, icon: const Icon(Icons.folder_open_outlined, size: 17), label: const LocalizedText('选择扫描目录')),
          FilledButton.icon(onPressed: _directory == null || _scanning || _defenderScanning || _loadingDatabase ? null : _scanLocal, icon: const Icon(Icons.search, size: 17), label: const LocalizedText('本地指纹扫描')),
        ]),
        if (_directory != null) ...[const SizedBox(height: 8), LocalizedText(_directory!, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10, color: Color(0xFF858C86)))],
      ])),
      const SizedBox(height: 10),
      _MaintenanceCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Row(children: [Icon(Icons.security_outlined, color: Color(0xFF718A78)), SizedBox(width: 9), LocalizedText('Microsoft Defender', style: TextStyle(fontWeight: FontWeight.w600))]),
        const SizedBox(height: 7),
        const LocalizedText('通过 Microsoft Defender 官方 PowerShell cmdlet 发起所选目录的自定义扫描。启动时会显示 UAC 提权提示；扫描结果请以 Windows 安全中心的保护历史记录为准。', style: TextStyle(fontSize: 11, color: Color(0xFF858C86), height: 1.5)),
        const SizedBox(height: 10),
        FilledButton.tonalIcon(onPressed: _directory == null || _scanning || _defenderScanning ? null : _runDefender, icon: const Icon(Icons.verified_user_outlined, size: 17), label: LocalizedText(_defenderScanning ? 'Defender 扫描中…' : '运行 Defender 扫描')),
        if (_defenderResult != null) ...[const SizedBox(height: 9), LocalizedText(_defenderResult!, style: const TextStyle(fontSize: 11, color: Color(0xFF737B74), height: 1.45))],
      ])),
      const SizedBox(height: 10),
      _MaintenanceCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const LocalizedText('扫描状态', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        const SizedBox(height: 7),
        LocalizedText(_status, style: const TextStyle(fontSize: 11, color: Color(0xFF737B74), height: 1.45)),
        if (_scanning || _defenderScanning) ...[const SizedBox(height: 9), const LinearProgressIndicator(minHeight: 3)],
        if (_scanned > 0) ...[const SizedBox(height: 7), LocalizedText('已扫描 $_scanned 个文件 · 跳过 $_skipped 个', style: const TextStyle(fontSize: 10, color: Color(0xFF858C86)))],
        if (_matches.isNotEmpty) ...[
          const SizedBox(height: 10),
          for (final match in _matches) Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.warning_amber_rounded, size: 16, color: Color(0xFFBD7653)),
              const SizedBox(width: 7),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [LocalizedText(match.name, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)), LocalizedText(match.path, style: const TextStyle(fontSize: 10, color: Color(0xFF858C86)), maxLines: 2, overflow: TextOverflow.ellipsis)])),
            ]),
          ),
        ],
      ])),
      const SizedBox(height: 8),
      const LocalizedText('重要说明：内置特征目前包含 EICAR 测试指纹，用于验证检测链路，不是完整恶意软件库。指纹未命中不等于文件安全；请以 Defender 等专业引擎结果为准。', style: TextStyle(fontSize: 10, color: Color(0xFF9A805E), height: 1.5)),
    ],
  );
}

class DriversPage extends StatefulWidget {
  const DriversPage({super.key, required this.onActivityChanged});
  final ValueChanged<bool> onActivityChanged;
  @override
  State<DriversPage> createState() => _DriversPageState();
}

class _DriversPageState extends State<DriversPage> {
  List<Map<String, dynamic>> _drivers = <Map<String, dynamic>>[];
  bool _loading = false;
  bool _scanningDevices = false;
  String? _status;

  Future<void> _loadDrivers() async {
    if (!Platform.isWindows) {
      setState(() => _status = '驱动清单仅支持 Windows。');
      return;
    }
    setState(() { _loading = true; _status = null; });
    widget.onActivityChanged(true);
    try {
      const script = r'''
$ErrorActionPreference='Stop'
$rows = @(Get-CimInstance Win32_PnPSignedDriver | Sort-Object DriverDate -Descending | Select-Object -First 100 DeviceName,DriverProviderName,DriverVersion,DriverDate,InfName,IsSigned)
ConvertTo-Json -InputObject @($rows) -Compress -Depth 3
''';
      final result = await Process.run('powershell.exe', ['-NoProfile', '-NonInteractive', '-Command', script], runInShell: false).timeout(const Duration(seconds: 45));
      if (result.exitCode != 0) throw ProcessException('powershell.exe', const [], result.stderr.toString(), result.exitCode);
      final decoded = jsonDecode(result.stdout.toString());
      final rows = decoded is List ? decoded : (decoded is Map ? [decoded] : <dynamic>[]);
      if (mounted) setState(() {
        _drivers = rows.whereType<Map>().map((row) => row.map((key, value) => MapEntry(key.toString(), value))).toList(growable: false);
        _status = '读取到 ${_drivers.length} 条设备驱动记录（最多展示 100 条）。';
      });
    } catch (error) {
      if (mounted) setState(() => _status = '驱动信息读取失败：$error');
    } finally {
      if (mounted) setState(() => _loading = false);
      widget.onActivityChanged(false);
    }
  }

  Future<void> _scanDevices() async {
    if (!Platform.isWindows) return;
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const LocalizedText('需要管理员权限'),
        content: const LocalizedText('重新扫描硬件设备需要提升权限。继续后 Windows 将显示 UAC 确认窗口。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const LocalizedText('取消')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const LocalizedText('继续并请求权限')),
        ],
      ),
    );
    if (approved != true || !mounted) return;
    setState(() { _scanningDevices = true; _status = '正在请求管理员权限并重新扫描设备…'; });
    widget.onActivityChanged(true);
    try {
      const script = r'''
$ErrorActionPreference = 'Stop'
$exe = Join-Path $env:WINDIR 'System32\pnputil.exe'
try {
  $process = Start-Process -FilePath $exe -ArgumentList '/scan-devices' -Verb RunAs -Wait -PassThru -ErrorAction Stop
  if ($process.ExitCode -ne 0) { exit $process.ExitCode }
  exit 0
} catch {
  [Console]::Error.WriteLine($_.Exception.Message)
  exit 1
}
''';
      final result = await Process.run(
        'powershell.exe',
        ['-NoProfile', '-NonInteractive', '-EncodedCommand', base64Encode(utf16le(script))],
        runInShell: false,
      ).timeout(const Duration(minutes: 3));
      if (result.exitCode != 0) {
        final details = result.stderr.toString().trim();
        throw ProcessException('pnputil.exe', const ['/scan-devices', 'RunAs'], details.isEmpty ? 'UAC 已取消或设备扫描失败（退出码 ${result.exitCode}）' : details, result.exitCode);
      }
      if (mounted) setState(() => _status = 'Windows 已完成硬件重新扫描。');
      await _loadDrivers();
    } catch (error) {
      if (mounted) setState(() => _status = '设备扫描未能完成：$error');
    } finally {
      if (mounted) setState(() => _scanningDevices = false);
      widget.onActivityChanged(false);
    }
  }

  Future<void> _installInf() async {
    if (!Platform.isWindows) return;
    final selected = await openFile(acceptedTypeGroups: [const XTypeGroup(label: 'Windows 驱动 INF', extensions: ['inf'])], confirmButtonText: '选择驱动 INF');
    if (selected == null) return;
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const LocalizedText('安装驱动？'),
        content: LocalizedText('将通过 Windows pnputil 安装此 INF，并请求 Windows UAC 管理员授权：\n\n${selected.path}\n\n请确认来源可信、型号匹配。错误驱动可能导致设备异常。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const LocalizedText('取消')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const LocalizedText('继续并请求权限')),
        ],
      ),
    );
    if (approved != true) return;
    widget.onActivityChanged(true);
    try {
      final path64 = base64Encode(utf8.encode(selected.path));
      final script = r'''
$inf=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('INF_BASE64'))
try {
  $argsLine = '/add-driver "' + $inf + '" /install'
  $p=Start-Process -FilePath (Join-Path $env:WINDIR 'System32\pnputil.exe') -ArgumentList $argsLine -Verb RunAs -Wait -PassThru -ErrorAction Stop
  exit $p.ExitCode
} catch { [Console]::Error.WriteLine($_.Exception.Message); exit 1 }
'''.replaceAll('INF_BASE64', path64);
      final result = await Process.run('powershell.exe', ['-NoProfile', '-NonInteractive', '-EncodedCommand', base64Encode(utf16le(script))], runInShell: false).timeout(const Duration(minutes: 10));
      if (result.exitCode != 0) throw ProcessException('pnputil.exe', ['/add-driver', selected.path, '/install'], result.stderr.toString().trim().isEmpty ? 'UAC 已取消或驱动安装失败' : result.stderr.toString(), result.exitCode);
      if (mounted) setState(() => _status = 'pnputil 已完成驱动安装命令。建议重启后检查设备管理器状态。');
      await _loadDrivers();
    } catch (error) {
      if (mounted) setState(() => _status = '驱动安装未能确认成功：$error');
    } finally {
      widget.onActivityChanged(false);
    }
  }

  Future<void> _openSystemUri(String uri) async {
    try {
      if (uri == 'devmgmt.msc') {
        final approved = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const LocalizedText('以管理员身份打开设备管理器？'),
            content: const LocalizedText('驱动安装、卸载和设备更改通常需要管理员权限。Windows 将显示 UAC 确认窗口。'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const LocalizedText('取消')),
              FilledButton(onPressed: () => Navigator.pop(context, true), child: const LocalizedText('继续')),
            ],
          ),
        );
        if (approved != true || !mounted) return;
        const script = r'''
$ErrorActionPreference = 'Stop'
try {
  Start-Process -FilePath (Join-Path $env:WINDIR 'System32\mmc.exe') -ArgumentList 'devmgmt.msc' -Verb RunAs -ErrorAction Stop | Out-Null
  exit 0
} catch { [Console]::Error.WriteLine($_.Exception.Message); exit 1 }
''';
        final result = await Process.run('powershell.exe', ['-NoProfile', '-NonInteractive', '-EncodedCommand', base64Encode(utf16le(script))], runInShell: false).timeout(const Duration(seconds: 30));
        if (result.exitCode != 0) {
          final details = result.stderr.toString().trim();
          throw ProcessException('mmc.exe', const ['devmgmt.msc', 'RunAs'], details.isEmpty ? 'UAC 已取消或设备管理器启动失败' : details, result.exitCode);
        }
      } else if (uri.startsWith('http')) {
        await Process.start('explorer.exe', [uri], runInShell: false);
      } else {
        await Process.start('explorer.exe', [uri], runInShell: false);
      }
    } catch (error) {
      if (mounted) setState(() => _status = '无法打开系统设置：$error');
    }
  }


  @override
  void initState() {
    super.initState();
    unawaited(_loadDrivers());
  }

  @override
  Widget build(BuildContext context) => _MaintenanceScroll(
    children: [
      const _MaintenanceHeader(eyebrow: 'DEVICE DRIVERS', title: '驱动管理', subtitle: '读取当前驱动、重新扫描设备，或使用 Windows 原生工具安装 INF。'),
      const SizedBox(height: 16),
      _MaintenanceCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(spacing: 8, runSpacing: 8, children: [
          FilledButton.icon(onPressed: _loading ? null : _loadDrivers, icon: const Icon(Icons.refresh, size: 17), label: const LocalizedText('刷新驱动清单')),
          OutlinedButton.icon(onPressed: _scanningDevices ? null : _scanDevices, icon: const Icon(Icons.devices_outlined, size: 17), label: LocalizedText(_scanningDevices ? '扫描中…' : '扫描硬件变更')),
          OutlinedButton.icon(onPressed: _installInf, icon: const Icon(Icons.download_for_offline_outlined, size: 17), label: const LocalizedText('安装 INF 驱动')),
        ]),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          TextButton.icon(onPressed: () => _openSystemUri('devmgmt.msc'), icon: const Icon(Icons.admin_panel_settings_outlined, size: 16), label: const LocalizedText('管理员设备管理器')),
          TextButton.icon(onPressed: () => _openSystemUri('ms-settings:windowsupdate'), icon: const Icon(Icons.system_update_alt, size: 16), label: const LocalizedText('Windows 更新')),
          TextButton.icon(onPressed: () => _openSystemUri('https://catalog.update.microsoft.com/'), icon: const Icon(Icons.open_in_new, size: 16), label: const LocalizedText('Microsoft Update Catalog')),
        ]),
      ])),
      if (_status != null) ...[const SizedBox(height: 10), _MaintenanceCard(child: LocalizedText(_status!, style: const TextStyle(fontSize: 11, color: Color(0xFF737B74), height: 1.5)))],
      const SizedBox(height: 10),
      if (_loading) const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator()))
      else if (_drivers.isEmpty) const _MaintenanceCard(child: LocalizedText('尚无驱动清单。点击“刷新驱动清单”读取 Windows 当前已安装的签名驱动。', style: TextStyle(fontSize: 11, color: Color(0xFF858C86))))
      else _MaintenanceCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        LocalizedText('已安装驱动 · ${_drivers.length}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        for (final driver in _drivers) Padding(
          padding: const EdgeInsets.symmetric(vertical: 7),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Icon(Icons.memory_outlined, size: 16, color: Color(0xFF718A78)),
            const SizedBox(width: 9),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              LocalizedText(driver['DeviceName']?.toString().trim().isNotEmpty == true ? driver['DeviceName'].toString() : '未命名设备', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
              const SizedBox(height: 3),
              LocalizedText('${driver['DriverProviderName'] ?? '未知提供商'} · ${driver['DriverVersion'] ?? '未知版本'} · ${driver['InfName'] ?? ''}', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10, color: Color(0xFF858C86))),
            ])),
            if (driver['IsSigned'] == true) const Tooltip(message: '已签名', child: Icon(Icons.verified_outlined, size: 15, color: Color(0xFF718A78))),
          ]),
        ),
      ])),
      const SizedBox(height: 8),
      const LocalizedText('驱动安装会调用 Windows pnputil 并显示 UAC。此页不提供未经验证的第三方驱动包，也不会自动替换当前驱动。', style: TextStyle(fontSize: 10, color: Color(0xFF9A805E), height: 1.5)),
    ],
  );
}

class _MaintenanceHeader extends StatelessWidget {
  const _MaintenanceHeader({required this.eyebrow, required this.title, required this.subtitle});
  final String eyebrow;
  final String title;
  final String subtitle;
  @override
  Widget build(BuildContext context) => FadeIn(
    duration: const Duration(milliseconds: 190),
    offset: 3,
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      LocalizedText(eyebrow, style: const TextStyle(fontSize: 9, letterSpacing: 1.4, color: Color(0xFF8B938C))),
      const SizedBox(height: 6),
      LocalizedText(title, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w600)),
      const SizedBox(height: 6),
      LocalizedText(subtitle, style: const TextStyle(fontSize: 11, color: Color(0xFF838A84))),
    ]),
  );
}

class _MaintenanceCard extends StatelessWidget {
  const _MaintenanceCard({required this.child, this.padding = const EdgeInsets.all(16)});
  final Widget child;
  final EdgeInsetsGeometry padding;
  @override
  Widget build(BuildContext context) => FadeIn(
    duration: const Duration(milliseconds: 170),
    offset: 4,
    child: Card(child: Padding(padding: padding, child: child)),
  );
}

class _MaintenanceScroll extends StatelessWidget {
  const _MaintenanceScroll({required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.fromLTRB(26, 22, 26, 28),
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
  );
}

String _formatBytes(int bytes) {
  if (bytes >= 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  if (bytes >= 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  return '$bytes B';
}

List<int> utf16le(String value) {
  final units = <int>[];
  for (final unit in value.codeUnits) {
    units..add(unit & 0xff)..add((unit >> 8) & 0xff);
  }
  return units;
}
