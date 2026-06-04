import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/entity.dart';
import '../../../core/vault_service.dart';
import '../../../shared/markdown/md_utils.dart';

// ── Section type registry ────────────────────────────────────────────────────

enum SectionType { wikilinks, list, generic }

// Sections the app owns semantically. Everything else is user territory.
const Map<String, SectionType> _semanticSections = {
  'Why Interesting': SectionType.list,
  'Related': SectionType.wikilinks,
  'Sources': SectionType.list,
};

class EntityFileWriter {
  // ── Frontmatter ────────────────────────────────────────────────────────────

  static String buildFrontmatter({
    required Entity entity,
    required String categoryName,
  }) {
    final buf = StringBuffer();
    buf.writeln('---');
    buf.writeln('alias: ${entity.id}');
    buf.writeln('category: $categoryName');
    if (entity.score != null) {
      buf.writeln('score: ${entity.score!.toStringAsFixed(1)}');
    }
    if (entity.watchedDate != null) buf.writeln('watched_date: ${entity.watchedDate}');
    if (entity.letterboxdUrl != null) buf.writeln('letterboxd_url: ${entity.letterboxdUrl}');
    if (entity.tmdbId != null) buf.writeln('tmdb_id: ${entity.tmdbId}');
    if (entity.tags.isNotEmpty) {
      buf.writeln('tags:');
      for (final tag in entity.tags) {
        buf.writeln('  - $tag');
      }
    }
    buf.writeln('created_at: ${msToIso(entity.createdAt)}');
    buf.writeln('updated_at: ${msToIso(entity.updatedAt)}');
    buf.write('---');
    return buf.toString();
  }

  // ── Semantic section renderer ──────────────────────────────────────────────

  static String renderSemanticSection(
    String sectionName,
    Entity entity,
    List<String> relatedEntityNames,
  ) {
    switch (sectionName) {
      case 'Why Interesting':
        return entity.notes.map((n) => '- $n').join('\n');
      case 'Sources':
        return entity.links.map((l) => '- $l').join('\n');
      case 'Related':
        return relatedEntityNames.map((n) => '- [[$n]]').join('\n');
      default:
        return '';
    }
  }

  // ── Section-aware patch ────────────────────────────────────────────────────

  static String patchEntityContent({
    required String existingContent,
    required Entity entity,
    required String categoryName,
    required List<String> relatedEntityNames,
  }) {
    final split = splitFrontmatter(existingContent);
    final body = split.body;
    final rawSections = parseSectionsH2(body);

    final newFrontmatter = buildFrontmatter(
      entity: entity,
      categoryName: categoryName,
    );

    final buf = StringBuffer();
    buf.writeln('# ${entity.name}');

    for (final sectionName in rawSections.keys) {
      buf.writeln();
      buf.writeln('## $sectionName');

      if (_semanticSections.containsKey(sectionName)) {
        final rendered = renderSemanticSection(sectionName, entity, relatedEntityNames);
        if (rendered.isNotEmpty) {
          buf.writeln();
          buf.write(rendered);
        }
      } else {
        final raw = rawSections[sectionName]!;
        if (raw.isNotEmpty) {
          buf.writeln();
          buf.write(raw);
        }
      }
    }

    // Append semantic sections present in app data but absent from the file
    for (final sectionName in _semanticSections.keys) {
      if (!rawSections.containsKey(sectionName)) {
        final rendered = renderSemanticSection(sectionName, entity, relatedEntityNames);
        if (rendered.isNotEmpty) {
          buf.writeln();
          buf.writeln('## $sectionName');
          buf.writeln();
          buf.write(rendered);
        }
      }
    }

    return '$newFrontmatter\n${buf.toString().trimRight()}\n';
  }

  // ── Template system ────────────────────────────────────────────────────────

  static Future<String?> loadTemplate(String vaultPath, String categoryName) async {
    try {
      final tdir = VaultService.templatesPath(vaultPath);
      final slug = slugify(categoryName);

      if (slug.isNotEmpty) {
        final catFile = File(p.join(tdir, '$slug.md'));
        if (await catFile.exists()) {
          final content = await catFile.readAsString();
          if (_isTemplate(content)) return content;
        }
      }

      final defaultFile = File(p.join(tdir, 'default.md'));
      if (await defaultFile.exists()) {
        final content = await defaultFile.readAsString();
        if (_isTemplate(content)) return content;
      }

      return null;
    } catch (_) {
      return null;
    }
  }

  static bool _isTemplate(String content) {
    final yaml = parseYamlMap(splitFrontmatter(content).frontmatter);
    return yaml != null && yaml['template'] == true;
  }

  static String _instantiateTemplate(String templateContent, String title) =>
      templateContent.replaceAll('{{title}}', title);

  // ── New entity content builder ─────────────────────────────────────────────

  static Future<String> buildNewEntityContent({
    required String vaultPath,
    required Entity entity,
    required String categoryName,
    required List<String> relatedEntityNames,
  }) async {
    final templateContent = await loadTemplate(vaultPath, categoryName);
    if (templateContent != null) {
      final instantiated = _instantiateTemplate(templateContent, entity.name);
      return patchEntityContent(
        existingContent: instantiated,
        entity: entity,
        categoryName: categoryName,
        relatedEntityNames: relatedEntityNames,
      );
    }
    return buildEntityMarkdown(
      entity: entity,
      categoryName: categoryName,
      relatedEntityNames: relatedEntityNames,
    );
  }

  // ── Legacy fallback markdown builder ──────────────────────────────────────

  // Ultimate fallback when no template is available and no existing file can
  // be patched. Intentionally does NOT include movie-specific fields — those
  // are only written by buildFrontmatter.
  static String buildEntityMarkdown({
    required Entity entity,
    required String categoryName,
    required List<String> relatedEntityNames,
  }) {
    final buf = StringBuffer();

    buf.writeln('---');
    buf.writeln('alias: ${entity.id}');
    buf.writeln('category: $categoryName');
    if (entity.score != null) {
      buf.writeln('score: ${entity.score!.toStringAsFixed(1)}');
    }
    if (entity.tags.isNotEmpty) {
      buf.writeln('tags:');
      for (final tag in entity.tags) {
        buf.writeln('  - $tag');
      }
    }
    buf.writeln('created_at: ${msToIso(entity.createdAt)}');
    buf.writeln('updated_at: ${msToIso(entity.updatedAt)}');
    buf.writeln('---');
    buf.writeln('# ${entity.name}');

    if (entity.notes.isNotEmpty) {
      buf.writeln();
      buf.writeln('## Why Interesting');
      buf.writeln();
      for (final note in entity.notes) {
        buf.writeln('- $note');
      }
    }

    if (relatedEntityNames.isNotEmpty) {
      buf.writeln();
      buf.writeln('## Related');
      buf.writeln();
      for (final name in relatedEntityNames) {
        buf.writeln('- [[$name]]');
      }
    }

    if (entity.links.isNotEmpty) {
      buf.writeln();
      buf.writeln('## Sources');
      buf.writeln();
      for (final link in entity.links) {
        buf.writeln('- $link');
      }
    }

    return buf.toString();
  }
}
