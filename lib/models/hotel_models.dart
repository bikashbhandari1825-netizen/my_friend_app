// models/hotel_models.dart
//
// Hotel Booking System — Phase 1: Firebase Data Structure & Microservice
// Schema। यो app मा अहिलेसम्म कतै पनि typed Firestore model class छैन (सबैतिर
// कच्चा Map<String, dynamic> नै प्रयोग हुन्छ — home_screen.dart/
// service_map_screen.dart हेर्नुहोस्), तर Hotel booking को दायरा (धेरै
// date/enum/nested field भएकोले) typed बनाउँदा गल्ती छिटो पक्रिन्छ।
// Firestore बाट/मा जाने bridge यहीँ `fromDoc`/`toMap` मार्फत हुन्छ — माथिल्लो
// UI तहले सधैँ यही class प्रयोग गर्ने, कहिल्यै कच्चा Map होइन।
//
// Firestore collections (सबै flat/top-level — serviceRequests कै उस्तै
// foreign-key-style ढाँचा, nested subcollection होइन, ताकि cross-hotel
// query (जस्तै "म्याचिङ मिति भएका सबै कोठा") सजिलो होस्):
//   hotels         — होटलको catalog जानकारी (Hotel)
//   rooms          — hotelId ले होटलसँग जोडिएको कोठा-प्रकार (HotelRoom)
//   hotel_bookings — प्रयोगकर्ताको बुकिङ (HotelBooking)
//   hotel_reviews  — होटल समीक्षा (HotelReview) — जानाजान `reviews` होइन,
//                    त्यो collection पहिल्यैदेखि worker/job review का लागि
//                    फरक schema मा प्रयोगमा छ (firestore.rules मा
//                    `match /reviews/{doc}` हेर्नुहोस्) — दुवैलाई एउटै
//                    collection मा मिसाउँदा schema/rules collision हुन्थ्यो।
import 'package:cloud_firestore/cloud_firestore.dart';

DateTime _tsToDate(dynamic v) {
  if (v is Timestamp) return v.toDate();
  if (v is DateTime) return v;
  return DateTime.fromMillisecondsSinceEpoch(0);
}

DateTime? _tsToDateOrNull(dynamic v) {
  if (v is Timestamp) return v.toDate();
  if (v is DateTime) return v;
  return null;
}

/// Hotel Registration/Onboarding — Super-Admin verification lifecycle।
/// नयाँ दर्ता गरिएको होटल सधैं `pending` बाटै सुरु हुन्छ (firestore.rules
/// ले creation मै यो जाँच्छ) — मालिक आफैंले यो field पछि बदल्न पाउँदैन,
/// admin (isAdmin()) ले मात्र `approved`/`rejected` तोक्छ। Guest-साइड
/// search (hotel_results_screen.dart) ले `approved` बाहेक कुनै पनि होटल
/// देखाउँदैन।
abstract class HotelVerificationStatus {
  static const pending = 'pending';
  static const approved = 'approved';
  static const rejected = 'rejected';
}

