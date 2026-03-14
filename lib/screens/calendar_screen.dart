import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../assets/figma_assets.dart';
import '../models/task.dart';
import '../widgets/event_card.dart';
import 'add_task_screen.dart';
import 'edit_task_screen.dart';
import 'notifications_screen.dart';
import 'family_screen.dart';
import 'chat_screen.dart';
import 'settings_screen.dart';

class CalendarEvent {
  final String id;
  final String eventName;
  final String eventTag;
  final DateTime eventDate;
  final String eventTime;
  final String userId;
  final String familyId;
  final String notes;
  final List<String> participants;
  final bool reminderEnabled;

  CalendarEvent({
    required this.id,
    required this.eventName,
    required this.eventTag,
    required this.eventDate,
    required this.eventTime,
    required this.userId,
    required this.familyId,
    required this.notes,
    required this.participants,
    required this.reminderEnabled,
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
      notes: (data['notes'] ?? '').toString(),
      participants: ((data['participants'] ?? []) as List)
          .map((e) => e.toString())
          .toList(),
      reminderEnabled: (data['reminderEnabled'] ?? true) == true,
    );
  }

  DateTime get startDateTime {
    final dateOnly = DateTime(eventDate.year, eventDate.month, eventDate.day);
    final timeOfDay = _parseStartTime(eventTime);

    return DateTime(
      dateOnly.year,
      dateOnly.month,
      dateOnly.day,
      timeOfDay.hour,
      timeOfDay.minute,
    );
  }

  DateTime get endDateTime {
    final dateOnly = DateTime(eventDate.year, eventDate.month, eventDate.day);
    final timeOfDay = _parseEndTime(eventTime);

    return DateTime(
      dateOnly.year,
      dateOnly.month,
      dateOnly.day,
      timeOfDay.hour,
      timeOfDay.minute,
    );
  }

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

    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  static TimeOfDay _parseStartTime(String raw) {
    final value = raw.trim();

    if (value.isEmpty) {
      return const TimeOfDay(hour: 0, minute: 0);
    }

    final firstPart = value.split('-').first.trim();

    final reg24 = RegExp(r'^(\d{1,2}):(\d{2})$');
    final match24 = reg24.firstMatch(firstPart);
    if (match24 != null) {
      return TimeOfDay(
        hour: int.parse(match24.group(1)!),
        minute: int.parse(match24.group(2)!),
      );
    }

    try {
      final dt = DateFormat('h:mm a').parse(firstPart.toUpperCase());
      return TimeOfDay(hour: dt.hour, minute: dt.minute);
    } catch (_) {}

    return const TimeOfDay(hour: 0, minute: 0);
  }

