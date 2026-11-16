// services/salon_partner_service.dart
//
// Salon provider (मालिक/receptionist) पक्षका सबै Firestore/Function अनुरोध —
// hotel_partner_service.dart कै भूमिका। "म कुन salon चलाउँछु" भन्ने `salons`
// collection मा `ownerId == uid` query बाट आउँछ — hotel जस्तो `users` doc मा
// self-writable list छैन (त्यही privilege-escalation बग यहाँ दोहोर्‍याइएको छैन)।
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart' show Uint8List;

import '../models/salon_models.dart';
import 'upload_validation.dart';

final _db = FirebaseFirestore.instance;
const _opTimeout = Duration(seconds: 20);

/// वर्तमान प्रयोगकर्ताले दर्ता गरेका salon हरू (प्रायः एउटा)।
Stream<List<Salon>> mySalons() {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return Stream.value(const []);
  return _db
      .collection('salons')
      .where('ownerId', isEqualTo: uid)
      .snapshots()
      .map((s) => s.docs.map(Salon.fromDoc).toList());
}

/// नयाँ salon दर्ता — rules ले `ownerId == आफ्नै uid`, `status == 'pending'`
/// (admin ले approve गरेपछि मात्र 'active'), rating शून्य माग्छ।
Future<String> createSalon({
  required String name,
  required String category,
  required String address,
  required String phone,
  required String description,
}) async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) throw Exception('You must be signed in.');
  final ref = _db.collection('salons').doc();
  await ref.set({
    'ownerId': uid,
    'name': name.trim(),
    'category': category,
    'address': address.trim(),
    'phone': phone.trim(),
    'description': description.trim(),
    'status': SalonStatus.pending,
    'slotStepMin': 30,
    'tzOffsetMin': 345,
    'ratingSum': 0,
    'ratingCount': 0,
    'createdAt': FieldValue.serverTimestamp(),
  }).timeout(_opTimeout);
  // Admin लाई "नयाँ salon approval चाहिन्छ" भनेर सूचना — best-effort।
  try {
    await _db.collection('adminNotifications').add({
      'title': 'New salon awaiting approval',
      'body': '${name.trim()} ($category) registered. Open Admin → Salons to approve.',
      'read': false,
      'createdAt': FieldValue.serverTimestamp(),
    }).timeout(_opTimeout);
  } catch (_) {}
  return ref.id;
}

/// Salon logo / barber फोटो अपलोड गरेर download URL फर्काउँछ — फाइल
/// `salon_photos/{मालिकको uid}/{salonId}/` मा (storage.rules: पढ्ने सबै
/// signed-in, लेख्ने मालिक मात्र)। फाइल पहिल्यै `UploadValidation` ले
/// जाँचिएको हुनुपर्छ (picker मै, `pickSalonImage`)।
Future<String> uploadSalonImage(
    String salonId, String kind, Uint8List bytes, String fileName) async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) throw Exception('You must be signed in.');
  final ext = UploadValidation.safeExtension(fileName);
  final ref = FirebaseStorage.instance.ref(
      'salon_photos/$uid/$salonId/${kind}_${DateTime.now().millisecondsSinceEpoch}.$ext');
  final sniffed = UploadValidation.sniffMime(bytes);
  await ref
      .putData(bytes,
          SettableMetadata(contentType: sniffed.isNotEmpty ? sniffed : 'image/jpeg'))
      .timeout(const Duration(seconds: 60));
  return ref.getDownloadURL();
}

/// खाली string = logo हटाउने।
Future<void> setSalonLogo(String salonId, String url) => _db
    .collection('salons')
    .doc(salonId)
    .update({'logoUrl': url}).timeout(_opTimeout);

/// खाली string = cover हटाउने।
Future<void> setSalonCover(String salonId, String url) => _db
    .collection('salons')
    .doc(salonId)
    .update({'coverUrl': url}).timeout(_opTimeout);

Future<void> addSalonPortfolioPhoto(String salonId, String url) => _db
    .collection('salons')
    .doc(salonId)
    .update({'photos': FieldValue.arrayUnion([url])}).timeout(_opTimeout);

Future<void> removeSalonPortfolioPhoto(String salonId, String url) => _db
    .collection('salons')
    .doc(salonId)
    .update({'photos': FieldValue.arrayRemove([url])}).timeout(_opTimeout);

/// [active] null = status नछुने (pending/rejected salon को मालिकले status
/// बदल्न पाउँदैन — rules ले पनि रोक्छ)।
Future<void> updateSalonProfile(
  String salonId, {
  required String name,
  required String category,
  required String address,
  required String phone,
  required String description,
  required int slotStepMin,
  bool? active,
  String? logoUrl,
  String? coverUrl,
}) {
  return _db.collection('salons').doc(salonId).update({
    'name': name.trim(),
    'category': category,
    'address': address.trim(),
    'phone': phone.trim(),
    'description': description.trim(),
    'slotStepMin': slotStepMin,
    if (active != null)
      'status': active ? SalonStatus.active : SalonStatus.paused,
    if (logoUrl != null) 'logoUrl': logoUrl,
    if (coverUrl != null) 'coverUrl': coverUrl,
  }).timeout(_opTimeout);
}

