import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/services/local_terminal_ai_managed_model_service.dart';
import '../../domain/services/local_terminal_ai_platform_service.dart';
import '../../domain/services/local_terminal_ai_service.dart';
import '../../domain/services/local_terminal_ai_settings_service.dart';

/// Bottom sheet for the experimental on-device terminal AI assistant.
class TerminalAiAssistantSheet extends ConsumerStatefulWidget {
  /// Creates a new [TerminalAiAssistantSheet].
  const TerminalAiAssistantSheet({
    required this.hostLabel,
    required this.onInsertSuggestedCommand,
    required this.onInsertCompletion,
    required this.onOpenSettings,
    this.currentTerminalLine,
    this.workingDirectoryPath,
    super.key,
  });

  /// The currently connected host label.
  final String hostLabel;

  /// Current command line snapshot from the terminal.
  final String? currentTerminalLine;

  /// Current working directory for the terminal session.
  final String? workingDirectoryPath;

  /// Inserts a full AI-generated command into the terminal.
  final Future<void> Function(String command) onInsertSuggestedCommand;

  /// Inserts an AI-generated completion suffix into the terminal.
  final Future<void> Function(String suffix) onInsertCompletion;

  /// Opens the settings screen so the user can configure the assistant.
  final VoidCallback onOpenSettings;

  @override
  ConsumerState<TerminalAiAssistantSheet> createState() =>
      _TerminalAiAssistantSheetState();
}

class _TerminalAiAssistantSheetState
    extends ConsumerState<TerminalAiAssistantSheet> {
  final _taskController = TextEditingController();
  List<LocalTerminalAiSuggestion> _suggestions =
      const <LocalTerminalAiSuggestion>[];
  LocalTerminalAiCompletion? _completion;
  bool _isGeneratingSuggestions = false;
  bool _isGeneratingCompletion = false;
  String? _errorMessage;

  @override
  void dispose() {
    _taskController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(localTerminalAiSettingsProvider);
    final managedModel = ref.watch(localTerminalAiManagedModelProvider);
    final runtimeInfo = ref.watch(localTerminalAiRuntimeInfoProvider);
    final theme = Theme.of(context);
    final currentLine = widget.currentTerminalLine?.trimRight();
    final canGenerate = _canUseAssistant(settings, runtimeInfo, managedModel);

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Text(
                    'On-device AI assistant',
                    style: theme.textTheme.titleLarge,
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                    tooltip: 'Close',
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Generate command suggestions locally and keep execution explicit.',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              _AssistantStatusCard(
                settings: settings,
                managedModel: managedModel,
                runtimeInfo: runtimeInfo,
                onOpenSettings: () {
                  Navigator.pop(context);
                  widget.onOpenSettings();
                },
              ),
              if (_errorMessage case final errorMessage?) ...[
                const SizedBox(height: 12),
                _ErrorBanner(message: errorMessage),
              ],
              const SizedBox(height: 20),
              Text('Describe a task', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              TextField(
                controller: _taskController,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: 'Example: tail the app logs and filter for errors',
                ),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: canGenerate && !_isGeneratingSuggestions
                    ? _generateSuggestions
                    : null,
                icon: _isGeneratingSuggestions
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.auto_awesome_outlined),
                label: const Text('Suggest commands'),
              ),
              if (_suggestions.isNotEmpty) ...[
                const SizedBox(height: 16),
                for (final suggestion in _suggestions)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _SuggestionCard(
                      suggestion: suggestion,
                      onInsert: () async {
                        await widget.onInsertSuggestedCommand(
                          suggestion.command,
                        );
                        if (!context.mounted) {
                          return;
                        }
                        Navigator.of(context).pop();
                      },
                      onCopy: () => _copyToClipboard(suggestion.command),
                    ),
                  ),
              ],
              const SizedBox(height: 8),
              Divider(color: theme.colorScheme.outlineVariant),
              const SizedBox(height: 8),
              Text(
                'Complete the current command',
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              if (currentLine == null || currentLine.trim().isEmpty)
                Text(
                  'Type part of a command in the terminal to ask for a completion.',
                  style: theme.textTheme.bodyMedium,
                )
              else ...[
                _CodePreview(text: currentLine),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: canGenerate && !_isGeneratingCompletion
                      ? _generateCompletion
                      : null,
                  icon: _isGeneratingCompletion
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.bolt_outlined),
                  label: const Text('Suggest completion'),
                ),
              ],
              if (_completion case final completion?) ...[
                const SizedBox(height: 16),
                Text('Completion preview', style: theme.textTheme.titleSmall),
                const SizedBox(height: 8),
                _CodePreview(text: completion.preview),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      onPressed: () async {
                        await widget.onInsertCompletion(completion.suffix);
                        if (!context.mounted) {
                          return;
                        }
                        Navigator.of(context).pop();
                      },
                      icon: const Icon(Icons.input_outlined),
                      label: const Text('Insert completion'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _copyToClipboard(completion.suffix),
                      icon: const Icon(Icons.copy_outlined),
                      label: const Text('Copy suffix'),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _generateSuggestions() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _errorMessage = null;
      _completion = null;
      _isGeneratingSuggestions = true;
    });

    final settings = ref.read(localTerminalAiSettingsProvider);
    try {
      final suggestions = await ref
          .read(localTerminalAiServiceProvider)
          .suggestCommands(
            settings: settings,
            taskDescription: _taskController.text,
            hostLabel: widget.hostLabel,
            workingDirectoryPath: widget.workingDirectoryPath,
            currentTerminalLine: widget.currentTerminalLine,
          );
      if (!mounted) {
        return;
      }
      setState(() {
        _suggestions = suggestions;
      });
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _suggestions = const <LocalTerminalAiSuggestion>[];
        _errorMessage = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() => _isGeneratingSuggestions = false);
      }
    }
  }

  Future<void> _generateCompletion() async {
    final currentLine = widget.currentTerminalLine?.trimRight();
    if (currentLine == null || currentLine.trim().isEmpty) {
      return;
    }

    setState(() {
      _errorMessage = null;
      _isGeneratingCompletion = true;
    });

    final settings = ref.read(localTerminalAiSettingsProvider);
    try {
      final completion = await ref
          .read(localTerminalAiServiceProvider)
          .completeCurrentCommand(
            settings: settings,
            currentTerminalLine: currentLine,
            hostLabel: widget.hostLabel,
            workingDirectoryPath: widget.workingDirectoryPath,
          );
      if (!mounted) {
        return;
      }
      setState(() {
        _completion = completion;
      });
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _completion = null;
        _errorMessage = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() => _isGeneratingCompletion = false);
      }
    }
  }

  Future<void> _copyToClipboard(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Copied to clipboard')));
  }
}