  static TimeOfDay _parseEndTime(String raw) {
    final value = raw.trim();

    if (value.isEmpty) {
      return const TimeOfDay(hour: 0, minute: 0);
    }

    final parts = value.split('-');
    if (parts.length < 2) {
      return _parseStartTime(raw);
    }

    final endPart = parts.last.trim();

    final reg24 = RegExp(r'^(\d{1,2}):(\d{2})$');
    final match24 = reg24.firstMatch(endPart);
    if (match24 != null) {
      return TimeOfDay(
        hour: int.parse(match24.group(1)!),
        minute: int.parse(match24.group(2)!),
      );
    }

    try {
      final dt = DateFormat('h:mm a').parse(endPart.toUpperCase());
      return TimeOfDay(hour: dt.hour, minute: dt.minute);
    } catch (_) {}

    return _parseStartTime(raw);
  }
}

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({Key? key}) : super(key: key);

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  static const bgColor = Color(0xFFFDFBF7);
  static const primaryColor = Color(0xFF0F172A);
  static const accentColor = Color(0xFFE2B736);

  /// TODO: Replace with real logged-in user/family context later.
  final String currentUserId = 'user_001';
  final String currentFamilyId = 'family_001';

  late DateTime selectedDate;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    selectedDate = DateTime(now.year, now.month, now.day);
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
        return sameDay && event.userId == currentUserId;
      }).toList();

      events.sort((a, b) => a.startDateTime.compareTo(b.startDateTime));
      return events;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgColor,
      body: SafeArea(
        child: Stack(
          children: [
            Center(
              child: Container(
                width: 430,
                constraints: const BoxConstraints(maxWidth: 430),
                child: Column(
                  children: [
                    _buildHeader(context),
                    const SizedBox(height: 16),
                    _buildDateSelector(),
                    const SizedBox(height: 16),
                    Expanded(child: _buildTimeline(context)),
                    const SizedBox(height: 90),
                  ],
                ),
              ),
            ),
            Positioned(
              right: 16,
              bottom: 72,
              child: FloatingActionButton(
                shape: const CircleBorder(),
                backgroundColor: accentColor,
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const AddTaskScreen()),
                  );
                },
                child: const Icon(Icons.add),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _buildBottomNav(context),
            ),
          ],
        ),
      ),
    );
  }

  // -----------------------------
  // Header
  // -----------------------------
  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              const CircleAvatar(
                radius: 20,
                backgroundColor: Colors.white,
                child: Icon(Icons.person, size: 24, color: Colors.grey),
              ),
              const SizedBox(width: 8),
              const CircleAvatar(
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
              color: primaryColor,
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
                  child: const Icon(Icons.notifications, size: 18, color: primaryColor),
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

  // -----------------------------
  // Date selector
  // -----------------------------
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
          final bool selected = _isSameDate(day, selectedDate);

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
                color: selected ? const Color(0x22E2B736) : Colors.white.withOpacity(0.5),
                border: Border.all(
                  color: selected ? accentColor : const Color(0xFFF1F5F9),
                  width: selected ? 2 : 1,
                ),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    DateFormat('EEE').format(day),
                    style: TextStyle(
                      color: selected ? accentColor : const Color(0xFF64748B),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    DateFormat('d').format(day),
                    style: TextStyle(
                      color: selected ? accentColor : primaryColor,
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

  // -----------------------------
  // Timeline
  // -----------------------------
  Widget _buildTimeline(BuildContext context) {
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
              style: const TextStyle(
                color: Colors.red,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
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

        return SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: _buildTimelineChildren(context, events),
            ),
          ),
        );
      },
    );
  }

  List<Widget> _buildTimelineChildren(
      BuildContext context,
      List<CalendarEvent> events,
      ) {
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

      children.add(_timeRow(event.hourLabel, _buildEventCard(context, event)));
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

  // -----------------------------
  // Event cards
  // -----------------------------
  Widget _buildEventCard(BuildContext context, CalendarEvent event) {
    final task = Task(
      title: event.eventName,
      category: event.eventTag,
      date: event.eventDate,
      startTime: event.startDateTime,
      endTime: event.endDateTime,
      notes: event.notes,
      participants: event.participants,
      reminderEnabled: event.reminderEnabled,
    );

    return EventCard(
      color: _cardColorByTag(event.eventTag),
      category: event.eventTag,
      title: event.eventName,
      timeRange: event.eventTime,
      participants: event.participants,
      subtitle: event.notes.isEmpty ? null : event.notes,
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
            color: primaryColor,
          ),
        ),
      ),
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => EditTaskScreen(
              initialTask: task,
              onUpdate: (updated) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Task updated')),
                );
              },
              onDelete: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Task deleted')),
                );
              },
            ),
          ),
        );
      },
    );
  }

  Color _cardColorByTag(String tag) {
    switch (tag.toLowerCase()) {
      case 'education':
        return const Color(0xFFE0F2FE);
      case 'family':
        return const Color(0xFFF3E8FF);
      case 'work':
        return const Color(0xFFE8F5E9);
      case 'health':
        return const Color(0xFFFFF1F2);
      default:
        return const Color(0xFFF8FAFC);
    }
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

  // -----------------------------
  // Bottom navigation
  // -----------------------------
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
          color: selected ? accentColor : const Color(0xFF94A3B8),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
            color: selected ? accentColor : const Color(0xFF94A3B8),
          ),
        ),
      ],
    );
  }

  bool _isSameDate(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }
}