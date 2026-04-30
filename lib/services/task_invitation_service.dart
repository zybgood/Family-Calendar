import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class TaskInvitationService {
  TaskInvitationService._();

  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  static Future<String> userDisplayName(String uid) async {
    if (uid.trim().isEmpty) return 'Member';

    final doc = await _firestore.collection('users').doc(uid).get();
    final data = doc.data();
    if (data == null) return 'Member';

    final name = (data['fullName'] ??
        data['name'] ??
        data['displayName'] ??
        data['username'] ??
        data['nickname'] ??
        data['email'] ??
        'Member')
        .toString()
        .trim();

    return name.isEmpty ? 'Member' : name;
  }

  static Future<void> createTaskInvitationNotifications({
    required String eventId,
    required String eventTitle,
    required String creatorId,
    required List<String> invitedUserIds,
  }) async {
    final cleanInvitedIds = invitedUserIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty && id != creatorId)
        .toSet()
        .toList();

    if (cleanInvitedIds.isEmpty) return;

    final creatorName = await userDisplayName(creatorId);
    final batch = _firestore.batch();
    final now = FieldValue.serverTimestamp();

    for (final inviteeId in cleanInvitedIds) {
      final inviteeName = await userDisplayName(inviteeId);

      batch.set(_firestore.collection('notifications').doc(), {
        'recipientId': inviteeId,
        'senderId': creatorId,
        'senderName': creatorName,
        'eventId': eventId,
        'eventTitle': eventTitle,
        'type': 'task_invitation',
        'title': 'New task invitation',
        'message': '$creatorName invite you to join the task：$eventTitle',
        'status': 'pending',
        'isRead': false,
        'createdAt': now,
        'updatedAt': now,
      });

      batch.set(_firestore.collection('notifications').doc(), {
        'recipientId': creatorId,
        'senderId': creatorId,
        'targetUserId': inviteeId,
        'targetUserName': inviteeName,
        'eventId': eventId,
        'eventTitle': eventTitle,
        'type': 'task_invitation_sent',
        'title': 'Invitation sent',
        'message': 'Invitation sent，wait for $inviteeName reply',
        'status': 'waiting',
        'isRead': false,
        'createdAt': now,
        'updatedAt': now,
      });
    }

    await batch.commit();
  }

  static Future<void> respondToInvitation({
    required String notificationId,
    required String eventId,
    required bool accepted,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw Exception('Please sign in first.');
    }

    final currentUid = user.uid;
    final notificationRef =
    _firestore.collection('notifications').doc(notificationId);
    final eventRef = _firestore.collection('events').doc(eventId);

    String creatorId = '';
    String eventTitle = '';
    bool shouldCreateReplyNotification = false;

    await _firestore.runTransaction((transaction) async {
      final notificationSnapshot = await transaction.get(notificationRef);
      if (!notificationSnapshot.exists) {
        throw Exception('Invitation not found.');
      }

      final notificationData =
          notificationSnapshot.data() ?? <String, dynamic>{};

      if ((notificationData['recipientId'] ?? '').toString() != currentUid) {
        throw Exception('This invitation does not belong to current user.');
      }

      final eventSnapshot = await transaction.get(eventRef);
      if (!eventSnapshot.exists) {
        transaction.delete(notificationRef);
        shouldCreateReplyNotification = false;
        return;
      }

      shouldCreateReplyNotification = true;

      final eventData = eventSnapshot.data() ?? <String, dynamic>{};

      creatorId =
          (eventData['createdBy'] ?? notificationData['senderId'] ?? '')
              .toString();
      eventTitle =
          (eventData['title'] ?? notificationData['eventTitle'] ?? 'Task')
              .toString();

      final participantIds =
      List<String>.from(eventData['participantIds'] ?? const []);
      final pendingIds =
      List<String>.from(eventData['pendingParticipantIds'] ?? const []);
      final acceptedIds =
      List<String>.from(eventData['acceptedParticipantIds'] ?? const []);
      final declinedIds =
      List<String>.from(eventData['declinedParticipantIds'] ?? const []);

      pendingIds.remove(currentUid);

      if (accepted) {
        if (!participantIds.contains(currentUid)) {
          participantIds.add(currentUid);
        }
        if (!acceptedIds.contains(currentUid)) {
          acceptedIds.add(currentUid);
        }
        declinedIds.remove(currentUid);
      } else {
        participantIds.remove(currentUid);
        acceptedIds.remove(currentUid);
        if (!declinedIds.contains(currentUid)) {
          declinedIds.add(currentUid);
        }
      }

      transaction.update(eventRef, {
        'participantIds': participantIds,
        'pendingParticipantIds': pendingIds,
        'acceptedParticipantIds': acceptedIds,
        'declinedParticipantIds': declinedIds,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      transaction.update(notificationRef, {
        'status': accepted ? 'accepted' : 'declined',
        'isRead': true,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });

    if (!shouldCreateReplyNotification) {
      return;
    }

    final userName = await userDisplayName(currentUid);

    await _firestore.collection('notifications').add({
      'recipientId': creatorId,
      'senderId': currentUid,
      'senderName': userName,
      'eventId': eventId,
      'eventTitle': eventTitle,
      'type': accepted
          ? 'task_invitation_accepted'
          : 'task_invitation_declined',
      'title': accepted ? 'Has been accepted' : 'Has been refused',
      'message': accepted
          ? '$userName has accepted the task：$eventTitle'
          : '$userName has refused the task：$eventTitle',
      'status': accepted ? 'accepted' : 'declined',
      'isRead': false,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  static Future<void> markAsRead(String notificationId) async {
    await _firestore.collection('notifications').doc(notificationId).update({
      'isRead': true,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }
}