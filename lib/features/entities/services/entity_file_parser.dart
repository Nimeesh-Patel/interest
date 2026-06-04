import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import '../models/entity.dart';
import '../../../shared/markdown/md_utils.dart';

class EntityFileParser {
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
