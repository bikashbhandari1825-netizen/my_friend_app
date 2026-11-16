// services/salon_chat_service.dart
//
// Salon ग्राहक ↔ salon मालिक सीधा Message / Voice / Video call — राइड/होटलमा
// बनाइएको साझा `ChatScreen` (र त्यसभित्रको `CallScreen`) लाई नै पुन:प्रयोग
// गरेर; नयाँ chat/call UI वा WebRTC कोड होइन।
//
// कुराकानी `salon_chats/{salonId}_{customerUid}` (ग्राहक-प्रति-salon एउटा) मा
// बस्छ — booking बिना पनि सम्पर्क गर्न मिलोस् भनेर। `ChatScreen` ले यही
// doc को `status == 'open'` हेरेर chat/call खुला मान्छ, र `chats/{id}`,
// `calls/{id}` (rules मा `isSalonChatParticipant`) साझा प्रयोग हुन्छन्।
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/salon_models.dart';
import '../screens/chat_screen.dart';

/// ग्राहकको नाम — users doc बाट, नभए Auth बाट, नभए "Customer"।
Future<String> _myDisplayName(User me) async {
  try {
    final d = (await FirebaseFirestore.instance
            .collection('users')
            .doc(me.uid)
            .get())
        .data();
    final name = (d?['name'] ??
            '${d?['firstName'] ?? ''} ${d?['lastName'] ?? ''}'.trim())
        .toString()
        .trim();
    if (name.isNotEmpty) return name;
  } catch (_) {}
  final n = (me.displayName ?? '').trim();
  return n.isEmpty ? 'Customer' : n;
}

/// ग्राहकले salon सँग chat खोल्छ। [callVideo] — null: सिधै chat; false: खुल्दा
/// voice call; true: खुल्दा video call। आफ्नै salon भए केही गर्दैन।
Future<void> openSalonChat(BuildContext context, Salon salon,
    {bool? callVideo}) async {
  final me = FirebaseAuth.instance.currentUser;
  final messenger = ScaffoldMessenger.of(context);
  final navigator = Navigator.of(context);
  if (me == null) {
    messenger.showSnackBar(const SnackBar(content: Text('Please log in first.')));
    return;
  }
  if (me.uid == salon.ownerId) return;
  final id = '${salon.id}_${me.uid}';
  final ref = FirebaseFirestore.instance.collection('salon_chats').doc(id);
  try {
    final snap = await ref.get();
    if (!snap.exists) {
      await ref.set({
        'salonId': salon.id,
        'salonName': salon.name,
        'ownerUid': salon.ownerId,
        'customerUid': me.uid,
        'customerName': await _myDisplayName(me),
        'participants': [me.uid, salon.ownerId],
        'status': 'open',
        'createdAt': FieldValue.serverTimestamp(),
      });
    }
  } catch (e) {
    messenger.showSnackBar(
        SnackBar(content: Text('Could not open chat: $e')));
    return;
  }
  navigator.push(MaterialPageRoute(
    builder: (_) => ChatScreen(
      requestId: id,
      workerName: salon.name,
      initialStatus: 'open',
      statusCollection: 'salon_chats',
      otherUid: salon.ownerId,
      unlockedStatuses: const {'open'},
      autoStartCallVideo: callVideo,
    ),
  ));
}

/// Salon मालिकले एउटा ग्राहकको chat खोल्छ (`salon_chats` को doc बाट)।
void openSalonChatAsOwner(
    BuildContext context, String chatId, Map<String, dynamic> data) {
  Navigator.of(context).push(MaterialPageRoute(
    builder: (_) => ChatScreen(
      requestId: chatId,
      workerName: (data['customerName'] ?? 'Customer').toString(),
      initialStatus: 'open',
      statusCollection: 'salon_chats',
      otherUid: (data['customerUid'] ?? '').toString(),
      unlockedStatuses: const {'open'},
    ),
  ));
}
