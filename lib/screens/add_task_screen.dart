import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'select_members_screen.dart';

class AddTaskScreen extends StatefulWidget {
  const AddTaskScreen({
    Key? key,
    this.initialTitle,
    this.initialNotes,
    this.initialDate,
    this.initialTime,
    this.initialCategory,
    this.initialReminderEnabled,
  }) : super(key: key);

  final String? initialTitle;
  final String? initialNotes;
  final DateTime? initialDate;
  final TimeOfDay? initialTime;
  final String? initialCategory;
  final bool? initialReminderEnabled;

  @override
  State<AddTaskScreen> createState() => _AddTaskScreenState();
}

class _AddTaskScreenState extends State<AddTaskScreen> {
  static const _background = Colors.white;
  static const _card = Color(0xFFFFF9EC);
  static const _labelColor = Color(0xFFB08F4C);
  static const _primaryColor = Color(0xFF0F172A);
  static const _accentColor = Color(0xFFFAC638);

  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();

  bool _reminderEnabled = true;
  bool _isSaving = false;
  String? _familyId;
  String _familyName = 'My Family';
  List<SelectedTaskMember> _selectedMembers = [];

  DateTime? _selectedDate;
  TimeOfDay? _selectedTime;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _titleController.text = widget.initialTitle?.trim() ?? '';
    _notesController.text = widget.initialNotes?.trim() ?? '';
    _selectedDate =
        widget.initialDate ?? DateTime(now.year, now.month, now.day);
    _selectedTime =
        widget.initialTime ?? TimeOfDay(hour: now.hour, minute: now.minute);
    _reminderEnabled = widget.initialReminderEnabled ?? true;

