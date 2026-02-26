import 'package:flutter/material.dart';

/// Simple inline message formatter for chat text.
///
/// Supports:
/// - **bold** → bold text
/// - *italic* → italic text
/// - `code` → monospace highlighted text
/// - bare URLs → underlined links
class MessageFormatter {
  MessageFormatter._();

  /// Parse inline formatting and return a list of TextSpans.
  static List<InlineSpan> format(
    String text, {
    required TextStyle baseStyle,
    Color? codeBackground,
  }) {
    final spans = <InlineSpan>[];
    final buffer = StringBuffer();
    var i = 0;

    while (i < text.length) {
      // Bold: **text**
      if (i + 1 < text.length && text[i] == '*' && text[i + 1] == '*') {
        final end = text.indexOf('**', i + 2);
        if (end != -1) {
          _flushBuffer(buffer, spans, baseStyle);
          spans.add(
            TextSpan(
              text: text.substring(i + 2, end),
              style: baseStyle.copyWith(fontWeight: FontWeight.bold),
            ),
          );
          i = end + 2;
          continue;
        }
        // No closing ** — treat as literal
        buffer.write('**');
        i += 2;
        continue;
      }

      // Italic: *text* (but not **)
      if (text[i] == '*' && (i + 1 >= text.length || text[i + 1] != '*')) {
        final end = text.indexOf('*', i + 1);
        if (end != -1) {
          _flushBuffer(buffer, spans, baseStyle);
          spans.add(
            TextSpan(
              text: text.substring(i + 1, end),
              style: baseStyle.copyWith(fontStyle: FontStyle.italic),
            ),
          );
          i = end + 1;
          continue;
        }
        // No closing * — treat as literal
        buffer.write('*');
        i++;
        continue;
      }

      // Code: `text`
      if (text[i] == '`') {
        final end = text.indexOf('`', i + 1);
        if (end != -1) {
          _flushBuffer(buffer, spans, baseStyle);
          spans.add(
            WidgetSpan(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: codeBackground ?? const Color(0x20FFFFFF),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text(
                  text.substring(i + 1, end),
                  style: baseStyle.copyWith(
                    fontFamily: 'monospace',
                    fontSize: (baseStyle.fontSize ?? 13) - 1,
                  ),
                ),
              ),
            ),
          );
          i = end + 1;
          continue;
        }
        // No closing ` — treat as literal
        buffer.write('`');
        i++;
        continue;
      }

      buffer.write(text[i]);
      i++;
    }

    _flushBuffer(buffer, spans, baseStyle);
    return spans;
  }

  /// URL pattern for detecting bare links.
  static final _urlPattern = RegExp(
    r'https?://[^\s<>]+|www\.[^\s<>]+',
    caseSensitive: false,
  );

  static void _flushBuffer(
    StringBuffer buffer,
    List<InlineSpan> spans,
    TextStyle style,
  ) {
    if (buffer.isEmpty) return;

    final text = buffer.toString();
    buffer.clear();

    // Scan for URLs in the buffered text
    final matches = _urlPattern.allMatches(text).toList();
    if (matches.isEmpty) {
      spans.add(TextSpan(text: text, style: style));
      return;
    }

    var lastEnd = 0;
    for (final match in matches) {
      // Text before the URL
      if (match.start > lastEnd) {
        spans.add(
          TextSpan(text: text.substring(lastEnd, match.start), style: style),
        );
      }
      // The URL itself — underlined + colored
      spans.add(
        TextSpan(
          text: match.group(0),
          style: style.copyWith(
            decoration: TextDecoration.underline,
            color: const Color(0xFF64B5F6), // light blue
          ),
        ),
      );
      lastEnd = match.end;
    }
    // Remaining text after last URL
    if (lastEnd < text.length) {
      spans.add(TextSpan(text: text.substring(lastEnd), style: style));
    }
  }
}
