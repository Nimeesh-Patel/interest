import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yaml/yaml.dart';

import '../shared/markdown/md_utils.dart';

class IntegrationsConfig {
  static const _defaultExcluded = [
    'Interesting', '.obsidian', 'Templates', 'Attachments'
  ];

  final String? hardcoverToken;

  /// AnkiConnect endpoint override; null means the transport default
  /// (http://127.0.0.1:8765). Set by hand-editing the `## AnkiConnect`
  /// section in integrations.md — there is no in-app editor.
  final String? ankiConnectUrl;

  /// Folders the Anki sync skips when scanning the vault for `***` problem
  /// notes. (Section name `## Resurface` is preserved in integrations.md for
  /// backward compatibility with existing vaults.)
  final List<String> resurfaceExcludedFolders;

  const IntegrationsConfig({
    this.hardcoverToken,
    this.ankiConnectUrl,
    List<String>? resurfaceExcludedFolders,
  }) : resurfaceExcludedFolders = resurfaceExcludedFolders ?? _defaultExcluded;
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
        hardcoverToken: _parseScalarSection(sections['Hardcover'] ?? '', 'token'),
        ankiConnectUrl: _parseScalarSection(sections['AnkiConnect'] ?? '', 'url'),
        resurfaceExcludedFolders:
            _parseResurfaceSection(sections['Resurface'] ?? ''),
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

  static Future<String?> getHardcoverToken(String vaultPath) async =>
      (await load(vaultPath)).hardcoverToken;

  static Future<void> setHardcoverToken(String vaultPath, String? token) async {
    final c = await load(vaultPath);
    await save(vaultPath, IntegrationsConfig(
      hardcoverToken: token,
      ankiConnectUrl: c.ankiConnectUrl,
      resurfaceExcludedFolders: c.resurfaceExcludedFolders,
    ));
  }

  static Future<void> setResurfaceExcludedFolders(
      String vaultPath, List<String> folders) async {
    final c = await load(vaultPath);
    await save(vaultPath, IntegrationsConfig(
      hardcoverToken: c.hardcoverToken,
      ankiConnectUrl: c.ankiConnectUrl,
      resurfaceExcludedFolders: folders,
    ));
  }

  // ── Migration from SharedPreferences (idempotent) ─────────────────────────

  static Future<void> migrateFromPrefs(String vaultPath) async {
    try {
      if (await File(configPath(vaultPath)).exists()) return;
      final prefs = await SharedPreferences.getInstance();
      final hardcoverToken = prefs.getString('hardcover_api_token');
      if (hardcoverToken == null) return;
      await save(vaultPath, IntegrationsConfig(hardcoverToken: hardcoverToken));
    } catch (_) {}
  }

  // ── Private: parsing ──────────────────────────────────────────────────────

  static String? _parseScalarSection(String sectionContent, String key) {
    if (sectionContent.trim().isEmpty) return null;
    try {
      final yaml = loadYaml(sectionContent.trim());
      if (yaml is YamlMap) {
        final value = yaml[key]?.toString();
        return (value != null && value.isNotEmpty) ? value : null;
      }
    } catch (_) {}
    return null;
  }

  static List<String> _parseResurfaceSection(String sectionContent) {
    if (sectionContent.trim().isEmpty) return IntegrationsConfig._defaultExcluded;
    try {
      final yaml = loadYaml(sectionContent.trim());
      if (yaml is! YamlMap) return IntegrationsConfig._defaultExcluded;
      final raw = yaml['excluded_folders'];
      if (raw is! YamlList) return IntegrationsConfig._defaultExcluded;
      final result = raw.map((e) => e.toString()).toList();
      return result.isEmpty ? IntegrationsConfig._defaultExcluded : result;
    } catch (_) {
      return IntegrationsConfig._defaultExcluded;
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
    buf.writeln('## Hardcover');
    buf.writeln();
    if (config.hardcoverToken != null && config.hardcoverToken!.isNotEmpty) {
      buf.writeln('token: ${yamlScalar(config.hardcoverToken!)}');
    }

    buf.writeln();
    buf.writeln('## AnkiConnect');
    buf.writeln();
    if (config.ankiConnectUrl != null && config.ankiConnectUrl!.isNotEmpty) {
      buf.writeln('url: ${yamlScalar(config.ankiConnectUrl!)}');
    }

    buf.writeln();
    buf.writeln('## Resurface');
    buf.writeln();
    buf.writeln('excluded_folders:');
    for (final folder in config.resurfaceExcludedFolders) {
      buf.writeln('  - $folder');
    }

    return '${buf.toString().trimRight()}\n';
  }
}
