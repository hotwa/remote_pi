import 'dart:async';

import 'package:app/pimic_bridge/pimic_host.dart';
import 'package:app/ui/core/themes/themes.dart';
import 'package:flutter/material.dart';
import 'package:pimic_addons/pimic_addons.dart';

/// A single optional composer seam; the existing send handler stays untouched.
class PimicComposerTool extends StatefulWidget {
  const PimicComposerTool({
    super.key,
    required this.host,
    required this.controller,
    required this.disabled,
    required this.target,
    required this.currentTarget,
  });

  final PimicHost? host;
  final TextEditingController controller;
  final bool disabled;
  final String? target;
  final String? Function() currentTarget;

  @override
  State<PimicComposerTool> createState() => _PimicComposerToolState();
}

class _PimicComposerToolState extends State<PimicComposerTool> {
  bool _opening = false;

  @override
  void initState() {
    super.initState();
    unawaited(widget.host?.ensureLoaded());
  }

  Future<void> _open() async {
    final host = widget.host;
    if (host == null || !host.enabled || widget.disabled || _opening) return;
    final revision = host.revision;
    final target = widget.target;
    final original = widget.controller.text;
    bool current() =>
        mounted &&
        !widget.disabled &&
        host.revision == revision &&
        widget.target == target &&
        widget.currentTarget() == target;
    setState(() => _opening = true);
    final result = await showDraftSheet(
      context,
      config: host.config,
      initialText: original,
      targetIsCurrent: current,
    );
    if (!mounted) return;
    setState(() => _opening = false);
    if (result == null) return;
    if (!current() || widget.controller.text != original) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Session or draft changed. The new result was discarded.',
          ),
        ),
      );
      return;
    }
    widget.controller.value = TextEditingValue(
      text: result,
      selection: TextSelection.collapsed(offset: result.length),
    );
  }

  @override
  Widget build(BuildContext context) {
    final host = widget.host;
    if (host == null) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: host,
      builder: (context, _) => !host.enabled
          ? const SizedBox.shrink()
          : IconButton(
              key: const Key('pimic-draft-tools'),
              tooltip: 'Voice & draft tools',
              icon: Icon(
                Icons.mic_external_on_outlined,
                size: 20,
                color: context.colors.accent,
              ),
              onPressed: widget.disabled || _opening ? null : _open,
            ),
    );
  }
}

/// Settings and a standalone test entry work before pairing any Pi.
class PimicSettingsEntry extends StatelessWidget {
  const PimicSettingsEntry({super.key, required this.host});
  final PimicHost? host;

  Future<void> _settings(BuildContext context) async {
    final host = this.host;
    if (host == null) return;
    final config = await Navigator.of(context).push<AddonConfig>(
      MaterialPageRoute(builder: (_) => AddonSettingsPage(store: host.store)),
    );
    if (config != null) host.acceptSaved(config);
  }

  Future<void> _test(BuildContext context) async {
    final host = this.host;
    if (host == null) return;
    await host.ensureLoaded();
    if (!context.mounted) return;
    final revision = host.revision;
    await showDraftSheet(
      context,
      config: host.config,
      targetIsCurrent: () => context.mounted && revision == host.revision,
    );
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      ListTile(
        leading: Icon(Icons.tune, color: context.colors.accent),
        title: Text(
          'PiMic · Voice & draft tools',
          style: TextStyle(color: context.colors.text),
        ),
        subtitle: Text(
          'Optional · both tools off by default',
          style: TextStyle(color: context.colors.muted),
        ),
        onTap: host == null ? null : () => _settings(context),
      ),
      ListTile(
        leading: Icon(Icons.science_outlined, color: context.colors.accent),
        title: Text(
          'Test voice / draft tools',
          style: TextStyle(color: context.colors.text),
        ),
        subtitle: Text(
          'Preview only · does not send to Pi',
          style: TextStyle(color: context.colors.muted),
        ),
        onTap: host == null ? null : () => _test(context),
      ),
    ],
  );
}
