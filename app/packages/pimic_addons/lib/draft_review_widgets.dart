import 'package:flutter/material.dart';

import 'draft_review.dart';

class DraftComparison extends StatelessWidget {
  const DraftComparison({
    super.key,
    required this.title,
    required this.text,
    this.ranges = const [],
  });
  final String title, text;
  final List<ReviewRange> ranges;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final spans = <TextSpan>[];
    var offset = 0;
    for (final range in ranges) {
      if (offset < range.start) {
        spans.add(TextSpan(text: text.substring(offset, range.start)));
      }
      spans.add(
        TextSpan(
          text: text.substring(range.start, range.end),
          style: TextStyle(
            backgroundColor: colors.errorContainer,
            color: colors.onErrorContainer,
            decoration: TextDecoration.underline,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
      offset = range.end;
    }
    if (offset < text.length) spans.add(TextSpan(text: text.substring(offset)));
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            if (ranges.isEmpty)
              SelectableText(text)
            else
              SelectableText.rich(TextSpan(children: spans)),
          ],
        ),
      ),
    );
  }
}

class DraftReviewNotice extends StatelessWidget {
  const DraftReviewNotice({
    super.key,
    required this.review,
    required this.acknowledged,
    required this.onChanged,
  });
  final DraftReview review;
  final bool acknowledged;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Text(
        '关键字段发生变化，请对照下划线标记检查。',
        style: TextStyle(fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 8),
      for (final change in review.changes.take(12))
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text(
            '${change.kind.label}: ${change.before ?? '（无）'} → ${change.after ?? '（无）'}',
          ),
        ),
      if (review.changes.length > 12)
        Text('另有 ${review.changes.length - 12} 项变化，已标记在原文和建议中。'),
      const Text('标记按文本规则检测；没有标记也需要检查原意。'),
      CheckboxListTile(
        key: const Key('acknowledge-protected-changes'),
        contentPadding: EdgeInsets.zero,
        controlAffinity: ListTileControlAffinity.leading,
        value: acknowledged,
        onChanged: (value) => onChanged(value ?? false),
        title: const Text('我已核对这些变化'),
        subtitle: const Text('确认后才可采用建议；也可直接保留原稿。'),
      ),
    ],
  );
}
