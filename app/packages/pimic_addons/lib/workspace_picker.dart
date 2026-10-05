import 'package:flutter/material.dart';
import 'workspaces.dart';

class WorkspacePicker extends StatefulWidget {
  const WorkspacePicker({
    super.key,
    required this.targets,
    required this.memory,
    required this.onSelect,
    this.current,
    this.loading = false,
    this.relayConnected = true,
  });
  final List<WorkspaceTarget> targets;
  final WorkspaceMemory memory;
  final ValueChanged<WorkspaceTarget> onSelect;
  final WorkspaceKey? current;
  final bool loading, relayConnected;
  @override
  State<WorkspacePicker> createState() => _WorkspacePickerState();
}

class _WorkspacePickerState extends State<WorkspacePicker> {
  String _query = '';
  bool _favoritesOnly = false;
  @override
  Widget build(BuildContext context) {
    final q = _query.trim().toLowerCase();
    final targets = widget.targets
        .where(
          (t) =>
              (!_favoritesOnly || widget.memory.isFavorite(t.key)) &&
              [
                t.device,
                t.title,
                t.path,
              ].any((s) => s.toLowerCase().contains(q)),
        )
        .toList();
    targets.sort((a, b) {
      final device = a.device.toLowerCase().compareTo(b.device.toLowerCase());
      if (device != 0) return device;
      final identity = a.key.peer.compareTo(b.key.peer);
      if (identity != 0) return identity;
      final project = a.path.compareTo(b.path);
      return project != 0 ? project : a.title.compareTo(b.title);
    });
    final rows = <Widget>[];
    String? lastPeer, lastProject;
    for (final target in targets) {
      if (target.key.peer != lastPeer) {
        lastPeer = target.key.peer;
        lastProject = null;
        rows.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              target.device,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
        );
      }
      if (target.path != lastProject) {
        lastProject = target.path;
        rows.add(
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Text(
              target.path.isEmpty ? '项目路径未提供' : target.path,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        );
      }
      final status = !widget.relayConnected
          ? '连接状态未知'
          : target.working
          ? '运行中'
          : target.online
          ? '在线'
          : '离线';
      rows.add(
        ListTile(
          key: ValueKey('workspace-${target.key.id}'),
          selected: target.key == widget.current,
          leading: Icon(
            target.key == widget.current
                ? Icons.check_circle_outline
                : Icons.chat_bubble_outline,
          ),
          title: Text(target.title),
          subtitle: Text(status),
          trailing: IconButton(
            tooltip: widget.memory.isFavorite(target.key) ? '取消收藏' : '收藏',
            icon: Icon(
              widget.memory.isFavorite(target.key)
                  ? Icons.star
                  : Icons.star_border,
            ),
            onPressed: () =>
                setState(() => widget.memory.toggleFavorite(target.key)),
          ),
          onTap: () => widget.onSelect(target),
        ),
      );
    }
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '切换机器 / 项目 / 会话',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  tooltip: '关闭目标列表',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Text('离线会话可查看缓存，发送需连接。切换不会停止其他 Pi 的任务。'),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              key: const Key('workspace-search'),
              decoration: const InputDecoration(
                labelText: '搜索机器、项目或会话',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
              onChanged: (value) => setState(() => _query = value),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: FilterChip(
                key: const Key('workspace-favorites'),
                label: const Text('仅收藏'),
                selected: _favoritesOnly,
                onSelected: (value) => setState(() => _favoritesOnly = value),
              ),
            ),
          ),
          Expanded(
            child: widget.loading
                ? const Center(child: CircularProgressIndicator())
                : rows.isEmpty
                ? const Center(child: Text('没有匹配的已配对会话；先在首页配对目标 Pi。'))
                : ListView.builder(
                    itemCount: rows.length,
                    itemBuilder: (_, i) => rows[i],
                  ),
          ),
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('草稿、滚动位置和收藏仅保留在本次运行中，最多缓存 32 个目标；重启会清除。'),
          ),
        ],
      ),
    );
  }
}
