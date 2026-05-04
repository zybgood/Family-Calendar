import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'task_invitation_service.dart';

class FamilyInvitationService {
  FamilyInvitationService._();

  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  static Future<void> createFamilyInvitation({
    required String recipientId,
    required String familyId,
    required String familyName,
    required String familyPhotoURL,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw Exception('Please sign in first.');
    }

    final senderId = user.uid;
    if (recipientId == senderId) {
      throw Exception('You cannot invite yourself.');
    }

    final senderName = await TaskInvitationService.userDisplayName(senderId);

    final duplicate = await _firestore
        .collection('notifications')
        .where('type', isEqualTo: 'family_invitation')
        .where('recipientId', isEqualTo: recipientId)
        .where('familyId', isEqualTo: familyId)
        .where('status', isEqualTo: 'pending')
        .limit(1)
        .get();

    if (duplicate.docs.isNotEmpty) {
      throw Exception('Invitation already sent. Please wait for a response.');
    }

    final now = FieldValue.serverTimestamp();

    await _firestore.collection('notifications').add({
      'recipientId': recipientId,
      'senderId': senderId,
      'senderName': senderName,
      'familyId': familyId,
      'familyName': familyName,
      'familyPhotoURL': familyPhotoURL,
      'type': 'family_invitation',
      'title': 'Family invitation',
      'message': '$senderName invite you to join the family：$familyName',
      'status': 'pending',
      'isRead': false,
      'createdAt': now,
      'updatedAt': now,
    });
  }

  static Future<void> respondToFamilyInvitation({
    required String notificationId,
    required bool accepted,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw Exception('Please sign in first.');
    }

    final currentUid = user.uid;
    final currentUserName = await TaskInvitationService.userDisplayName(currentUid);
    final notificationRef = _firestore.collection('notifications').doc(notificationId);

    await _firestore.runTransaction((tx) async {
      final notificationSnap = await tx.get(notificationRef);
      if (!notificationSnap.exists) throw Exception('Invitation not found.');

      final data = notificationSnap.data() ?? <String, dynamic>{};
      if ((data['recipientId'] ?? '').toString() != currentUid) {
        throw Exception('This invitation does not belong to current user.');
      }
      if ((data['status'] ?? '').toString() != 'pending') {
        throw Exception('This invitation has already been handled.');
      }

      final familyId = (data['familyId'] ?? '').toString();
      final familyName = (data['familyName'] ?? 'Family').toString();
      final familyPhotoURL = (data['familyPhotoURL'] ?? '').toString();
      final senderId = (data['senderId'] ?? '').toString();

      if (familyId.isEmpty) throw Exception('Family information is missing.');

      final familyRef = _firestore.collection('families').doc(familyId);
      final memberRef = familyRef.collection('members').doc(currentUid);
      final userFamilyRef = _firestore
          .collection('users')
          .doc(currentUid)
          .collection('families')
          .doc(familyId);

      if (accepted) {
        final familySnap = await tx.get(familyRef);
        if (!familySnap.exists) throw Exception('Family no longer exists.');

        final existingMember = await tx.get(memberRef);
        final existingUserFamily = await tx.get(userFamilyRef);
        final now = Timestamp.now();

        if (!existingMember.exists) {
          tx.set(memberRef, {
            'uid': currentUid,
            'nickname': currentUserName,
            'role': 'member',
            'familyRole': 'member',
            'status': 'active',
            'joinedAt': now,
          });
        }

        if (!existingUserFamily.exists) {
          tx.set(userFamilyRef, {
            'familyId': familyId,
            'familyName': familyName,
            'joinedAt': now,
            'photoURL': familyPhotoURL,
            'role': 'member',
          });
        }
      }

      tx.update(notificationRef, {
        'status': accepted ? 'accepted' : 'declined',
        'isRead': true,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (senderId.isNotEmpty) {
        tx.set(_firestore.collection('notifications').doc(), {
          'recipientId': senderId,
          'senderId': currentUid,
          'senderName': currentUserName,
          'familyId': familyId,
          'familyName': familyName,
          'type': accepted
              ? 'family_invitation_accepted'
              : 'family_invitation_declined',
          'title': accepted ? 'Family invitation accepted' : 'Family invitation refused',
          'message': accepted
              ? 'Accepted to join the family：$familyName'
              : 'Refused to join the family：$familyName',
          'status': accepted ? 'accepted' : 'declined',
          'isRead': false,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    });
  }
}