    _initializeFamilyContext();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final initialDate = _selectedDate ?? now;

    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 5),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: _accentColor,
              onPrimary: Colors.white,
              onSurface: _primaryColor,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _selectedDate = picked;
      });
    }
  }

  Future<void> _pickTime() async {
    final initialTime = _selectedTime ?? const TimeOfDay(hour: 9, minute: 0);

    final picked = await showTimePicker(
      context: context,
      initialTime: initialTime,
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
          child: Theme(
            data: Theme.of(context).copyWith(
              colorScheme: const ColorScheme.light(
                primary: _accentColor,
                onPrimary: Colors.white,
                onSurface: _primaryColor,
                surface: Colors.white,
              ),
              timePickerTheme: TimePickerThemeData(
                backgroundColor: Colors.white,
                dialBackgroundColor: const Color(0xFFFFF2CC),
                dialHandColor: _accentColor,
                hourMinuteColor: WidgetStateColor.resolveWith((states) {
                  if (states.contains(WidgetState.selected)) {
                    return _accentColor;
                  }
                  return const Color(0xFFFFF7E1);
                }),
                hourMinuteTextColor: WidgetStateColor.resolveWith((states) {
                  if (states.contains(WidgetState.selected)) {
                    return Colors.white;
                  }
                  return _primaryColor;
                }),
                dayPeriodColor: WidgetStateColor.resolveWith((states) {
                  if (states.contains(WidgetState.selected)) {
                    return _accentColor.withOpacity(0.18);
                  }
                  return const Color(0xFFFFF7E1);
                }),
                dayPeriodTextColor: WidgetStateColor.resolveWith((states) {
                  if (states.contains(WidgetState.selected)) {
                    return _accentColor;
                  }
                  return const Color(0xFF8A6D2F);
                }),
                entryModeIconColor: _accentColor,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(28),
                ),
              ),
            ),
            child: child!,
          ),
        );
      },
    );

    if (picked != null) {
      setState(() {
        _selectedTime = picked;
      });
    }
  }

  String _dateText() {
    if (_selectedDate == null) return 'Select date';
    return DateFormat('MM/dd/yyyy').format(_selectedDate!);
  }

  String _timeText() {
    if (_selectedTime == null) return 'Select time';
    final hour = _selectedTime!.hour.toString().padLeft(2, '0');
    final minute = _selectedTime!.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  DateTime _buildStartDateTime() {
    final date = _selectedDate!;
    final time = _selectedTime!;
    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  Future<void> _initializeFamilyContext() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final userDoc = await _loadCurrentUserDoc(user.uid);
      final userData = userDoc?.data() ?? <String, dynamic>{};

      final selfName =
          (userData['fullName'] ??
                  userData['name'] ??
                  userData['displayName'] ??
                  userData['username'] ??
                  userData['email'] ??
                  user.displayName ??
                  'Me')
              .toString()
              .trim();
      final selfAvatar =
          (userData['photoURL'] ??
                  userData['photoUrl'] ??
                  userData['avatar'] ??
                  user.photoURL ??
                  '')
              .toString()
              .trim();

      final familyId = await _loadCurrentFamilyId(user.uid);
      String familyName = _familyName;
      if (familyId != null && familyId.isNotEmpty) {
        final familyDoc = await FirebaseFirestore.instance
            .collection('families')
            .doc(familyId)
            .get();
        familyName = (familyDoc.data()?['familyName'] ?? 'My Family')
            .toString()
            .trim();
      }

      if (!mounted) return;
      setState(() {
        _familyId = familyId;
        _familyName = familyName.isEmpty ? 'My Family' : familyName;
        _selectedMembers = _mergeCurrentUserIntoMembers(
          currentUserId: user.uid,
          currentUserName: selfName.isEmpty ? 'Me' : selfName,
          currentUserAvatar: selfAvatar,
          members: _selectedMembers,
        );
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _selectedMembers = _mergeCurrentUserIntoMembers(
          currentUserId: user.uid,
          currentUserName: user.displayName?.trim().isNotEmpty == true
              ? user.displayName!.trim()
              : 'Me',
          currentUserAvatar: user.photoURL ?? '',
          members: _selectedMembers,
        );
      });
    }
  }

  Future<DocumentSnapshot<Map<String, dynamic>>?> _loadCurrentUserDoc(
    String uid,
  ) async {
    final firestore = FirebaseFirestore.instance;
    final directDoc = await firestore.collection('users').doc(uid).get();
    if (directDoc.exists) {
      return directDoc;
    }

    final query = await firestore
        .collection('users')
        .where('uid', isEqualTo: uid)
        .limit(1)
        .get();

    if (query.docs.isNotEmpty) {
      return query.docs.first;
    }

    return null;
  }

  Future<String?> _loadCurrentFamilyId(String uid) async {
    final firestore = FirebaseFirestore.instance;
    final memberships = await firestore
        .collection('users')
        .doc(uid)
        .collection('families')
        .limit(1)
        .get();

    if (memberships.docs.isNotEmpty) {
      final membershipData = memberships.docs.first.data();
      final membershipFamilyId =
          (membershipData['familyId'] ?? memberships.docs.first.id)
              .toString()
              .trim();
      if (membershipFamilyId.isNotEmpty) {
        return membershipFamilyId;
      }
    }

    final userDoc = await _loadCurrentUserDoc(uid);
    final userData = userDoc?.data();

    if (userData != null) {
      final directKeys = ['familyId', 'currentFamilyId', 'selectedFamilyId'];

      for (final key in directKeys) {
        final value = userData[key];
        if (value is String && value.trim().isNotEmpty) {
          return value.trim();
        }
      }

      final listKeys = ['familyIds', 'families'];
      for (final key in listKeys) {
        final value = userData[key];
        if (value is List && value.isNotEmpty) {
          final first = value.first;
          if (first is String && first.trim().isNotEmpty) {
            return first.trim();
          }
        }
      }
    }

    final familyMembership = await firestore
        .collectionGroup('members')
        .where('uid', isEqualTo: uid)
        .limit(1)
        .get();

    if (familyMembership.docs.isNotEmpty) {
      return familyMembership.docs.first.reference.parent.parent?.id;
    }

    return null;
  }

  List<SelectedTaskMember> _mergeCurrentUserIntoMembers({
    required String currentUserId,
    required String currentUserName,
    required String currentUserAvatar,
    required List<SelectedTaskMember> members,
  }) {
    final merged = <SelectedTaskMember>[
      SelectedTaskMember(
        id: currentUserId,
        name: currentUserName,
        avatarUrl: currentUserAvatar,
      ),
    ];

    for (final member in members) {
      if (member.id == currentUserId) continue;
      merged.add(member);
    }

    return merged;
  }

  List<String> _loadParticipantIds(String currentUid) {
    final ids = _selectedMembers.map((member) => member.id).toSet();
    ids.add(currentUid);
    return ids.toList();
  }

  Future<void> _selectMembers() async {
    var familyId = _familyId;
    if (familyId == null || familyId.isEmpty) {
      await _initializeFamilyContext();
      familyId = _familyId;
    }

    if (familyId == null || familyId.isEmpty) {
      _showMessage('Family not found. Please join or create a family first.');
      return;
    }

    final resolvedFamilyId = familyId;
    if (!mounted) return;

    final result = await Navigator.of(context).push<List<SelectedTaskMember>>(
      MaterialPageRoute(
        builder: (_) => SelectMembersScreen(
          initialSelectedIds: _selectedMembers
              .map((member) => member.id)
              .toList(),
          familyId: resolvedFamilyId,
          familyName: _familyName,
        ),
      ),
    );

    if (result == null || !mounted) return;

    final currentUser = FirebaseAuth.instance.currentUser;
    setState(() {
      _selectedMembers = currentUser == null
          ? result
          : _mergeCurrentUserIntoMembers(
              currentUserId: currentUser.uid,
              currentUserName: _selectedMembers.isNotEmpty
                  ? _selectedMembers.first.name
                  : (currentUser.displayName?.trim().isNotEmpty == true
                        ? currentUser.displayName!.trim()
                        : 'Me'),
              currentUserAvatar: _selectedMembers.isNotEmpty
                  ? _selectedMembers.first.avatarUrl
                  : (currentUser.photoURL ?? ''),
              members: result,
            );
    });
  }

  Future<void> _saveTask() async {
    final user = FirebaseAuth.instance.currentUser;
    final title = _titleController.text.trim();

    if (user == null) {
      _showMessage('Please sign in first.');
      return;
    }

    if (title.isEmpty) {
      _showMessage('Please enter task title.');
      return;
    }

    if (_selectedDate == null) {
      _showMessage('Please select date.');
      return;
    }

    if (_selectedTime == null) {
      _showMessage('Please select time.');
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      final familyId = await _loadCurrentFamilyId(user.uid) ?? user.uid;
      final participantIds = _loadParticipantIds(user.uid);
      final startTime = _buildStartDateTime();
      final endTime = startTime.add(const Duration(hours: 1));
      final now = Timestamp.now();

      await FirebaseFirestore.instance.collection('events').add({
        'title': title,
        'description': _notesController.text.trim(),
        'eventType': 'family',
        'familyId': familyId,
        'isAllDay': false,
        'location': '',
        'participantIds': participantIds,
        'reminderMinutes': _reminderEnabled ? 15 : 0,
        'repeatType': 'none',
        'startTime': Timestamp.fromDate(startTime),
        'endTime': Timestamp.fromDate(endTime),
        'status': 'active',
        'createdBy': user.uid,
        'createdAt': now,
      });

      if (!mounted) return;
      _showMessage('Task saved!');
      Navigator.of(context).pop(true);
    } catch (e) {
      _showMessage('Failed to save task: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _background,
      body: SafeArea(
        child: Center(
          child: SizedBox(
            width: 430,
            child: Column(
              children: [
                _buildHeader(context),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 18),
                        _buildTitleInput(),
                        const SizedBox(height: 22),
                        _buildDateTimeCard(),
                        const SizedBox(height: 20),
                        _buildParticipantsSection(),
                        const SizedBox(height: 20),
                        _buildNotesSection(),
                        const SizedBox(height: 20),
                        _buildReminderCard(),
                        const SizedBox(height: 32),
                        _buildSaveButton(context),
                        const SizedBox(height: 36),
                      ],
                    ),
                  ),
                ),
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
          InkWell(
            borderRadius: BorderRadius.circular(999),
            onTap: () => Navigator.of(context).pop(),
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(999),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.06),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: const Center(
                child: Icon(
                  Icons.arrow_back_ios_new,
                  size: 18,
                  color: _primaryColor,
                ),
              ),
            ),
          ),
          const Text(
            'Add Task',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: _primaryColor,
            ),
          ),
          const SizedBox(width: 40),
        ],
      ),
    );
  }

  Widget _buildTitleInput() {
    return Container(
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(20),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: TextField(
        controller: _titleController,
        decoration: const InputDecoration(
          hintText: 'Task title',
          hintStyle: TextStyle(
            color: Color(0xFF94A3B8),
            fontWeight: FontWeight.w500,
          ),
          border: InputBorder.none,
        ),
        style: const TextStyle(
          color: Color(0xFF334155),
          fontSize: 16,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _buildDateTimeCard() {
    return Container(
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(20),
      ),
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
      child: Column(
        children: [
          _buildDateTimeRow(
            icon: Icons.calendar_month,
            label: 'Date',
            value: _dateText(),
            onTap: _pickDate,
          ),
          const Divider(height: 24, thickness: 1, color: Color(0xFFEDE6D3)),
          _buildDateTimeRow(
            icon: Icons.access_time,
            label: 'Time',
            value: _timeText(),
            onTap: _pickTime,
          ),
        ],
      ),
    );
  }

  Widget _buildDateTimeRow({
    required IconData icon,
    required String label,
    required String value,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Icon(icon, color: _accentColor, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      color: _primaryColor,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    value,
                    style: const TextStyle(
                      color: Color(0xFF64748B),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Color(0xFF94A3B8)),
          ],
        ),
      ),
    );
  }

  Widget _buildNotesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: const [
            Icon(Icons.notes, size: 18, color: _labelColor),
            SizedBox(width: 8),
            Text(
              'NOTES',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: _labelColor,
                letterSpacing: 1.2,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          constraints: const BoxConstraints(minHeight: 120),
          decoration: BoxDecoration(
            color: _card,
            borderRadius: BorderRadius.circular(20),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: TextField(
            controller: _notesController,
            maxLines: null,
            minLines: 4,
            decoration: const InputDecoration(
              hintText: 'Add some extra details here...',
              hintStyle: TextStyle(
                color: Color(0xFF94A3B8),
                fontWeight: FontWeight.w500,
              ),
              border: InputBorder.none,
            ),
            style: const TextStyle(color: Color(0xFF334155), fontSize: 15),
          ),
        ),
      ],
    );
  }

  Widget _buildParticipantsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Family Members',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: _primaryColor,
              ),
            ),
            TextButton(
              onPressed: _selectMembers,
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: const Size(50, 32),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text(
                '+ Select',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: _accentColor,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (_selectedMembers.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
            decoration: BoxDecoration(
              color: _card,
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Text(
              'No family member selected yet.',
              style: TextStyle(
                color: Color(0xFF64748B),
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          )
        else
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: _selectedMembers
                .map((member) => _buildMemberChip(member))
                .toList(),
          ),
      ],
    );
  }

  Widget _buildMemberChip(SelectedTaskMember member) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFF2E7BF)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildMemberAvatar(member),
          const SizedBox(width: 10),
          Text(
            member.name,
            style: const TextStyle(
              color: _primaryColor,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMemberAvatar(SelectedTaskMember member) {
    final hasAvatar = member.avatarUrl.isNotEmpty;
    return CircleAvatar(
      radius: 18,
      backgroundColor: const Color(0xFFF4DFC0),
      backgroundImage: hasAvatar ? NetworkImage(member.avatarUrl) : null,
      child: hasAvatar
          ? null
          : Text(
              _memberInitials(member.name),
              style: const TextStyle(
                color: Color(0xFF8A6D2F),
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
    );
  }

  String _memberInitials(String name) {
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty);
    final initials = parts.take(2).map((part) => part[0]).join();
    return initials.isEmpty ? '?' : initials.toUpperCase();
  }

  Widget _buildReminderCard() {
    return Container(
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(20),
      ),
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: const Icon(Icons.notifications, color: _accentColor),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text(
                  'Reminders',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: _primaryColor,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  '15 minutes before',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: _reminderEnabled,
            activeColor: _accentColor,
            onChanged: (value) {
              setState(() {
                _reminderEnabled = value;
              });
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSaveButton(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFFDBA3C), Color(0xFFFFA800)],
          ),
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFEA9E22).withOpacity(0.35),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(24),
            onTap: _isSaving ? null : _saveTask,
            child: Center(
              child: _isSaving
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Text(
                      'Save Task',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: Colors.black,

                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
