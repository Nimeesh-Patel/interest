import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import '../models/entity.dart';
import '../../../shared/markdown/md_utils.dart';

class EntityFileParser {
  /// An entity file is identified by a `collection:` frontmatter key — nothing
  /// else. `alias`, `category`, and the body shape are all orthogonal to
  /// entity-ness.
  ///
  /// WHY collection (not category/alias): `category:` is a Problem-Note property
  /// (the AnkiDroid deck); keying entity discovery on it conflated the two and
  /// caused the June 2026 corruption. `collection:` is owned solely by the
  /// entity layer, so it is an unambiguous discriminator. A note may be both a
  /// Problem Note (`***` in body) and an Entity (`collection:` in frontmatter).
  static bool isEntityFrontmatter(YamlMap? yaml) =>
      yaml != null && yaml.containsKey('collection');

  /// True if [content] matches the June 2026 entity-save corruption signature:
  /// entity-ish frontmatter (`alias` + `created_at` + `updated_at`) over a body
  /// that is only an H1 title — no `***` separator, no `##` sections, no other
  /// prose. Diagnostic only; a legitimately empty note is indistinguishable, so
  /// treat matches as candidates for review.
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
    if (body.contains('***')) return false;
    final lines =
        body.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
    return lines.length == 1 && lines.first.startsWith('# ');
  }

  /// Parses a single entity file's [content] (read from [filePath]) into an
  /// [Entity] plus the names of entities wikilinked anywhere in the body.
  /// The app reads only frontmatter + the wikilink graph; the body is otherwise
  /// the user's territory. Never throws.
  static ({Entity entity, List<String> relatedNames, String collectionName})
      parseEntityFile(String content, String filePath) {
    final split = splitFrontmatter(content);
    final body = split.body;
    final basename = p.basenameWithoutExtension(filePath);

    String collectionName = '';
    double? score;
    List<String> tags = [];
    final now = DateTime.now().millisecondsSinceEpoch;
    int createdAt = now;
    int updatedAt = now;
    String aliasSlug = '';

    final yaml = parseYamlMap(split.frontmatter);
    if (yaml != null) {
      collectionName = yaml['collection']?.toString() ?? '';
      final rawAlias = yaml['alias'];
      if (rawAlias != null) aliasSlug = slugify(rawAlias.toString());
      final rawScore = yaml['score'];
      if (rawScore is num) score = rawScore.toDouble();
      final rawTags = yaml['tags'];
      if (rawTags is YamlList) {
        tags = rawTags.map((t) => t.toString()).toList();
      }
      createdAt = parseIsoToMs(yaml['created_at']?.toString()) ?? now;
      updatedAt = parseIsoToMs(yaml['updated_at']?.toString()) ?? createdAt;
    }

    final baseSlug = slugify(basename);
    final id = aliasSlug.isNotEmpty
        ? aliasSlug
        : (baseSlug.isNotEmpty ? baseSlug : 'entity');

    final relatedNames = extractWikilinks(body).toSet().toList();

    final entity = Entity(
      id: id,
      name: basename,
      collection: collectionName,
      tags: tags,
      score: score,
      createdAt: createdAt,
      updatedAt: updatedAt,
      sourcePath: filePath,
    );

    return (entity: entity, relatedNames: relatedNames, collectionName: collectionName);
  }
}
