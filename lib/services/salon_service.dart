// services/salon_service.dart
//
// Salon / Beauty Appointment Booking — ग्राहक-पक्षको सबै Firestore/Function
// अनुरोध यहीँबाट (hotel_booking_service.dart कै "UI ले सिधै Firestore नछुने"
// pattern)। slot गणना र बुकिङ-लेखाइ दुवै Cloud Function (functions/salon.js)
// मा हुन्छ — यहाँ केवल callable र typed-error mapping छ। hotel module मा
// documented double-booking race यहाँ छैन: `bookSalonAppointment` Firestore
// transaction भित्र चल्छ।
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/salon_models.dart';

final _db = FirebaseFirestore.instance;
const _opTimeout = Duration(seconds: 20);

/// `FirebaseFunctionsException` लाई प्रयोगकर्ताले बुझ्ने वाक्यमा — function ले
/// आफैं पठाएको `message` (अंग्रेजी, user-facing) नै प्राथमिकता।
String _fnError(Object e) {
  if (e is TimeoutException) {
    return 'The request timed out. Please check your connection and try again.';
  }
  if (e is FirebaseFunctionsException) {
    if (e.code == 'not-found' && (e.message ?? '').toLowerCase() == 'not_found') {
      // function नै deploy नभएको अवस्था।
      return 'Appointment booking is not available yet. Please try again later.';
    }
    return e.message ?? 'Something went wrong (${e.code}).';
  }
  return 'Something went wrong: $e';
}

// ── Browse / profile ─────────────────────────────────────────────────────

/// सबै सक्रिय salon — रेटिङ अनुसार (धेरै → थोरै), त्यसपछि पुराना-अघि।
Stream<List<Salon>> activeSalons() {
  return _db
      .collection('salons')
      .where('status', isEqualTo: SalonStatus.active)
      .snapshots()
      .map((snap) {
    final list = snap.docs.map(Salon.fromDoc).toList();
    list.sort((a, b) {
      final r = b.avgRating.compareTo(a.avgRating);
      return r != 0 ? r : b.ratingCount.compareTo(a.ratingCount);
    });
    return list;
  });
}

Stream<Salon?> salonStream(String salonId) => _db
    .collection('salons')
    .doc(salonId)
    .snapshots()
    .map((d) => d.exists ? Salon.fromDoc(d) : null);

/// Service menu — निष्क्रिय (`active: false`) service ग्राहकलाई देखाइँदैन।
Stream<List<SalonService>> salonServices(String salonId,
    {bool includeInactive = false}) {
  return _db
      .collection('salons')
      .doc(salonId)
      .collection('services')
      .snapshots()
      .map((snap) {
    final list = snap.docs
        .map((d) => SalonService.fromDoc(salonId, d))
        .where((s) => includeInactive || s.active)
        .toList();
    list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return list;
  });
}

Stream<List<SalonStaff>> salonStaff(String salonId,
    {bool includeInactive = false}) {
  return _db
      .collection('salons')
      .doc(salonId)
      .collection('staff')
      .snapshots()
      .map((snap) {
    final list = snap.docs
        .map((d) => SalonStaff.fromDoc(salonId, d))
        .where((s) => includeInactive || s.active)
        .toList();
    list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return list;
  });
}

Stream<List<SalonReview>> salonReviews(String salonId) => _db
    .collection('salon_reviews')
    .where('salonId', isEqualTo: salonId)
    .orderBy('createdAt', descending: true)
    .limit(30)
    .snapshots()
    .map((s) => s.docs.map(SalonReview.fromDoc).toList());

// ── Slots + booking (Cloud Function) ─────────────────────────────────────

class SalonSlotsResult {
  final List<SalonSlot> slots;
  final int durationMin;
  final String? error;
  const SalonSlotsResult(this.slots, this.durationMin, {this.error});
}

/// त्यो मिति/service/staff का लागि खाली समय-स्लट। staff `null`/'any' भए सबै
/// योग्य staff मध्ये कुनै एक खाली भए पनि स्लट देखिन्छ।
Future<SalonSlotsResult> fetchSalonSlots({
  required String salonId,
  required DateTime date,
  required List<String> serviceIds,
  String? staffId,
}) async {
  try {
    final res = await FirebaseFunctions.instance
        .httpsCallable('salonAvailableSlots')
        .call<Map<Object?, Object?>>({
      'salonId': salonId,
      'date': salonDateKey(date),
      'serviceIds': serviceIds,
      'staffId': staffId ?? 'any',
    }).timeout(_opTimeout);
    final raw = (res.data['slots'] as List?) ?? const [];
    final slots = raw.map((e) {
      final m = Map<String, dynamic>.from(e as Map);
      return SalonSlot(
        DateTime.fromMillisecondsSinceEpoch((m['startMs'] as num).toInt()),
        List<String>.from(m['staffIds'] as List),
      );
    }).toList();
    return SalonSlotsResult(slots, (res.data['durationMin'] as num?)?.toInt() ?? 0);
  } catch (e) {
    return SalonSlotsResult(const [], 0, error: _fnError(e));
  }
}

class SalonBookingResult {
  final String? appointmentId;
  final String? error;
  const SalonBookingResult({this.appointmentId, this.error});
  bool get success => appointmentId != null;
}

