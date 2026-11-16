// services/hotel_partner_service.dart
//
// Hotel Partner & Receptionist Management System — सबै B2B Firestore
// अनुरोध यहीँबाट (hotel_booking_service.dart कै उही "सबै लेखाइ/पढाइ एकै
// ठाउँमा" pattern)। "कुन होटल मैले managed गर्छु" भन्ने list
// `users/{uid}.partnerHotelIds` मा बस्छ — हाल कुनै admin-driven partner
// onboarding UI नभएकोले, [becomeDemoPartner] ले सबै mock होटल आफ्नै
// खातामा self-assign गर्छ (DEMO/dev shortcut मात्र — साँचो production मा
// यो admin-मात्रको काम हुनुपर्छ)।
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../app_globals.dart' show createNotificationForUser;
import '../data/hotel_mock_data.dart';
import '../models/hotel_models.dart';

final _db = FirebaseFirestore.instance;
const _opTimeout = Duration(seconds: 15);

/// वर्तमान प्रयोगकर्ताले managed गर्ने होटल ID हरू — खाली भए Partner Mode
/// Settings मा "Become a Hotel Partner (Demo)" मात्र देखिन्छ।
Stream<List<String>> myPartnerHotelIds() {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return Stream.value(const []);
  return _db.collection('users').doc(uid).snapshots().map((doc) {
    final raw = doc.data()?['partnerHotelIds'];
    return raw is List ? List<String>.from(raw) : const <String>[];
  });
}

/// DEMO shortcut — छुट्टै hotel-partner onboarding/admin UI नभएसम्मको
/// लागि, वर्तमान प्रयोगकर्तालाई सबै mock होटलको partner बनाउने।
Future<void> becomeDemoPartner() async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return;
  await _db.collection('users').doc(uid).set(
    {'partnerHotelIds': mockHotels.map((h) => h.id).toList()},
    SetOptions(merge: true),
  ).timeout(_opTimeout);
}

/// Hotel Registration/Onboarding — नयाँ दर्ता गरेको होटल आफ्नै
/// `partnerHotelIds` मा थप्ने (arrayUnion — [becomeDemoPartner] जस्तो
/// पूरै overwrite होइन, त्यसैले पहिल्यैदेखि अरू होटल managed गरिरहेको
/// भए ती गुम्दैनन्)।
Future<void> grantSelfHotelPartner(String hotelId) async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return;
  await _db.collection('users').doc(uid).set(
    {
      'partnerHotelIds': FieldValue.arrayUnion([hotelId])
    },
    SetOptions(merge: true),
  ).timeout(_opTimeout);
}

Future<void> leaveDemoPartnerMode() async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return;
  await _db
      .collection('users')
      .doc(uid)
      .set({'partnerHotelIds': <String>[]}, SetOptions(merge: true))
      .timeout(_opTimeout);
}

/// एउटा होटलका सबै बुकिङ — receptionist dashboard (Live Feed + Booking
/// Management) दुवैले यही स्ट्रिम प्रयोग गर्छन्।
Stream<List<HotelBooking>> bookingsForHotel(String hotelId) {
  return _db
      .collection('hotel_bookings')
      .where('hotelId', isEqualTo: hotelId)
      .snapshots()
      .map((snap) {
    final list = snap.docs.map(HotelBooking.fromDoc).toList();
    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list.where(_isRecentOrActive).toList();
  });
}

/// Dashboard Clutter Cleanup — ४ दिनभन्दा पुरानो भइसकेको cancelled/no-show/
/// completed (checked-out) बुकिङ (अब कहिल्यै active हुन नसक्ने, पुरानो भएर
/// मात्र dashboard भरिने) receptionist को live booking list बाट लुकाउने।
/// Firestore बाट साँच्चै मेटिँदैन (Guest Logbook, `allBookingsForHotel`,
/// ले अझै पूरा history देखाउँछ) — यो केवल यही "live/actionable" view-level
/// filter हो।
bool _isRecentOrActive(HotelBooking b) {
  const staleAfter = Duration(days: 4);
  final isStaleStatus = b.status == HotelBookingStatus.cancelled ||
      b.status == HotelBookingStatus.noShow ||
      b.status == HotelBookingStatus.completed;
  if (!isStaleStatus) return true;
  return DateTime.now().difference(b.checkOutDate) < staleAfter;
}

/// एउटा होटलका *सबै* बुकिङ (`_isRecentOrActive` फिल्टर बिना) — Guest
/// Logbook (पूरा history: past + present guest) ले यही प्रयोग गर्छ,
/// `bookingsForHotel` (Bookings tab, हाल-सक्रिय मात्र) भन्दा छुट्टै।
Stream<List<HotelBooking>> allBookingsForHotel(String hotelId) {
  return _db
      .collection('hotel_bookings')
      .where('hotelId', isEqualTo: hotelId)
      .snapshots()
      .map((snap) {
    final list = snap.docs.map(HotelBooking.fromDoc).toList();
    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  });
}

