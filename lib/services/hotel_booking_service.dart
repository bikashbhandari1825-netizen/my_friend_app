// services/hotel_booking_service.dart
//
// Hotel Booking System — Phase 4: inventory availability जाँच + बुकिङ
// सिर्जना/रद्द। सबै `hotel_bookings` लेखाइ/पढाइ यहीँबाट — UI (checkout/
// detail screen) ले सिधै Firestore नछोई यही service मार्फत मात्र, ताकि
// availability-गणना logic एकै ठाउँमा (duplicate नहोस्)।
//
// ⚠️ Known limitation (double-booking race): Firestore transaction ले
// arbitrary WHERE query लाई atomically लक गर्न सक्दैन (केवल `get()` गरिएका
// specific doc मात्र लक हुन्छन्, query result होइन)। यहाँको availability
// जाँच (`remainingRoomUnits`) एउटा सामान्य query हो — hard transaction
// भित्र होइन। त्यसैले ठ्याक्कै उही मिलिसेकेन्डमा दुई फरक प्रयोगकर्ताले
// आखिरी कोठा एकैचोटि बुक गरे (धेरै दुर्लभ तर सैद्धान्तिक रूपमा सम्भव) भने
// दुवै सफल हुनसक्छन्। बलियो (airtight) समाधानका लागि भविष्यमा
// `availability/{roomId}_{date}` जस्तो per-night counter document
// (transactional increment/decrement) थप्नु सिफारिस गरिन्छ — हाल
// best-effort (check-then-write, checkout screen खुल्दा र "Confirm"
// थिच्दा दुवैतिर पुनः-जाँच) नै, वास्तविक-विश्वका धेरै MVP बुकिङ
// सिस्टमले सुरुमा प्रयोग गर्ने उस्तै pattern।
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../app_globals.dart'
    show createNotification, createNotificationForUser;
import '../models/hotel_models.dart';

final _db = FirebaseFirestore.instance;

/// कुनै पनि Firestore अनुरोध (network हराएको/धेरै ढिलो भएको अवस्थामा)
/// यो भन्दा बढी समय नपर्खी स्पष्ट error दिने — "Confirm Booking" बटन
/// कहिल्यै अनन्तकालसम्म loading मा नअडोस् भनेर।
const _opTimeout = Duration(seconds: 15);

const _activeBookingStatuses = [
  HotelBookingStatus.pending,
  HotelBookingStatus.confirmed,
  HotelBookingStatus.checkedIn,
];

bool _overlaps(
        DateTime aStart, DateTime aEnd, DateTime bStart, DateTime bEnd) =>
    aStart.isBefore(bEnd) && aEnd.isAfter(bStart);

/// दिइएको मिति-दायरामा त्यो कोठा-प्रकारका कति युनिट अझै खाली छन् — यही
/// function होटल विवरण पेज (dates छानिएपछि "X left"/"Sold out") र checkout
/// (Confirm थिच्दा फेरि-जाँच) दुवैले बोलाउँछन्। Network/permission असफल भए
/// यहीँ catch नगरी caller लाई नै फैसला गर्न दिन rethrow गर्छ (स्पष्ट
/// `Exception` सहित) — caller (createHotelBooking/detail screen) ले
/// आ-आफ्नै सन्दर्भ अनुसार (block vs. cosmetic-skip) ह्यान्डल गर्छन्।
Future<int> remainingRoomUnits(
    HotelRoom room, DateTime checkIn, DateTime checkOut) async {
  // Booking-Privacy Fix — availability अब सर्भर (Cloud Function
  // `hotelRoomAvailability`, Admin SDK) ले गन्छ ताकि client ले अरूको बुकिङ
  // (guest नाम/फोन/इमेल सहित) पढ्नै नपरोस् (firestore.rules हेर्नुहोस्)।
  // Function अझै deploy नभएको (`not-found`) बेला मात्र पुरानो सिधा query
  // मा फर्कने — rules कडा भइसकेपछि त्यो permission-denied हुन्छ, त्यसैले
  // function पहिले deploy गर्नुपर्छ।
  try {
    final res = await FirebaseFunctions.instance
        .httpsCallable('hotelRoomAvailability')
        .call<Map<Object?, Object?>>({
      'roomId': room.id,
      'checkIn': checkIn.millisecondsSinceEpoch,
      'checkOut': checkOut.millisecondsSinceEpoch,
      'totalInventory': room.totalInventory,
    }).timeout(_opTimeout);
    final remaining = (res.data['remaining'] as num?)?.toInt();
    if (remaining != null) return remaining.clamp(0, room.totalInventory);
  } on TimeoutException {
    throw Exception(
        'Could not check room availability — the request timed out.');
  } on FirebaseFunctionsException catch (e) {
    if (e.code != 'not-found') {
      throw Exception('Could not check room availability (${e.code}).');
    }
    // function deploy भएको छैन — तल पुरानो तरिका।
  }
  final QuerySnapshot<Map<String, dynamic>> snap;
  try {
    snap = await _db
        .collection('hotel_bookings')
        .where('roomId', isEqualTo: room.id)
        .where('status', whereIn: _activeBookingStatuses)
        .get()
        .timeout(_opTimeout);
  } on TimeoutException {
    throw Exception(
        'Could not check room availability — the request timed out.');
  } on FirebaseException catch (e) {
    throw Exception('Could not check room availability (${e.code}).');
  }
  // Unit Selector — एउटै booking ले एकभन्दा बढी इकाई (`unitsCount`) ओगट्न
  // सक्ने भएकोले, अब overlapping booking *गन्ती* होइन, तिनका `unitsCount`
  // को *योग* नै घटाउने — पहिले हरेक booking लाई सधैं 1 इकाई मान्थ्यो, जसले
  // multi-unit booking पछि वास्तविक भन्दा बढी खाली इकाई देखाउँथ्यो (overbooking
  // जोखिम)। पुरानो doc (field नभएका) मा डिफल्ट 1 नै (fromDoc कै उस्तै)।
  final overlappingUnits = snap.docs.fold<int>(0, (acc, d) {
    final data = d.data();
    final ci = data['checkInDate'];
    final co = data['checkOutDate'];
    if (ci is! Timestamp || co is! Timestamp) return acc;
    if (!_overlaps(checkIn, checkOut, ci.toDate(), co.toDate())) return acc;
    final units = (data['unitsCount'] as num?)?.toInt() ?? 1;
    return acc + units;
  });
  return (room.totalInventory - overlappingUnits)
      .clamp(0, room.totalInventory);
}