/// `hotels` collection।
class Hotel {
  final String id;
  final String name;
  final String description;
  final String address;
  final GeoPoint location;
  final List<String> amenities;
  final double starRating;
  final String rules;
  final List<String> images;
  final String checkInTime; // "HH:mm", जस्तै "14:00"
  final String checkOutTime; // "HH:mm", जस्तै "11:00"
  // Hotel Contact Numbers — front-desk को सिधा सम्पर्क नम्बर, owner/partner
  // खातासँग जोडिएको `users/{ownerId}.phone` (Booking Pass को "Call" बटनले
  // अहिलेसम्म प्रयोग गर्ने) भन्दा फरक — त्यो owner व्यक्तिको आफ्नै मोबाइल
  // हो, यो भने होटलकै आधिकारिक मोबाइल/landline (receptionist/counter staff
  // ले उठाउने, owner भिन्न ठाउँमा भए पनि)। Registration/Profile edit दुवैमा
  // अनिवार्य।
  final String officialMobileNumber;
  final String landlinePhone;
  // Detailed Rating Breakdown (Booking.com-style) — Super Admin ले मात्र
  // लेख्न/बदल्न पाउने प्रति-category score (/10, keys: Cleanliness/Comfort/
  // Facilities/Host/Location/Value for money/WiFi — hotel_detail_screen.dart
  // कै `kRatingCategories` सँगै मिल्ने)। खाली/नपुगेको category भए guest-साइड
  // UI ले overall `starRating` बाट deterministic estimate मा fallback गर्छ
  // (hotel_detail_screen.dart::_ratingBreakdownCard हेर्नुहोस्) — admin ले
  // अझै कुनै होटलको स्कोर नछोइकन पनि UI कहिल्यै खाली नदेखियोस्।
  final Map<String, double> categoryRatings;
  // Hotel Registration/Onboarding — self-registered होटलको मालिक (uid)।
  // Admin-seeded mock होटल (htl_1..htl_6) मा खाली नै रहन्छ।
  final String ownerId;
  // Hotel Registration/Onboarding — KYC (hotel_registration_screen.dart)।
  // Admin-seeded mock होटल मा लागू हुँदैन, त्यसैले डिफल्ट नै `approved`
  // (fromDoc मा पनि field नभेटिए उस्तै — पुरानो data नतोडियोस्)।
  final String businessRegNumber;
  final String panVatNumber;
  final List<String> documentUrls;
  final String status; // HotelVerificationStatus.* मध्ये एक
  // Owner Identity Verification (Face Liveness + OCR cross-match) — पहिले
  // यो flow मा owner-पहिचान भन्ने अवधारणा नै थिएन (होटल/व्यवसाय-स्तरका
  // कागजात मात्र)। सबै optional/additive — पुरानो/admin-seeded होटल
  // (खाली रहने) लाई असर नपरोस् भनेर, र hotel_verification_admin_screen.dart
  // जस्ता अरू उपभोक्ताले यी नचिने पनि पहिल्यैझैं राम्रोसँग काम गरिरहून्।
  final String ownerName;
  final String ownerDob;
  final String ownerCitizenshipFrontUrl;
  final String ownerCitizenshipBackUrl;
  final String ownerSelfieUrl;

  const Hotel({
    required this.id,
    required this.name,
    required this.description,
    required this.address,
    required this.location,
    required this.amenities,
    required this.starRating,
    required this.rules,
    required this.images,
    required this.checkInTime,
    required this.checkOutTime,
    this.officialMobileNumber = '',
    this.landlinePhone = '',
    this.categoryRatings = const {},
    this.ownerId = '',
    this.businessRegNumber = '',
    this.panVatNumber = '',
    this.documentUrls = const [],
    this.status = HotelVerificationStatus.approved,
    this.ownerName = '',
    this.ownerDob = '',
    this.ownerCitizenshipFrontUrl = '',
    this.ownerCitizenshipBackUrl = '',
    this.ownerSelfieUrl = '',
  });

  String get coverImage => images.isNotEmpty ? images.first : '';

  /// Hotel Partner Dashboard — Amenities/Photo editing ले यही प्रयोग गर्छ
  /// (बाँकी field सबै `final` भएकोले सिधै mutate गर्न मिल्दैन, नयाँ copy
  /// बनाएर `mockHotels` सूचीमा replace गरिन्छ)।
  Hotel copyWith({
    List<String>? amenities,
    List<String>? images,
    String? officialMobileNumber,
    String? landlinePhone,
    Map<String, double>? categoryRatings,
    String? ownerId,
  }) =>
      Hotel(
        id: id,
        name: name,
        description: description,
        address: address,
        location: location,
        amenities: amenities ?? this.amenities,
        starRating: starRating,
        rules: rules,
        images: images ?? this.images,
        checkInTime: checkInTime,
        checkOutTime: checkOutTime,
        officialMobileNumber: officialMobileNumber ?? this.officialMobileNumber,
        landlinePhone: landlinePhone ?? this.landlinePhone,
        categoryRatings: categoryRatings ?? this.categoryRatings,
        ownerId: ownerId ?? this.ownerId,
        businessRegNumber: businessRegNumber,
        panVatNumber: panVatNumber,
        documentUrls: documentUrls,
        status: status,
        ownerName: ownerName,
        ownerDob: ownerDob,
        ownerCitizenshipFrontUrl: ownerCitizenshipFrontUrl,
        ownerCitizenshipBackUrl: ownerCitizenshipBackUrl,
        ownerSelfieUrl: ownerSelfieUrl,
      );

