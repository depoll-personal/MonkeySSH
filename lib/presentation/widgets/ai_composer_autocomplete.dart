import 'package:flutter/services.dart';

/// Supported composer autocomplete suggestion categories.
enum AiComposerSuggestionType {
  /// Slash command suggestion.
  slashCommand,

  /// Remote file-reference suggestion.
  fileReference,
}

/// Composer suggestion item.
class AiComposerSuggestion {
  /// Creates an [AiComposerSuggestion].
  const AiComposerSuggestion({
    required this.label,
    required this.insertText,
    required this.type,
  });

  /// Human-readable suggestion label.
  final String label;

  /// Text inserted into the composer when selected.
  final String insertText;

  /// Suggestion category.
  final AiComposerSuggestionType type;
}

/// Text-composer autocomplete logic for slash commands and file references.
class AiComposerAutocompleteEngine {
  /// Creates an [AiComposerAutocompleteEngine].
  const AiComposerAutocompleteEngine({required List<String> slashCommands})
    : _slashCommands = slashCommands;

  final List<String> _slashCommands;

  /// Whether [value] currently requires remote file suggestions.
  bool requiresRemoteFileSuggestions(TextEditingValue value) {
    final token = _activeToken(value);
    return token != null &&
        token.type == AiComposerSuggestionType.fileReference;
  }

  /// Returns suggestions for [value].
  List<AiComposerSuggestion> suggestionsFor(
    TextEditingValue value, {
    List<String> remoteFiles = const <String>[],
  }) {
    final token = _activeToken(value);
    if (token == null) {
      return const <AiComposerSuggestion>[];
    }

    final normalizedQuery = token.query.toLowerCase();
    if (token.type == AiComposerSuggestionType.slashCommand) {
      return _slashCommands
          .where(
            (command) => command.toLowerCase().startsWith('/$normalizedQuery'),
          )
          .map(
            (command) => AiComposerSuggestion(
              label: command,
              insertText: command,
              type: AiComposerSuggestionType.slashCommand,
            ),
          )
          .toList(growable: false);
    }

    return remoteFiles
        .where((path) => path.toLowerCase().contains(normalizedQuery))
        .take(8)
        .map(
          (path) => AiComposerSuggestion(
            label: '@$path',
            insertText: '@$path',
            type: AiComposerSuggestionType.fileReference,
          ),
        )
        .toList(growable: false);
  }

  /// Applies [suggestion] to [value] and returns updated text state.
  TextEditingValue applySuggestion(
    TextEditingValue value,
    AiComposerSuggestion suggestion,
  ) {
    final token = _activeToken(value);
    if (token == null) {
      return value;
    }

    final before = value.text.substring(0, token.start);
    final after = value.text.substring(token.end);
    final shouldAppendSpace = after.isEmpty || !after.startsWith(' ');
    final replacement = shouldAppendSpace
        ? '${suggestion.insertText} '
        : suggestion.insertText;
    final updatedText = '$before$replacement$after';
    final cursorOffset = before.length + replacement.length;
    return TextEditingValue(
      text: updatedText,
      selection: TextSelection.collapsed(offset: cursorOffset),
    );
  }

  _AiComposerToken? _activeToken(TextEditingValue value) {
    final cursor = value.selection.baseOffset;
    if (cursor < 0 || cursor > value.text.length) {
      return null;
    }

    final leftText = value.text.substring(0, cursor);
    final tokenStart = leftText.lastIndexOf(RegExp(r'[\s\n\t]')) + 1;
    final tokenText = leftText.substring(tokenStart);
    if (tokenText.length < 2) {
      return null;
    }

    if (tokenText.startsWith('/')) {
      return _AiComposerToken(
        start: tokenStart,
        end: cursor,
        query: tokenText.substring(1),
        type: AiComposerSuggestionType.slashCommand,
      );
    }
    if (tokenText.startsWith('@')) {
      return _AiComposerToken(
        start: tokenStart,
        end: cursor,
        query: tokenText.substring(1),
        type: AiComposerSuggestionType.fileReference,
      );
    }
    return null;
  }
}

class _AiComposerToken {
  const _AiComposerToken({
    required this.start,
    required this.end,
    required this.query,
    required this.type,
  });

  final int start;
  final int end;
  final String query;
  final AiComposerSuggestionType type;
}
