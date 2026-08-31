import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/core/utils/disabled_prompt_tag_syntax.dart';

void main() {
  group('DisabledPromptTagSyntax', () {
    test('finds top-level tags while protecting prompt syntax', () {
      const prompt =
          'one, {two, three}, 1.2::four, five::, ||six, seven||，eight\nnine';

      expect(
        DisabledPromptTagSyntax.segments(
          prompt,
        ).map((segment) => segment.sourceText(prompt)),
        [
          'one',
          '{two, three}',
          '1.2::four, five::',
          '||six, seven||',
          'eight',
          'nine',
        ],
      );
    });

    test('toggles the tag containing a collapsed caret', () {
      const prompt = 'one, {two}, three';
      final disabled = DisabledPromptTagSyntax.toggleSelection(
        prompt,
        selectionBase: 7,
        selectionExtent: 7,
      )!;

      expect(disabled.text, 'one, ~{two}~, three');
      expect(disabled.selectionBase, 8);
      expect(disabled.selectionExtent, 8);

      final enabled = DisabledPromptTagSyntax.toggleSelection(
        disabled.text,
        selectionBase: disabled.selectionBase,
        selectionExtent: disabled.selectionExtent,
      )!;
      expect(enabled.text, prompt);
      expect(enabled.selectionBase, 7);
    });

    test('preserves a text selection while toggling', () {
      const prompt = 'one, two, three';
      final disabled = DisabledPromptTagSyntax.toggleSelection(
        prompt,
        selectionBase: 5,
        selectionExtent: 8,
      )!;

      expect(disabled.text, 'one, ~two~, three');
      expect(disabled.selectionBase, 6);
      expect(disabled.selectionExtent, 9);
    });

    test('removes disabled tags from generated output', () {
      expect(
        DisabledPromptTagSyntax.outputOf(
          'one, ~{two, three}~, 1.2::four, five::, ~six~',
        ),
        'one, 1.2::four, five::',
      );
      expect(DisabledPromptTagSyntax.outputOf('~only~'), isEmpty);
    });

    test('preserves enabled formatting while removing disabled tags', () {
      expect(
        DisabledPromptTagSyntax.outputOf('one,  ~two~,\n  three'),
        'one,  \n  three',
      );
      expect(
        DisabledPromptTagSyntax.outputOf('one\n~two~\nthree'),
        'one\nthree',
      );
    });

    test('keeps a disabled numeric-weight group as one segment', () {
      const prompt = '~1.2::four, five::~, six';
      final segments = DisabledPromptTagSyntax.segments(prompt);

      expect(segments, hasLength(2));
      expect(segments.first.disabled, isTrue);
      expect(DisabledPromptTagSyntax.outputOf(prompt), 'six');
    });

    test('leaves prompts without disabled tags byte-for-byte unchanged', () {
      const prompt = 'one， {two, three}\nfour';
      expect(DisabledPromptTagSyntax.outputOf(prompt), prompt);
    });

    test('does not treat an escaped closing tilde as disabled syntax', () {
      const prompt = r'~literal\~, next';
      final segments = DisabledPromptTagSyntax.segments(prompt);

      expect(segments.first.disabled, isFalse);
      expect(DisabledPromptTagSyntax.outputOf(prompt), prompt);
    });

    test('rejects selections spanning more than one tag', () {
      expect(
        DisabledPromptTagSyntax.toggleSelection(
          'one, two',
          selectionBase: 1,
          selectionExtent: 7,
        ),
        isNull,
      );
    });
  });
}