  factory Hotel.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const <String, dynamic>{};
    return Hotel(
      id: doc.id,
      name: (d['name'] ?? '').toString(),
      description: (d['description'] ?? '').toString(),
      address: (d['address'] ?? '').toString(),
      location: (d['location'] as GeoPoint?) ?? const GeoPoint(0, 0),
      amenities: List<String>.from(d['amenities'] as List? ?? const []),
      starRating: (d['starRating'] as num?)?.toDouble() ?? 0,
      rules: (d['rules'] ?? '').toString(),
      images: List<String>.from(d['images'] as List? ?? const []),
      checkInTime: (d['checkInTime'] ?? '14:00').toString(),
      checkOutTime: (d['checkOutTime'] ?? '11:00').toString(),
      officialMobileNumber: (d['officialMobileNumber'] ?? '').toString(),
      landlinePhone: (d['landlinePhone'] ?? '').toString(),
      categoryRatings: (d['categoryRatings'] as Map<String, dynamic>? ?? const {})
          .map((k, v) => MapEntry(k, (v as num).toDouble())),
      ownerId: (d['ownerId'] ?? '').toString(),
      businessRegNumber: (d['businessRegNumber'] ?? '').toString(),
      panVatNumber: (d['panVatNumber'] ?? '').toString(),
      documentUrls: List<String>.from(d['documentUrls'] as List? ?? const []),
      status: (d['status'] ?? HotelVerificationStatus.approved).toString(),
      ownerName: (d['ownerName'] ?? '').toString(),
      ownerDob: (d['ownerDob'] ?? '').toString(),
      ownerCitizenshipFrontUrl:
          (d['ownerCitizenshipFrontUrl'] ?? '').toString(),
      ownerCitizenshipBackUrl:
          (d['ownerCitizenshipBackUrl'] ?? '').toString(),
      ownerSelfieUrl: (d['ownerSelfieUrl'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toMap() => {
        'name': name,
        'description': description,
        'address': address,
        'location': location,
        'amenities': amenities,
        'starRating': starRating,
        'ownerId': ownerId,
        'rules': rules,
        'images': images,
        'checkInTime': checkInTime,
        'checkOutTime': checkOutTime,
        'officialMobileNumber': officialMobileNumber,
        'landlinePhone': landlinePhone,
        'categoryRatings': categoryRatings,
        'businessRegNumber': businessRegNumber,
        'panVatNumber': panVatNumber,
        'documentUrls': documentUrls,
        'status': status,
        'ownerName': ownerName,
        'ownerDob': ownerDob,
        'ownerCitizenshipFrontUrl': ownerCitizenshipFrontUrl,
        'ownerCitizenshipBackUrl': ownerCitizenshipBackUrl,
        'ownerSelfieUrl': ownerSelfieUrl,
      };
}

/// कोठा-प्रकारका सामान्य preset — बन्द enum होइन (hotel partner ले नयाँ नाम
/// जस्तै "Family Room" पनि थप्न सक्ने), तर UI (filter chip/icon) ले चिन्ने
/// साझा मान यहीँ।
abstract class HotelRoomType {
  static const single = 'Single';
  static const deluxe = 'Deluxe';
  static const suite = 'Suite';
  static const presets = [single, deluxe, suite];

  /// Dynamic Smart Room Amenities — "Add Room" फारममा category छानेपछि
  /// यिनै default amenities स्वतः pre-check हुन्छन् (owner ले पछि आफैं
  /// कुनै पनि थप्ने/हटाउने गरी customize गर्न सक्छ — यो त सुरुको
  /// starting-point मात्र हो, लागू/अनिवार्य होइन)। Comprehensive Master
  /// List — app-भरि साझा हुने ८ global amenity (होटलको आफ्नै Info-tab
  /// amenity सँगै उस्तै, `kHotelAmenities`/hotel_common.dart हेर्नुहोस्)
  /// देखि room-विशेष comfort/luxury amenity (Smart TV, Jacuzzi, आदि)
  /// दुवै — पूरा combined सूची (चिप grid) यहाँ होइन, `hotel_partner_
  /// dashboard_screen.dart::_kRoomAmenityMasterList` मा (models तहले
  /// screens-तहको `kHotelAmenities` import नगर्नु भनेर layering जोगाउन)।
  static const Map<String, List<String>> defaultAmenities = {
    single: ['WiFi', 'AC', 'Smart TV', 'Desk / Workspace'],
    deluxe: [
      'WiFi',
      'AC',
      'Smart TV',
      'Coffee/Tea Maker',
      'Mini Fridge',
      'Balcony / Private Terrace',
      'Restaurant',
      'Breakfast',
    ],
    suite: [
      'WiFi',
      'Pool',
      'Spa',
      'Restaurant',
      'Parking',
      'Gym',
      'AC',
      'Breakfast',
      'Smart TV',
      'Coffee/Tea Maker',
      'Mini Fridge',
      'Balcony / Private Terrace',
      'Jacuzzi / Bathtub',
      'Mini Bar',
      'Living Area / Sofa',
    ],
  };
}

/// Receptionist/manager (Hotel Partner Dashboard) ले कोठा-युनिटको
/// housekeeping अवस्था तोक्ने ४ मान — `available` मात्र guest-booking
/// योग्य; बाँकी तीन (occupied/cleaning/out_of_order) ले त्यो कोठा
/// अस्थायी रूपमा सूचीबाट लुकाउँछ (`HotelRoom.isActive` हेर्नुहोस्)।
abstract class HotelRoomStatus {
  static const available = 'available';
  static const occupied = 'occupied';
  static const cleaning = 'cleaning';
  static const outOfOrder = 'out_of_order';
  static const presets = [available, occupied, cleaning, outOfOrder];
}

/// `rooms` collection।
class HotelRoom {
  final String id;
  final String hotelId;
  final String roomType;
  // Hotel Partner Dashboard — "Add Room" ले भर्ने कोठा नम्बर/नाम (जस्तै
  // "Room 101", "Suite 302")। `roomType` (Single/Deluxe/Suite — category)
  // भन्दा फरक — उस्तै category भित्र धेरै भौतिक कोठा छुट्याउनका लागि। पुरानो
  // doc (यो field थपिनुअघि सिर्जना भएका) मा खाली रहन सक्छ, UI ले त्यस्तोमा
  // `roomType` मै fallback गर्छ (हेर्नुहोस् `_RoomEditRow`/`_RoomTile`)।
  final String roomNumber;
  // Hotel Partner System (Phase: B2B dashboard) — receptionist/manager ले
  // यी दुई field live बदल्न सक्छन् (Room Status Toggle/Rate Management),
  // त्यसैले `final` होइन — बाँकी सबै field (hotelId/roomType/capacity/...)
  // झैं immutable छन् (ती partner-editable होइनन्, admin-मात्र catalog
  // structure)।
  double pricePerNight;
  final int capacity;
  final int totalInventory;
  final List<String> amenities;
  final List<String> images;
  String status; // HotelRoomStatus.* मध्ये एक

  HotelRoom({
    required this.id,
    required this.hotelId,
    required this.roomType,
    this.roomNumber = '',
    required this.pricePerNight,
    required this.capacity,
    required this.totalInventory,
    required this.amenities,
    required this.images,
    required this.status,
  });

  // booking-योग्य (guest ले देख्ने/छान्न सक्ने) कोठा — 'available' मात्र।
  // पुरानो Firestore doc (`fromDoc`) मा अझै 'active' भेटिए पनि उस्तै
  // गणना (backward-compatible)।
  bool get isActive => status == HotelRoomStatus.available || status == 'active';
  String get coverImage => images.isNotEmpty ? images.first : '';

  factory HotelRoom.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const <String, dynamic>{};
    return HotelRoom(
      id: doc.id,
      hotelId: (d['hotelId'] ?? '').toString(),
      roomType: (d['roomType'] ?? HotelRoomType.single).toString(),
      roomNumber: (d['roomNumber'] ?? '').toString(),
      pricePerNight: (d['pricePerNight'] as num?)?.toDouble() ?? 0,
      capacity: (d['capacity'] as num?)?.toInt() ?? 1,
      totalInventory: (d['totalInventory'] as num?)?.toInt() ?? 0,
      amenities: List<String>.from(d['amenities'] as List? ?? const []),
      images: List<String>.from(d['images'] as List? ?? const []),
      status: (d['status'] ?? HotelRoomStatus.available).toString(),
    );
  }

  Map<String, dynamic> toMap() => {
        'hotelId': hotelId,
        'roomType': roomType,
        'roomNumber': roomNumber,
        'pricePerNight': pricePerNight,
        'capacity': capacity,
        'totalInventory': totalInventory,
        'amenities': amenities,
        'images': images,
        'status': status,
      };
}

/// बुकिङको lifecycle — status string यही ४ मानमा मात्र सीमित राख्ने (UI र
/// Firestore rules दुवैतिर उही मान, serviceRequests कै `activeJobStatuses()`
/// जस्तै pattern)।
abstract class HotelBookingStatus {
  static const pending = 'pending';
  static const confirmed = 'confirmed';
  static const checkedIn = 'checked_in';
  static const cancelled = 'cancelled';
  // Hotel Partner Dashboard — receptionist ले "Mark No-Show" थिच्दा मात्र
  // (guest आफैंले कहिल्यै यो status मा जाँदैन)।
  static const noShow = 'no_show';
  // Booking Lifecycle — receptionist ले "Check-Out" थिच्दा मात्र (अघि
  // checked_in मै रहन्थ्यो — त्यहाँ Active Stays/Departures metric
  // (computeLiveStats) कहिल्यै decrement नहुने बग थियो, किनभने कुनै
  // terminal status नै थिएन)। यो नै stay-lifecycle को अन्तिम step हो।
  static const completed = 'completed';
}

// ── Acceptance-Gated Communication (Hotel) ───────────────────────────────
// Call/Video/Chat booking स्वीकृत (`confirmed`/`checked_in`) भएको क्षणदेखि
// नै स्थायी रूपमा खुल्ला रहन्छन् — कुनै थप registration/gating step बिना।
// `job_actions.dart` कै `kActiveJobStatuses`/`isCommunicationUnlocked` को
// उस्तै pattern, ride/service job भन्दा फरक booking status set भएकोले
// छुट्टै।
const kActiveHotelBookingStatuses = {
  HotelBookingStatus.confirmed,
  HotelBookingStatus.checkedIn,
};
// Communication Never Locks — booking status (completed/cancelled/no_show
// समेत) ले Call/Video/Chat बटन कहिल्यै नहटाउने — गर्नु पर्ने दुइटा मात्र:
// (१) त्यो होटलको साँचो partner खाता छ (ownerId non-empty, caller-साइडमै
// छुट्टै जाँचिन्छ), (२) बुकिङ कहिल्यै बनिसकेको छ। पहिले यहाँ
// `kActiveHotelBookingStatuses` (confirmed/checked_in) मात्र थियो — checkout/
// cancel भइसकेपछि Booking Pass/Partner Dashboard बाटै Call/Video/Message
// बटन हराउने, र ChatScreen मा "This job is completed. Chat & calls are
// closed" देखिने गुनासोको जड।
bool isHotelCommunicationUnlocked(String? status) => true;

abstract class HotelPaymentType {
  static const payAtHotel = 'pay_at_hotel';
  static const onlinePaid = 'online_paid';
}

/// `hotel_bookings` collection।
class HotelBooking {
  final String id;
  final String userId;
  final String hotelId;
  final String roomId;
  final DateTime checkInDate;
  final DateTime checkOutDate;
  final int guestsCount;
  final double totalPrice;
  // Unit Selector — बुकिङ गर्दा छानिएको भौतिक कोठा-इकाई संख्या (Booking.com
  // जस्तै "1 unit"/"2 units")। मूल Phase-1 मा थिएन — सधैं 1 मानिन्थ्यो।
  // पुरानो doc (यो field थपिनुअघि सिर्जना भएका) मा खाली रहन सक्छ, UI/गणना
  // दुवैतिर 1 मा fallback (तल `fromDoc`)।
  final int unitsCount;
  final String status;
  final String paymentType;
  final String qrCodeData;
  final DateTime createdAt;
  // मूल Phase-1 spec मा थिएनन् — Phase 4 को checkout "Guest details form"
  // (section 4) ले जम्मा गर्ने जानकारी कतै लेख्नु पर्ने भएकोले थपिएको।
  final String guestName;
  final String guestPhone;
  final String guestEmail;
  // Guest Booking Pass / Partner Dashboard Amenity Sync — booking सिर्जना
  // हुँदैकै क्षणको `room.amenities` स्नैपशट (पछि owner ले room amenities
  // बदले पनि यो बुकिङको आफ्नै रेकर्ड नबदलिने — किनभने तेस्रो पेज,
  // Hotel Partner Dashboard को booking row/QR Scan dialog, सिधै room
  // document जोडी नपढ्दै देखाउन सकोस् भन्ने हो)। पुरानो doc (यो field
  // थपिनुअघि सिर्जना भएका) मा खाली रहन सक्छ — UI ले त्यस्तोमा
  // `room.amenities` मा fallback गर्छ।
  final List<String> amenities;
  // Booking Lifecycle / Guest Logbook — साँचो QR Check-In/Check-Out भएको
  // क्षण (`updatePartnerBookingStatus` बाटै `FieldValue.serverTimestamp()`
  // ले लेख्ने) — `checkInDate`/`checkOutDate` (योजना गरिएको stay-मिति)
  // भन्दा फरक। कहिल्यै नभए (अझै checked-in/out नभएको) null नै रहन्छ।
  final DateTime? checkedInAt;
  final DateTime? checkedOutAt;
  // Fraud/No-Show Prevention — `paymentType == payAtHotel` हुँदा मात्र भरिने
  // (बाँकी online-pay booking मा दुवै खाली/शून्य नै रहन्छन्, पूरै totalPrice
  // नै अग्रिम तिरिसकेको हुने भएकोले छुट्टै token deposit चाहिँदैन)। साँचो
  // payment gateway यो app मा कतै छैन (checkout screen को "Pay Online" पनि
  // declare-your-own-reference sandbox मात्र हो) — त्यसैले "paid" भनेको
  // guest ले आफ्नै reference ID declare गरेको, admin/reception ले भेरिफाई
  // गर्ने भन्ने उस्तै pattern।
  final double depositAmount;
  final String depositReference;
  // Advanced Check-out — Settlement Confirmation Sheet (hotel_partner_
  // dashboard_screen.dart) मा receptionist ले check-out गर्दा घोषणा गर्ने
  // कुनै पनि pending room-service/incidental amount। यो app मा itemized
  // billing भन्ने अलग system कतै छैन (माथिकै deposit जस्तै, सबै sandbox/
  // declare-your-own-amount pattern) — शून्य भनेको कुनै थप शुल्क नभएको।
  final double checkoutAdditionalCharges;

  const HotelBooking({
    required this.id,
    required this.userId,
    required this.hotelId,
    required this.roomId,
    required this.checkInDate,
    required this.checkOutDate,
    required this.guestsCount,
    required this.totalPrice,
    this.unitsCount = 1,
    required this.status,
    required this.paymentType,
    required this.qrCodeData,
    required this.createdAt,
    this.guestName = '',
    this.guestPhone = '',
    this.guestEmail = '',
    this.amenities = const [],
    this.checkedInAt,
    this.checkedOutAt,
    this.depositAmount = 0,
    this.depositReference = '',
    this.checkoutAdditionalCharges = 0,
  });

  /// checkIn/checkOut बीचको रात संख्या — कम्तीमा १ (एउटै दिन छानिए पनि
  /// शून्य/ऋणात्मक नदेखियोस्)।
  int get nights =>
      checkOutDate.difference(checkInDate).inDays.clamp(1, 1000000);

  factory HotelBooking.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const <String, dynamic>{};
    return HotelBooking(
      id: doc.id,
      userId: (d['userId'] ?? '').toString(),
      hotelId: (d['hotelId'] ?? '').toString(),
      roomId: (d['roomId'] ?? '').toString(),
      checkInDate: _tsToDate(d['checkInDate']),
      checkOutDate: _tsToDate(d['checkOutDate']),
      guestsCount: (d['guestsCount'] as num?)?.toInt() ?? 1,
      totalPrice: (d['totalPrice'] as num?)?.toDouble() ?? 0,
      unitsCount: (d['unitsCount'] as num?)?.toInt() ?? 1,
      status: (d['status'] ?? HotelBookingStatus.pending).toString(),
      paymentType:
          (d['paymentType'] ?? HotelPaymentType.payAtHotel).toString(),
      qrCodeData: (d['qrCodeData'] ?? '').toString(),
      createdAt: _tsToDate(d['createdAt']),
      guestName: (d['guestName'] ?? '').toString(),
      guestPhone: (d['guestPhone'] ?? '').toString(),
      guestEmail: (d['guestEmail'] ?? '').toString(),
      amenities: List<String>.from(d['amenities'] as List? ?? const []),
      checkedInAt: _tsToDateOrNull(d['checkedInAt']),
      checkedOutAt: _tsToDateOrNull(d['checkedOutAt']),
      depositAmount: (d['depositAmount'] as num?)?.toDouble() ?? 0,
      depositReference: (d['depositReference'] ?? '').toString(),
      checkoutAdditionalCharges:
          (d['checkoutAdditionalCharges'] as num?)?.toDouble() ?? 0,
    );
  }

  /// `createdAt` जानाजान यहाँ छैन — त्यो सधैँ `FieldValue.serverTimestamp()`
  /// बाट नै आउनुपर्छ (client घडी भर पर्दैन), सिर्जना गर्ने कोडले छुट्टै थप्ने।
  Map<String, dynamic> toMap() => {
        'userId': userId,
        'hotelId': hotelId,
        'roomId': roomId,
        'checkInDate': Timestamp.fromDate(checkInDate),
        'checkOutDate': Timestamp.fromDate(checkOutDate),
        'guestsCount': guestsCount,
        'totalPrice': totalPrice,
        'unitsCount': unitsCount,
        'status': status,
        'paymentType': paymentType,
        'qrCodeData': qrCodeData,
        'guestName': guestName,
        'guestPhone': guestPhone,
        'guestEmail': guestEmail,
        'amenities': amenities,
        'depositAmount': depositAmount,
        'depositReference': depositReference,
      };
}

/// Detailed Rating Breakdown — guest Hotel Details स्क्रिनले देखाउने ७
/// category (Booking.com-style), `Hotel.categoryRatings` का keys यिनै
/// हुनुपर्छ — admin screen/guest screen/partner dashboard तीनैले यही एउटा
/// साझा क्रम/हिज्जे प्रयोग गर्छन्, आ-आफ्नै छुट्टै सूची होइन।
const List<String> kHotelRatingCategories = [
  'Cleanliness',
  'Comfort',
  'Facilities',
  'Host',
  'Location',
  'Value for money',
  'WiFi',
];

/// `hotel_reviews` collection।
class HotelReview {
  final String id;
  final String hotelId;
  final String userId;
  final double rating;
  final String comment;
  final DateTime createdAt;
  // Guest Quote Cards ("Guests who stayed here loved") — guest ले review
  // दिंदा आफैं भरेको प्रदर्शन-नाम/देश (कुनै साँचो KYC verification होइन,
  // ride/job review कै उस्तै self-declared caption मात्र)। पुरानो review
  // (यी field थपिनुअघि सिर्जना भएका) मा खाली रहन्छन् — UI ले त्यस्तोमा
  // "Guest"/कुनै flag नदेखाएर gracefully हाइड गर्छ।
  final String reviewerName;
  final String country;
  // Two-Tier Admin Control — Super Admin वा त्यो होटलकै partner (केवल
  // यही एउटा field, firestore.rules मा diff-limited) ले toggle गर्ने —
  // "Guests who stayed here loved" मा कुन review देखाउने भन्ने छनोट।
  final bool featured;

  const HotelReview({
    required this.id,
    required this.hotelId,
    required this.userId,
    required this.rating,
    required this.comment,
    required this.createdAt,
    this.reviewerName = '',
    this.country = '',
    this.featured = false,
  });

  factory HotelReview.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const <String, dynamic>{};
    return HotelReview(
      id: doc.id,
      hotelId: (d['hotelId'] ?? '').toString(),
      userId: (d['userId'] ?? '').toString(),
      rating: (d['rating'] as num?)?.toDouble() ?? 0,
      comment: (d['comment'] ?? '').toString(),
      createdAt: _tsToDate(d['createdAt']),
      reviewerName: (d['reviewerName'] ?? '').toString(),
      country: (d['country'] ?? '').toString(),
      featured: (d['featured'] ?? false) == true,
    );
  }

  Map<String, dynamic> toMap() => {
        'hotelId': hotelId,
        'userId': userId,
        'rating': rating,
        'comment': comment,
        'reviewerName': reviewerName,
        'country': country,
        'featured': featured,
      };
}
