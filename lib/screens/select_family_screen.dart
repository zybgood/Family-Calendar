import 'dart:ui';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'calendar_screen.dart';
import 'create_family_dialog.dart';
import 'family_screen.dart';
import 'memo_screen.dart';
import 'settings_screen.dart';

// Fallback avatars when member photoURL is empty
const _avatar1 =
    'https://www.figma.com/api/mcp/asset/5dc71948-299e-4b3b-8f45-10afbf1a750a';
const _avatar2 =
    'https://www.figma.com/api/mcp/asset/06ff95bd-fcec-4f6d-b260-778a17cbf7ae';
const _avatar3 =
    'https://www.figma.com/api/mcp/asset/d1a3cb03-516d-4788-a974-afeeb6c81cc1';
const _avatar4 =
    'https://www.figma.com/api/mcp/asset/03802e4e-f495-4b7e-902a-f25d65096656';
const _avatar5 =
    'https://www.figma.com/api/mcp/asset/99a00811-045c-47fa-8c19-8bb31fe139a4';
const _avatar6 =
    'https://www.figma.com/api/mcp/asset/436113e7-c2dd-46a7-85f6-0bbfb0be1806';
const _avatar7 =
    'https://www.figma.com/api/mcp/asset/c4ac9b5a-eb93-4cfe-bde6-ac024476efbd';
const _avatar8 =
    'https://www.figma.com/api/mcp/asset/86824d61-0625-4c86-8c95-a942c59dab7b';
const _avatar9 =
    'https://www.figma.com/api/mcp/asset/63ffd1a8-2bd8-4239-a051-a79bafc20a76';

const List<String> _fallbackAvatars = [
  _avatar1,
  _avatar2,
  _avatar3,
  _avatar4,
  _avatar5,
  _avatar6,
  _avatar7,
  _avatar8,
  _avatar9,
];

// Color constants
const _background = Color(0xFFFCFBF8);
const _headline = Color(0xFF0F172A);
const _accent = Color(0xFFFAC638);
const _border = Color.fromRGBO(255, 255, 255, 0.2);

class SelectFamilyScreen extends StatefulWidget {
  const SelectFamilyScreen({Key? key}) : super(key: key);

  @override
  State<SelectFamilyScreen> createState() => _SelectFamilyScreenState();
}

class _SelectFamilyScreenState extends State<SelectFamilyScreen> {
  int _selectedNavIndex = 1;
  late Future<List<_FamilyGroup>> _groupsFuture;

  @override
  void initState() {
    super.initState();
    _groupsFuture = _loadFamilies();
  }

  Future<void> _refreshFamilies() async {
    final future = _loadFamilies();
    setState(() {
      _groupsFuture = future;
    });
    await future;
  }

