import 'dart:async';

import 'package:app/config/dependencies.dart';
import 'package:app/data/preferences/preferences.dart';
import 'package:app/pimic_bridge/pimic_host.dart';
import 'package:app/routing/adaptive.dart';
import 'package:app/ui/home/states/home_state.dart';
import 'package:app/ui/home/viewmodels/home_viewmodel.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:pimic_addons/pimic_addons.dart';
import 'package:provider/provider.dart';

WorkspaceKey? workspaceKey(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  final i = raw.indexOf(':');
  return WorkspaceKey(
    i < 0 ? raw : raw.substring(0, i),
    i < 0 ? 'main' : raw.substring(i + 1),
  );
}

/// Host seam: upstream still owns selection, routing and typed Pi actions.
class PimicWorkspaceActions extends StatefulWidget {
  const PimicWorkspaceActions({
    super.key,
    required this.host,
    required this.target,
    required this.blockReason,
    required this.onActions,
    required this.actionsReason,
    this.createHome,
  });
  final PimicHost? host;
  final String? target;
  final String? Function() blockReason;
  final VoidCallback? onActions;
  final String actionsReason;
  final HomeViewModel Function()? createHome;
  @override
  State<PimicWorkspaceActions> createState() => _PimicWorkspaceActionsState();
}

class _PimicWorkspaceActionsState extends State<PimicWorkspaceActions> {
  bool _opening = false;
  void _notice(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }

  void _actions() {
    final reason = widget.blockReason();
    if (reason != null) {
      _notice(reason);
      return;
    }
    widget.onActions?.call();
  }

