import 'dart:async';

import 'package:drift/drift.dart' as drift;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/database/database.dart';
import '../../data/repositories/group_repository.dart';
import '../../data/repositories/host_repository.dart';
import '../../domain/services/ssh_service.dart';

/// Screen displaying list of saved hosts.
class HostsScreen extends ConsumerStatefulWidget {
  /// Creates a new [HostsScreen].
  const HostsScreen({super.key});

  @override
  ConsumerState<HostsScreen> createState() => _HostsScreenState();
}

class _HostsScreenState extends ConsumerState<HostsScreen> {
  String _searchQuery = '';
  int? _selectedGroupId;
  String? _selectedGroupName;

  @override
  Widget build(BuildContext context) {
    final hostsAsync = ref.watch(allHostsProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Hosts'),
        actions: [
          IconButton(
            icon: Icon(
              _searchQuery.isEmpty ? Icons.search : Icons.search_rounded,
            ),
            onPressed: _showSearchDialog,
            tooltip: 'Search',
            color: _searchQuery.isEmpty ? null : theme.colorScheme.primary,
          ),
          IconButton(
            icon: Icon(
              _selectedGroupId == null ? Icons.folder : Icons.folder_open,
            ),
            onPressed: _showGroupsDialog,
            tooltip: 'Groups',
            color: _selectedGroupId == null ? null : theme.colorScheme.primary,
          ),
        ],
      ),
      body: hostsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.error_outline,
                size: 48,
                color: theme.colorScheme.error,
              ),
              const SizedBox(height: 16),
              Text('Error loading hosts: $error'),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => ref.invalidate(allHostsProvider),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
        data: _buildHostList,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/hosts/add'),
        icon: const Icon(Icons.add),
        label: const Text('Add Host'),
      ),
    );
  }

  Widget _buildHostList(List<Host> hosts) {
    var filteredHosts = hosts;
    final hasSearch = _searchQuery.isNotEmpty;
    final hasGroupFilter = _selectedGroupId != null;

    // Apply search filter
    if (hasSearch) {
      final query = _searchQuery.toLowerCase();
      filteredHosts = filteredHosts
          .where(
            (h) =>
                h.label.toLowerCase().contains(query) ||
                h.hostname.toLowerCase().contains(query) ||
                h.username.toLowerCase().contains(query),
          )
          .toList();
    }

    // Apply group filter
    if (hasGroupFilter) {
      filteredHosts = filteredHosts
          .where((h) => h.groupId == _selectedGroupId)
          .toList();
    }

    final content = filteredHosts.isEmpty
        ? _buildEmptyState(hasSearch: hasSearch, hasGroupFilter: hasGroupFilter)
        : ListView.builder(
            padding: const EdgeInsets.only(bottom: 88),
            itemCount: filteredHosts.length,
            itemBuilder: (context, index) {
              final host = filteredHosts[index];
              return _HostListTile(
                host: host,
                onTap: () => _connectToHost(host),
                onNewConnection: () => unawaited(_openNewConnection(host)),
                onEdit: () => context.push('/hosts/edit/${host.id}'),
                onDelete: () => _deleteHost(host),
              );
            },
          );

    if (!hasSearch && !hasGroupFilter) {
      return content;
    }

    return Column(
      children: [
        _buildActiveFilters(),
        Expanded(child: content),
      ],
    );
  }

  Widget _buildEmptyState({
    required bool hasSearch,
    required bool hasGroupFilter,
  }) => Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          hasSearch || hasGroupFilter
              ? Icons.filter_alt_off
              : Icons.dns_outlined,
          size: 64,
          color: Theme.of(context).colorScheme.outline,
        ),
        const SizedBox(height: 16),
        Text(
          hasSearch && hasGroupFilter
              ? 'No hosts match your search in ${_selectedGroupName ?? 'the selected group'}'
              : hasSearch
              ? 'No hosts match your search'
              : hasGroupFilter
              ? 'No hosts in ${_selectedGroupName ?? 'the selected group'}'
              : 'No hosts yet',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Text(
          hasSearch || hasGroupFilter
              ? 'Try clearing one or more filters.'
              : 'Tap + to add your first host',
          style: Theme.of(context).textTheme.bodyMedium,
          textAlign: TextAlign.center,
        ),
      ],
    ),
  );

  Widget _buildActiveFilters() => Container(
    width: double.infinity,
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
    child: Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (_searchQuery.isNotEmpty)
          InputChip(
            label: Text('Search: $_searchQuery'),
            onDeleted: () => setState(() => _searchQuery = ''),
          ),
        if (_selectedGroupId != null)
          InputChip(
            label: Text('Group: ${_selectedGroupName ?? 'Selected'}'),
            onDeleted: () {
              setState(() {
                _selectedGroupId = null;
                _selectedGroupName = null;
              });
            },
          ),
        TextButton.icon(
          onPressed: () {
            setState(() {
              _searchQuery = '';
              _selectedGroupId = null;
              _selectedGroupName = null;
            });
          },
          icon: const Icon(Icons.clear_all),
          label: const Text('Clear all'),
        ),
      ],
    ),
  );

  Future<void> _openNewConnection(Host host) async {
    final result = await ref
        .read(activeSessionsProvider.notifier)
        .connect(host.id, forceNew: true);
    if (!mounted) return;
    if (!result.success || result.connectionId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.error ?? 'Connection failed')),
      );
      return;
    }
    unawaited(
      context.push('/terminal/${host.id}?connectionId=${result.connectionId}'),
    );
  }

  Future<void> _connectToHost(Host host) async {
    final sessionsNotifier = ref.read(activeSessionsProvider.notifier);
    final connectionIds = sessionsNotifier.getConnectionsForHost(host.id);

    if (connectionIds.isEmpty) {
      final result = await sessionsNotifier.connect(host.id, forceNew: true);
      if (!mounted) return;
      if (!result.success || result.connectionId == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result.error ?? 'Connection failed')),
        );
        return;
      }
      unawaited(
        context.push(
          '/terminal/${host.id}?connectionId=${result.connectionId}',
        ),
      );
      return;
    }

    if (connectionIds.length == 1) {
      unawaited(
        context.push(
          '/terminal/${host.id}?connectionId=${connectionIds.first}',
        ),
      );
      return;
    }

    final selected = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(host.label),
              subtitle: Text('${connectionIds.length} active connections'),
            ),
            for (final connectionId in connectionIds.reversed)
              ListTile(
                leading: const Icon(Icons.terminal),
                title: Text('Connection #$connectionId'),
                subtitle: Text(
                  '${host.username}@${host.hostname}:${host.port}',
                ),
                onTap: () => Navigator.pop(context, '$connectionId'),
              ),
            ListTile(
              leading: const Icon(Icons.add),
              title: const Text('New connection'),
              onTap: () => Navigator.pop(context, 'new'),
            ),
          ],
        ),
      ),
    );

    if (!mounted || selected == null) {
      return;
    }
    if (selected == 'new') {
      final result = await sessionsNotifier.connect(host.id, forceNew: true);
      if (!mounted) return;
      if (!result.success || result.connectionId == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result.error ?? 'Connection failed')),
        );
        return;
      }
      unawaited(
        context.push(
          '/terminal/${host.id}?connectionId=${result.connectionId}',
        ),
      );
      return;
    }

    final connectionId = int.tryParse(selected);
    if (connectionId != null) {
      unawaited(
        context.push('/terminal/${host.id}?connectionId=$connectionId'),
      );
    }
  }

  Future<void> _deleteHost(Host host) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Host'),
        content: Text('Are you sure you want to delete "${host.label}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed ?? false) {
      await ref.read(hostRepositoryProvider).delete(host.id);
      ref.invalidate(allHostsProvider);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Deleted "${host.label}"')));
      }
    }
  }

  void _showSearchDialog() {
    final controller = TextEditingController(text: _searchQuery);
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Search Hosts'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Search by name, hostname, or username',
            prefixIcon: Icon(Icons.search),
          ),
          textInputAction: TextInputAction.search,
          onSubmitted: (_) {
            setState(() => _searchQuery = controller.text.trim());
            Navigator.pop(context);
          },
        ),
        actions: [
          if (_searchQuery.isNotEmpty)
            TextButton(
              onPressed: () {
                controller.clear();
                setState(() => _searchQuery = '');
                Navigator.pop(context);
              },
              child: const Text('Clear'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              setState(() => _searchQuery = controller.text.trim());
              Navigator.pop(context);
            },
            child: const Text('Apply'),
          ),
        ],
      ),
    );
  }

  Future<void> _showGroupsDialog() async {
    final selection =
        await showModalBottomSheet<({int? groupId, String? groupName})>(
          context: context,
          showDragHandle: true,
          builder: (context) {
            final theme = Theme.of(context);
            final groupRepo = ref.read(groupRepositoryProvider);

            return SafeArea(
              child: StreamBuilder<List<Group>>(
                stream: groupRepo.watchAll(),
                builder: (context, snapshot) {
                  final groups = snapshot.data ?? const <Group>[];
                  return SizedBox(
                    height: 420,
                    child: Column(
                      children: [
                        ListTile(
                          title: const Text('Groups'),
                          subtitle: Text(
                            _selectedGroupId == null
                                ? 'Showing all hosts'
                                : 'Filtered by selected group',
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.create_new_folder_outlined),
                            tooltip: 'Create group',
                            onPressed: () {
                              Navigator.pop(context);
                              unawaited(_showCreateGroupDialog());
                            },
                          ),
                        ),
                        Expanded(
                          child: ListView(
                            children: [
                              ListTile(
                                leading: const Icon(Icons.list),
                                title: const Text('All hosts'),
                                selected: _selectedGroupId == null,
                                onTap: () => Navigator.pop(context, (
                                  groupId: null,
                                  groupName: null,
                                )),
                              ),
                              for (final group in groups)
                                ListTile(
                                  leading: const Icon(Icons.folder_outlined),
                                  title: Text(group.name),
                                  selected: _selectedGroupId == group.id,
                                  trailing: _selectedGroupId == group.id
                                      ? Icon(
                                          Icons.check,
                                          color: theme.colorScheme.primary,
                                        )
                                      : null,
                                  onTap: () => Navigator.pop(context, (
                                    groupId: group.id,
                                    groupName: group.name,
                                  )),
                                ),
                              if (groups.isEmpty)
                                const Padding(
                                  padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
                                  child: Text(
                                    'No groups yet. Create one to organize hosts.',
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            );
          },
        );

    if (!mounted || selection == null) {
      return;
    }

    setState(() {
      _selectedGroupId = selection.groupId;
      _selectedGroupName = selection.groupName;
    });
  }

  Future<void> _showCreateGroupDialog() async {
    final controller = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final created = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New Group'),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Group name',
              hintText: 'Production',
            ),
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Please enter a group name';
              }
              return null;
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.pop(context, true);
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );

    final name = controller.text.trim();
    controller.dispose();
    if (created != true || name.isEmpty) {
      return;
    }

    final id = await ref
        .read(groupRepositoryProvider)
        .insert(GroupsCompanion.insert(name: name));
    if (!mounted) {
      return;
    }
    setState(() => _selectedGroupId = id);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Created group "$name"')));
  }
}

class _HostListTile extends ConsumerWidget {
  const _HostListTile({
    required this.host,
    required this.onTap,
    required this.onNewConnection,
    required this.onEdit,
    required this.onDelete,
  });

  final Host host;
  final VoidCallback onTap;
  final VoidCallback onNewConnection;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final connectionStates = ref.watch(activeSessionsProvider);
    final sessionsNotifier = ref.read(activeSessionsProvider.notifier);
    final connectionIds = sessionsNotifier.getConnectionsForHost(host.id);
    final states = connectionIds
        .map((connectionId) => connectionStates[connectionId])
        .whereType<SshConnectionState>()
        .toList(growable: false);
    final isConnected = states.any(
      (state) => state == SshConnectionState.connected,
    );
    final isConnecting = states.any(
      (state) =>
          state == SshConnectionState.connecting ||
          state == SshConnectionState.authenticating,
    );

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: isConnected
            ? Colors.green.withAlpha(50)
            : theme.colorScheme.surfaceContainerHighest,
        child: Icon(
          isConnected ? Icons.link : Icons.dns,
          color: isConnected ? Colors.green : theme.colorScheme.primary,
        ),
      ),
      title: Text(host.label),
      subtitle: Text(
        connectionIds.isEmpty
            ? '${host.username}@${host.hostname}:${host.port}'
            : '${host.username}@${host.hostname}:${host.port}  •  '
                  '${connectionIds.length} connection(s)',
        style: theme.textTheme.bodySmall,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (host.isFavorite)
            const Icon(Icons.star, color: Colors.amber, size: 20),
          if (isConnecting)
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'New connection',
            onPressed: onNewConnection,
          ),
          PopupMenuButton<String>(
            onSelected: (action) {
              switch (action) {
                case 'edit':
                  onEdit();
                case 'delete':
                  onDelete();
                case 'duplicate':
                  _duplicateHost(context, ref);
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'edit', child: Text('Edit')),
              const PopupMenuItem(value: 'duplicate', child: Text('Duplicate')),
              PopupMenuItem(
                value: 'delete',
                child: Text(
                  'Delete',
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ),
            ],
          ),
        ],
      ),
      onTap: onTap,
    );
  }

  Future<void> _duplicateHost(BuildContext context, WidgetRef ref) async {
    final repo = ref.read(hostRepositoryProvider);
    await repo.insert(
      HostsCompanion.insert(
        label: '${host.label} (copy)',
        hostname: host.hostname,
        port: drift.Value(host.port),
        username: host.username,
        password: drift.Value(host.password),
        keyId: drift.Value(host.keyId),
        groupId: drift.Value(host.groupId),
        jumpHostId: drift.Value(host.jumpHostId),
        color: drift.Value(host.color),
      ),
    );
    ref.invalidate(allHostsProvider);
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Host duplicated')));
    }
  }
}

/// Provider for all hosts - uses stream for auto-refresh on changes.
final allHostsProvider = StreamProvider<List<Host>>((ref) {
  final repo = ref.watch(hostRepositoryProvider);
  return repo.watchAll();
});