bool _canUseAssistant(
  LocalTerminalAiSettings settings,
  AsyncValue<LocalTerminalAiRuntimeInfo> runtimeInfo,
  LocalTerminalAiManagedModelState managedModel,
) {
  if (!settings.enabled) {
    return false;
  }
  final nativeReady = runtimeInfo.asData?.value.canUseNativeRuntime ?? false;
  if (nativeReady) {
    return true;
  }
  return managedModel.isReady;
}

class _AssistantStatusCard extends StatelessWidget {
  const _AssistantStatusCard({
    required this.settings,
    required this.managedModel,
    required this.runtimeInfo,
    required this.onOpenSettings,
  });

  final LocalTerminalAiSettings settings;
  final LocalTerminalAiManagedModelState managedModel;
  final AsyncValue<LocalTerminalAiRuntimeInfo> runtimeInfo;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final managedSpec = localTerminalAiManagedGemma4Spec();
    final isConfigured = _canUseAssistant(settings, runtimeInfo, managedModel);
    final subtitle = runtimeInfo.when(
      data: (info) {
        if (!settings.enabled) {
          return managedSpec == null
              ? 'Enable the assistant in Settings to start using it.'
              : 'Enable the assistant in Settings to start downloading ${managedSpec.displayName}.';
        }
        if (info.canUseNativeRuntime) {
          return info.modelName == null
              ? 'Using ${info.providerLabel} on this device.'
              : 'Using ${info.providerLabel} (${info.modelName}) on this device.';
        }
        if (managedSpec != null) {
          return switch (managedModel.status) {
            LocalTerminalAiManagedModelStatus.ready =>
              'Using managed ${managedSpec.displayName}.',
            LocalTerminalAiManagedModelStatus.downloading =>
              'Downloading managed ${managedSpec.displayName} (${managedModel.progress}%).',
            LocalTerminalAiManagedModelStatus.failed =>
              'Managed ${managedSpec.displayName} download failed. Open Settings to retry.',
            LocalTerminalAiManagedModelStatus.idle =>
              'Preparing the managed ${managedSpec.displayName} download...',
          };
        }
        return '${info.statusMessage} Managed Gemma 4 download is not available on this platform.';
      },
      loading: () {
        if (!settings.enabled) {
          return managedSpec == null
              ? 'Enable the assistant in Settings to start using it.'
              : 'Enable the assistant in Settings to start downloading ${managedSpec.displayName}.';
        }
        if (managedSpec != null) {
          return managedModel.isReady
              ? 'Managed ${managedSpec.displayName} is ready while the built-in runtime is still being checked.'
              : 'Checking the built-in runtime and managed ${managedSpec.displayName} download status...';
        }
        return 'Checking whether this device exposes a built-in on-device model...';
      },
      error: (error, _) {
        if (managedSpec != null) {
          return managedModel.isReady
              ? 'Native runtime check failed. Managed ${managedSpec.displayName} remains available as fallback.'
              : 'Native runtime check failed and managed ${managedSpec.displayName} is not ready yet.';
        }
        return error.toString();
      },
    );

    return Card(
      color: isConfigured
          ? theme.colorScheme.primaryContainer.withAlpha(70)
          : theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isConfigured
                      ? Icons.check_circle_outline
                      : Icons.settings_suggest_outlined,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    isConfigured ? 'Assistant ready' : 'Setup required',
                    style: theme.textTheme.titleSmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(subtitle, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: onOpenSettings,
              icon: const Icon(Icons.settings_outlined),
              label: const Text('Open Settings'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SuggestionCard extends StatelessWidget {
  const _SuggestionCard({
    required this.suggestion,
    required this.onInsert,
    required this.onCopy,
  });

  final LocalTerminalAiSuggestion suggestion;
  final VoidCallback onInsert;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _CodePreview(text: suggestion.command),
            const SizedBox(height: 12),
            Text(suggestion.explanation, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: onInsert,
                  icon: const Icon(Icons.input_outlined),
                  label: const Text('Insert'),
                ),
                OutlinedButton.icon(
                  onPressed: onCopy,
                  icon: const Icon(Icons.copy_outlined),
                  label: const Text('Copy'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CodePreview extends StatelessWidget {
  const _CodePreview({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(12),
    ),
    child: SelectableText(
      text,
      style: const TextStyle(fontFamily: 'monospace'),
    ),
  );
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.errorContainer,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Text(
      message,
      style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer),
    ),
  );
}
