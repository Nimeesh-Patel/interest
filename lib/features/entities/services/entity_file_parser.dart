import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import '../models/entity.dart';
import '../../../shared/markdown/md_utils.dart';

class EntityFileParser {
  /// An entity file is identified by BOTH a `category:` and an `alias:` key.
  ///
  /// `category:` alone is NOT sufficient: problem notes (Resurface `***` cards)
  /// carry `category:` for AnkiDroid deck mapping but never an `alias:`. The
  /// June 2026 corruption arose precisely because discovery keyed on `category:`
  /// alone, pulling problem notes into the entity list where `saveData` then
  /// rewrote them in entity format. Requiring both keys excludes them.
  /// Bookmarks, books, and articles have `alias:` but no `category:`, so they
  /// are also correctly excluded.
  static bool isEntityFrontmatter(YamlMap? yaml) =>
      yaml != null && yaml.containsKey('category') && yaml.containsKey('alias');

  /// True if [content] matches the June 2026 entity-save corruption signature:
  /// entity frontmatter (`alias` + `created_at` + `updated_at`) over a body that
  /// is only an H1 title — no `***` separator, no `##` sections, no other prose.
  ///
  /// Diagnostic only, never authoritative: a legitimately empty, template-less
  /// entity is structurally identical to a corrupted problem-note husk. Treat
  /// matches as candidates for human review, not certainties.
  static bool isCorruptedHusk(String content) {
    final split = splitFrontmatter(content);
    final yaml = parseYamlMap(split.frontmatter);
    if (yaml == null) return false;
    if (!yaml.containsKey('alias') ||
        !yaml.containsKey('created_at') ||
        !yaml.containsKey('updated_at')) {
      return false;
    }
    final body = split.body;
    if (body.contains('***')) return false; // a card separator → not a husk
    final lines =
        body.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
    return lines.length == 1 && lines.first.startsWith('# ');
  }

  /// Parses a single entity file's [content] (read from [filePath]).
  /// Returns the parsed Entity, the names of related entities found in the
  /// body, and the raw category name string from the frontmatter.
  /// Never throws.
  static ({Entity entity, List<String> relatedNames, String categoryName})
      parseEntityFile(String content, String filePath) {
    final split = splitFrontmatter(content);
    final body = split.body;
    final basename = p.basenameWithoutExtension(filePath);

    String alias = slugify(basename).isEmpty ? 'entity' : slugify(basename);
    String categoryName = '';
    double? score;
    List<String> tags = [];
    String? watchedDate;
    String? letterboxdUrl;
    String? tmdbId;
    final now = DateTime.now().millisecondsSinceEpoch;
    int createdAt = now;
    int updatedAt = now;

    final yaml = parseYamlMap(split.frontmatter);
    if (yaml != null) {
      final rawAlias = yaml['alias'];
      if (rawAlias != null) {
        final a = slugify(rawAlias.toString());
        if (a.isNotEmpty) alias = a;
      }
      categoryName = yaml['category']?.toString() ?? '';
      final rawScore = yaml['score'];
      if (rawScore is num) score = rawScore.toDouble();
      final rawTags = yaml['tags'];
      if (rawTags is YamlList) {
        tags = rawTags.map((t) => t.toString()).toList();
      }
      createdAt = parseIsoToMs(yaml['created_at']?.toString()) ?? now;
      updatedAt = parseIsoToMs(yaml['updated_at']?.toString()) ?? createdAt;
      watchedDate = yaml['watched_date']?.toString();
      letterboxdUrl = yaml['letterboxd_url']?.toString();
      tmdbId = yaml['tmdb_id']?.toString();
    }

    final name = extractH1(body) ?? basename;

    final rawSections = parseSectionsH2(body);
    final notes = parseSectionAsList(rawSections['Why Interesting'] ?? '');
    final links = parseSectionAsList(rawSections['Sources'] ?? '');
    final relatedNames = {
      ...parseSectionAsWikilinks(rawSections['Related'] ?? ''),
      ...extractWikilinks(body),
    }.toList();

    final catId = categoryName.isEmpty
        ? 'uncategorized'
        : (slugify(categoryName).isEmpty ? 'uncategorized' : slugify(categoryName));

    final entity = Entity(
      id: alias,
      name: name,
      categoryId: catId,
      notes: notes,
      links: links,
      tags: tags,
      score: score,
      createdAt: createdAt,
      updatedAt: updatedAt,
      rawSections: rawSections,
      watchedDate: watchedDate,
      letterboxdUrl: letterboxdUrl,
      tmdbId: tmdbId,
    );

    return (entity: entity, relatedNames: relatedNames, categoryName: categoryName);
  }
}
