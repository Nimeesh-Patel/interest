import 'package:yaml/yaml.dart';

/// Patch only named top-level fields. Values are YAML fragments; null removes
/// a field. Source outside those fields, including the entire body, is copied
/// verbatim. Unsupported/invalid YAML is refused rather than reconstructed.
String patchFrontmatterText(String source, Map<String, String?> changes) {
  final bom = source.startsWith('\uFEFF') ? '\uFEFF' : '';
  final text = source.substring(bom.length);
  final newline = text.contains('\r\n') ? '\r\n' : '\n';
  final opening = RegExp(r'^---[^\S\r\n]*(?:\r\n|\n|$)').firstMatch(text);
  String prefix;
  String fm;
  String suffix;
  if (opening == null) {
    prefix = '$bom---$newline';
    fm = '';
    suffix = '---$newline$text';
  } else {
    final closing = RegExp(
      r'^---[^\S\r\n]*(?:\r\n|\n|$)',
      multiLine: true,
    ).firstMatch(text.substring(opening.end));
    if (closing == null) {
      throw const FormatException('malformed opening frontmatter');
    }
    final closeStart = opening.end + closing.start;
    prefix = '$bom${text.substring(0, opening.end)}';
    fm = text.substring(opening.end, closeStart);
    suffix = text.substring(closeStart);
  }

  final parsed = loadYamlNode(fm);
  if (parsed is! YamlMap && parsed.value != null) {
    throw const FormatException('frontmatter must be a YAML mapping');
  }
  if (parsed is YamlMap && parsed.style != CollectionStyle.BLOCK) {
    throw const FormatException(
      'flow-style frontmatter cannot be patched safely',
    );
  }
  final edits = <({int start, int end, String text})>[];
  final remaining = Map<String, String?>.of(changes);
  if (parsed is YamlMap) {
    for (final entry in parsed.nodes.entries) {
      final key = entry.key as YamlNode;
      if (!changes.containsKey(key.value)) continue;
      // Complex keys and alias spans do not describe an independently owned
      // source range. Refuse them instead of guessing a replacement boundary.
      final start = key.span.start.offset;
      var end = _contentEnd(entry.value);
      if (key is! YamlScalar ||
          key.span.start.column != 0 ||
          end < key.span.end.offset ||
          end > fm.length) {
        throw const FormatException('unsupported frontmatter field span');
      }
      while (end > start && (fm[end - 1] == '\n' || fm[end - 1] == '\r')) {
        end--;
      }
      final value = remaining.remove(key.value);
      edits.add((
        start: start,
        end: end,
        text:
            value == null
                ? ''
                : '${fm.substring(start, key.span.end.offset)}: $value',
      ));
    }
  }
  edits.sort((a, b) => b.start.compareTo(a.start));
  for (final edit in edits) {
    fm = fm.replaceRange(edit.start, edit.end, edit.text);
  }
  for (final entry in remaining.entries) {
    if (entry.value == null) continue;
    if (!RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(entry.key)) {
      throw const FormatException('unsupported new frontmatter key');
    }
    if (fm.isNotEmpty && !fm.endsWith('\n')) fm += newline;
    fm += '${entry.key}: ${entry.value}$newline';
  }
  // Includes refusal when replacing an anchor would strand an unowned alias.
  final verified = loadYamlNode(fm);
  if (verified is! YamlMap && verified.value != null) {
    throw const FormatException('patch did not produce a YAML mapping');
  }
  return '$prefix$fm$suffix';
}

// Block collections' parser spans include comments before the following key.
// The last child, rather than the collection span, ends the owned content.
int _contentEnd(YamlNode node) {
  if (node is YamlList &&
      node.style == CollectionStyle.BLOCK &&
      node.nodes.isNotEmpty) {
    return _contentEnd(node.nodes.last);
  }
  if (node is YamlMap &&
      node.style == CollectionStyle.BLOCK &&
      node.nodes.isNotEmpty) {
    return _contentEnd(node.nodes.values.last);
  }
  return node.span.end.offset;
}
