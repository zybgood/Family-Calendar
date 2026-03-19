import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../assets/figma_assets.dart';
import 'family_selection_screen.dart';

class AddTaskScreen extends StatefulWidget {
  const AddTaskScreen({Key? key}) : super(key: key);

  @override
  State<AddTaskScreen> createState() => _AddTaskScreenState();
}

class _AddTaskScreenState extends State<AddTaskScreen> {
  static const _background = Color(0xFFFDFBF7);
  static const _card = Color(0xFFFAF6EB);
  static const _labelColor = Color(0xFFB08F4C);
  static const _primaryColor = Color(0xFF0F172A);
  static const _accentColor = Color(0xFFE2B736);

  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();

  bool _reminderEnabled = true;
  bool _isSaving = false;
  int _selectedCategoryIndex = 0;
  List<String> _selectedMembers = [];

  DateTime? _selectedDate;
  TimeOfDay? _selectedTime;

  static const _categories = [
    {
      'label': 'Education',
      'color': Color(0xFF3B82F6),
    },
    {
      'label': 'Family',
      'color': Color(0xFF8B5CF6),
    },
    {
      'label': 'Leisure',
      'color': Color(0xFFF97316),
    },
  ];

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedDate = DateTime(now.year, now.month, now.day);
    _selectedTime = TimeOfDay(hour: now.hour, minute: now.minute);
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
    return DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );
  }

  String _selectedEventType() {
    return (_categories[_selectedCategoryIndex]['label'] as String).toLowerCase();
  }

  Future<String?> _loadCurrentFamilyId(String uid) async {
    final userDoc =
    await FirebaseFirestore.instance.collection('users').doc(uid).get();
    final userData = userDoc.data();

    if (userData != null) {
      final directKeys = [
        'familyId',
        'currentFamilyId',
        'selectedFamilyId',
      ];

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

    final familyQuery = await FirebaseFirestore.instance
        .collection('families')
        .where('memberIds', arrayContains: uid)
        .limit(1)
        .get();

    if (familyQuery.docs.isNotEmpty) {
      return familyQuery.docs.first.id;
    }

    return null;
  }

  Future<List<String>> _loadParticipantIds(String currentUid) async {
    final ids = <String>{currentUid};

    if (_selectedMembers.isEmpty) {
      return ids.toList();
    }

    final snapshot = await FirebaseFirestore.instance.collection('users').get();

    for (final doc in snapshot.docs) {
      final data = doc.data();
      final fullName = (data['fullName'] ?? '').toString().trim();
      final username = (data['username'] ?? '').toString().trim();
      final email = (data['email'] ?? '').toString().trim();

      final matched = _selectedMembers.any(
            (name) =>
        name.toLowerCase() == fullName.toLowerCase() ||
            name.toLowerCase() == username.toLowerCase() ||
            name.toLowerCase() == email.toLowerCase(),
      );

      if (matched) {
        ids.add(doc.id);
      }
    }

    return ids.toList();
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
      final participantIds = await _loadParticipantIds(user.uid);
      final startTime = _buildStartDateTime();
      final endTime = startTime.add(const Duration(hours: 1));
      final now = Timestamp.now();

      await FirebaseFirestore.instance.collection('events').add({
        'title': title,
        'description': _notesController.text.trim(),
        'eventType': _selectedEventType(),
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFFDFBF7), Color(0xFFFFF7E1)],
          ),
        ),
        child: SafeArea(
          child: Stack(
            children: [
              Center(
                child: Container(
                  width: 430,
                  constraints: const BoxConstraints(maxWidth: 430),
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
                              const SizedBox(height: 20),
                              _buildCategoryChips(),
                              const SizedBox(height: 22),
                              _buildDateTimeCard(),
                              const SizedBox(height: 20),
                              _buildNotesSection(),
                              const SizedBox(height: 20),
                              _buildParticipantsSection(),
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
            ],
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

  Widget _buildCategoryChips() {
    return Row(
      children: List.generate(_categories.length, (index) {
        final item = _categories[index];
        final selected = index == _selectedCategoryIndex;
        final color = item['color'] as Color;

        return Padding(
          padding: EdgeInsets.only(right: index == _categories.length - 1 ? 0 : 8),
          child: InkWell(
            borderRadius: BorderRadius.circular(999),
            onTap: () {
              setState(() {
                _selectedCategoryIndex = index;
              });
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: selected ? color.withOpacity(0.12) : _card,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: selected ? color.withOpacity(0.35) : const Color(0xFFE8E2D2),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    item['label'] as String,
                    style: TextStyle(
                      color: selected ? color : const Color(0xFF64748B),
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }),
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
            style: const TextStyle(
              color: Color(0xFF334155),
              fontSize: 15,
            ),
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
              'Participants',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: _primaryColor,
              ),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const FamilySelectionScreen(),
                  ),
                );
              },
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: const Size(50, 32),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text(
                '+ Edit Member',
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
        Row(
          children: _selectedMembers.isNotEmpty
              ? _selectedMembers
              .map(
                (name) => Padding(
              padding: const EdgeInsets.only(right: 8.0),
              child: _buildMemberAvatar(name),
            ),
          )
              .toList()
              : [
            const CircleAvatar(
              radius: 22,
              backgroundColor: Color(0xFFDCE1E8),
              child: Icon(Icons.person, size: 22, color: Colors.white),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildMemberAvatar(String name) {
    final url = _memberAvatarUrl(name);
    return CircleAvatar(
      radius: 22,
      backgroundColor: const Color(0xFFDCE1E8),
      backgroundImage: NetworkImage(url),
    );
  }

  String _memberAvatarUrl(String name) {
    switch (name) {
      case 'Mom':
        return FigmaAssets.familyImgMom;
      case 'Dad':
        return FigmaAssets.familyImgDad;
      case 'Sister':
        return FigmaAssets.familyImgUncleArthur;
      case 'Brother':
        return FigmaAssets.familyImgCousinSarah;
      default:
        return FigmaAssets.familyImgMom;
    }
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
            child: const Icon(
              Icons.notifications,
              color: _accentColor,
            ),
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
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}