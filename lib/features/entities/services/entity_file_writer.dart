import '../models/entity.dart';
import '../../../shared/markdown/md_utils.dart';

/// Writes entity files by patching ONLY the frontmatter keys the app owns —
/// it never rebuilds, reshapes, or even reads the body for meaning. An entity
/// is a plain Markdown note with a `collection:` key; its body is the user's
/// territory and is preserved byte-for-byte on every save.
///
/// This is the structural fix for the June 2026 corruption: there is no longer
/// any code path that rewrites an entity's body, so the entity save can never
/// destroy note content (including a Problem Note's `***` front/back).
class EntityFileWriter {
  /// App-owned frontmatter keys, in canonical order. Only `collection` is always
  /// written; `tags`/`score` are written when set. Every other key present in the
  /// file (`alias`, `created_at`/`updated_at` if the user keeps them, `category`/
  /// deck, `anki_note_id`, `up`, user-defined keys, …) is preserved untouched.
  /// The app neither requires nor stamps timestamps — an entity is simply a note
  /// with `collection:`.
  static const _knownOrder = ['collection', 'alias', 'tags', 'score'];

  /// Returns [existingContent] with the entity-owned frontmatter keys updated
  /// from [entity] and the body preserved verbatim. Pure (string→string).
  static String patchFrontmatter({
    required String existingContent,
    required Entity entity,
  }) {
    final split = splitFrontmatter(existingContent);
    final merged = <String, dynamic>{};
    parseYamlMap(split.frontmatter)
        ?.forEach((k, v) => merged[k.toString()] = v);

    merged['collection'] = entity.collection;
    if (entity.score != null) {
      merged['score'] = entity.score!.toStringAsFixed(1);
    } else {
      merged.remove('score');
    }
    if (entity.tags.isNotEmpty) {
      merged['tags'] = entity.tags;
    } else {
      merged.remove('tags');
    }

    return '${buildFrontmatterBlock(merged, _knownOrder)}\n${split.body}';
  }

  /// Content for a brand-new entity: just `collection:` frontmatter. No body
  /// structure is imposed — not even an H1 — and no timestamps. The note starts
  /// empty; the user writes whatever they want via the note editor, and the
  /// filename carries the name.
  static String buildNewEntity({required String collection}) =>
      '${buildFrontmatterBlock({'collection': collection}, _knownOrder)}\n';
}
