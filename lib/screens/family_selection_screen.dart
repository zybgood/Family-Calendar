import 'dart:ui';

import 'package:flutter/material.dart';

import 'family_screen.dart';

// Remote avatars (expires after ~7 days from Figma export)
const _avatar1 = 'https://www.figma.com/api/mcp/asset/a38506d9-8e64-45b1-93ab-b1e18f83e69e';
const _avatar2 = 'https://www.figma.com/api/mcp/asset/51ff2ec7-813c-4944-a4c3-916cf4aaaddc';
const _avatar3 = 'https://www.figma.com/api/mcp/asset/f8b63427-429a-4a69-bd63-b25f74fe06db';
const _avatar4 = 'https://www.figma.com/api/mcp/asset/0382f5d1-6d7c-4319-8d9d-087939698fc4';
const _avatar5 = 'https://www.figma.com/api/mcp/asset/3320c70a-e5bf-4888-bc8f-13c8b5ce741b';
const _avatar6 = 'https://www.figma.com/api/mcp/asset/ab68295f-48c2-43d1-a4af-c12be1ae41a2';
const _avatar7 = 'https://www.figma.com/api/mcp/asset/deaeb81f-2d2e-46ad-ac6c-361c966cd6b2';
const _avatar8 = 'https://www.figma.com/api/mcp/asset/73f6d153-7dc0-4b39-875e-459bb8f3d981';
const _avatar9 = 'https://www.figma.com/api/mcp/asset/d245a2c3-c270-40af-92fa-7c4ae5594204';

// Color constants
const _background = Color(0xFFFCFBF8);
const _headline = Color(0xFF0F172A);
const _accent = Color(0xFFFAC638);
const _border = Color.fromRGBO(255, 255, 255, 0.2);
const _buttonBg = Color(0xFFF3EEE0);

class FamilySelectionScreen extends StatefulWidget {
  const FamilySelectionScreen({Key? key}) : super(key: key);

  @override
  State<FamilySelectionScreen> createState() => _FamilySelectionScreenState();
}

class _FamilySelectionScreenState extends State<FamilySelectionScreen> {
  final List<_FamilyGroup> _groups = const [
    _FamilyGroup(
      id: 'family_001',
      name: 'Our Cozy Home',
      memberCount: 4,
      avatars: [_avatar1, _avatar2, _avatar3],
      extraCount: 1,
    ),
    _FamilyGroup(
      id: 'family_002',
      name: 'Smith Family',
      memberCount: 6,
      avatars: [_avatar4, _avatar5, _avatar6],
      extraCount: 3,
    ),
    _FamilyGroup(
      id: 'family_003',
      name: 'Grandma\'s House',
      memberCount: 3,
      avatars: [_avatar7, _avatar8, _avatar9],
      extraCount: 0,
    ),
  ];

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
                Positioned(top: 0, left: 0, right: 0, child: _buildTopBar()),
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
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: _buttonBg,
                borderRadius: BorderRadius.circular(9999),
              ),
              child: const Icon(
                Icons.arrow_back_ios_new,
                size: 14,
                color: _headline,
              ),
            ),
          ),
          const Expanded(
            child: Center(
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
          ),
          const SizedBox(width: 40),
        ],
      ),
    );
  }

  Widget _buildList() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: _groups
            .map(
              (group) => Padding(
            padding: const EdgeInsets.only(bottom: 24),
            child: _FamilyGroupCard(
              group: group,
              onSelectAll: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Selected all members from ${group.name}'),
                    duration: const Duration(seconds: 2),
                  ),
                );
              },
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
    );
  }
}

class _FamilyGroup {
  final String id;
  final String name;
  final int memberCount;
  final List<String> avatars;
  final int extraCount;

  const _FamilyGroup({
    required this.id,
    required this.name,
    required this.memberCount,
    required this.avatars,
    required this.extraCount,
  });
}

class _FamilyGroupCard extends StatelessWidget {
  final _FamilyGroup group;
  final VoidCallback? onSelectAll;
  final VoidCallback? onTap;

  const _FamilyGroupCard({
    Key? key,
    required this.group,
    this.onSelectAll,
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
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _buildAvatars(),
                GestureDetector(
                  onTap: onSelectAll,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    decoration: BoxDecoration(
                      color: _accent,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 2,
                          offset: const Offset(0, 1),
                        ),
                      ],
                    ),
                    child: const Text(
                      'Select All',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: _headline,
                      ),
                    ),
                  ),
                ),
              ],
            ),
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
        Transform.translate(
          offset: Offset(i > 0 ? -8 : 0, 0),
          child: Container(
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
                ),
              ),
            ),
          ),
        ),
      );
    }

    if (group.extraCount > 0) {
      children.add(
        Transform.translate(
          offset: const Offset(-8, 0),
          child: Container(
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
        ),
      );
    }

    return ClipRect(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: children,
      ),
    );
  }
}