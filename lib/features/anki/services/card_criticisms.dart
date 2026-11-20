import 'dart:convert';

import 'package:yaml/yaml.dart';

/// Open criticisms of a Problem Note, as the card shows them.
///
/// A review often raises an objection that cannot be answered on the spot.
/// A rating brings the card back but says nothing about what was wrong, so
/// the objection is recorded on the challenged note, in a `criticisms:`
/// property, and the card's answer side lists what is still open. An entry
/// is a link to the note that holds the objection, picked with Obsidian's
/// own note search in Properties. Removing the entry is how the author says
/// it no longer applies; nothing here decides that for him.
class CardCriticisms {
  CardCriticisms._();

  /// The frontmatter key on the challenged note.
  static const property = 'criticisms';

  /// Class of the section that closes the card's back. Readers that want the
  /// conjecture alone cut the back at this marker ([withoutSection]).
  static const marker = 'interest-criticisms';

  /// The entries as authored, in order. A malformed property is an error,
  /// never an empty list: silently dropping objections would make the card
  /// claim there are none.
  static List<String> parse(Object? value) {
    if (value == null) return const [];
    final entries = _kept(
      value is String
          ? [value]
          : value is List
          ? [for (final item in value) _entry(item)]
          : throw const FormatException(_shape),
    );
    for (final entry in entries) {
      if (_target(entry) == null) throw const FormatException(_shape);
    }
    return entries;
  }

  static const _shape = 'criticisms must be links to notes, like "[[Note]]"';

  static String _entry(Object? item) {
    if (item == null) return '';
    if (item is String) return item;
    // An unquoted `- [[Note]]` is YAML for a list inside a list. It can only
    // have meant the link, so it is read as one.
    if (item is YamlList && item.length == 1) {
      final inner = item.first;
      if (inner is YamlList && inner.length == 1 && inner.first is String) {
        return '[[${inner.first}]]';
      }
    }
    throw const FormatException(_shape);
  }

  static List<String> _kept(Iterable<String> entries) => [
    for (final entry in entries)
      if (entry.trim().isNotEmpty) entry.trim(),
  ];

  static const _arrow =
      '<svg width="14" height="14" viewBox="0 0 24 24" fill="none" '
      'stroke="currentColor" stroke-width="2.2" stroke-linecap="round" '
      'stroke-linejoin="round" aria-hidden="true" '
      'style="flex:none;display:block;opacity:0.7;">'
      '<path d="M7 17 17 7"/><path d="M8 7h9v9"/></svg>';

  /// The section appended to the card's back, or '' when nothing is open.
  ///
  /// It holds no nested `div`, so [withoutSection] and `_plainText` can cut
  /// it off whole. The heading and links take the card's foreground colour.
  static String html(
    List<String> entries,
    ({String href, String title}) Function(String target) destination,
  ) {
    if (entries.isEmpty) return '';
    final rows = StringBuffer();
    for (final entry in entries) {
      rows.write(_row(destination(_target(entry)!)));
    }
    return '<div class="$marker" style="margin:24px 0 4px;'
        'padding:12px 0 0;border-top:1px solid currentColor;'
        'text-align:left;font-size:16px;line-height:1.4;color:inherit;">'
        '<h2 style="margin:0 0 4px;font-size:0.875em;font-weight:600;'
        'color:inherit;">'
        '${entries.length == 1 ? 'Open criticism' : 'Open criticisms'}</h2>'
        '$rows</div>';
  }

  static final _wholeLink = RegExp(r'^\[\[([^\]|]+)(?:\|([^\]]+))?\]\]$');
  static String? _target(String entry) {
    final target = _wholeLink.firstMatch(entry)?.group(1)?.trim();
    if (target == null || target.isEmpty) return null;
    return target;
  }

  static Iterable<String> targets(List<String> entries) =>
      entries.map((entry) => _target(entry)!);

  static const _escape = HtmlEscape(HtmlEscapeMode.element);

  static String _row(({String href, String title}) link) =>
      '<a href="${link.href}" style="display:flex;'
      'align-items:center;gap:8px;min-height:48px;padding:6px 0;'
      'color:inherit;text-decoration:none;">'
      '<span style="flex:1;min-width:0;overflow-wrap:anywhere;'
      'text-decoration:underline;text-underline-offset:3px;">'
      '${_escape.convert(link.title)}</span>$_arrow</a>';

  /// Class of the line that says which notes this one is raised against.
  static const raisedMarker = 'interest-raised';

  /// The relation read from the objection's side: the notes that list this
  /// one in their `criticisms:`. Derived, so nothing is authored twice.
  static String raisedAgainstHtml(List<({String href, String title})> notes) {
    if (notes.isEmpty) return '';
    final links = notes
        .map(
          (note) =>
              '<a href="${note.href}" style="color:inherit;'
              'text-decoration:underline;text-underline-offset:3px;">'
              '${_escape.convert(note.title)}</a>',
        )
        .join(', ');
    return '<div class="$raisedMarker" style="margin:20px 0 4px;'
        'text-align:left;font-size:0.8125em;line-height:1.5;opacity:0.72;'
        'color:inherit;">Raised against: $links</div>';
  }

  /// The card's back without the criticisms section: the conjecture alone.
  static String withoutSection(String back) {
    final cuts = [
      for (final name in [marker, raisedMarker])
        back.indexOf('<div class="$name"'),
    ].where((at) => at >= 0);
    return cuts.isEmpty
        ? back
        : back.substring(0, cuts.reduce((a, b) => a < b ? a : b));
  }
}
