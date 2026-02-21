import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monkeyssh/presentation/widgets/ai_composer_autocomplete.dart';

void main() {
  group('AiComposerAutocompleteEngine', () {
    const engine = AiComposerAutocompleteEngine(
      slashCommands: <String>['/help', '/clear', '/model'],
    );

    test('filters slash command suggestions from active token', () {
      final suggestions = engine.suggestionsFor(
        const TextEditingValue(
          text: '/mo',
          selection: TextSelection.collapsed(offset: 3),
        ),
      );

      expect(suggestions.map((s) => s.label), <String>['/model']);
    });

    test('shows slash command suggestions when only prefix is typed', () {
      final suggestions = engine.suggestionsFor(
        const TextEditingValue(
          text: '/',
          selection: TextSelection.collapsed(offset: 1),
        ),
      );

      expect(suggestions.map((s) => s.label), <String>[
        '/help',
        '/clear',
        '/model',
      ]);
    });

    test('filters remote file suggestions from active file token', () {
      final suggestions = engine.suggestionsFor(
        const TextEditingValue(
          text: 'open @main',
          selection: TextSelection.collapsed(offset: 10),
        ),
        remoteFiles: const <String>[
          'lib/main.dart',
          'README.md',
          'test/widget/ai_chat_ui_test.dart',
        ],
      );

      expect(suggestions.map((s) => s.label), <String>['@lib/main.dart']);
    });

    test('applies selected suggestion and moves cursor', () {
      final updatedValue = engine.applySuggestion(
        const TextEditingValue(
          text: 'please open @rea',
          selection: TextSelection.collapsed(offset: 16),
        ),
        const AiComposerSuggestion(
          label: '@README.md',
          insertText: '@README.md',
          type: AiComposerSuggestionType.fileReference,
        ),
      );

      expect(updatedValue.text, 'please open @README.md ');
      expect(updatedValue.selection.baseOffset, 23);
    });
  });
}