// ── Admin: salon approval ────────────────────────────────────────────────

/// Admin का लागि सबै salon (नयाँ पहिले) — firestore.rules: `salons` पढ्न
/// signed-in सबैलाई मिल्छ, बदल्न admin मात्र।
Stream<List<Salon>> allSalonsForAdmin() => _db
    .collection('salons')
    .snapshots()
    .map((s) {
      final list = s.docs.map(Salon.fromDoc).toList();
      list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return list;
    });

/// Admin: approve (→ 'active', browse/बुकिङमा देखिने) वा reject (कारण सहित)।
Future<void> setSalonApproval(String salonId,
    {required bool approved, String reason = ''}) {
  return _db.collection('salons').doc(salonId).update({
    'status': approved ? SalonStatus.active : SalonStatus.rejected,
    'rejectionReason': approved ? '' : reason.trim(),
    'reviewedAt': FieldValue.serverTimestamp(),
  }).timeout(_opTimeout);
}

/// Service थप/सम्पादन (`serviceId == null` भए नयाँ)।
Future<void> saveSalonService(
  String salonId, {
  String? serviceId,
  required String name,
  required String description,
  required double price,
  required int durationMin,
  required bool active,
}) {
  final col = _db.collection('salons').doc(salonId).collection('services');
  return (serviceId == null ? col.doc() : col.doc(serviceId)).set({
    'name': name.trim(),
    'description': description.trim(),
    'price': price,
    'durationMin': durationMin,
    'active': active,
  }).timeout(_opTimeout);
}

/// मेटाउँदा पुराना बुकिङमा नाम snapshot (`serviceNames`) बाँकी रहन्छ।
Future<void> deleteSalonService(String salonId, String serviceId) => _db
    .collection('salons')
    .doc(salonId)
    .collection('services')
    .doc(serviceId)
    .delete()
    .timeout(_opTimeout);

Future<void> saveSalonStaff(
  String salonId, {
  String? staffId,
  required String name,
  required String title,
  required bool active,
  required List<String> serviceIds,
  required Map<int, SalonDayHours> hours,
  String photoUrl = '',
}) {
  final col = _db.collection('salons').doc(salonId).collection('staff');
  return (staffId == null ? col.doc() : col.doc(staffId)).set({
    'name': name.trim(),
    'title': title.trim(),
    'active': active,
    'serviceIds': serviceIds,
    'hours': SalonStaff.hoursToMap(hours),
    'photoUrl': photoUrl,
  }).timeout(_opTimeout);
}

Future<void> deleteSalonStaff(String salonId, String staffId) => _db
    .collection('salons')
    .doc(salonId)
    .collection('staff')
    .doc(staffId)
    .delete()
    .timeout(_opTimeout);

/// यो salon को सबै बुकिङ — आउँदो पहिले (startAt बढ्दो क्रम)।
Stream<List<SalonAppointment>> appointmentsForSalon(String salonId) {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return const Stream.empty();
  // `ownerId` पनि फिल्टरमा राखेको — rules ले query-level मा पनि जाँच्ने भएकोले
  // (मालिक बाहेक अरूको बुकिङ हुँदै नपढिने)।
  return _db
      .collection('salon_appointments')
      .where('ownerId', isEqualTo: uid)
      .where('salonId', isEqualTo: salonId)
      .snapshots()
      .map((snap) {
    final list = snap.docs.map(SalonAppointment.fromDoc).toList();
    list.sort((a, b) => a.startAt.compareTo(b.startAt));
    return list;
  });
}

/// Confirm/Complete/Cancel/No-show — rules ले `status`/`paymentStatus`/
/// `completedAt` मात्र बदल्न दिन्छ; 'completed' अपोइन्टमेन्ट सुरु भएपछि मात्र।
Future<String?> setAppointmentStatus(
    SalonAppointment a, String status) async {
  try {
    await _db.collection('salon_appointments').doc(a.id).update({
      'status': status,
      if (status == SalonAppointmentStatus.completed) ...{
        'completedAt': FieldValue.serverTimestamp(),
        // Pay-at-salon: सेवा सकिएपछि नगद लिइसकेको मानिन्छ; online-declared
        // मा भने provider ले अलग "Mark paid" ले मात्र पुष्टि गर्छ।
        if (a.paymentType == SalonPaymentType.paySalon) 'paymentStatus': 'paid',
      },
    }).timeout(_opTimeout);
    return null;
  } on FirebaseException catch (e) {
    return e.code == 'permission-denied'
        ? 'Not allowed — a visit can only be completed after its start time.'
        : 'Could not update (${e.code}).';
  } catch (e) {
    return 'Could not update: $e';
  }
}

