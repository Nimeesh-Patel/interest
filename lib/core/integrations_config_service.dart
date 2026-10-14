import 'package:people_tracker/shared/markdown/markdown_file.dart';
import 'dart:io';
import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import '../shared/markdown/md_utils.dart';
import '../shared/markdown/frontmatter_patch.dart';
import '../shared/markdown/md_io.dart';

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
    {
      final file = File(configPath(vaultPath));
      if (!await file.exists()) return const IntegrationsConfig();
      final content = await readPreservingUtf8(file);
      final split = splitFrontmatter(content);
      if (content.trimLeft().startsWith('---') && split.frontmatter == null) {
        throw const FormatException('Integration frontmatter is not closed.');
      }
      if (split.frontmatter != null) _sectionYaml(split.frontmatter!);
      for (final name in ['AnkiConnect', 'Resurface']) {
        if (RegExp(
              '^## $name\\s*\\r?\$',
              multiLine: true,
            ).allMatches(split.body).length >
            1) {
          throw FormatException('Duplicate $name configuration section.');
        }
      }
      final sections = parseSectionsH2(split.body);
      return IntegrationsConfig(
        ankiConnectUrl: _parseScalarSection(
          sections['AnkiConnect'] ?? '',
          'url',
        ),
        excludedFolders: _parseExcludedSection(sections['Resurface'] ?? ''),
      );
    }
  }

  // ── Save ──────────────────────────────────────────────────────────────────

  static Future<bool> save(String vaultPath, IntegrationsConfig config) async {
    try {
      return await _saveFields(vaultPath, {
        'AnkiConnect': {
          'url':
              config.ankiConnectUrl == null
                  ? null
                  : yamlScalar(config.ankiConnectUrl!),
        },
        'Resurface': {
          'excluded_folders':
              '[${config.excludedFolders.map(yamlScalar).join(', ')}]',
        },
      }, config);
    } catch (_) {
      return false;
    }
  }

  static Future<bool> setExcludedFolders(
    String vaultPath,
    List<String> folders,
  ) async {
    try {
      return await _saveFields(vaultPath, {
        'Resurface': {
          'excluded_folders': '[${folders.map(yamlScalar).join(', ')}]',
        },
      }, IntegrationsConfig(excludedFolders: folders));
    } catch (_) {
      return false;
    }
  }

  // ── Private: parsing ──────────────────────────────────────────────────────

  static Map<dynamic, dynamic> _sectionYaml(String text) {
    if (text.trim().isEmpty) return const {};
    final value = loadYaml(text);
    if (value == null) return const {};
    if (value is! YamlMap) {
      throw const FormatException(
        'Integration sections must be YAML mappings.',
      );
    }
    return value;
  }

  static String? _parseScalarSection(String text, String key) {
    final value = _sectionYaml(text)[key];
    if (value == null) return null;
    if (value is! String) throw FormatException('$key must be text.');
    return value.trim().isEmpty ? null : value.trim();
  }

  static List<String> _parseExcludedSection(String text) {
    final value = _sectionYaml(text)['excluded_folders'];
    if (value == null) return const [];
    if (value is! List || value.any((item) => item is! String)) {
      throw const FormatException('excluded_folders must be a text list.');
    }
    return value.cast<String>().toList();
  }

  static String _patchSection(
    String source,
    String heading,
    Map<String, String?> fields,
  ) {
    final matches =
        RegExp(
          r'^## ([^\r\n]+)\r?$',
          multiLine: true,
        ).allMatches(source).toList();
    final selected =
        matches.where((match) => match.group(1)!.trim() == heading).toList();
    if (selected.length > 1) {
      throw FormatException('Duplicate $heading configuration section.');
    }
    if (selected.isEmpty) {
      final body = fields.entries
          .where((entry) => entry.value != null)
          .map((entry) => '${entry.key}: ${entry.value}')
          .join('\n');
      return '$source${source.endsWith('\n') ? '' : '\n'}\n## $heading\n\n$body\n';
    }
    final match = selected.single;
    final next = matches.indexOf(match) + 1;
    final end = next < matches.length ? matches[next].start : source.length;
    final section = source.substring(match.end, end);
    final wrapped = '---\n$section${section.endsWith('\n') ? '' : '\n'}---\n';
    final patched = patchFrontmatterText(wrapped, fields);
    return source.replaceRange(
      match.end,
      end,
      patched.substring(4, patched.length - 4),
    );
  }

  static Future<bool> _saveFields(
    String vaultPath,
    Map<String, Map<String, String?>> fields,
    IntegrationsConfig initial,
  ) async {
    final path = configPath(vaultPath);
    final file = File(path);
    if (!await file.exists()) {
      await file.parent.create(recursive: true);
      await file.create(exclusive: true);
      await file.writeAsString(_buildContent(initial), flush: true);
      return true;
    }
    final loaded = await MarkdownFile.loadSnapshot(path);
    if (loaded.snapshot == null) return false;
    // Validate both current owned sections before any edit; never overwrite
    // an unreadable config with guessed defaults.
    await load(vaultPath);
    var source = await readPreservingUtf8(file);
    final observed = utf8.encode(source);
    final expected = loaded.snapshot!.bytes;
    if (observed.length != expected.length) return false;
    for (var index = 0; index < observed.length; index++) {
      if (observed[index] != expected[index]) return false;
    }
    for (final entry in fields.entries) {
      source = _patchSection(source, entry.key, entry.value);
    }
    return (await MarkdownFile.guardedReplaceBytes(
      path,
      loaded.snapshot!,
      utf8.encode(source),
    )).applied;
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
    buf.writeln(
      config.excludedFolders.isEmpty
          ? 'excluded_folders: []'
          : 'excluded_folders:',
    );
    for (final folder in config.excludedFolders) {
      buf.writeln('  - $folder');
    }

    return '${buf.toString().trimRight()}\n';
  }
}
