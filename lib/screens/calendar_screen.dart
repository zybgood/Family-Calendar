import 'dart:math' as math;
import 'dart:ui';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../assets/figma_assets.dart';
import '../models/task.dart';
import '../widgets/event_card.dart';
import 'add_task_screen.dart';
import 'edit_task_screen.dart';
import 'memo_screen.dart';
import 'notifications_screen.dart';
import 'select_family_screen.dart';
import 'settings_screen.dart';

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({Key? key}) : super(key: key);

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  static const bgColor = Color(0xFFFDFBF7);
  static const primaryColor = Color(0xFF0F172A);
  static const accentColor = Color(0xFFE2B736);
  static const secondaryAccent = Color(0xFFFDE047);

  static const _hourRowHeight = 92.0;
  static const _leftTimeWidth = 60.0;
  static const _timelineGap = 16.0;
  static const _eventCardHeight = 168.0;
  static const _lineTopOffset = 18.0;
  static const _cardTopGapFromMarker = 0.0;
  static const _cardBottomGap = 14.0;

  int _selectedNavIndex = 2;
  late final List<DateTime> _days;
  late int _selectedDayIndex;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    final weekStart = DateTime(now.year, now.month, now.day).subtract(
      Duration(days: now.weekday - 1),
    );
    _days = List.generate(7, (index) => weekStart.add(Duration(days: index)));
    _selectedDayIndex = math.max(0, math.min(6, now.weekday - 1));
  }

  DateTime get _selectedDate => _days[_selectedDayIndex];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgColor,
      body: SafeArea(
        child: Center(
          child: Container(
            width: 430,
            constraints: const BoxConstraints(maxWidth: 430),
            height: double.infinity,
            child: Stack(
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: bgColor,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.25),
                        blurRadius: 50,
                        offset: const Offset(0, 20),
                      ),
                    ],
                  ),
                ),
                Positioned.fill(
                  child: Column(
                    children: [
                      const SizedBox(height: 74),
                      _buildDateSelector(),
                      const SizedBox(height: 8),
                      Expanded(child: _buildTimeline(context)),
                      const SizedBox(height: 94),
                    ],
                  ),
                ),
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: _buildHeader(context),
                ),
                Positioned(
                  right: 24,
                  bottom: 112,
                  child: _buildFab(context),
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
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 17),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.45),
            border: Border.all(color: const Color(0xFFF1F5F9)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildHeaderAvatars(),
              Text(
                DateFormat('MMMM').format(_selectedDate),
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: primaryColor,
                  letterSpacing: -0.5,
                ),
              ),
              _buildNotificationsButton(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderAvatars() {
    return Row(
      children: [
        _buildAvatar(FigmaAssets.imgMember1),
        const SizedBox(width: 0),
        _buildAvatar(FigmaAssets.imgMember2, overlap: -8),
      ],
    );
  }

  Widget _buildAvatar(String imageUrl, {double overlap = 0}) {
    return Transform.translate(
      offset: Offset(overlap, 0),
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ClipOval(
          child: Image.network(
            imageUrl,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) =>
            const Icon(Icons.person, size: 18, color: Colors.grey),
          ),
        ),
      ),
    );
  }

  Widget _buildNotificationsButton(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const NotificationsScreen()),
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.5),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 2,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            child: const Center(
              child: Icon(Icons.notifications, size: 18, color: primaryColor),
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
    );
  }

  Widget _buildDateSelector() {
    return SizedBox(
      height: 104,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        scrollDirection: Axis.horizontal,
        itemCount: _days.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final day = _days[index];
          final selected = index == _selectedDayIndex;

          return GestureDetector(
            onTap: () => setState(() => _selectedDayIndex = index),
            child: Container(
              width: 80,
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
              decoration: BoxDecoration(
                color:
                selected ? const Color(0x22E2B736) : Colors.white.withOpacity(0.5),
                border: Border.all(
                  color: selected ? accentColor : const Color(0xFFF1F5F9),
                  width: selected ? 2 : 1,
                ),
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 2,
                    offset: const Offset(0, 1),
                  ),
                ],
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

  Widget _buildTimeline(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return const Center(
        child: Text(
          'Please sign in first.',
          style: TextStyle(
            color: Color(0xFF64748B),
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('events')
          .where('participantIds', arrayContains: user.uid)
          .where('status', isEqualTo: 'active')
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return const Center(
            child: Text(
              'Failed to load events.',
              style: TextStyle(
                color: Color(0xFF64748B),
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          );
        }

        final allEvents = snapshot.data?.docs
            .map((doc) => _CalendarEvent.fromFirestore(doc))
            .where((event) => event != null)
            .cast<_CalendarEvent>()
            .toList() ??
            <_CalendarEvent>[];

        final selectedEvents = allEvents
            .where((event) => _isSameDay(event.startTime, _selectedDate))
            .toList()
          ..sort((a, b) => a.startTime.compareTo(b.startTime));

        if (selectedEvents.isEmpty) {
          return SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(
                children: [
                  const SizedBox(height: 24),
                  _emptyState(),
                  const SizedBox(height: 140),
                ],
              ),
            ),
          );
        }

        return FutureBuilder<Map<String, String>>(
          future: _loadParticipantNames(selectedEvents),
          builder: (context, namesSnapshot) {
            final participantNames = namesSnapshot.data ?? <String, String>{};

            final minHour = math.max(
              0,
              math.min(
                23,
                selectedEvents.map((e) => e.startTime.hour).reduce(math.min) - 1,
              ),
            );

            final maxHour = math.max(
              minHour + 1,
              math.min(
                23,
                selectedEvents
                    .map((e) => e.endTime.hour + (e.endTime.minute > 0 ? 1 : 0))
                    .reduce(math.max),
              ),
            );

            final startHour = math.min(8, minHour);
            final endHour = math.max(11, maxHour);

            final flowItems = _buildFlowItems(
              context,
              selectedEvents,
              participantNames,
              startHour,
              endHour,
            );

            return SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: _leftTimeWidth,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: flowItems
                            .map((item) => SizedBox(
                          height: item.height,
                          child: Align(
                            alignment: item.alignment,
                            child: item.leftLabel == null
                                ? const SizedBox.shrink()
                                : Padding(
                              padding: EdgeInsets.only(
                                top: item.leftTopPadding,
                              ),
                              child: Text(
                                item.leftLabel!,
                                textAlign: TextAlign.right,
                                style: const TextStyle(
                                  color: Color(0xFF94A3B8),
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ))
                            .toList(),
                      ),
                    ),
                    const SizedBox(width: _timelineGap),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: flowItems.map((item) {
                          switch (item.type) {
                            case _FlowItemType.hourGap:
                            case _FlowItemType.minuteGap:
                              return SizedBox(
                                height: item.height,
                                child: Align(
                                  alignment: item.alignment,
                                  child: Padding(
                                    padding: EdgeInsets.only(top: item.lineTopPadding),
                                    child: Container(
                                      height: 2,
                                      color: const Color(0xFFF1F5F9),
                                    ),
                                  ),
                                ),
                              );
                            case _FlowItemType.event:
                              return Padding(
                                padding: EdgeInsets.only(
                                  top: item.eventTopPadding,
                                  bottom: item.eventBottomPadding,
                                ),
                                child: SizedBox(
                                  height: _eventCardHeight,
                                  child: _buildEventCard(
                                    context,
                                    item.event!,
                                    participantNames,
                                  ),
                                ),
                              );
                          }
                        }).toList(),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  List<_FlowItem> _buildFlowItems(
      BuildContext context,
      List<_CalendarEvent> events,
      Map<String, String> participantNames,
      int startHour,
      int endHour,
      ) {
    final items = <_FlowItem>[];
    final sortedEvents = [...events]..sort((a, b) => a.startTime.compareTo(b.startTime));

    int currentMinutes = startHour * 60;
    final endMinutes = (endHour + 1) * 60;

    items.add(
      _FlowItem.hourGap(
        label: '${startHour.toString().padLeft(2, '0')}:00',
        height: _hourRowHeight,
      ),
    );
    currentMinutes += 60;

    for (final event in sortedEvents) {
      final eventStartMinutes = event.startTime.hour * 60 + event.startTime.minute;

      while (currentMinutes <= eventStartMinutes) {
        final hour = currentMinutes ~/ 60;
        final markerMinutes = hour * 60;

        if (markerMinutes < eventStartMinutes) {
          final gapHeight =
              ((eventStartMinutes - markerMinutes) / 60.0) * _hourRowHeight;

          if (gapHeight > 0) {
            items.add(
              _FlowItem.minuteGap(
                label: DateFormat('HH:mm').format(event.startTime),
                height: gapHeight,
              ),
            );
          }

          currentMinutes = eventStartMinutes;
          break;
        } else if (markerMinutes == eventStartMinutes) {
          currentMinutes = eventStartMinutes;
          break;
        } else {
          break;
        }
      }

      items.add(_FlowItem.event(event));

      final nextHourAfterEventStart = ((eventStartMinutes ~/ 60) + 1) * 60;
      currentMinutes = math.max(currentMinutes, nextHourAfterEventStart);

      while (currentMinutes <= endMinutes &&
          currentMinutes < (((sortedEvents.last.startTime.hour) + 1) * 60)) {
        break;
      }

      final nextEvent = _nextEventAfter(sortedEvents, event);
      final nextTargetMinutes = nextEvent != null
          ? nextEvent.startTime.hour * 60 + nextEvent.startTime.minute
          : endMinutes;

      while (currentMinutes < nextTargetMinutes) {
        final hour = currentMinutes ~/ 60;
        final hourLabel = '${hour.toString().padLeft(2, '0')}:00';

        if (currentMinutes + 60 <= nextTargetMinutes) {
          items.add(_FlowItem.hourGap(label: hourLabel, height: _hourRowHeight));
          currentMinutes += 60;
        } else {
          final gapHeight =
              ((nextTargetMinutes - currentMinutes) / 60.0) * _hourRowHeight;
          if (gapHeight > 0) {
            items.add(
              _FlowItem.minuteGap(
                label: nextEvent != null
                    ? DateFormat('HH:mm').format(nextEvent.startTime)
                    : null,
                height: gapHeight,
              ),
            );
          }
          currentMinutes = nextTargetMinutes;
        }
      }
    }

    int tailHour = currentMinutes ~/ 60;
    if (currentMinutes <= endMinutes) {
      while (tailHour <= endHour) {
        items.add(
          _FlowItem.hourGap(
            label: '${tailHour.toString().padLeft(2, '0')}:00',
            height: _hourRowHeight,
          ),
        );
        tailHour += 1;
      }
    }

    return items;
  }

  _CalendarEvent? _nextEventAfter(List<_CalendarEvent> events, _CalendarEvent current) {
    final index = events.indexOf(current);
    if (index == -1 || index + 1 >= events.length) return null;
    return events[index + 1];
  }

  Widget _buildEventCard(
      BuildContext context,
      _CalendarEvent event,
      Map<String, String> participantNames,
      ) {
    final participants = event.participantIds
        .map((id) => participantNames[id] ?? 'Member')
        .toList();

    return EventCard(
      color: _eventColor(event.eventType),
      category: event.eventType,
      title: event.title,
      timeRange: _formatTimeRange(
        event.startTime,
        event.endTime,
        event.isAllDay,
      ),
      participants: event.participantIds,
      subtitle: event.description.isEmpty ? null : event.description,
      trailingIcon: _buildTrailingIcon(event),
      onTap: () {
        final task = Task(
          id: event.id,
          title: event.title,
          category: event.eventType,
          date: DateTime(
            event.startTime.year,
            event.startTime.month,
            event.startTime.day,
          ),
          startTime: event.startTime,
          endTime: event.endTime,
          notes: event.description,
          participants: participants,
          reminderEnabled: event.reminderMinutes > 0,
        );

        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => EditTaskScreen(
              initialTask: task,
              onUpdate: (_) {
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

  Widget _emptyState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.7),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFF1F5F9)),
      ),
      child: const Column(
        children: [
          Icon(Icons.event_available, color: Color(0xFF94A3B8), size: 28),
          SizedBox(height: 12),
          Text(
            'No events for this day',
            style: TextStyle(
              color: Color(0xFF0F172A),
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTrailingIcon(_CalendarEvent event) {
    IconData icon;
    switch (event.eventType.toLowerCase()) {
      case 'meeting':
        icon = Icons.event;
        break;
      case 'health':
        icon = Icons.favorite;
        break;
      case 'shopping':
        icon = Icons.shopping_cart;
        break;
      case 'family':
        icon = Icons.people;
        break;
      case 'education':
        icon = Icons.school;
        break;
      default:
        icon = Icons.event_note;
    }

    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.6),
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Icon(icon, size: 18, color: primaryColor),
      ),
    );
  }

  Color _eventColor(String eventType) {
    switch (eventType.toLowerCase()) {
      case 'meeting':
        return const Color(0xFFE0F2FE);
      case 'health':
        return const Color(0xFFECFDF5);
      case 'family':
        return const Color(0xFFF3E8FF);
      case 'shopping':
        return const Color(0xFFFCE7F3);
      case 'education':
        return const Color(0xFFE0F2FE);
      default:
        return const Color(0xFFF8FAFC);
    }
  }

  String _formatTimeRange(DateTime start, DateTime end, bool isAllDay) {
    if (isAllDay) return 'All day';
    final formatter = DateFormat('h:mm a');
    return '${formatter.format(start)} - ${formatter.format(end)}';
  }

  Future<Map<String, String>> _loadParticipantNames(
      List<_CalendarEvent> events,
      ) async {
    final ids = events.expand((event) => event.participantIds).toSet().toList();
    if (ids.isEmpty) return <String, String>{};

    final firestore = FirebaseFirestore.instance;
    final result = <String, String>{};

    for (int i = 0; i < ids.length; i += 10) {
      final batch = ids.sublist(i, math.min(i + 10, ids.length));
      final snapshot = await firestore
          .collection('users')
          .where(FieldPath.documentId, whereIn: batch)
          .get();

      for (final doc in snapshot.docs) {
        final data = doc.data();
        final name = (data['fullName'] ?? data['username'] ?? data['email'] ?? '')
            .toString()
            .trim();
        if (name.isNotEmpty) {
          result[doc.id] = name;
        }
      }
    }

    for (final id in ids) {
      result.putIfAbsent(id, () => 'Member');
    }

    return result;
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  Widget _buildFab(BuildContext context) {
    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const AddTaskScreen()),
        );
      },
      child: Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [accentColor, secondaryAccent],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: accentColor.withOpacity(0.3),
              blurRadius: 25,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: const Center(
          child: Icon(Icons.add, size: 28, color: Colors.white),
        ),
      ),
    );
  }

  Widget _buildBottomNav(BuildContext context) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 25, vertical: 17),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.8),
            border: const Border(
              top: BorderSide(color: Color(0xFFF1F5F9)),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _bottomNavItem(Icons.chat_bubble_outline, 'Memo', 0, onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const MemoScreen()),
                );
              }),
              _bottomNavItem(Icons.people, 'Family', 1, onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const SelectFamilyScreen()),
                );
              }),
              _bottomNavItem(Icons.calendar_today, 'Today', 2),
              _bottomNavItem(Icons.settings, 'Settings', 3, onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const SettingsScreen()),
                );
              }),
            ],
          ),
        ),
      ),
    );
  }

  Widget _bottomNavItem(
      IconData icon,
      String label,
      int index, {
        VoidCallback? onTap,
      }) {
    final selected = index == _selectedNavIndex;
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedNavIndex = index;
        });
        onTap?.call();
      },
      child: Column(
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
      ),
    );
  }
}

