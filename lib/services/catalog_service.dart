import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/catalog_item.dart';

class CatalogService {
  static const _systemKey = 'moepurekit.catalog.system';
  static const _softwareKey = 'moepurekit.catalog.software';

  Future<List<CatalogItem>> loadSystem() =>
      _load(_systemKey, assetPath: 'assets/iso.json');

  Future<List<CatalogItem>> loadSoftware() =>
      _load(_softwareKey, assetPath: 'assets/app.json');

  Future<void> saveSystem(String json) => _save(_systemKey, json);

  Future<void> saveSoftware(String json) => _save(_softwareKey, json);

  Future<List<CatalogItem>> _load(
    String key, {
    required String assetPath,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final source = prefs.getString(key);
    if (source != null && source.trim().isNotEmpty) return _parse(source);
    return _parse(await rootBundle.loadString(assetPath));
  }

  Future<void> _save(String key, String source) async {
    final items = _parse(source);
    final normalized = const JsonEncoder.withIndent('  ')
        .convert(items.map((item) => item.toJson()).toList());
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setString(key, normalized)) {
      throw StateError('无法保存资源清单');
    }
  }

  List<CatalogItem> _parse(String source) {
    if (source.trim().isEmpty) return const [];
    final decoded = jsonDecode(source);
    final List<dynamic> entries;
    if (decoded is List<dynamic>) {
      entries = decoded;
    } else if (decoded is Map<String, dynamic> &&
        decoded['categories'] is List<dynamic>) {
      entries = [];
      for (final category in decoded['categories'] as List<dynamic>) {
        if (category is! Map<String, dynamic> ||
            category['items'] is! List<dynamic>) {
          throw const FormatException('categories 中的每项必须包含 items 数组');
        }
        final categoryName = category['name'] as String? ?? '';
        for (final item in category['items'] as List<dynamic>) {
          if (item is! Map<String, dynamic>) {
            throw const FormatException('资源条目必须为 JSON 对象');
          }
          entries.add({...item, 'category': categoryName});
        }
      }
    } else {
      throw const FormatException('清单顶层必须是 JSON 数组或包含 categories 的对象');
    }
    return entries.map((value) {
      if (value is! Map<String, dynamic>) {
        throw const FormatException('每个清单条目必须是 JSON 对象');
      }
      return CatalogItem.fromJson(value);
    }).toList();
  }
}
