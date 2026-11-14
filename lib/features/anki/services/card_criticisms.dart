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

  /// A red that clears 4.5:1 on both a white and a black card (4.55 and
  /// 4.62), because a field cannot tell which theme will show it.
  static const _red = '#d93a3a';

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
      if (!_wholeLink.hasMatch(entry)) throw const FormatException(_shape);
    }
    return entries;
  }

  static const _shape =
      'criticisms must be links to notes, like "[[Note]]"';

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
  /// it off whole. Links take the card's own colour; only the label and the
  /// rule are red. Each link is a 40 px tall target.
  static String html(
    List<String> entries,
    String Function(String target) hrefFor,
  ) {
    if (entries.isEmpty) return '';
    final rows = StringBuffer();
    for (final entry in entries) {
      rows.write(_row(entry, hrefFor));
    }
    return '<div class="$marker" style="margin:28px 0 4px;'
        'padding:12px 14px 8px 16px;border-left:3px solid $_red;'
        'border-radius:3px 12px 12px 3px;background:rgba(217,58,58,0.10);'
        'text-align:left;font-size:16px;line-height:1.4;">'
        '<span style="display:block;margin:0 0 6px;font-size:13px;'
        'font-weight:600;color:$_red;">'
        '${entries.length == 1 ? 'Open criticism' : 'Open criticisms'}</span>'
        '$rows</div>';
  }

  static final _wholeLink = RegExp(r'^\[\[([^\]|]+)(?:\|([^\]]+))?\]\]$');
  static const _escape = HtmlEscape(HtmlEscapeMode.element);

  static String _row(String entry, String Function(String target) hrefFor) {
    // parse() admits only whole links, so the row is always the tap target.
    final link = _wholeLink.firstMatch(entry)!;
    final target = link.group(1)!.trim();
    final label = (link.group(2) ?? target).trim();
    return '<a href="${hrefFor(target)}" style="display:flex;'
        'align-items:center;gap:8px;min-height:40px;color:inherit;'
        'text-decoration:none;-webkit-tap-highlight-color:transparent;">'
        '<span style="flex:1;">${_escape.convert(label)}</span>$_arrow</a>';
  }

  /// The card's back without the criticisms section: the conjecture alone.
  static String withoutSection(String back) {
    final at = back.indexOf('<div class="$marker"');
    return at < 0 ? back : back.substring(0, at);
  }
}
