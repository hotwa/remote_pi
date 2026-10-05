import 'package:flutter_test/flutter_test.dart';
import 'package:pimic_addons/draft_review.dart';

void main() {
  test('changed port, filename and removed restriction are marked', () {
    const before = '检查 package.json 端口17891，不要修改文件。';
    const after = '修改 package.yaml 端口17890。';
    final review = DraftReview.compare(before, after);
    expect(review.needsAcknowledgement, isTrue);
    expect(
      review.changes.map((c) => c.kind).toSet(),
      ProtectedKind.values.toSet(),
    );
    expect(
      review.changes.any((c) => c.before == '17891' && c.after == '17890'),
      isTrue,
    );
    expect(
      review.changes.any((c) => c.before == '不要修改文件' && c.after == null),
      isTrue,
    );
    final left = review.beforeRanges
        .map((r) => before.substring(r.start, r.end))
        .join('|');
    expect(left, contains('package.json'));
    expect(left, contains('不要修改文件'));
  });

  test('reordering protected fields does not create spurious changes', () {
    final review = DraftReview.compare(
      'README package.json 17891。不要修改文件。只报告问题。',
      '只报告问题。不要修改文件。17891 package.json README。',
    );
    expect(review.needsAcknowledgement, isFalse);
    expect(review.beforeRanges, isEmpty);
  });

  test('repeated numbers use occurrence counts', () {
    final review = DraftReview.compare('17891 17891', '17891');
    expect(review.changes, hasLength(1));
    expect(review.changes.single.before, '17891');
    expect(review.changes.single.after, isNull);
  });

  test(
    'Windows Unix and quoted paths, code names and Chinese digits protected',
    () {
      final review = DraftReview.compare(
        r'读取 C:\work\test.ts 和 /tmp/a.json，调用 loadConfig，一七八九一，`myfile`。',
        r'读取 C:\work\test.js 和 /tmp/b.json，调用 loadSettings，一七八九二，`other`。',
      );
      for (final value in [
        r'C:\work\test.ts',
        '/tmp/a.json',
        'loadConfig',
        '一七八九一',
        '`myfile`',
      ]) {
        expect(
          review.changes.any((c) => c.before == value),
          isTrue,
          reason: value,
        );
      }
      for (final ranges in [review.beforeRanges, review.afterRanges]) {
        for (var i = 1; i < ranges.length; i++) {
          expect(ranges[i].start, greaterThan(ranges[i - 1].end));
        }
      }
    },
  );

  test('Chinese action negations and English contractions are marked', () {
    for (final source in [
      '不修改文件。',
      '不执行命令。',
      "Don't delete files.",
      'Don’t delete files.',
      'Only report issues.',
    ]) {
      expect(
        DraftReview.compare(
          source,
          'Proceed.',
        ).changes.any((c) => c.kind == ProtectedKind.constraint),
        isTrue,
        reason: source,
      );
    }
    expect(
      DraftReview.compare(
        'donut tastes good',
        'donuts taste good',
      ).needsAcknowledgement,
      isFalse,
    );
  });

  test(
    'restriction whitespace and sentence punctuation tolerated, added restriction marked',
    () {
      expect(
        DraftReview.compare('不要 修改 文件。', '不要修改文件！').needsAcknowledgement,
        isFalse,
      );
      expect(
        DraftReview.compare('检查文件。', '检查文件。不要修改文件。').changes.single.after,
        '不要修改文件',
      );
    },
  );
}