  Future<void> _open() async {
    final host = widget.host;
    final source = workspaceKey(widget.target);
    if (host == null || !host.workspaceEnabled || _opening || source == null) {
      return;
    }
    final blocked = widget.blockReason();
    if (blocked != null) {
      _notice(blocked);
      return;
    }
    if (host.workspaceMemory.read(source).tooLarge) {
      _notice('草稿超过 64000 字符，切换前请复制或缩短。');
      return;
    }
    final prefs = context.read<Preferences>();
    if (workspaceKey(prefs.selectedRoomRaw) != source) {
      _notice('会话正在切换，请稍后重试。');
      return;
    }
    final selection = context.read<SessionSelection>();
    final sourceRaw = prefs.selectedRoomRaw;
    final revision = host.revision;
    final generation = host.workspaceGeneration;
    bool current() =>
        mounted &&
        host.workspaceEnabled &&
        host.revision == revision &&
        host.workspaceGeneration == generation &&
        prefs.selectedRoomRaw == sourceRaw;
    final vm = widget.createHome?.call() ?? injector.get<HomeViewModel>();
    BuildContext? sheetContext;
    final timer = Timer.periodic(const Duration(milliseconds: 250), (_) {
      final sheet = sheetContext;
      if (!current() &&
          sheet != null &&
          sheet.mounted &&
          ModalRoute.of(sheet)?.isCurrent == true) {
        Navigator.of(sheet).pop();
      }
    });
    setState(() => _opening = true);
    try {
      final target = await showModalBottomSheet<WorkspaceTarget>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (sheet) {
          sheetContext = sheet;
          return SizedBox(
            height: MediaQuery.sizeOf(sheet).height * .86,
            child: ListenableBuilder(
              listenable: vm,
              builder: (_, _) {
                final state = vm.state;
                final targets = state is HomeList
                    ? state
                          .items(
                            normalizeEpk: HomeViewModel.normalizeEpkForLookup,
                          )
                          .map(
                            (item) => WorkspaceTarget(
                              key: WorkspaceKey(
                                item.peer.remoteEpk,
                                item.room.roomId,
                              ),
                              device: item.peer.nickname?.isNotEmpty == true
                                  ? item.peer.nickname!
                                  : item.peer.sessionName,
                              title: item.displayName,
                              path: item.room.cwd ?? '',
                              online: vm.isRoomLive(
                                item.peer.remoteEpk,
                                item.room.roomId,
                              ),
                              working: vm.isRoomWorking(
                                item.peer.remoteEpk,
                                item.room.roomId,
                              ),
                            ),
                          )
                          .toList()
                    : const <WorkspaceTarget>[];
                return WorkspacePicker(
                  targets: targets,
                  memory: host.workspaceMemory,
                  current: source,
                  loading: state is HomeLoading,
                  relayConnected: vm.isRelayConnected,
                  onSelect: (target) => Navigator.of(sheet).pop(target),
                );
              },
            ),
          );
        },
      );
      if (target == null || target.key == source || !current()) return;
      final reason = widget.blockReason();
      if (reason != null) {
        _notice(reason);
        return;
      }
      // Exactly the existing Home selection path; no prompt/stop is dispatched.
      await vm.openSession(target.key.peer, roomId: target.key.room);
      if (!mounted || workspaceKey(prefs.selectedRoomRaw) != target.key) return;
      selection.select(
        target.key.peer,
        target.key.room,
        target.title,
        target.device,
        target.online,
      );
      if (!isWideLayout(context)) {
        context.pushReplacement(
          '/chat',
          extra: {
            'title': target.title,
            'device': target.device,
            'online': target.online,
            'target': '${target.key.peer}:${target.key.room}',
          },
        );
      }
    } on Object {
      _notice('无法切换目标，请重试。草稿仍保留在原会话。');
    } finally {
      timer.cancel();
      vm.dispose();
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final host = widget.host;
    if (host == null) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: host,
      builder: (_, _) => !host.workspaceEnabled
          ? const SizedBox.shrink()
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  key: const Key('pimic-workspace-switch'),
                  tooltip: '切换机器 / 项目 / 会话',
                  onPressed: _opening || widget.target == null ? null : _open,
                  icon: const Icon(Icons.swap_horiz, size: 20),
                ),
                IconButton(
                  key: const Key('pimic-pi-actions'),
                  tooltip: widget.onActions == null
                      ? widget.actionsReason
                      : 'Pi 操作：模型、思考、新会话、压缩',
                  onPressed: _opening || widget.onActions == null
                      ? null
                      : _actions,
                  icon: Text(
                    '/',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                      color: _opening || widget.onActions == null
                          ? Theme.of(context).disabledColor
                          : Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class PimicWorkspaceComposer extends StatelessWidget {
  const PimicWorkspaceComposer({
    super.key,
    required this.host,
    required this.target,
    required this.currentTarget,
    required this.builder,
  });
  final PimicHost? host;
  final String? target;
  final String? Function() currentTarget;
  final Widget Function(
    String? key,
    String initialDraft,
    ValueChanged<String>? onChanged,
    bool current,
  )
  builder;
  @override
  Widget build(BuildContext context) {
    final host = this.host;
    if (host == null) return builder(null, '', null, true);
    return ListenableBuilder(
      listenable: host,
      builder: (_, _) {
        final key = workspaceKey(target);
        if (!host.workspaceEnabled || key == null) {
          return builder(null, '', null, true);
        }
        final generation = host.workspaceGeneration;
        return builder(
          key.id,
          host.workspaceMemory.read(key).text,
          (value) {
            if (host.workspaceEnabled &&
                generation == host.workspaceGeneration) {
              host.workspaceMemory.saveText(key, value);
            }
          },
          workspaceKey(currentTarget()) == key,
        );
      },
    );
  }
}

class PimicWorkspaceHistory extends StatelessWidget {
  const PimicWorkspaceHistory({
    super.key,
    required this.host,
    required this.target,
    required this.builder,
  });
  final PimicHost? host;
  final String? target;
  final Widget Function(ScrollController?) builder;
  @override
  Widget build(BuildContext context) {
    final host = this.host;
    if (host == null) return builder(null);
    return ListenableBuilder(
      listenable: host,
      builder: (_, _) {
        final key = workspaceKey(target);
        if (!host.workspaceEnabled || key == null) return builder(null);
        return _WorkspaceScroll(
          key: ValueKey(key),
          host: host,
          target: key,
          builder: builder,
        );
      },
    );
  }
}

class _WorkspaceScroll extends StatefulWidget {
  const _WorkspaceScroll({
    super.key,
    required this.host,
    required this.target,
    required this.builder,
  });
  final PimicHost host;
  final WorkspaceKey target;
  final Widget Function(ScrollController) builder;
  @override
  State<_WorkspaceScroll> createState() => _WorkspaceScrollState();
}

class _WorkspaceScrollState extends State<_WorkspaceScroll> {
  late final _generation = widget.host.workspaceGeneration;
  late final _controller = ScrollController(
    initialScrollOffset: widget.host.workspaceMemory.read(widget.target).scroll,
    keepScrollOffset: false,
  )..addListener(_save);
  void _save() {
    if (widget.host.workspaceEnabled &&
        widget.host.workspaceGeneration == _generation &&
        _controller.hasClients) {
      widget.host.workspaceMemory.saveScroll(widget.target, _controller.offset);
    }
  }

  @override
  void dispose() {
    _save();
    _controller.removeListener(_save);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(_controller);
}
