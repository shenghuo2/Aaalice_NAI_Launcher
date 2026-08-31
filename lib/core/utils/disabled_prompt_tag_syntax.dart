class DisabledPromptTagSegment {
  const DisabledPromptTagSegment({
    required this.start,
    required this.end,
    required this.contentStart,
    required this.contentEnd,
    required this.disabled,
  });

  final int start;
  final int end;
  final int contentStart;
  final int contentEnd;
  final bool disabled;

  String sourceText(String source) => source.substring(start, end);

  String contentText(String source) =>
      source.substring(contentStart, contentEnd);
}

class DisabledPromptTagEdit {
  const DisabledPromptTagEdit({
    required this.text,
    required this.selectionBase,
    required this.selectionExtent,
  });

  final String text;
  final int selectionBase;
  final int selectionExtent;
}

/// Editing-only syntax for keeping prompt tags visible while excluding them
/// from generation. A disabled top-level tag is wrapped as `~tag~`.
abstract final class DisabledPromptTagSyntax {
  static List<DisabledPromptTagSegment> segments(String prompt) {
    if (prompt.trim().isEmpty) return const [];

    final segments = <DisabledPromptTagSegment>[];
    final wrappers = <String>[];
    var tokenStart = 0;
    var numericWeightOpen = false;
    var inPipe = false;
    var escaped = false;

    void addSegment(int rawEnd) {
      var start = tokenStart;
      var end = rawEnd;
      while (start < end && prompt[start].trim().isEmpty) {
        start++;
      }
      while (end > start && prompt[end - 1].trim().isEmpty) {
        end--;
      }
      if (start >= end) return;

      final disabled =
          end - start >= 2 &&
          prompt[start] == '~' &&
          prompt[end - 1] == '~' &&
          !_isEscapedAt(prompt, start) &&
          !_isEscapedAt(prompt, end - 1);
      segments.add(
        DisabledPromptTagSegment(
          start: start,
          end: end,
          contentStart: disabled ? start + 1 : start,
          contentEnd: disabled ? end - 1 : end,
          disabled: disabled,
        ),
      );
    }

    for (var index = 0; index < prompt.length; index++) {
      final character = prompt[index];
      if (escaped) {
        escaped = false;
        continue;
      }
      if (character == r'\') {
        escaped = true;
        continue;
      }

      if (index + 1 < prompt.length &&
          character == '|' &&
          prompt[index + 1] == '|') {
        inPipe = !inPipe;
        index++;
        continue;
      }

      if (index + 1 < prompt.length &&
          character == ':' &&
          prompt[index + 1] == ':') {
        if (numericWeightOpen) {
          numericWeightOpen = false;
        } else {
          final prefix = prompt.substring(tokenStart, index).trimLeft();
          if (RegExp(
            r'^~?[\(\[\{]*\s*[+-]?(?:\d+(?:\.\d+)?|\.\d+)\s*$',
          ).hasMatch(prefix)) {
            numericWeightOpen = true;
          }
        }
        index++;
        continue;
      }

      final closing = switch (character) {
        '(' => ')',
        '[' => ']',
        '{' => '}',
        _ => null,
      };
      if (closing != null) {
        wrappers.add(closing);
        continue;
      }
      if (wrappers.isNotEmpty && character == wrappers.last) {
        wrappers.removeLast();
        continue;
      }

      if ((character == ',' || character == '，' || character == '\n') &&
          wrappers.isEmpty &&
          !numericWeightOpen &&
          !inPipe) {
        addSegment(index);
        tokenStart = index + 1;
      }
    }
    addSegment(prompt.length);
    return List.unmodifiable(segments);
  }

  static DisabledPromptTagSegment? segmentForSelection(
    String prompt, {
    required int selectionStart,
    required int selectionEnd,
  }) {
    if (selectionStart < 0 || selectionEnd < 0) return null;
    final start = selectionStart < selectionEnd ? selectionStart : selectionEnd;
    final end = selectionStart < selectionEnd ? selectionEnd : selectionStart;
    if (end > prompt.length) return null;

    for (final segment in segments(prompt)) {
      if (start >= segment.start && end <= segment.end) {
        return segment;
      }
    }
    return null;
  }

  static DisabledPromptTagEdit? toggleSelection(
    String prompt, {
    required int selectionBase,
    required int selectionExtent,
  }) {
    final segment = segmentForSelection(
      prompt,
      selectionStart: selectionBase,
      selectionEnd: selectionExtent,
    );
    if (segment == null) return null;

    late final String replacement;
    late final int Function(int offset) mapOffset;
    if (segment.disabled) {
      replacement = segment.contentText(prompt);
      mapOffset = (offset) {
        if (offset <= segment.start) return segment.start;
        if (offset < segment.end) return offset - 1;
        return offset - 2;
      };
    } else {
      replacement = '~${segment.sourceText(prompt)}~';
      mapOffset = (offset) {
        if (offset < segment.start) return offset;
        if (offset <= segment.end) return offset + 1;
        return offset + 2;
      };
    }

    final text = prompt.replaceRange(segment.start, segment.end, replacement);
    return DisabledPromptTagEdit(
      text: text,
      selectionBase: mapOffset(selectionBase).clamp(0, text.length),
      selectionExtent: mapOffset(selectionExtent).clamp(0, text.length),
    );
  }

  static String outputOf(String prompt) {
    var output = prompt;
    var changed = false;
    while (true) {
      DisabledPromptTagSegment? disabled;
      for (final segment in segments(output)) {
        if (segment.disabled) {
          disabled = segment;
          break;
        }
      }
      if (disabled == null) break;

      final range = _rangeWithSeparator(output, disabled.start, disabled.end);
      output = output.replaceRange(range.$1, range.$2, '');
      changed = true;
    }
    return changed ? output.trim() : prompt;
  }

  static (int, int) _rangeWithSeparator(String text, int start, int end) {
    var right = end;
    while (right < text.length && _isHorizontalSpace(text[right])) {
      right++;
    }
    if (right < text.length && _isSeparator(text[right])) {
      right++;
      while (right < text.length && _isHorizontalSpace(text[right])) {
        right++;
      }
      return (start, right);
    }

    var left = start;
    while (left > 0 && _isHorizontalSpace(text[left - 1])) {
      left--;
    }
    if (left > 0 && _isSeparator(text[left - 1])) {
      left--;
      while (left > 0 && _isHorizontalSpace(text[left - 1])) {
        left--;
      }
      return (left, end);
    }
    return (start, end);
  }

  static bool _isSeparator(String character) =>
      character == ',' || character == '，' || character == '\n';

  static bool _isHorizontalSpace(String character) =>
      character == ' ' || character == '\t' || character == '\r';

  static bool _isEscapedAt(String text, int index) {
    var slashCount = 0;
    for (
      var cursor = index - 1;
      cursor >= 0 && text[cursor] == r'\';
      cursor--
    ) {
      slashCount++;
    }
    return slashCount.isOdd;
  }
}