enum _FlowItemType { hourGap, minuteGap, event }

class _FlowItem {
  final _FlowItemType type;
  final double height;
  final String? leftLabel;
  final double leftTopPadding;
  final double lineTopPadding;
  final Alignment alignment;
  final double eventTopPadding;
  final double eventBottomPadding;
  final _CalendarEvent? event;

  const _FlowItem._({
    required this.type,
    required this.height,
    required this.leftLabel,
    required this.leftTopPadding,
    required this.lineTopPadding,
    required this.alignment,
    required this.eventTopPadding,
    required this.eventBottomPadding,
    required this.event,
  });

  factory _FlowItem.hourGap({
    required String label,
    required double height,
  }) {
    return _FlowItem._(
      type: _FlowItemType.hourGap,
      height: height,
      leftLabel: label,
      leftTopPadding: 8,
      lineTopPadding: _CalendarScreenState._lineTopOffset,
      alignment: Alignment.topCenter,
      eventTopPadding: 0,
      eventBottomPadding: 0,
      event: null,
    );
  }

  factory _FlowItem.minuteGap({
    String? label,
    required double height,
  }) {
    return _FlowItem._(
      type: _FlowItemType.minuteGap,
      height: height,
      leftLabel: label,
      leftTopPadding: 0,
      lineTopPadding: 0,
      alignment: Alignment.topCenter,
      eventTopPadding: 0,
      eventBottomPadding: 0,
      event: null,
    );
  }

