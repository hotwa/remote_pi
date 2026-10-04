enum ProtectedKind {
  number('数字/端口'),
  identifier('路径/文件名/标识符'),
  constraint('否定/范围限制');

  const ProtectedKind(this.label);
  final String label;
}

class ReviewRange {
  const ReviewRange(this.start, this.end);
  final int start, end;
}

class ProtectedChange {
  const ProtectedChange(this.kind, this.before, this.after);
  final ProtectedKind kind;
  final String? before, after;
}

class DraftReview {
  const DraftReview(this.changes, this.beforeRanges, this.afterRanges);
  final List<ProtectedChange> changes;
  final List<ReviewRange> beforeRanges, afterRanges;
  bool get needsAcknowledgement => changes.isNotEmpty;

  factory DraftReview.compare(String before, String after) {
    final left = _tokens(before), right = _tokens(after);
    final changes = <ProtectedChange>[];
    final leftRanges = <ReviewRange>[], rightRanges = <ReviewRange>[];
    for (final kind in ProtectedKind.values) {
      final unmatched = right.where((t) => t.kind == kind).toList();
      final removed = <_Token>[];
      for (final token in left.where((t) => t.kind == kind)) {
        final index = unmatched.indexWhere(
          (t) => t.canonical == token.canonical,
        );
        if (index < 0) {
          removed.add(token);
        } else {
          unmatched.removeAt(index);
        }
      }
      final count = removed.length > unmatched.length
          ? removed.length
          : unmatched.length;
      for (var i = 0; i < count; i++) {
        final old = i < removed.length ? removed[i] : null;
        final next = i < unmatched.length ? unmatched[i] : null;
        changes.add(ProtectedChange(kind, old?.value, next?.value));
        if (old != null) leftRanges.add(ReviewRange(old.start, old.end));
        if (next != null) rightRanges.add(ReviewRange(next.start, next.end));
      }
    }
    return DraftReview(
      List.unmodifiable(changes),
      _merge(leftRanges),
      _merge(rightRanges),
    );
  }

  static List<ReviewRange> _merge(List<ReviewRange> ranges) {
    ranges.sort((a, b) => a.start.compareTo(b.start));
    final result = <ReviewRange>[];
    for (final range in ranges) {
      if (result.isNotEmpty && range.start <= result.last.end) {
        final last = result.removeLast();
        result.add(
          ReviewRange(last.start, range.end > last.end ? range.end : last.end),
        );
      } else {
        result.add(range);
      }
    }
    return List.unmodifiable(result);
  }

  static List<_Token> _tokens(String text) {
    final result = <_Token>[];
    void collect(
      RegExp pattern,
      ProtectedKind kind, {
      bool skipContained = false,
    }) {
      for (final match in pattern.allMatches(text)) {
        if (skipContained &&
            result.any(
              (t) =>
                  t.kind == kind &&
                  t.start <= match.start &&
                  t.end >= match.end,
            )) {
          continue;
        }
        result.add(_Token(kind, match.group(0)!, match.start, match.end));
      }
    }

    // Heuristics for review, not a proof of semantic equivalence.
    collect(
      RegExp(
        r'`[^`\n]+`|[A-Za-z]:[\\/][^\s，。；!?<>"`]+|(?<![\w])(?:~?/|\.{1,2}/)[A-Za-z0-9_.~@/\\-]+',
      ),
      ProtectedKind.identifier,
    );
    collect(
      RegExp(
        r'\b[A-Za-z0-9_][A-Za-z0-9_-]*(?:\.[A-Za-z0-9_-]+)+\b|\b(?:[A-Z]{2,}[A-Za-z0-9_-]*|[a-z]+[A-Z][A-Za-z0-9]*|[A-Za-z]+[_-][A-Za-z0-9_-]+|[A-Za-z]+\d+[A-Za-z0-9_-]*)\b',
      ),
      ProtectedKind.identifier,
      skipContained: true,
    );
    collect(
      RegExp(r'\d+(?:[.:]\d+)*|[零〇一二两三四五六七八九十百千万亿点]{2,}'),
      ProtectedKind.number,
    );
    collect(
      RegExp(
        r'''(?:不(?:要|得|能|允许|准|执行|修改|删除|运行|写入|安装|发送|提交|部署)|禁止|切勿|勿|仅|只(?:能|允许)?)[^，。！？；\n]{0,96}|\b(?:do\s+not|don['’]t|never|must\s+not|only|without)\b[^.,!?\n]{0,96}''',
        caseSensitive: false,
      ),
      ProtectedKind.constraint,
    );
    return result;
  }
}

class _Token {
  const _Token(this.kind, this.value, this.start, this.end);
  final ProtectedKind kind;
  final String value;
  final int start, end;
  String get canonical => kind == ProtectedKind.constraint
      ? value.replaceAll(RegExp(r'\s+'), '').toLowerCase()
      : value;
}
