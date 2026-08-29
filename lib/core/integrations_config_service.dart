import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import '../shared/markdown/md_utils.dart';

class IntegrationsConfig {
  /// AnkiConnect endpoint override; null means the transport default
  /// (http://127.0.0.1:8765). Set by hand-editing the `## AnkiConnect`
  /// section in integrations.md — there is no in-app editor.
  final String? ankiConnectUrl;

  /// Additional authored folders the Anki sync skips. The non-current/system
  /// boundary is enforced centrally by CurrentVaultContent and cannot be
  /// weakened through configuration. (The `## Resurface` section name remains
  /// for compatibility with existing vaults.)
  final List<String> excludedFolders;

  const IntegrationsConfig({this.ankiConnectUrl, List<String>? excludedFolders})
    : excludedFolders = excludedFolders ?? const [];
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
        ankiConnectUrl: _parseScalarSection(
          sections['AnkiConnect'] ?? '',
          'url',
        ),
        excludedFolders: _parseExcludedSection(sections['Resurface'] ?? ''),
      );
    } catch (_) {
      return const IntegrationsConfig();
    }
  }

  // ── Save ──────────────────────────────────────────────────────────────────

  static Future<bool> save(String vaultPath, IntegrationsConfig config) async {
    try {
      final file = File(configPath(vaultPath));
      await file.parent.create(recursive: true);
      await file.writeAsString(_buildContent(config));
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> setExcludedFolders(
    String vaultPath,
    List<String> folders,
  ) async {
    final c = await load(vaultPath);
    return save(
      vaultPath,
      IntegrationsConfig(
        ankiConnectUrl: c.ankiConnectUrl,
        excludedFolders: folders,
      ),
    );
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

  static List<String> _parseExcludedSection(String sectionContent) {
    if (sectionContent.trim().isEmpty) return const [];
    try {
      final yaml = loadYaml(sectionContent.trim());
      if (yaml is! YamlMap) return const [];
      final raw = yaml['excluded_folders'];
      if (raw is! YamlList) return const [];
      final result = raw.map((e) => e.toString()).toList();
      return result;
    } catch (_) {
      return const [];
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
    buf.writeln('## AnkiConnect');
    buf.writeln();
    if (config.ankiConnectUrl != null && config.ankiConnectUrl!.isNotEmpty) {
      buf.writeln('url: ${yamlScalar(config.ankiConnectUrl!)}');
    }

    // Section name kept as `Resurface` for backward compatibility with vaults
    // written before the role change; it now scopes the Anki problem-note scan.
    buf.writeln();
    buf.writeln('## Resurface');
    buf.writeln();
    buf.writeln('excluded_folders:');
    for (final folder in config.excludedFolders) {
      buf.writeln('  - $folder');
    }

    return '${buf.toString().trimRight()}\n';
  }
}
