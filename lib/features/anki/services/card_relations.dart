import '../../../shared/markdown/link_targets.dart';
import 'sync_manifest.dart';

/// Which notes list a note in `criticisms:`, read from the objection's side.
///
/// The objection's own card says which notes it is raised against. This is
/// derived from what every note already records ([NoteFacts.criticisms]);
/// nothing is authored twice.
class CardRelations {
  /// The notes that list a note in `criticisms:`, by that note's path in
  /// lower case: each as the vault-relative path (no `.md`) to link to.
  final Map<String, List<String>> challenged;

  const CardRelations({this.challenged = const {}});

  static const none = CardRelations();

  /// The relations among [facts] (every current note, by vault-relative path
  /// with `.md`), resolving criticism links through [linkTargets].
  factory CardRelations.from(
    Map<String, NoteFacts> facts,
    Map<String, String> linkTargets,
  ) {
    final challenged = <String, List<String>>{};
    for (final entry in facts.entries) {
      final path = pathOf(entry.key);
      for (final link in entry.value.criticisms) {
        final target = (linkTargets[link] ?? link).toLowerCase();
        challenged.putIfAbsent(target, () => []).add(path);
      }
    }
    for (final list in challenged.values) {
      list.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    }
    return CardRelations(challenged: challenged);
  }

  /// The relations among [facts], resolving links by the notes' own aliases.
  factory CardRelations.of(Map<String, NoteFacts> facts) => CardRelations.from(
    facts,
    resolveLinkTargets({
      for (final entry in facts.entries) entry.key: entry.value.aliases,
    }),
  );

  /// A note's link-resolution path from its vault-relative file path.
  static String pathOf(String key) =>
      key.toLowerCase().endsWith('.md')
          ? key.substring(0, key.length - 3)
          : key;

  List<String> challengedBy(String notePath) =>
      challenged[notePath.toLowerCase()] ?? const [];

  /// What the card of the note at [key] shows of other notes. When it
  /// differs between two syncs, that card must be rendered again even though
  /// its own file did not change.
  String signature(String key) => challengedBy(pathOf(key)).join('\u001e');
}