  Future<List<_FamilyGroup>> _loadFamilies() async {
    final currentUser = FirebaseAuth.instance.currentUser;

    if (currentUser == null) {
      throw Exception('Current user is null. Please login first.');
    }

    final String uid = currentUser.uid;
    final FirebaseFirestore firestore = FirebaseFirestore.instance;

    final membershipSnapshot = await firestore
        .collection('users')
        .doc(uid)
        .collection('families')
        .get();

    if (membershipSnapshot.docs.isEmpty) {
      return [];
    }

    final List<_FamilyGroup> result = [];

    for (int i = 0; i < membershipSnapshot.docs.length; i++) {
      final membershipData = membershipSnapshot.docs[i].data();
      final String familyId =
      (membershipData['familyId'] ?? '').toString().trim();

      if (familyId.isEmpty) {
        continue;
      }

      final familyDoc =
      await firestore.collection('families').doc(familyId).get();

      if (!familyDoc.exists) {
        continue;
      }

      final familyData = familyDoc.data() ?? {};

      final membersSnapshot = await firestore
          .collection('families')
          .doc(familyId)
          .collection('members')
          .get();

      final List<Map<String, dynamic>> membersPreview = [];
      final List<String> avatars = [];

      for (int j = 0; j < membersSnapshot.docs.length; j++) {
        final memberDoc = membersSnapshot.docs[j];
        final memberData = memberDoc.data();

        // 优先读字段 userId；如果没有，则默认文档 id 就是 userId
        final String memberUserId =
        (memberData['userId'] ?? memberDoc.id).toString().trim();

        if (memberUserId.isEmpty) {
          continue;
        }

        final userDoc =
        await firestore.collection('users').doc(memberUserId).get();

        if (!userDoc.exists) {
          continue;
        }

        final userData = userDoc.data() ?? {};
        final String fullName =
        (userData['fullName'] ?? userData['name'] ?? 'Unknown Member')
            .toString();
        final String photoUrl = (userData['photoURL'] ?? '').toString().trim();
        final String role = (memberData['role'] ?? 'member').toString();

        membersPreview.add({
          'userId': memberUserId,
          'name': fullName,
          'photoURL': photoUrl,
          'role': role,
        });

        if (avatars.length < 3) {
          if (photoUrl.isNotEmpty) {
            avatars.add(photoUrl);
          } else {
            avatars.add(_fallbackAvatars[(i + j) % _fallbackAvatars.length]);
          }
        }
      }

      if (avatars.isEmpty) {
        avatars.add(_fallbackAvatars[i % _fallbackAvatars.length]);
      }

      final int memberCount = membersPreview.length;
      final int extraCount = memberCount > 3 ? memberCount - 3 : 0;

      result.add(
        _FamilyGroup(
          id: familyId,
          name: (familyData['familyName'] ??
              membershipData['familyName'] ??
              'Unnamed Family')
              .toString(),
          memberCount: memberCount,
          avatars: avatars,
          extraCount: extraCount,
          description: (familyData['description'] ?? '').toString(),
          membersPreview: membersPreview,
        ),
      );
    }

    return result;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _background,
      body: SafeArea(
        child: Center(
          child: Container(
            width: 430,
            constraints: const BoxConstraints(maxWidth: 430),
            height: double.infinity,
            child: Stack(
              children: [
                Positioned.fill(
                  child: Column(
                    children: [
                      const SizedBox(height: 77),
                      Expanded(child: _buildList()),
                      const SizedBox(height: 242),
                    ],
                  ),
                ),
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: _buildTopBar(),
                ),
                Positioned(
                  left: 24,
                  right: 24,
                  bottom: 100,
                  child: _buildCreateFamilyButton(),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: _buildBottomNav(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Container(
      height: 77,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: const Center(
        child: Text(
          'Select Family',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: _headline,
            letterSpacing: -0.5,
          ),
        ),
      ),
    );
  }

  Widget _buildList() {
    return FutureBuilder<List<_FamilyGroup>>(
      future: _groupsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: _accent),
          );
        }

        if (snapshot.hasError) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.error_outline,
                  size: 40,
                  color: Colors.redAccent,
                ),
                const SizedBox(height: 12),
                Text(
                  'Failed to load families\n${snapshot.error}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: _headline,
                  ),
                ),
                const SizedBox(height: 16),
                GestureDetector(
                  onTap: _refreshFamilies,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: _accent,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Text(
                      'Retry',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: Colors.black87,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        }

        final groups = snapshot.data ?? [];

        if (groups.isEmpty) {
          return SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            child: const Column(
              children: [
                SizedBox(height: 80),
                Icon(Icons.groups_outlined, size: 44, color: Color(0xFF94A3B8)),
                SizedBox(height: 12),
                Text(
                  'No family found',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: _headline,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  'Create a new family or join one via invitation link',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          );
        }

        return RefreshIndicator(
          onRefresh: _refreshFamilies,
          color: _accent,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: groups
                  .map(
                    (group) => Padding(
                  padding: const EdgeInsets.only(bottom: 24),
                  child: _FamilyGroupCard(
                    group: group,
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => FamilyScreen(
                            familyId: group.id,
                            familyName: group.name,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              )
                  .toList(growable: false),
            ),
          ),
        );
      },
    );
  }

  Widget _buildCreateFamilyButton() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: _showCreateFamilyDialog,
          child: Container(
            height: 56,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [Color(0xFFFAC638), Color(0xFFF59E0B)],
              ),
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFFAC638).withOpacity(0.2),
                  blurRadius: 15,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: const [
                Icon(Icons.add, color: Colors.black87, size: 18),
                SizedBox(width: 8),
                Text(
                  'Create New Family',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: Colors.black87,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'You can join another group via invitation link',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: Color(0xFF64748B),
          ),
        ),
      ],
    );
  }

  void _showCreateFamilyDialog() async {
    await showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.3),
      builder: (context) {
        return const CreateFamilyDialog();
      },
    );

    _refreshFamilies();
  }

  Widget _buildBottomNav() {
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
              _navItem(Icons.chat_bubble_outline, 'Memo', 0, onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const MemoScreen()),
                );
              }),
              _navItem(Icons.people, 'Family', 1, onTap: null),
              _navItem(Icons.calendar_today, 'Today', 2, onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const CalendarScreen()),
                );
              }),
              _navItem(Icons.settings, 'Settings', 3, onTap: () {
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

  Widget _navItem(
      IconData icon,
      String label,
      int index, {
        VoidCallback? onTap,
      }) {
    final selected = index == _selectedNavIndex;
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 20,
            color: selected ? _accent : const Color(0xFF94A3B8),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
              color: selected ? _accent : const Color(0xFF94A3B8),
            ),
          ),
        ],
      ),
    );
  }
}

class _FamilyGroup {
  final String id;
  final String name;
  final int memberCount;
  final List<String> avatars;
  final int extraCount;
  final String description;
  final List<Map<String, dynamic>> membersPreview;

  const _FamilyGroup({
    required this.id,
    required this.name,
    required this.memberCount,
    required this.avatars,
    required this.extraCount,
    required this.description,
    required this.membersPreview,
  });
}

class _FamilyGroupCard extends StatelessWidget {
  final _FamilyGroup group;
  final VoidCallback? onTap;

  const _FamilyGroupCard({
    Key? key,
    required this.group,
    this.onTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(25),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.4),
          border: Border.all(color: _border),
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
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              group.name,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: _headline,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${group.memberCount} family members',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: _accent,
              ),
            ),
            const SizedBox(height: 16),
            _buildAvatars(),
          ],
        ),
      ),
    );
  }

  Widget _buildAvatars() {
    final avatars = group.avatars;
    final children = <Widget>[];

    for (var i = 0; i < avatars.length; i++) {
      children.add(
        Container(
          margin: EdgeInsets.only(left: i == 0 ? 0 : 0),
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0xFFFCFBF8), width: 2),
          ),
          child: ClipOval(
            child: Image.network(
              avatars[i],
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                color: Colors.grey.shade300,
                child: const Icon(Icons.person, size: 16, color: Colors.white),
              ),
            ),
          ),
        ),
      );
    }

    if (group.extraCount > 0) {
      children.add(
        Container(
          margin: const EdgeInsets.only(left: 0),
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: _accent.withOpacity(0.2),
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0xFFFCFBF8), width: 2),
          ),
          child: Center(
            child: Text(
              '+${group.extraCount}',
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                color: _accent,
              ),
            ),
          ),
        ),
      );
    }

    return Row(children: children);
  }
}