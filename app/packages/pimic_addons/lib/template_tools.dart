import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'optimization.dart';
import 'prompt_template.dart';

/// Template editing is local and never enables a provider or starts a request.
class TemplateTools extends StatelessWidget {
  const TemplateTools({
    super.key,
    required this.controller,
    this.enabled = true,
  });
  final TextEditingController controller;
  final bool enabled;

  Future<void> _import(BuildContext context) async {
    final template = await showDialog<PromptTemplate>(
      context: context,
      builder: (_) => _ImportDialog(initialText: controller.text),
    );
    if (!context.mounted || template == null) return;
    controller.text = template.exportJson();
  }

  Future<void> _copy(BuildContext context, String json) async {
    try {
      await Clipboard.setData(ClipboardData(text: json));
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('模板已复制；可在 Prompt Optimizer 导入。')),
      );
    } on Object {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('复制失败，请重试。')));
    }
  }

  @override
  Widget build(BuildContext context) => ExpansionTile(
    key: const Key('prompt-template-tools'),
    tilePadding: EdgeInsets.zero,
    title: const Text('Prompt Optimizer 模板（可选）'),
    subtitle: const Text('仅用于“整理提示词”；“仅纠错”使用内置规则。'),
    children: [
      const Text(
        '导入单个 userOptimize 模板 JSON，或复制内置模板到开源 Prompt Optimizer 编辑。'
        '支持纯文本、system/user 消息及 originalPrompt / helpers.toJson；高级循环和其他变量暂不支持。'
        '导入后需保存设置；不会自动启用模型或发送请求。',
      ),
      const SizedBox(height: 8),
      ValueListenableBuilder<TextEditingValue>(
        valueListenable: controller,
        builder: (context, value, _) {
          String? name;
          try {
            if (value.text.isNotEmpty) {
              name = PromptTemplate.parse(value.text).name;
            }
          } on FormatException {
            name = '模板格式有误，请重新导入或恢复内置模板。';
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name == null ? '当前：PiMic 内置整理规则' : '当前：$name'),
              Wrap(
                spacing: 8,
                children: [
                  TextButton.icon(
                    key: const Key('import-prompt-template'),
                    onPressed: enabled ? () => _import(context) : null,
                    icon: const Icon(Icons.file_upload_outlined),
                    label: const Text('导入 JSON'),
                  ),
                  TextButton.icon(
                    key: const Key('export-prompt-template'),
                    onPressed: enabled
                        ? () => _copy(
                            context,
                            value.text.isEmpty
                                ? builtinRewriteTemplate.exportJson()
                                : value.text,
                          )
                        : null,
                    icon: const Icon(Icons.copy_outlined),
                    label: Text(value.text.isEmpty ? '复制内置模板' : '复制当前模板'),
                  ),
                  if (value.text.isNotEmpty)
                    TextButton(
                      key: const Key('reset-prompt-template'),
                      onPressed: enabled ? controller.clear : null,
                      child: const Text('恢复内置模板'),
                    ),
                ],
              ),
            ],
          );
        },
      ),
    ],
  );
}

class _ImportDialog extends StatefulWidget {
  const _ImportDialog({required this.initialText});
  final String initialText;
  @override
  State<_ImportDialog> createState() => _ImportDialogState();
}

class _ImportDialogState extends State<_ImportDialog> {
  late final _text = TextEditingController(text: widget.initialText);
  String? _error;
  bool _pasting = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _paste() async {
    setState(() => _pasting = true);
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      if (!mounted) return;
      final text = data?.text ?? '';
      if (text.length > PromptTemplate.maxJsonCharacters) {
        setState(
          () => _error = 'Template JSON is limited to 16384 characters.',
        );
      } else {
        _text.text = text;
        setState(() => _error = null);
      }
    } on Object {
      if (mounted) setState(() => _error = '无法读取剪贴板，请手动粘贴。');
    } finally {
      if (mounted) setState(() => _pasting = false);
    }
  }

  void _submit() {
    try {
      Navigator.of(context).pop(PromptTemplate.parse(_text.text));
    } on FormatException catch (error) {
      setState(() => _error = error.message);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('导入整理模板'),
    content: SizedBox(
      width: 480,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              key: const Key('prompt-template-json'),
              controller: _text,
              minLines: 5,
              maxLines: 8,
              maxLength: PromptTemplate.maxJsonCharacters,
              autocorrect: false,
              enableSuggestions: false,
              decoration: const InputDecoration(labelText: '单模板 JSON'),
            ),
            if (_error != null)
              Text(
                _error!,
                key: const Key('prompt-template-error'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(onPressed: _pasting ? null : _paste, child: const Text('粘贴')),
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('取消'),
      ),
      FilledButton(
        key: const Key('confirm-prompt-template'),
        onPressed: _submit,
        child: const Text('导入'),
      ),
    ],
  );
}
