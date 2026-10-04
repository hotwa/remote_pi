import 'dart:convert';

/// Independently implemented compatibility with Prompt Optimizer's exported
/// Template JSON shape. No upstream engine or template text is bundled.
class PromptTemplate {
  const PromptTemplate({
    required this.id,
    required this.name,
    required this.content,
  });

  static const maxJsonCharacters = 16384;
  final String id, name;
  final Object content;

  static final _jsonHelper = RegExp(
    r'\{\{#\s*helpers\.toJson\s*\}\}\s*\{\{\{\s*originalPrompt\s*\}\}\}\s*\{\{/\s*helpers\.toJson\s*\}\}',
  );
  static final _variable = RegExp(
    r'\{\{\{\s*originalPrompt\s*\}\}\}|\{\{\s*originalPrompt\s*\}\}',
  );

  factory PromptTemplate.parse(String source) {
    if (source.length > maxJsonCharacters) {
      throw const FormatException(
        'Template JSON is limited to 16384 characters.',
      );
    }
    try {
      final json = jsonDecode(source);
      if (json is! Map<String, dynamic> ||
          json['metadata'] is! Map<String, dynamic> ||
          (json['metadata'] as Map)['templateType'] != 'userOptimize') {
        throw const FormatException(
          'Import one userOptimize template, not a full backup or system template.',
        );
      }
      final id = _label(json['id'], 128);
      final name = _label(json['name'], 80);
      final content = json['content'];
      if (content is String) {
        _validateText(content, renderVariables: false);
        return PromptTemplate(id: id, name: name, content: content);
      }
      if (content is! List || content.isEmpty || content.length > 4) {
        throw const FormatException(
          'Template must contain text or 1–4 messages.',
        );
      }
      final messages = <Map<String, String>>[];
      for (final item in content) {
        if (item is! Map ||
            !['system', 'user'].contains(item['role']) ||
            item.keys.any((key) => key != 'role' && key != 'content')) {
          throw const FormatException(
            'Only plain system/user messages are supported.',
          );
        }
        final text = item['content'];
        if (text is! String) {
          throw const FormatException('Message text is required.');
        }
        _validateText(text, renderVariables: true);
        messages.add({'role': item['role'] as String, 'content': text});
      }
      return PromptTemplate(id: id, name: name, content: messages);
    } on FormatException catch (error) {
      // JSON parser exceptions can include the user's private template text.
      if (error.source != null) {
        throw const FormatException('Invalid template JSON.');
      }
      rethrow;
    } on Object {
      throw const FormatException('Invalid template JSON.');
    }
  }

  static String _label(Object? value, int limit) {
    if (value is! String ||
        value.trim().isEmpty ||
        value.length > limit ||
        RegExp(r'[\x00-\x1f\x7f]').hasMatch(value)) {
      throw const FormatException('Template ID/name is empty or too long.');
    }
    return value;
  }

  static void _validateText(String text, {required bool renderVariables}) {
    if (text.trim().isEmpty ||
        text.length > 8192 ||
        RegExp(r'[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]').hasMatch(text)) {
      throw const FormatException(
        'Template text must contain 1–8192 characters.',
      );
    }
    if (!renderVariables) return;
    final remaining = text
        .replaceAll(_jsonHelper, '')
        .replaceAll(_variable, '');
    if (remaining.contains('{{') || remaining.contains('}}')) {
      throw const FormatException(
        'Supported variables: originalPrompt and helpers.toJson only. Advanced loops/variables need a simpler template.',
      );
    }
  }

  /// Replace only tokens from the template, never reprocess inserted source.
  /// This preserves braces and helper-like text spoken/typed by the user.
  List<Map<String, String>> render(String original) {
    if (content is String) {
      return [
        {'role': 'system', 'content': content as String},
      ];
    }
    final pattern = RegExp('${_jsonHelper.pattern}|${_variable.pattern}');
    return (content as List<Map<String, String>>)
        .map(
          (message) => {
            'role': message['role']!,
            'content': message['content']!.replaceAllMapped(pattern, (match) {
              final token = match.group(0)!;
              if (token.startsWith('{{#')) return jsonEncode(original);
              if (token.startsWith('{{{')) return original;
              return _escapeHtml(original);
            }),
          },
        )
        .toList(growable: false);
  }

  static String _escapeHtml(String value) {
    const replacements = {
      '&': '&amp;',
      '<': '&lt;',
      '>': '&gt;',
      '"': '&quot;',
      "'": '&#39;',
      '/': '&#x2F;',
      '`': '&#x60;',
      '=': '&#x3D;',
    };
    return value.replaceAllMapped(
      RegExp(r'''[&<>"'/`=]'''),
      (match) => replacements[match[0]]!,
    );
  }

  String exportJson() => jsonEncode({
    'id': id,
    'name': name,
    'content': content,
    'metadata': {
      'version': '1.0.0',
      'lastModified': 0,
      'author': 'PiMic',
      'description': 'User-selected local drafting template',
      'templateType': 'userOptimize',
      'language': 'zh',
    },
    'isBuiltin': false,
  });
}
