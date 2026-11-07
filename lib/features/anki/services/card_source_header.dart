import 'dart:convert';

/// The header every Interest card front starts with: one link back to the
/// card's Problem Note, which is also the card's ownership anchor.
///
/// Readers rely on its shape, so it is a contract, not decoration:
/// - `AnkiSyncService._ownedSource` takes the first `obsidian://open` href;
/// - `retireNote` (both transports) checks `href="<uri>"` before deleting;
/// - `_plainText` strips one leading `<div …>…</div>`, so the header holds
///   no nested `div`;
/// - Perspirator's `anki_query.py` matches the leading
///   `<div class="interest-source"` and requires exactly one `<a href>`.
///
/// Its look follows the card: text and icon use the card's own colour
/// (`currentColor`) and the tint is a translucent neutral, so AnkiDroid's
/// night mode (which may invert colours) and any deck styling stay legible.
/// The pill is a 36 px tall target with room around it, the title stays on
/// one line, and the pencil says what the tap is for: editing the note.
class CardSourceHeader {
  CardSourceHeader._();

  static const marker = 'interest-source';

  static const _pencil =
      '<svg width="15" height="15" viewBox="0 0 24 24" fill="none" '
      'stroke="currentColor" stroke-width="2" stroke-linecap="round" '
      'stroke-linejoin="round" aria-hidden="true" '
      'style="flex:none;display:block;">'
      '<path d="M12 20h9"/>'
      '<path d="M16.5 3.5a2.12 2.12 0 0 1 3 3L7 19l-4 1 1-4Z"/>'
      '</svg>';

  static String html(String sourceUri, String title) =>
      '<div class="$marker" style="display:flex;justify-content:flex-end;'
      'margin:0 0 14px;">'
      '<a href="$sourceUri" style="display:inline-flex;align-items:center;'
      'gap:7px;max-width:88%;min-height:36px;box-sizing:border-box;'
      'padding:0 14px 0 12px;border-radius:18px;'
      'background:rgba(128,128,128,0.14);color:inherit;opacity:0.78;'
      'font-size:14px;line-height:1.2;font-weight:500;text-decoration:none;'
      '-webkit-tap-highlight-color:transparent;">'
      '$_pencil'
      '<span style="overflow:hidden;text-overflow:ellipsis;white-space:nowrap;">'
      '${const HtmlEscape(HtmlEscapeMode.element).convert(title)}</span>'
      '</a></div>';
}