class HotelBookingResult {
  final bool success;
  final String? error;
  final HotelBooking? booking;
  const HotelBookingResult({required this.success, this.error, this.booking});
}

/// बुकिङ सिर्जना — लेख्नुअघि नै फेरि availability जाँच्छ (checkout screen
/// खुल्दा र "Confirm" थिच्दा बीचको समयमा अरूले त्यही कोठा लिइसकेको नहोस्
/// भनेर — माथिको known-limitation note हेर्नुहोस्)। यो function कहिल्यै
/// exception throw गर्दैन — जे भए पनि (permission/timeout/अन्य) सधैँ
/// `HotelBookingResult(success:false, error:...)` फर्काउँछ, ताकि caller
/// (checkout screen) ले uncaught exception को कारण `_submitting` कहिल्यै
/// अनन्तकालसम्म `true` मै नअडोस् ("Confirm Booking" बटन सधैँ loading मै
/// अड्किने बगको साँचो मूल कारण — अघि `remainingRoomUnits` भित्रको
/// permission-denied यहाँसम्म uncaught आइपुग्थ्यो)।
Future<HotelBookingResult> createHotelBooking({
  required Hotel hotel,
  required HotelRoom room,
  required DateTime checkIn,
  required DateTime checkOut,
  required int guestsCount,
  required String guestName,
  required String guestPhone,
  required String guestEmail,
  required String paymentType,
  int unitsCount = 1,
  double depositAmount = 0,
  String depositReference = '',
}) async {
  try {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return const HotelBookingResult(
          success: false, error: 'You must be signed in to book.');
    }
    // Unit Selector — guest ले एकभन्दा बढी इकाई (जस्तै "2 units") छान्न
    // सक्ने भएकोले, अब कम्तीमा छानेको जति नै बाँकी (`>= unitsCount`) छ कि
    // भनेर जाँच्ने — पहिले सधैं `<= 0` (एक इकाईको मान्यता) मात्र थियो।
    final remaining = await remainingRoomUnits(room, checkIn, checkOut);
    if (remaining < unitsCount) {
      return HotelBookingResult(
          success: false,
          error: remaining <= 0
              ? 'Sorry, this room just sold out for these dates.'
              : 'Only $remaining unit${remaining == 1 ? '' : 's'} left for these dates.');
    }
    final nights = checkOut.difference(checkIn).inDays.clamp(1, 1000000);
    final totalPrice = room.pricePerNight * nights * unitsCount;
    final ref = _db.collection('hotel_bookings').doc();
    final qrData = 'KAAMMITRA-HOTEL-${ref.id}';
    final booking = HotelBooking(
      id: ref.id,
      userId: uid,
      hotelId: hotel.id,
      roomId: room.id,
      checkInDate: checkIn,
      checkOutDate: checkOut,
      guestsCount: guestsCount,
      totalPrice: totalPrice,
      unitsCount: unitsCount,
      status: HotelBookingStatus.confirmed,
      paymentType: paymentType,
      qrCodeData: qrData,
      createdAt: DateTime.now(),
      guestName: guestName,
      guestPhone: guestPhone,
      guestEmail: guestEmail,
      amenities: room.amenities,
      depositAmount: depositAmount,
      depositReference: depositReference,
    );
    await ref
        .set({
          ...booking.toMap(),
          'createdAt': FieldValue.serverTimestamp(),
        })
        .timeout(_opTimeout);
    unawaited(createNotification(
      'Booking Confirmed',
      '${hotel.name} · ${room.roomType} · $nights night${nights > 1 ? 's' : ''}',
    ));
    unawaited(_notifyHotelPartners(hotel, guestName, room, nights));
    return HotelBookingResult(success: true, booking: booking);
  } on TimeoutException {
    return const HotelBookingResult(
        success: false,
        error:
            'The request timed out. Please check your connection and try again.');
  } on FirebaseException catch (e) {
    return HotelBookingResult(
        success: false, error: 'Booking failed: ${e.message ?? e.code}');
  } catch (e) {
    return HotelBookingResult(success: false, error: 'Booking failed: $e');
  }
}