  factory _FlowItem.event(_CalendarEvent event) {
    return _FlowItem._(
      type: _FlowItemType.event,
      height: _CalendarScreenState._eventCardHeight +
          _CalendarScreenState._cardTopGapFromMarker +
          _CalendarScreenState._cardBottomGap,
      leftLabel: null,
      leftTopPadding: 0,
      lineTopPadding: 0,
      alignment: Alignment.topCenter,
      eventTopPadding: _CalendarScreenState._cardTopGapFromMarker,
      eventBottomPadding: _CalendarScreenState._cardBottomGap,
      event: event,
    );
  }
}

class _CalendarEvent {
  final String id;
  final String title;
  final String description;
  final String eventType;
  final String familyId;
  final bool isAllDay;
  final String location;
  final List<String> participantIds;
  final int reminderMinutes;
  final String repeatType;
  final DateTime startTime;
  final DateTime endTime;
  final String status;
  final String createdBy;
  final DateTime? createdAt;

  _CalendarEvent({
    required this.id,
    required this.title,
    required this.description,
    required this.eventType,
    required this.familyId,
    required this.isAllDay,
    required this.location,
    required this.participantIds,
    required this.reminderMinutes,
    required this.repeatType,
    required this.startTime,
    required this.endTime,
    required this.status,
    required this.createdBy,
    required this.createdAt,
  });

