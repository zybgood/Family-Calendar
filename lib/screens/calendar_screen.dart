import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../widgets/event_card.dart';
import 'notifications_screen.dart';
import 'family_screen.dart';
import 'chat_screen.dart';
import 'settings_screen.dart';

class CalendarEvent {
  final String id;
  final String eventName;
  final String eventTag;
  final DateTime eventDate;
  final String eventTime; // 原始时间字符串，例如：08:00 或 8:00 AM - 9:30 AM
  final String userId;
  final String familyId;

  CalendarEvent({
    required this.id,
    required this.eventName,
    required this.eventTag,
    required this.eventDate,
    required this.eventTime,
    required this.userId,
    required this.familyId,
  });

  factory CalendarEvent.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;

    return CalendarEvent(
      id: doc.id,
      eventName: (data['eventName'] ?? '').toString(),
      eventTag: (data['eventTag'] ?? '').toString(),
      eventDate: _parseEventDate(data['eventDate']),
      eventTime: (data['eventTime'] ?? '').toString(),
      userId: (data['userId'] ?? '').toString(),
      familyId: (data['familyId'] ?? '').toString(),
    );
  }

  /// 取事件开始时间，用于时间轴排序和定位
  DateTime get startDateTime {
    final DateTime dateOnly = DateTime(eventDate.year, eventDate.month, eventDate.day);
    final TimeOfDay timeOfDay = _parseStartTime(eventTime);
    return DateTime(
      dateOnly.year,
      dateOnly.month,
      dateOnly.day,
      timeOfDay.hour,
      timeOfDay.minute,
    );
  }

  /// 用于左侧显示 08:00 / 10:00
  String get hourLabel {
    return DateFormat('HH:mm').format(startDateTime);
  }

  static DateTime _parseEventDate(dynamic value) {
    if (value is Timestamp) {
      final d = value.toDate();
      return DateTime(d.year, d.month, d.day);
    }
    if (value is DateTime) {
      return DateTime(value.year, value.month, value.day);
    }
    if (value is String && value.isNotEmpty) {
      try {
        final d = DateTime.parse(value);
        return DateTime(d.year, d.month, d.day);
      } catch (_) {}
      try {
        final d = DateFormat('yyyy-MM-dd').parse(value);
        return DateTime(d.year, d.month, d.day);
      } catch (_) {}
    }
    return DateTime.now();
  }

  static TimeOfDay _parseStartTime(String raw) {
    final value = raw.trim();

    if (value.isEmpty) {
      return const TimeOfDay(hour: 0, minute: 0);
    }

    // 先取区间左边，例如 "8:00 AM - 9:30 AM" -> "8:00 AM"
    final firstPart = value.split('-').first.trim();

    // 24小时制：08:00
    final reg24 = RegExp(r'^(\d{1,2}):(\d{2})$');
    final match24 = reg24.firstMatch(firstPart);
    if (match24 != null) {
      return TimeOfDay(
        hour: int.parse(match24.group(1)!),
        minute: int.parse(match24.group(2)!),
      );
    }

    // 12小时制：8:00 AM
    try {
      final dt = DateFormat('h:mm a').parse(firstPart.toUpperCase());
      return TimeOfDay(hour: dt.hour, minute: dt.minute);
    } catch (_) {}

    return const TimeOfDay(hour: 0, minute: 0);
  }
}

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({Key? key}) : super(key: key);

  static const bgColor = Color(0xFFFDFBF7);
  static const primaryColor = Color(0xFF0F172A);
  static const accentColor = Color(0xFFE2B736);

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  /// 这里先写死，后面你可以替换成登录用户 / 当前家庭上下文
  final String currentUserId = 'user_001';
  final String currentFamilyId = 'family_001';

  late DateTime selectedDate;

  @override
  void initState() {
    super.initState();
    selectedDate = DateTime.now();
  }

  List<DateTime> get weekDays {
    final monday = selectedDate.subtract(Duration(days: selectedDate.weekday - 1));
    return List.generate(6, (index) => monday.add(Duration(days: index)));
  }

  Stream<List<CalendarEvent>> _eventStream() {
    return FirebaseFirestore.instance
        .collection('calendar_events')
        .where('familyId', isEqualTo: currentFamilyId)
        .snapshots()
        .map((snapshot) {
      final events = snapshot.docs
          .map((doc) => CalendarEvent.fromFirestore(doc))
          .where((event) {
        final sameDay = _isSameDate(event.eventDate, selectedDate);

        // 这里的逻辑是：
        // 1. familyId 必须一致（上面 query 已经过滤）
        // 2. userId 必须等于当前用户
        return sameDay && event.userId == currentUserId;
      })
          .toList();

      events.sort((a, b) => a.startDateTime.compareTo(b.startDateTime));
      return events;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CalendarScreen.bgColor,
      body: SafeArea(
        child: Center(
          child: Container(
            width: 430,
            constraints: const BoxConstraints(maxWidth: 430),
            child: Column(
              children: [
                _buildHeader(context),
                const SizedBox(height: 16),
                _buildDateSelector(),
                const SizedBox(height: 16),
                Expanded(child: _buildTimeline()),
                _buildBottomNav(context),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: Colors.white,
                child: Icon(Icons.person, size: 24, color: Colors.grey),
              ),
              SizedBox(width: 8),
              CircleAvatar(
                radius: 20,
                backgroundColor: Colors.white,
                child: Icon(Icons.person, size: 24, color: Colors.grey),
              ),
            ],
          ),
          Text(
            DateFormat('MMMM').format(selectedDate),
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: CalendarScreen.primaryColor,
            ),
          ),
          GestureDetector(
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const NotificationsScreen()),
            ),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: Colors.white.withOpacity(0.6),
                  child: const Icon(
                    Icons.notifications,
                    size: 18,
                    color: CalendarScreen.primaryColor,
                  ),
                ),
                Positioned(
                  top: -4,
                  right: -4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    decoration: const BoxDecoration(
                      color: Color(0xFFEF4444),
                      borderRadius: BorderRadius.all(Radius.circular(999)),
                    ),
                    child: const Text(
                      '99+',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDateSelector() {
    return SizedBox(
      height: 104,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        scrollDirection: Axis.horizontal,
        itemCount: weekDays.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final day = weekDays[index];
          final bool isSelected = _isSameDate(day, selectedDate);

          return GestureDetector(
            onTap: () {
              setState(() {
                selectedDate = DateTime(day.year, day.month, day.day);
              });
            },
            child: Container(
              width: 80,
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
              decoration: BoxDecoration(
                color: isSelected
                    ? const Color(0x22E2B736)
                    : Colors.white.withOpacity(0.5),
                border: Border.all(
                  color: isSelected
                      ? CalendarScreen.accentColor
                      : const Color(0xFFF1F5F9),
                  width: isSelected ? 2 : 1,
                ),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    DateFormat('EEE').format(day),
                    style: TextStyle(
                      color: isSelected
                          ? CalendarScreen.accentColor
                          : const Color(0xFF64748B),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    DateFormat('d').format(day),
                    style: TextStyle(
                      color: isSelected
                          ? CalendarScreen.accentColor
                          : CalendarScreen.primaryColor,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildTimeline() {
    return StreamBuilder<List<CalendarEvent>>(
      stream: _eventStream(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(
            child: Text(
              '读取事件失败：${snapshot.error}',
              style: const TextStyle(color: Colors.red),
            ),
          );
        }

        final events = snapshot.data ?? [];

        if (events.isEmpty) {
          return const Center(
            child: Text(
              '当天没有事件',
              style: TextStyle(
                color: Color(0xFF94A3B8),
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          );
        }

        return ListView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          children: _buildTimelineChildren(events),
        );
      },
    );
  }

  List<Widget> _buildTimelineChildren(List<CalendarEvent> events) {
    final List<Widget> children = [];
    int? previousHour;

    for (final event in events) {
      final int currentHour = event.startDateTime.hour;

      if (previousHour == null) {
        children.add(const SizedBox(height: 8));
      } else if (currentHour > previousHour) {
        for (int h = previousHour + 1; h <= currentHour - 1; h++) {
          children.add(const SizedBox(height: 24));
          children.add(_timeDivider('${h.toString().padLeft(2, '0')}:00'));
          children.add(const SizedBox(height: 24));
        }
      }

      children.add(_timeRow(event.hourLabel, _buildEventCard(event)));
      children.add(const SizedBox(height: 24));

      previousHour = currentHour;
    }

    final lastHour = events.last.startDateTime.hour + 1;
    children.add(_timeDivider('${lastHour.toString().padLeft(2, '0')}:00'));
    children.add(const SizedBox(height: 80));

    return children;
  }

  Widget _timeRow(String time, Widget right) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 60,
          child: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              time,
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: Color(0xFF94A3B8),
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(child: right),
      ],
    );
  }

  Widget _timeDivider(String time) {
    return Row(
      children: [
        SizedBox(
          width: 60,
          child: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              time,
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: Color(0xFF94A3B8),
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Container(
            height: 2,
            color: const Color(0xFFF1F5F9),
          ),
        ),
      ],
    );
  }

  Widget _buildEventCard(CalendarEvent event) {
    final bool isEducation =
        event.eventTag.toLowerCase() == 'education';

    return EventCard(
      color: isEducation ? const Color(0xFFE0F2FE) : const Color(0xFFF3E8FF),
      category: event.eventTag,
      title: event.eventName,
      timeRange: event.eventTime,
      participants: const [],
      trailingIcon: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.6),
          shape: BoxShape.circle,
        ),
        child: Center(
          child: Icon(
            _iconByTag(event.eventTag),
            size: 18,
            color: CalendarScreen.primaryColor,
          ),
        ),
      ),
    );
  }

  IconData _iconByTag(String tag) {
    switch (tag.toLowerCase()) {
      case 'education':
        return Icons.school_outlined;
      case 'family':
        return Icons.shopping_basket_outlined;
      case 'work':
        return Icons.work_outline;
      case 'health':
        return Icons.favorite_border;
      default:
        return Icons.event;
    }
  }

  Widget _buildBottomNav(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 25, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.85),
        border: const Border(
          top: BorderSide(color: Color(0xFFF1F5F9)),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _navItem(Icons.calendar_today, 'Today', selected: true),
          GestureDetector(
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const FamilyScreen()),
            ),
            child: _navItem(Icons.people, 'Family'),
          ),
          GestureDetector(
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ChatScreen()),
            ),
            child: _navItem(Icons.chat_bubble_outline, 'Chat'),
          ),
          GestureDetector(
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
            child: _navItem(Icons.settings, 'Settings'),
          ),
        ],
      ),
    );
  }

  Widget _navItem(IconData icon, String label, {bool selected = false}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: 20,
          color: selected ? CalendarScreen.accentColor : const Color(0xFF94A3B8),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
            color: selected ? CalendarScreen.accentColor : const Color(0xFF94A3B8),
          ),
        ),
      ],
    );
  }

  bool _isSameDate(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }
}