/// नयाँ बुकिङ हुनेबित्तिकै त्यो होटल managed गर्ने सबै hotel-partner/
/// receptionist लाई instant notification (Hotel Partner Dashboard, "Guest
/// Communication & Notification Alerts" section) — "कुन user यो होटलको
/// partner हो" भन्ने `users.partnerHotelIds array-contains hotelId` query
/// मार्फत (`users` collection कुनै पनि signed-in user ले unconditionally
/// पढ्न पाउने भएकोले यो query सुरक्षित — firestore.rules मा `match
/// /users/{uid}` हेर्नुहोस्)। best-effort मात्र — असफल भए पनि booking
/// आफैं पहिल्यै सफल भइसकेको हुन्छ।
Future<void> _notifyHotelPartners(
    Hotel hotel, String guestName, HotelRoom room, int nights) async {
  try {
    final snap = await _db
        .collection('users')
        .where('partnerHotelIds', arrayContains: hotel.id)
        .get()
        .timeout(_opTimeout);
    // मालिक (hotel.ownerId) `partnerHotelIds` सूचीमा नभए पनि सूचित हुन्छ।
    final notify = <String>{
      for (final doc in snap.docs) doc.id,
      if (hotel.ownerId.isNotEmpty) hotel.ownerId,
    };
    for (final uid in notify) {
      unawaited(createNotificationForUser(
        uid,
        'New booking — ${hotel.name}',
        '$guestName · ${room.roomType} · $nights night${nights > 1 ? 's' : ''}',
      ));
    }
  } catch (_) {
    // best-effort — guest-side booking यसमा कहिल्यै निर्भर हुँदैन।
  }
}

/// आफ्नै बुकिङ रद्द — `status` मात्र बदल्ने (firestore.rules कै
/// `hotel_bookings` update नियम — owner ले यही एउटा field मात्र आफैं
/// बदल्न पाउँछ, हेर्नुहोस्)। सफल भए/नभए `bool` फर्काउँछ — कहिल्यै throw
/// गर्दैन, caller (booking pass screen) ले सधैँ loading state सफा रिसेट
/// गर्न सकोस् भनेर।
Future<bool> cancelHotelBooking(HotelBooking booking, String hotelName) async {
  try {
    await _db
        .collection('hotel_bookings')
        .doc(booking.id)
        .update({'status': HotelBookingStatus.cancelled})
        .timeout(_opTimeout);
    unawaited(createNotification('Booking Cancelled', hotelName));
    return true;
  } catch (_) {
    return false;
  }
}

/// प्रयोगकर्ताको आफ्नै सबै hotel booking — नयाँ अघि।
Stream<List<HotelBooking>> myHotelBookings() {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return const Stream.empty();
  return _db
      .collection('hotel_bookings')
      .where('userId', isEqualTo: uid)
      .snapshots()
      .map((snap) {
    final list = snap.docs.map(HotelBooking.fromDoc).toList();
    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  });
}

/// Hotel owner को registered mobile number — Booking Pass को "Call" बटनले
/// सिधै native dialer (`tel:`) खोलोस् भनेर, in-app WebRTC होइन। `Hotel`
/// model मा आफैंमा फोन-नम्बर field छैन, त्यसैले मालिकको `users/{ownerId}`
/// doc बाट (driver/worker registration कै उस्तै `phone` field-name
/// convention, एकपटक मात्र fetch — यो लाइव-परिवर्तन हुने डेटा होइन)।
Future<String?> hotelOwnerPhone(String ownerId) async {
  if (ownerId.isEmpty) return null;
  try {
    final doc = await _db.collection('users').doc(ownerId).get();
    final phone = (doc.data()?['phone'] ?? '').toString().trim();
    return phone.isEmpty ? null : phone;
  } catch (_) {
    return null;
  }
}