/// बुकिङ — कहिल्यै throw गर्दैन (hotel `createHotelBooking` कै सम्झौता), सधैँ
/// `SalonBookingResult`। मूल्य/अवधि/staff server ले नै गणना गर्छ — यहाँबाट
/// मूल्य पठाइँदैन।
Future<SalonBookingResult> bookSalonAppointment({
  required Salon salon,
  required List<String> serviceIds,
  String? staffId,
  required DateTime start,
  required String customerName,
  required String customerPhone,
  required String paymentType,
  String paymentMethod = '',
  String paymentRef = '',
}) async {
  if (FirebaseAuth.instance.currentUser == null) {
    return const SalonBookingResult(error: 'You must be signed in to book.');
  }
  try {
    final res = await FirebaseFunctions.instance
        .httpsCallable('bookSalonAppointment')
        .call<Map<Object?, Object?>>({
      'salonId': salon.id,
      'serviceIds': serviceIds,
      'staffId': staffId ?? 'any',
      // salon कै स्थानीय मिति — start ग्राहकको device-समयमा बनेको भए पनि
      // salon को `tzOffsetMin` बाट मिति निकालिन्छ (device टाइमजोन फरक भए पनि)।
      'date': salonDateKey(_salonLocalDate(start, salon.tzOffsetMin)),
      'startMs': start.millisecondsSinceEpoch,
      'customerName': customerName,
      'customerPhone': customerPhone,
      'paymentType': paymentType,
      'paymentMethod': paymentMethod,
      'paymentRef': paymentRef,
    }).timeout(_opTimeout);
    final id = res.data['appointmentId']?.toString();
    if (id == null || id.isEmpty) {
      return const SalonBookingResult(error: 'Booking failed. Please try again.');
    }
    return SalonBookingResult(appointmentId: id);
  } catch (e) {
    return SalonBookingResult(error: _fnError(e));
  }
}

/// Salon को स्थानीय मिति — UTC instant + salon offset, फेरि UTC भागहरू मात्र।
DateTime _salonLocalDate(DateTime instant, int tzOffsetMin) {
  final shifted = instant.toUtc().add(Duration(minutes: tzOffsetMin));
  return DateTime(shifted.year, shifted.month, shifted.day);
}

/// यही फाइलबाहिर (slot screen) ले पनि salon-स्थानीय "आजको मिति" चाहिन्छ।
DateTime salonToday(Salon salon) =>
    _salonLocalDate(DateTime.now(), salon.tzOffsetMin);

/// स्लट/अपोइन्टमेन्टको समय salon-स्थानीय घडीमा (device टाइमजोन फरक भए पनि
/// salon ले देखाउने समय उही) — `h:mm AM/PM`।
String salonClock(DateTime instant, Salon? salon) {
  final shifted =
      instant.toUtc().add(Duration(minutes: salon?.tzOffsetMin ?? 345));
  final h = shifted.hour % 12 == 0 ? 12 : shifted.hour % 12;
  final m = shifted.minute.toString().padLeft(2, '0');
  return '$h:$m ${shifted.hour < 12 ? 'AM' : 'PM'}';
}

/// salon-स्थानीय मिति `Mon, 4 Nov`।
String salonDateLabel(DateTime instant, Salon? salon) {
  const wd = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  const mo = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];
  final s = instant.toUtc().add(Duration(minutes: salon?.tzOffsetMin ?? 345));
  return '${wd[s.weekday - 1]}, ${s.day} ${mo[s.month - 1]}';
}

// ── My appointments / cancel / review ────────────────────────────────────

Stream<List<SalonAppointment>> myAppointments() {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return const Stream.empty();
  return _db
      .collection('salon_appointments')
      .where('userId', isEqualTo: uid)
      .snapshots()
      .map((snap) {
    final list = snap.docs.map(SalonAppointment.fromDoc).toList();
    list.sort((a, b) => b.startAt.compareTo(a.startAt));
    return list;
  });
}

Stream<SalonAppointment?> appointmentStream(String id) => _db
    .collection('salon_appointments')
    .doc(id)
    .snapshots()
    .map((d) => d.exists ? SalonAppointment.fromDoc(d) : null);

/// आफ्नै बुकिङ रद्द — `status` मात्र बदल्ने (firestore.rules: ग्राहकले अरू
/// कुनै field बदल्न पाउँदैन, र केवल `confirmed` बाट)। स्लट स्वतः फेरि खाली।
Future<bool> cancelSalonAppointment(String appointmentId) async {
  try {
    await _db
        .collection('salon_appointments')
        .doc(appointmentId)
        .update({'status': SalonAppointmentStatus.cancelled}).timeout(_opTimeout);
    return true;
  } catch (_) {
    return false;
  }
}

/// Verified review — सफल भए `null`, नत्र error सन्देश।
Future<String?> submitSalonReview({
  required String appointmentId,
  required int rating,
  String comment = '',
}) async {
  try {
    await FirebaseFunctions.instance.httpsCallable('submitSalonReview').call({
      'appointmentId': appointmentId,
      'rating': rating,
      'comment': comment,
    }).timeout(_opTimeout);
    return null;
  } catch (e) {
    return _fnError(e);
  }
}