/// Check-In/No-Show/Cancel/Check-Out ले कोठाको housekeeping status मा
/// पार्ने असर — Check-In ले assigned Room Number लाई "occupied" बनाउँछ
/// (त्यो कोठा अब guest-साइड listing बाट लुक्छ, `HotelRoom.isActive`
/// हेर्नुहोस्); No-Show/Cancel ले फेरि "available" (guest कहिल्यै बसेन,
/// कोठा तुरुन्तै फेरि बुक्न मिल्छ); Check-Out (`completed`) ले "cleaning"
/// (guest बसिसक्यो — अर्को guest लाई दिनुअघि सफा नगरी available होइन)।
String? _roomStatusForBookingStatus(String bookingStatus) => switch (bookingStatus) {
      HotelBookingStatus.checkedIn => HotelRoomStatus.occupied,
      HotelBookingStatus.noShow => HotelRoomStatus.available,
      HotelBookingStatus.cancelled => HotelRoomStatus.available,
      HotelBookingStatus.completed => HotelRoomStatus.cleaning,
      _ => null,
    };

/// receptionist ले status बदल्ने (Confirm/Check-In/Check-Out/Cancel/
/// No-Show) — guest लाई पनि तुरुन्तै notification, सोही कोठाको Room
/// Number status स्वतः sync (माथि `_roomStatusForBookingStatus`), र
/// Check-In/Check-Out को साँचो क्षण (`checkedInAt`/`checkedOutAt`,
/// Guest Logbook + Customer Booking Pass बिल्ला दुवैका लागि) स्टाम्प।
Future<bool> updatePartnerBookingStatus(
    HotelBooking booking, String newStatus, String hotelName,
    {double? additionalCharges}) async {
  try {
    final updates = <String, dynamic>{'status': newStatus};
    if (newStatus == HotelBookingStatus.checkedIn) {
      updates['checkedInAt'] = FieldValue.serverTimestamp();
    } else if (newStatus == HotelBookingStatus.completed) {
      updates['checkedOutAt'] = FieldValue.serverTimestamp();
      // Advanced Check-out — Settlement Confirmation Sheet ले घोषणा गरेको
      // कुनै पनि pending room-service/incidental amount (0 भए पनि, "केही
      // बाँकी छैन" भनेर स्पष्ट रूपमा लेखिने — नलेखिएको/undefined भन्दा फरक)।
      if (additionalCharges != null) {
        updates['checkoutAdditionalCharges'] = additionalCharges;
      }
    }
    await _db
        .collection('hotel_bookings')
        .doc(booking.id)
        .update(updates)
        .timeout(_opTimeout);
    final roomStatus = _roomStatusForBookingStatus(newStatus);
    if (roomStatus != null && booking.roomId.isNotEmpty) {
      updateMockRoomStatus(booking.roomId, roomStatus);
    }
    final label = switch (newStatus) {
      HotelBookingStatus.confirmed => 'confirmed',
      HotelBookingStatus.checkedIn => 'checked in',
      HotelBookingStatus.cancelled => 'cancelled',
      HotelBookingStatus.noShow => 'marked as no-show',
      HotelBookingStatus.completed => 'checked out',
      _ => newStatus,
    };
    unawaited(createNotificationForUser(
      booking.userId,
      'Booking update — $hotelName',
      'Your booking is now $label.',
    ));
    return true;
  } catch (_) {
    return false;
  }
}

/// QR Scanner ले भेट्टाएको raw text (`booking.qrCodeData`, "KAAMMITRA-
/// HOTEL-<id>") बाट साँचो booking फेला पार्ने — check-in/out verification।
Future<HotelBooking?> findBookingByQrData(String qrData) async {
  try {
    // Booking-Privacy Fix — rules अनुसार partner ले आफ्नो होटलको बुकिङ मात्र
    // पढ्न पाउँछ, त्यसैले `qrCodeData` मात्रको खुला query होइन — QR मा
    // भएको id बाट सिधै त्यो एउटा doc (अरू होटलको भए permission-denied → null)।
    const prefix = 'KAAMMITRA-HOTEL-';
    final text = qrData.trim();
    if (!text.startsWith(prefix)) return null;
    final id = text.substring(prefix.length);
    if (id.isEmpty || id.contains('/')) return null;
    final doc = await _db
        .collection('hotel_bookings')
        .doc(id)
        .get()
        .timeout(_opTimeout);
    if (!doc.exists) return null;
    final booking = HotelBooking.fromDoc(doc);
    return booking.qrCodeData == text ? booking : null;
  } catch (_) {
    return null;
  }
}

/// Live Status Feed का लागि आजको arrival/departure/active-stay/revenue
/// जोड।
class HotelLiveStats {
  final int arrivalsToday;
  final int departuresToday;
  final int activeStays;
  final double totalRevenue;
  const HotelLiveStats({
    required this.arrivalsToday,
    required this.departuresToday,
    required this.activeStays,
    required this.totalRevenue,
  });
}

bool _isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

HotelLiveStats computeLiveStats(List<HotelBooking> bookings) {
  final today = DateTime.now();
  var arrivals = 0, departures = 0, active = 0;
  var revenue = 0.0;
  for (final b in bookings) {
    if (b.status == HotelBookingStatus.cancelled) continue;
    revenue += b.totalPrice;
    if (_isSameDay(b.checkInDate, today) &&
        (b.status == HotelBookingStatus.pending ||
            b.status == HotelBookingStatus.confirmed)) {
      arrivals++;
    }
    if (_isSameDay(b.checkOutDate, today) &&
        b.status == HotelBookingStatus.checkedIn) {
      departures++;
    }
    if (b.status == HotelBookingStatus.checkedIn) active++;
  }
  return HotelLiveStats(
    arrivalsToday: arrivals,
    departuresToday: departures,
    activeStays: active,
    totalRevenue: revenue,
  );
}