  static _CalendarEvent? fromFirestore(
      DocumentSnapshot<Map<String, dynamic>> doc,
      ) {
    final data = doc.data();
    if (data == null) return null;

    final startTimestamp = data['startTime'];
    final endTimestamp = data['endTime'];

    if (startTimestamp is! Timestamp || endTimestamp is! Timestamp) {
      return null;
    }

    return _CalendarEvent(
      id: doc.id,
      title: (data['title'] ?? '').toString(),
      description: (data['description'] ?? '').toString(),
      eventType: (data['eventType'] ?? 'event').toString(),
      familyId: (data['familyId'] ?? '').toString(),
      isAllDay: data['isAllDay'] == true,
      location: (data['location'] ?? '').toString(),
      participantIds: List<String>.from(data['participantIds'] ?? const []),
      reminderMinutes: (data['reminderMinutes'] ?? 0) is int
          ? data['reminderMinutes'] as int
          : int.tryParse('${data['reminderMinutes']}') ?? 0,
      repeatType: (data['repeatType'] ?? 'none').toString(),
      startTime: startTimestamp.toDate(),
      endTime: endTimestamp.toDate(),
      status: (data['status'] ?? '').toString(),
      createdBy: (data['createdBy'] ?? '').toString(),
      createdAt: data['createdAt'] is Timestamp
          ? (data['createdAt'] as Timestamp).toDate()
          : null,
    );
  }
}