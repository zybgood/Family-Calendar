import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/task_invitation_service.dart';
import '../services/family_invitation_service.dart';
import '../themes/app_theme.dart';

class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({Key? key}) : super(key: key);

  static const _primaryColor = Color(0xFF0F172A);
  static const _mutedColor = Color(0xFF64748B);
  static const _accentColor = Color(0xFFE2B736);

  @override
  Widget build(BuildContext context) {
    final statusBarHeight = MediaQuery.of(context).padding.top;

    return Scaffold(
      backgroundColor: AppTheme.pageBackground,
      body: Stack(
        children: [
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: statusBarHeight,
            child: const ColoredBox(color: AppTheme.headerBackground),
          ),
          SafeArea(
            child: Column(
              children: [
                _buildAppBar(context),
                Expanded(child: _buildBody(context)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAppBar(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
      decoration: const BoxDecoration(
        color: AppTheme.headerBackground,
        boxShadow: [AppTheme.headerShadow],
      ),
      child: Row(
        children: [
          AppTheme.backButton(
            context,
            onPressed: () => Navigator.of(context).pop(),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Notifications',
              textAlign: TextAlign.center,
              style: AppTheme.headlineStyle,
            ),
          ),
          const SizedBox(width: 48),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return const Center(child: Text('Please sign in first.'));
    }

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('notifications')
          .where('recipientId', isEqualTo: user.uid)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Center(child: Text('Failed to load notifications.'));
        }

        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final docs = [
          ...(snapshot.data?.docs ??
              const <QueryDocumentSnapshot<Map<String, dynamic>>>[])
        ]..sort((a, b) {
          final aTime = a.data()['createdAt'];
          final bTime = b.data()['createdAt'];
          final aDate = aTime is Timestamp
              ? aTime.toDate()
              : DateTime.fromMillisecondsSinceEpoch(0);
          final bDate = bTime is Timestamp
              ? bTime.toDate()
              : DateTime.fromMillisecondsSinceEpoch(0);
          return bDate.compareTo(aDate);
        });

        if (docs.isEmpty) {
          return const Center(child: Text('No notifications yet.'));
        }

        return ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 16),
          itemCount: docs.length,
          itemBuilder: (context, index) {
            return _buildNotificationCard(context, docs[index]);
          },
        );
      },
    );
  }

  Widget _buildNotificationCard(
      BuildContext context,
      QueryDocumentSnapshot<Map<String, dynamic>> doc,
      ) {
    final data = doc.data();

    final type = (data['type'] ?? '').toString();
    final title = (data['title'] ?? 'Notification').toString();
    final message = (data['message'] ?? '').toString();
    final eventTitle = (data['eventTitle'] ?? '').toString();
    final senderName = (data['senderName'] ?? '').toString();
    final familyName = (data['familyName'] ?? '').toString();
    final eventId = (data['eventId'] ?? '').toString();
    final status = (data['status'] ?? '').toString();
    final isRead = data['isRead'] == true;

    final createdAt =
    data['createdAt'] is Timestamp ? (data['createdAt'] as Timestamp).toDate() : null;

    final isTaskInvitation = type == 'task_invitation' && status == 'pending';
    final isFamilyInvitation = type == 'family_invitation' && status == 'pending';
    final isInvitation = isTaskInvitation || isFamilyInvitation;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () async {
          if (!isRead) {
            await TaskInvitationService.markAsRead(doc.id);
          }
        },
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isRead ? Colors.white : const Color(0xFFFFFBEB),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isRead
                  ? const Color(0xFFF1F5F9)
                  : const Color(0xFFFDE68A),
            ),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _iconForType(type),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        color: _primaryColor,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  if (!isRead)
                    Container(
                      width: 9,
                      height: 9,
                      decoration: const BoxDecoration(
                        color: Color(0xFFEF4444),
                        shape: BoxShape.circle,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              if (isInvitation) ...[
                Text(
                  isTaskInvitation
                      ? '任务名称：${eventTitle.isEmpty ? 'Task' : eventTitle}'
                      : '家庭名称：${familyName.isEmpty ? 'Family' : familyName}',
                  style: const TextStyle(
                    color: _primaryColor,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '邀请人：${senderName.isEmpty ? 'Member' : senderName}',
                  style: const TextStyle(color: _mutedColor, fontSize: 13),
                ),
              ] else
                Text(
                  message,
                  style: const TextStyle(color: _mutedColor, fontSize: 14),
                ),
              if (createdAt != null) ...[
                const SizedBox(height: 8),
                Text(
                  DateFormat('MMM d, HH:mm').format(createdAt),
                  style: const TextStyle(
                    color: Color(0xFF94A3B8),
                    fontSize: 12,
                  ),
                ),
              ],
              if (isInvitation) ...[
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => isTaskInvitation
                            ? _respondTask(
                                context,
                                notificationId: doc.id,
                                eventId: eventId,
                                accepted: false,
                              )
                            : _respondFamily(
                                context,
                                notificationId: doc.id,
                                accepted: false,
                              ),
                        child: const Text('拒绝'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _accentColor,
                          foregroundColor: Colors.white,
                        ),
                        onPressed: () => isTaskInvitation
                            ? _respondTask(
                                context,
                                notificationId: doc.id,
                                eventId: eventId,
                                accepted: true,
                              )
                            : _respondFamily(
                                context,
                                notificationId: doc.id,
                                accepted: true,
                              ),
                        child: const Text('接受'),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _respondTask(
      BuildContext context, {
        required String notificationId,
        required String eventId,
        required bool accepted,
      }) async {
    try {
      await TaskInvitationService.respondToInvitation(
        notificationId: notificationId,
        eventId: eventId,
        accepted: accepted,
      );

      if (!context.mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(accepted ? '已接受邀请' : '已拒绝邀请')),
      );
    } catch (e) {
      if (!context.mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('操作失败：$e')),
      );
    }
  }


  Future<void> _respondFamily(
      BuildContext context, {
        required String notificationId,
        required bool accepted,
      }) async {
    try {
      await FamilyInvitationService.respondToFamilyInvitation(
        notificationId: notificationId,
        accepted: accepted,
      );

      if (!context.mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(accepted ? '已接受邀请' : '已拒绝邀请')),
      );
    } catch (e) {
      if (!context.mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('操作失败：$e')),
      );
    }
  }
  Widget _iconForType(String type) {
    IconData icon;
    Color background;

    switch (type) {
      case 'task_invitation':
        icon = Icons.assignment;
        background = Colors.orange.shade600;
        break;
      case 'task_invitation_sent':
        icon = Icons.schedule_send;
        background = Colors.blue.shade500;
        break;
      case 'task_invitation_accepted':
        icon = Icons.check_circle;
        background = Colors.green.shade600;
        break;
      case 'task_invitation_declined':
        icon = Icons.cancel;
        background = Colors.red.shade500;
        break;
      case 'family_invitation':
        icon = Icons.group_add;
        background = Colors.deepPurple.shade400;
        break;
      case 'family_invitation_accepted':
        icon = Icons.how_to_reg;
        background = Colors.green.shade700;
        break;
      case 'family_invitation_declined':
        icon = Icons.person_off;
        background = Colors.red.shade700;
        break;
      default:
        icon = Icons.notifications;
        background = Colors.grey.shade500;
    }

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: background,
        shape: BoxShape.circle,
      ),
      child: Icon(icon, size: 22, color: Colors.white),
    );
  }
}