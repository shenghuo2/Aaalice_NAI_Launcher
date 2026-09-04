import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/l10n/app_localizations.dart';
import 'package:nai_launcher/presentation/widgets/prompt/unified/unified_prompt_config.dart';
import 'package:nai_launcher/presentation/widgets/prompt/unified/unified_prompt_input.dart';

void main() {
  testWidgets('toggles the tag containing the current selection', (
    tester,
  ) async {
    final controller = TextEditingController.fromValue(
      const TextEditingValue(
        text: 'one, two, three',
        selection: TextSelection.collapsed(offset: 6),
      ),
    );
    final focusNode = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: Scaffold(
            body: SizedBox(
              width: 500,
              height: 180,
              child: UnifiedPromptInput(
                controller: controller,
                focusNode: focusNode,
                enableAssistant: false,
                config: const UnifiedPromptConfig(
                  enableAutocomplete: false,
                  enableAutoFormat: false,
                ),
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('prompt_tag_action_bar')), findsOneWidget);
    expect(find.text('two'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('prompt_tag_toggle_button')));
    await tester.pump();

    expect(controller.text, 'one, ~two~, three');
    expect(controller.selection.baseOffset, 7);
    expect(find.byIcon(Icons.visibility), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('prompt_tag_toggle_button')));
    await tester.pump();

    expect(controller.text, 'one, two, three');
    expect(controller.selection.baseOffset, 6);
  });

  testWidgets('does not show the action for a cross-tag selection', (
    tester,
  ) async {
    final controller = TextEditingController.fromValue(
      const TextEditingValue(
        text: 'one, two',
        selection: TextSelection(baseOffset: 1, extentOffset: 7),
      ),
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: Scaffold(
            body: UnifiedPromptInput(
              controller: controller,
              enableAssistant: false,
              config: const UnifiedPromptConfig(enableAutocomplete: false),
            ),
          ),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('prompt_tag_action_bar')), findsNothing);
  });

  testWidgets('adjusts the tag under a collapsed caret without legacy overlay', (
    tester,
  ) async {
    final controller = TextEditingController.fromValue(
      const TextEditingValue(
        text: 'one, two, three',
        selection: TextSelection.collapsed(offset: 6),
      ),
    );
    final focusNode = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: Scaffold(
            body: SizedBox(
              width: 500,
              height: 180,
              child: UnifiedPromptInput(
                controller: controller,
                focusNode: focusNode,
                enableAssistant: false,
                config: const UnifiedPromptConfig(
                  enableAutocomplete: false,
                  enableAutoFormat: false,
                ),
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('prompt_tag_weight_value')), findsOneWidget);
    expect(find.text('1.00'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('weight_adjust_toolbar_surface')),
      findsNothing,
    );

    await tester.tap(
      find.byKey(const ValueKey('prompt_tag_weight_increase_button')),
    );
    await tester.pump();

    expect(controller.text, 'one, 1.05::two::, three');
    expect(controller.selection.textInside(controller.text), '1.05::two::');
    expect(find.text('1.05'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('weight_adjust_toolbar_surface')),
      findsNothing,
    );

    await tester.tap(
      find.byKey(const ValueKey('prompt_tag_weight_reset_button')),
    );
    await tester.pump();

    expect(controller.text, 'one, two, three');
    expect(controller.selection.textInside(controller.text), 'two');
    expect(find.text('1.00'), findsOneWidget);
  });

  testWidgets('keeps weight changes inside a disabled tag wrapper', (
    tester,
  ) async {
    final controller = TextEditingController.fromValue(
      const TextEditingValue(
        text: 'one, ~two~, three',
        selection: TextSelection.collapsed(offset: 7),
      ),
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: Scaffold(
            body: SizedBox(
              width: 500,
              height: 180,
              child: UnifiedPromptInput(
                controller: controller,
                enableAssistant: false,
                config: const UnifiedPromptConfig(
                  enableAutocomplete: false,
                  enableAutoFormat: false,
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(
      find.byKey(const ValueKey('prompt_tag_weight_decrease_button')),
    );
    await tester.pump();

    expect(controller.text, 'one, ~0.95::two::~, three');
    expect(find.byIcon(Icons.visibility), findsOneWidget);
  });
}
