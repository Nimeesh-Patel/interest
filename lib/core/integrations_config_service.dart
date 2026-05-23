import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yaml/yaml.dart';

import '../shared/markdown/md_utils.dart';

class IntegrationsConfig {
  final String? readwiseToken;
  final String? hardcoverToken;
  final List<Map<String, dynamic>> rssFeeds;

  const IntegrationsConfig({
    this.readwiseToken,
    this.hardcoverToken,
    List<Map<String, dynamic>>? rssFeeds,
  }) : rssFeeds = rssFeeds ?? const [];
}

class IntegrationsConfigService {
  static String configPath(String vaultPath) =>
      p.join(vaultPath, 'Interesting', 'System', 'integrations.md');

  // ── Load ──────────────────────────────────────────────────────────────────

  static Future<IntegrationsConfig> load(String vaultPath) async {
    try {
      final file = File(configPath(vaultPath));
      if (!await file.exists()) return const IntegrationsConfig();
      final content = await file.readAsString();
      final split = splitFrontmatter(content);
      final sections = parseSectionsH2(split.body);
      return IntegrationsConfig(
        readwiseToken: _parseTokenSection(sections['Readwise'] ?? ''),
        hardcoverToken: _parseTokenSection(sections['Hardcover'] ?? ''),
        rssFeeds: _parseRssSection(sections['RSS'] ?? ''),
      );
    } catch (_) {
      return const IntegrationsConfig();
    }
  }

  // ── Save ──────────────────────────────────────────────────────────────────

  static Future<void> save(String vaultPath, IntegrationsConfig config) async {
    try {
      final file = File(configPath(vaultPath));
      await file.parent.create(recursive: true);
      await file.writeAsString(_buildContent(config));
    } catch (_) {}
  }

  // ── Token convenience methods ─────────────────────────────────────────────

  static Future<String?> getReadwiseToken(String vaultPath) async =>
      (await load(vaultPath)).readwiseToken;

  static Future<void> setReadwiseToken(String vaultPath, String? token) async {
    final c = await load(vaultPath);
    await save(vaultPath, IntegrationsConfig(
      readwiseToken: token,
      hardcoverToken: c.hardcoverToken,
      rssFeeds: c.rssFeeds,
    ));
  }

  static Future<String?> getHardcoverToken(String vaultPath) async =>
      (await load(vaultPath)).hardcoverToken;

  static Future<void> setHardcoverToken(String vaultPath, String? token) async {
    final c = await load(vaultPath);
    await save(vaultPath, IntegrationsConfig(
      readwiseToken: c.readwiseToken,
      hardcoverToken: token,
      rssFeeds: c.rssFeeds,
    ));
  }

  // ── RSS convenience methods ───────────────────────────────────────────────

  static Future<List<Map<String, dynamic>>> getRssFeeds(
          String vaultPath) async =>
      (await load(vaultPath)).rssFeeds;

  static Future<void> setRssFeeds(
      String vaultPath, List<Map<String, dynamic>> feeds) async {
    final c = await load(vaultPath);
    await save(vaultPath, IntegrationsConfig(
      readwiseToken: c.readwiseToken,
      hardcoverToken: c.hardcoverToken,
      rssFeeds: feeds,
    ));
  }

  // ── Migration from SharedPreferences (idempotent) ─────────────────────────

  static Future<void> migrateFromPrefs(String vaultPath) async {
    try {
      if (await File(configPath(vaultPath)).exists()) return;
      final prefs = await SharedPreferences.getInstance();
      final readwiseToken = prefs.getString('readwise_access_token');
      final hardcoverToken = prefs.getString('hardcover_api_token');
      List<Map<String, dynamic>> rssFeeds = [];
      final rssJson = prefs.getString('rss_feeds');
      if (rssJson != null && rssJson.isNotEmpty) {
        try {
          final list = jsonDecode(rssJson) as List<dynamic>;
          rssFeeds = list.whereType<Map<String, dynamic>>().toList();
        } catch (_) {}
      }
      if (rssFeeds.isEmpty) {
        final legacyUrl = prefs.getString('letterboxd_rss_url');
        if (legacyUrl != null && legacyUrl.isNotEmpty) {
          rssFeeds = [{
            'id': 'letterboxd-${DateTime.now().millisecondsSinceEpoch}',
            'name': 'Letterboxd',
            'url': legacyUrl,
            'type': 'letterboxd',
          }];
        }
      }
      await save(vaultPath, IntegrationsConfig(
        readwiseToken: readwiseToken,
        hardcoverToken: hardcoverToken,
        rssFeeds: rssFeeds,
      ));
    } catch (_) {}
  }

  // ── Private: parsing ──────────────────────────────────────────────────────

  static String? _parseTokenSection(String sectionContent) {
    if (sectionContent.trim().isEmpty) return null;
    try {
      final yaml = loadYaml(sectionContent.trim());
      if (yaml is YamlMap) {
        final token = yaml['token']?.toString();
        return (token != null && token.isNotEmpty) ? token : null;
      }
    } catch (_) {}
    return null;
  }

  static List<Map<String, dynamic>> _parseRssSection(String sectionContent) {
    if (sectionContent.trim().isEmpty) return [];
    try {
      final yaml = loadYaml(sectionContent.trim());
      if (yaml is! YamlList) return [];
      final result = <Map<String, dynamic>>[];
      for (final item in yaml) {
        if (item is YamlMap) {
          final map = <String, dynamic>{};
          for (final entry in item.entries) {
            map[entry.key.toString()] = entry.value;
          }
          result.add(map);
        }
      }
      return result;
    } catch (_) {
      return [];
    }
  }

  // ── Private: building ─────────────────────────────────────────────────────

  static String _buildContent(IntegrationsConfig config) {
    final now = DateTime.now().toUtc().toIso8601String();
    final buf = StringBuffer();
    buf.writeln('---');
    buf.writeln('type: system_config');
    buf.writeln('updated_at: $now');
    buf.writeln('---');

    buf.writeln();
    buf.writeln('## Readwise');
    buf.writeln();
    if (config.readwiseToken != null && config.readwiseToken!.isNotEmpty) {
      buf.writeln('token: ${_yamlQuote(config.readwiseToken!)}');
    }

    buf.writeln();
    buf.writeln('## Hardcover');
    buf.writeln();
    if (config.hardcoverToken != null && config.hardcoverToken!.isNotEmpty) {
      buf.writeln('token: ${_yamlQuote(config.hardcoverToken!)}');
    }

    buf.writeln();
    buf.writeln('## RSS');
    buf.writeln();
    for (final feed in config.rssFeeds) {
      buf.writeln('- id: ${feed['id']}');
      buf.writeln('  name: ${_yamlQuote(feed['name']?.toString() ?? '')}');
      buf.writeln('  url: ${_yamlQuote(feed['url']?.toString() ?? '')}');
      buf.writeln('  type: ${feed['type']}');
    }

    return '${buf.toString().trimRight()}\n';
  }

  static String _yamlQuote(String v) {
    if (v.isEmpty || v.contains(':') || v.contains('#') || v.contains('"') ||
        v.startsWith(' ') || v.endsWith(' ')) {
      return '"${v.replaceAll('\\', '\\\\').replaceAll('"', '\\"')}"';
    }
    return v;
  }
}
