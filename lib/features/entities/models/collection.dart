/// A Collection is a free-form grouping of entities, derived at load time from
/// the distinct `collection:` frontmatter values across all entity files.
/// It is not a stored object — there is no collection table.
class Collection {
  final String id;
  String name;

  Collection({required this.id, required this.name});
}