/// ग्राहकले declare गरेको eSewa/Khalti reference provider ले आफ्नै app/
/// statement मा हेरेर "paid" पुष्टि गर्ने (हामी gateway verify गर्दैनौँ)।
Future<bool> markAppointmentPaid(String appointmentId) async {
  try {
    await _db
        .collection('salon_appointments')
        .doc(appointmentId)
        .update({'paymentStatus': 'paid'}).timeout(_opTimeout);
    return true;
  } catch (_) {
    return false;
  }
}

class SalonCheckInResult {
  final bool ok;
  final String? error;
  final bool alreadyCheckedIn;
  final String customerName;
  final String staffName;
  final List<String> serviceNames;
  final DateTime? start;
  final double totalPrice;
  final String paymentStatus;
  final String paymentType;
  const SalonCheckInResult({
    required this.ok,
    this.error,
    this.alreadyCheckedIn = false,
    this.customerName = '',
    this.staffName = '',
    this.serviceNames = const [],
    this.start,
    this.totalPrice = 0,
    this.paymentStatus = '',
    this.paymentType = '',
  });
}

/// QR payload लाई server ले प्रमाणित गरी `checked_in` बनाउँछ — token
/// मिल्नुपर्ने, यही salon को हुनुपर्ने, रद्द/पूरा भइसकेको नहुनुपर्ने।
Future<SalonCheckInResult> checkInByQr(String payload) async {
  try {
    final res = await FirebaseFunctions.instance
        .httpsCallable('salonCheckIn')
        .call<Map<Object?, Object?>>({'payload': payload}).timeout(_opTimeout);
    final d = Map<String, dynamic>.from(res.data);
    return SalonCheckInResult(
      ok: true,
      alreadyCheckedIn: d['alreadyCheckedIn'] == true,
      customerName: (d['customerName'] ?? '').toString(),
      staffName: (d['staffName'] ?? '').toString(),
      serviceNames: d['serviceNames'] is List
          ? List<String>.from(d['serviceNames'])
          : const [],
      start: d['startMs'] is num
          ? DateTime.fromMillisecondsSinceEpoch((d['startMs'] as num).toInt())
          : null,
      totalPrice: (d['totalPrice'] as num?)?.toDouble() ?? 0,
      paymentStatus: (d['paymentStatus'] ?? '').toString(),
      paymentType: (d['paymentType'] ?? '').toString(),
    );
  } on FirebaseFunctionsException catch (e) {
    return SalonCheckInResult(
        ok: false, error: e.message ?? 'Check-in failed (${e.code}).');
  } catch (e) {
    return SalonCheckInResult(ok: false, error: 'Check-in failed: $e');
  }
}

/// Test Helper (debug/profile मात्र, `!kReleaseMode` बटनबाट) — एक थिचाइमा
/// वर्तमान प्रयोगकर्ताको नाममा नमुना salon बनाउँछ: ३ सेवा, २ staff, हप्ताभरि
/// ०९:००–१८:००। सबै लेखाइ सामान्य `createSalon`/`saveSalon*` बाटै हुन्छ
/// (firestore.rules जस्ताको तस्तै लागू) — कुनै नयाँ खाता/विशेषाधिकार बनाउँदैन।
/// Customer तर्फबाट परीक्षण गर्न *अर्को* खाता चाहिन्छ (आफ्नै salon बुक गर्न
/// मिल्दैन — `bookSalonAppointment` ले रोक्छ)।
Future<String> createSampleSalon() async {
  final id = await createSalon(
    name: 'Test Barber & Salon',
    category: 'Barber',
    address: 'Test Street, Kathmandu',
    phone: '9800000000',
    description: 'Sample salon created for testing appointment booking.',
  );
  final svcCol = _db.collection('salons').doc(id).collection('services');
  final haircut = svcCol.doc().id;
  final beard = svcCol.doc().id;
  final facial = svcCol.doc().id;
  await saveSalonService(id,
      serviceId: haircut,
      name: 'Haircut',
      description: 'Classic cut and style',
      price: 500,
      durationMin: 30,
      active: true);
  await saveSalonService(id,
      serviceId: beard,
      name: 'Beard Trim',
      description: 'Shape and trim',
      price: 300,
      durationMin: 20,
      active: true);
  await saveSalonService(id,
      serviceId: facial,
      name: 'Facial',
      description: 'Cleansing facial',
      price: 1200,
      durationMin: 60,
      active: true);
  final week = <int, SalonDayHours>{
    for (var d = 1; d <= 7; d++) d: const SalonDayHours('09:00', '18:00'),
  };
  await saveSalonStaff(id,
      name: 'Ram',
      title: 'Senior Barber',
      active: true,
      serviceIds: [haircut, beard],
      hours: week);
  await saveSalonStaff(id,
      name: 'Sita',
      title: 'Stylist',
      active: true,
      serviceIds: [haircut, facial],
      hours: week);
  return id;
}
