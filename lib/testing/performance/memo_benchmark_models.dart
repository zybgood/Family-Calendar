import 'package:intl/intl.dart';

import '../../screens/memo_screen.dart';

class MemoBenchmarkSection {
  const MemoBenchmarkSection({required this.title, required this.items});

  final String title;
  final List<MemoBenchmarkItem> items;
}

class MemoBenchmarkItem {
  const MemoBenchmarkItem({
    required this.id,
    required this.title,
    required this.dateLabel,
    required this.body,
  });

  final String id;
  final String title;
  final String dateLabel;
  final String body;
}

class MemoBenchmarkModels {
  const MemoBenchmarkModels._();

  static List<MemoBenchmarkSection> buildSections(
      List<MemoRecord> memos, {
        DateTime? now,
      }) {
    final resolvedNow = now ?? DateTime.now();
    final sections = <MemoBenchmarkSection>[];
    String? currentKey;
    List<MemoBenchmarkItem> currentItems = [];

    for (final memo in memos) {
      final key = sectionKeyForDate(memo.createdAt, now: resolvedNow);
      if (currentKey != key) {
        if (currentKey != null) {
          sections.add(
            MemoBenchmarkSection(
              title: currentKey,
              items: List.unmodifiable(currentItems),
            ),
          );
        }
        currentKey = key;
        currentItems = [];
      }

      currentItems.add(
        MemoBenchmarkItem(
          id: memo.id,
          title: memo.displayTitle,
          dateLabel: cardDateLabel(memo.createdAt, now: resolvedNow),
          body: memo.body,
        ),
      );
    }

    if (currentKey != null) {
      sections.add(
        MemoBenchmarkSection(
          title: currentKey,
          items: List.unmodifiable(currentItems),
        ),
      );
    }

    return sections;
  }

  static String sectionKeyForDate(DateTime date, {DateTime? now}) {
    final localDate = date.toLocal();
    final resolvedNow = now ?? DateTime.now();
    final today = DateTime(resolvedNow.year, resolvedNow.month, resolvedNow.day);
    final memoDay = DateTime(localDate.year, localDate.month, localDate.day);
    final difference = today.difference(memoDay).inDays;

    if (difference == 0) {
      return 'Today';
    }
    if (difference == 1) {
      return 'Yesterday';
    }
    return DateFormat('yyyy.MM.dd').format(localDate);
  }

  static String cardDateLabel(DateTime date, {DateTime? now}) {
    final localDate = date.toLocal();
    final resolvedNow = now ?? DateTime.now();
    final today = DateTime(resolvedNow.year, resolvedNow.month, resolvedNow.day);
    final memoDay = DateTime(localDate.year, localDate.month, localDate.day);
    final difference = today.difference(memoDay).inDays;

    if (difference == 0 || difference == 1) {
      return DateFormat('h:mm a').format(localDate);
    }
    return DateFormat('yyyy.MM.dd').format(localDate);
  }

  static List<MemoRecord> generateSampleMemos(
      int count, {
        DateTime? now,
        int bodyRepeatFactor = 12,
      }) {
    final resolvedNow = now ?? DateTime.now();
    return List<MemoRecord>.generate(count, (index) {
      final createdAt = resolvedNow.subtract(
        Duration(minutes: index * 7, days: index ~/ 18),
      );
      final body = List<String>.generate(
        bodyRepeatFactor,
            (bodyIndex) => 'Memo $index line $bodyIndex lorem ipsum dolor sit amet.',
      ).join(' ');

      return MemoRecord(
        id: 'memo_$index',
        title: index.isEven ? 'Memo title $index' : '',
        body: body,
        createdAt: createdAt,
      );
    });
  }
}