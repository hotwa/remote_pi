import 'dart:async';

import 'package:flutter/material.dart';

/// An independent entry: the original sync instructions/recheck stay intact.
class LocalIdentityEntry extends StatefulWidget {
  const LocalIdentityEntry({
    super.key,
    required this.activate,
    required this.onReady,
  });

  final Future<void> Function() activate;
  final FutureOr<void> Function() onReady;

  @override
  State<LocalIdentityEntry> createState() => _LocalIdentityEntryState();
}

class _LocalIdentityEntryState extends State<LocalIdentityEntry> {
  bool _busy = false;
  String? _error;

  Future<void> _activate() async {
    if (_busy) return;
    setState(() => _busy = true);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('仅存于此手机 / Local identity'),
        content: const Text(
          '配对身份将安全保存在本机，无需 Google 账户或云同步。'
          '这是此 fork 的独立身份，需要重新配对 Pi。'
          '卸载并删除数据、清除应用数据或更换手机后，需要重新配对。'
          '此选项不会上传或导入原版的身份。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('使用本地身份'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (confirmed != true) {
      setState(() => _busy = false);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.activate();
      if (mounted) await widget.onReady();
    } on Object {
      if (mounted) {
        setState(() {
          _error = '无法启用本地身份，已有数据保持不变。请检查应用存储状态。';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (_error != null)
        Text(_error!, style: const TextStyle(color: Colors.red)),
      OutlinedButton.icon(
        onPressed: _busy ? null : _activate,
        icon: const Icon(Icons.phone_android),
        label: Text(_busy ? '正在保存…' : '仅存于此手机 · 无需 Google 同步'),
      ),
    ],
  );
}

class LocalIdentityStatus extends StatefulWidget {
  const LocalIdentityStatus({super.key, required this.isLocal});
  final Future<bool> Function() isLocal;

  @override
  State<LocalIdentityStatus> createState() => _LocalIdentityStatusState();
}

class _LocalIdentityStatusState extends State<LocalIdentityStatus> {
  late final _status = widget.isLocal();

  @override
  Widget build(BuildContext context) => FutureBuilder<bool>(
    future: _status,
    builder: (context, snapshot) => ListTile(
      leading: const Icon(Icons.key),
      title: const Text('配对身份 / Pairing identity'),
      subtitle: Text(
        snapshot.hasError
            ? '本地身份读取失败，已有数据保持不变'
            : snapshot.data == true
            ? '仅存于此手机 · 重启保留 · 清除数据后需重新配对'
            : snapshot.data == false
            ? '原版 Google 同步模式'
            : '正在读取…',
      ),
    ),
  );
}
