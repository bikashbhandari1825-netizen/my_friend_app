// data/hotel_mock_data.dart
//
// Hotel Booking System — Phase 2 UI लाई Firestore मा साँचो hotel/room डेटा
// (हाल कुनै admin/partner panel छैन, त्यसैले खाली collection) नभई पनि पूरा
// देखाउन/टेस्ट गर्न सकिने in-memory mock dataset। Phase 3 मा यसलाई साँचो
// Firestore repository (`hotels`/`rooms` query) ले replace/augment गर्नेछ —
// UI तहले `Hotel`/`HotelRoom`/`HotelReview` model class मार्फत नै डेटा
// लिने भएकोले त्यो बेला screen कोड यथावत् रहन्छ, केवल डेटा-स्रोत बदलिन्छ।
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show ValueNotifier;

import '../models/hotel_models.dart';

String _img(String seed, int i) =>
    'https://picsum.photos/seed/$seed$i/800/600';

/// Hotel Partner Dashboard बाट Room Status/Rate बदलिँदा bump हुने — guest-
/// साइड search/results/detail screen ले यो listen गरेर तुरुन्तै rebuild
/// हुन्छन् (`ValueListenableBuilder`), ताकि partner को परिवर्तन सोही app
/// session भित्र सबैतिर "live" देखियोस्। (catalog अझै in-memory/mock भएकोले
/// restart सम्मै मात्र टिक्छ — माथिको file-doc comment हेर्नुहोस्।)
final ValueNotifier<int> hotelCatalogVersion = ValueNotifier(0);

void _touchCatalog() => hotelCatalogVersion.value++;

HotelRoom? _findMockRoom(String roomId) {
  for (final r in mockRooms) {
    if (r.id == roomId) return r;
  }
  return null;
}

/// Real-Time Room Status Sync — पहिले यहाँ `.update(fields)` (आंशिक field
/// मात्र, doc पहिल्यै अस्तित्वमा चाहिने) थियो, जुन mock seed कोठा (`rm_1_1`
/// आदि, कुनै `rooms/{id}` doc नै नभएको) मा सधैं NOT_FOUND भई चुपचाप
/// असफल हुन्थ्यो — त्यसैले seed होटलको room status partner ले बदले पनि
/// Firestore मा कहिल्यै persist नहुने, र guest-साइड live stream
/// (hotel_detail_screen.dart::roomsStreamForHotel) ले कहिल्यै नदेख्ने
/// गुनासोको जड। अब `.set(room.toMap(), merge:true)` — पूरै current room
/// data (केवल बदलिएको field मात्र होइन) पठाएर, ताकि पहिलोपटक लेखिंदा doc
/// मा `hotelId` लगायत सबै field सुरुदेखि नै भरिएको होस् (नत्र `where
/// ('hotelId', ...)` query ले त्यस्तो आंशिक doc कहिल्यै फेला पार्दैन)।
void _persistRoom(HotelRoom room) {
  FirebaseFirestore.instance
      .collection('rooms')
      .doc(room.id)
      .set(room.toMap(), SetOptions(merge: true))
      .catchError((_) {});
}

/// Hotel Partner Dashboard — कोठाको housekeeping status बदल्ने।
void updateMockRoomStatus(String roomId, String status) {
  final room = _findMockRoom(roomId);
  if (room == null) return;
  room.status = status;
  _touchCatalog();
  _persistRoom(room);
}

/// Hotel Partner Dashboard — कोठाको रात-भाडा बदल्ने (Rate Management)।
void updateMockRoomPrice(String roomId, double pricePerNight) {
  final room = _findMockRoom(roomId);
  if (room == null) return;
  room.pricePerNight = pricePerNight;
  _touchCatalog();
  _persistRoom(room);
}

/// Hotel Partner Dashboard — "Add Room" (नयाँ कोठा-प्रकार/दर)। साँचो
/// (self-registered) होटलका लागि Firestore `rooms` collection मा doc पनि
/// सिर्जना हुन्छ (firestore.rules ले त्यही होटलको `ownerId` जाँच्छ); mock
/// seed होटलका लागि भने त्यो लेखाइ असफल हुन्छ (कुनै `hotels/{id}` doc नै
/// नभएकोले owner-जाँच पास हुँदैन) — तर in-memory catalog मा जहिल्यै थपिन्छ,
/// ताकि demo session भरि नै देखिइरहोस्।
/// कोठाको फोटो अपलोड सुरु हुनुअघि नै (Storage path मा चाहिने) room-id चाहिँदा
/// — Firestore client SDK ले `.doc()` (कुनै `.set()`/network call बिना)
/// स्थानीय रूपमै तुरुन्तै नयाँ ID दिन्छ, पछि `addRoomToHotel(roomId: ...)`
/// लाई उही ID दोहोर्‍याएर दिए सोही doc मा लेखिन्छ।
String newRoomId() => FirebaseFirestore.instance.collection('rooms').doc().id;

Future<void> addRoomToHotel(
  String hotelId, {
  required String roomType,
  String roomNumber = '',
  required double pricePerNight,
  required int capacity,
  required int totalInventory,
  List<String> amenities = const [],
  List<String> images = const [],
  String? roomId,
}) async {
  final ref = FirebaseFirestore.instance
      .collection('rooms')
      .doc(roomId ?? FirebaseFirestore.instance.collection('rooms').doc().id);
  final room = HotelRoom(
    id: ref.id,
    hotelId: hotelId,
    roomType: roomType,
    roomNumber: roomNumber,
    pricePerNight: pricePerNight,
    capacity: capacity,
    totalInventory: totalInventory,
    amenities: amenities,
    images: images,
    status: HotelRoomStatus.available,
  );
  mockRooms.add(room);
  _touchCatalog();
  try {
    await ref.set(room.toMap());
  } catch (_) {
    // best-effort — mock seed होटल (कुनै साँचो `hotels` doc नभएको) का लागि
    // rules ले owner-जाँच पास गर्न नसक्ने भएकोले अपेक्षित असफलता।
  }
}

/// Hotel Partner Dashboard — Amenities सम्पादन। mock seed होटलका लागि
/// in-memory मात्र (restart सम्मै टिक्छ); self-registered होटलका लागि
/// Firestore `hotels/{id}.amenities` मा पनि (best-effort) लेखिन्छ।
void updateHotelAmenities(String hotelId, List<String> amenities) {
  final i = mockHotels.indexWhere((h) => h.id == hotelId);
  if (i == -1) return;
  mockHotels[i] = mockHotels[i].copyWith(amenities: amenities);
  _touchCatalog();
  FirebaseFirestore.instance
      .collection('hotels')
      .doc(hotelId)
      .update({'amenities': amenities}).catchError((_) {});
}

/// Hotel Partner Dashboard — Contact Number सम्पादन (officialMobileNumber/
/// landlinePhone)। mock seed होटलका लागि in-memory मात्र; self-registered
/// होटलका लागि Firestore मा पनि (best-effort) लेखिन्छ — `updateHotelAmenities`
/// कै उस्तै pattern।
void updateHotelContactNumbers(
    String hotelId, String officialMobileNumber, String landlinePhone) {
  final i = mockHotels.indexWhere((h) => h.id == hotelId);
  if (i == -1) return;
  mockHotels[i] = mockHotels[i].copyWith(
    officialMobileNumber: officialMobileNumber,
    landlinePhone: landlinePhone,
  );
  _touchCatalog();
  FirebaseFirestore.instance.collection('hotels').doc(hotelId).update({
    'officialMobileNumber': officialMobileNumber,
    'landlinePhone': landlinePhone,
  }).catchError((_) {});
}

/// Two-Tier Admin Control — Super Admin वा त्यो होटलकै partner ("Guest Quote"
/// छनोट, firestore.rules मा `featured`-मात्र diff-limited) ले review
/// feature/unfeature गर्ने। `.set(merge:true)` जानाजान (`.update()` होइन) —
/// seed review (`rv_1` आदि) को Firestore मा doc नभए पनि admin/partner को
/// toggle सधैं persist होस् भनेर (admin/partner कै प्रत्यक्ष अनुरोध,
/// best-effort cosmetic होइन)।
void setReviewFeatured(String reviewId, bool featured) {
  final i = mockReviews.indexWhere((r) => r.id == reviewId);
  if (i != -1) {
    final r = mockReviews[i];
    mockReviews[i] = HotelReview(
      id: r.id,
      hotelId: r.hotelId,
      userId: r.userId,
      rating: r.rating,
      comment: r.comment,
      createdAt: r.createdAt,
      reviewerName: r.reviewerName,
      country: r.country,
      featured: featured,
    );
  }
  _touchCatalog();
  FirebaseFirestore.instance
      .collection('hotel_reviews')
      .doc(reviewId)
      .set({'featured': featured}, SetOptions(merge: true)).catchError((_) {});
}

/// Super Admin — कुनै review जुनसुकै होटलको भए पनि globally मेटाउने।
Future<void> deleteHotelReview(String reviewId) async {
  mockReviews.removeWhere((r) => r.id == reviewId);
  _touchCatalog();
  try {
    await FirebaseFirestore.instance
        .collection('hotel_reviews')
        .doc(reviewId)
        .delete();
  } catch (_) {
    // seed review (कुनै Firestore doc नै नभएको) मेटाउँदा NOT_FOUND अपेक्षित —
    // in-memory list बाटै हटिसकेको छ, त्यति नै पर्याप्त।
  }
}

/// Super Admin — होटलको Detailed Rating Breakdown (`kHotelRatingCategories`
/// का ७ category, /10) सेट/सच्याउने। `.set(merge:true)` — unclaimed seed
/// होटल (`hotels/{id}` doc अझै नभएको) मा पनि admin को edit सधैं persist
/// होस् भनेर।
void updateHotelCategoryRatings(String hotelId, Map<String, double> ratings) {
  final i = mockHotels.indexWhere((h) => h.id == hotelId);
  if (i != -1) {
    mockHotels[i] = mockHotels[i].copyWith(categoryRatings: ratings);
  }
  _touchCatalog();
  FirebaseFirestore.instance
      .collection('hotels')
      .doc(hotelId)
      .set({'categoryRatings': ratings}, SetOptions(merge: true))
      .catchError((_) {});
}

/// Hotel Partner Dashboard — नयाँ फोटो थप्ने (अपलोड भइसकेको Storage URL)।
void addHotelPhoto(String hotelId, String url) {
  final i = mockHotels.indexWhere((h) => h.id == hotelId);
  if (i == -1) return;
  final images = [...mockHotels[i].images, url];
  mockHotels[i] = mockHotels[i].copyWith(images: images);
  _touchCatalog();
  FirebaseFirestore.instance
      .collection('hotels')
      .doc(hotelId)
      .update({'images': images}).catchError((_) {});
}

/// Hotel Partner Dashboard — फोटो हटाउने।
void removeHotelPhoto(String hotelId, String url) {
  final i = mockHotels.indexWhere((h) => h.id == hotelId);
  if (i == -1) return;
  final images = mockHotels[i].images.where((u) => u != url).toList();
  mockHotels[i] = mockHotels[i].copyWith(images: images);
  _touchCatalog();
  FirebaseFirestore.instance
      .collection('hotels')
      .doc(hotelId)
      .update({'images': images}).catchError((_) {});
}

/// Hotel Registration/Onboarding — नयाँ सिर्जना गरिएको होटल/कोठा यही
/// in-memory catalog मा पनि तुरुन्तै थप्ने, ताकि guest-साइड search/detail
/// (जसले यही `mockHotels`/`mockRooms` पढ्छन्) लाई छुट्टै कोड नचाहिकनै
/// तुरुन्तै देखियोस्। साँचो persistence भने Firestore `hotels`/`rooms`
/// collection मा नै (hotel_registration_screen.dart हेर्नुहोस्)।
void addHotelToCatalog(Hotel hotel, HotelRoom room) {
  if (mockHotels.every((h) => h.id != hotel.id)) mockHotels.add(hotel);
  if (mockRooms.every((r) => r.id != room.id)) mockRooms.add(room);
  _touchCatalog();
}

bool _firestoreHydrated = false;

/// Firestore मा साँचो (अघिल्लो session मा self-registered) होटल/कोठा भए
/// in-memory catalog मा हाइड्रेट गर्ने — ताकि app फेरि खोल्दा पनि आफैं
/// दर्ता गरेको होटल guest search मा देखिइरहोस् (केवल mock seed मात्र
/// होइन)। app session मा एकपटक मात्र, best-effort (असफल भए mock-only
/// सूची नै कायमै रहन्छ)।
Future<void> hydrateHotelsFromFirestore() async {
  if (_firestoreHydrated) return;
  _firestoreHydrated = true;
  try {
    final db = FirebaseFirestore.instance;
    final hotelsSnap = await db.collection('hotels').get();
    var changed = false;
    for (final doc in hotelsSnap.docs) {
      final i = mockHotels.indexWhere((h) => h.id == doc.id);
      if (i == -1) {
        mockHotels.add(Hotel.fromDoc(doc));
        changed = true;
        continue;
      }
      // Seed Hotel Claiming — पहिले यहाँ known (seed htl_1..htl_6) id भेटिए
      // सिधै `continue` हुन्थ्यो, Firestore मा जे लेखिए पनि कहिल्यै overlay
      // नहुने — त्यसैले कुनै seed होटललाई (admin/backend बाटै directly)
      // साँचो `ownerId` दिइए पनि app ले त्यो कहिल्यै नदेख्ने। अब त्यो एउटा
      // field मात्र (बाँकी सबै hardcoded seed data नै authoritative, कुनै
      // डेटा हराउने जोखिम बिना) — Firestore मा साँचो ownerId भेटिए overlay।
      final ownerId = (doc.data()['ownerId'] ?? '').toString();
      if (ownerId.isNotEmpty && mockHotels[i].ownerId != ownerId) {
        mockHotels[i] = mockHotels[i].copyWith(ownerId: ownerId);
        changed = true;
      }
    }
    final roomsSnap = await db.collection('rooms').get();
    final knownRoomIds = mockRooms.map((r) => r.id).toSet();
    for (final doc in roomsSnap.docs) {
      if (knownRoomIds.contains(doc.id)) continue;
      mockRooms.add(HotelRoom.fromDoc(doc));
      changed = true;
    }
    if (changed) _touchCatalog();
  } catch (_) {
    // best-effort — guest browsing mock-only सूचीमै जारी रहन्छ।
  }
}

final List<Hotel> mockHotels = [
  Hotel(
    id: 'htl_1',
    name: 'Kathmandu Grand Palace',
    description:
        'Thamel कै मुटुमा रहेको luxury होटल — rooftop view, spa, र 24/7 '
        'concierge सहित।',
    address: 'Thamel, Kathmandu',
    location: const GeoPoint(27.7154, 85.3123),
    amenities: const ['WiFi', 'Pool', 'Spa', 'Restaurant', 'Parking', 'Gym'],
    starRating: 5,
    rules: 'No smoking inside rooms. Pets not allowed. ID proof required at check-in.',
    images: [for (var i = 1; i <= 4; i++) _img('grand', i)],
    checkInTime: '14:00',
    checkOutTime: '12:00',
  ),
  Hotel(
    id: 'htl_2',
    name: 'Everest View Residency',
    description: 'शान्त वातावरण, पहाडको दृश्य सहितको पारिवारिक होटल।',
    address: 'Boudha, Kathmandu',
    location: const GeoPoint(27.7215, 85.3620),
    amenities: const ['WiFi', 'Breakfast', 'Parking', 'AC'],
    starRating: 4,
    rules: 'Check-in after 1 PM. Early check-in subject to availability.',
    images: [for (var i = 1; i <= 4; i++) _img('everest', i)],
    checkInTime: '13:00',
    checkOutTime: '11:00',
  ),
  Hotel(
    id: 'htl_3',
    name: 'Patan Heritage Inn',
    description: 'ऐतिहासिक Patan Durbar Square नजिकैको बुटिक होटल।',
    address: 'Patan, Lalitpur',
    location: const GeoPoint(27.6727, 85.3250),
    amenities: const ['WiFi', 'Restaurant', 'AC'],
    starRating: 3,
    rules: 'Quiet hours after 10 PM. No outside food in rooms.',
    images: [for (var i = 1; i <= 4; i++) _img('patan', i)],
    checkInTime: '14:00',
    checkOutTime: '11:00',
  ),
  Hotel(
    id: 'htl_4',
    name: 'Budget Stay Lodge',
    description: 'यात्रुका लागि किफायती, सफा र सुरक्षित बास।',
    address: 'New Road, Kathmandu',
    location: const GeoPoint(27.7040, 85.3100),
    amenities: const ['WiFi', 'Parking'],
    starRating: 2,
    rules: 'Check-out strictly by 10 AM.',
    images: [for (var i = 1; i <= 3; i++) _img('budget', i)],
    checkInTime: '12:00',
    checkOutTime: '10:00',
  ),
  Hotel(
    id: 'htl_5',
    name: 'Pokhara Lakeside Resort',
    description: 'Phewa Lake को किनारमै — sunrise/sunset दुवै दृश्य।',
    address: 'Lakeside, Pokhara',
    location: const GeoPoint(28.2096, 83.9560),
    amenities: const ['WiFi', 'Pool', 'Breakfast', 'Restaurant', 'Parking'],
    starRating: 4,
    rules: 'Pool access 6 AM - 9 PM. Children must be supervised near water.',
    images: [for (var i = 1; i <= 4; i++) _img('pokhara', i)],
    checkInTime: '14:00',
    checkOutTime: '12:00',
  ),
  Hotel(
    id: 'htl_6',
    name: 'Durbar Square Suites',
    description: 'आधुनिक सुविधा सहितको व्यापारिक यात्रुका लागि उपयुक्त होटल।',
    address: 'Basantapur, Kathmandu',
    location: const GeoPoint(27.7040, 85.3070),
    amenities: const ['WiFi', 'Gym', 'AC', 'Breakfast'],
    starRating: 4,
    rules: 'Business center open 24 hours. Laundry service available.',
    images: [for (var i = 1; i <= 4; i++) _img('durbar', i)],
    checkInTime: '14:00',
    checkOutTime: '11:00',
  ),
];

final List<HotelRoom> mockRooms = [
  // htl_1 — Kathmandu Grand Palace
  HotelRoom(
    id: 'rm_1_1', hotelId: 'htl_1', roomType: HotelRoomType.single,
    pricePerNight: 4500, capacity: 1, totalInventory: 6,
    amenities: ['WiFi', 'AC'], images: [], status: HotelRoomStatus.available,
  ),
  HotelRoom(
    id: 'rm_1_2', hotelId: 'htl_1', roomType: HotelRoomType.deluxe,
    pricePerNight: 7500, capacity: 2, totalInventory: 8,
    amenities: ['WiFi', 'AC', 'Breakfast'], images: [], status: HotelRoomStatus.available,
  ),
  HotelRoom(
    id: 'rm_1_3', hotelId: 'htl_1', roomType: HotelRoomType.suite,
    pricePerNight: 14000, capacity: 4, totalInventory: 3,
    amenities: ['WiFi', 'AC', 'Breakfast', 'Pool'], images: [],
    status: HotelRoomStatus.available,
  ),
  // htl_2 — Everest View Residency
  HotelRoom(
    id: 'rm_2_1', hotelId: 'htl_2', roomType: HotelRoomType.single,
    pricePerNight: 2200, capacity: 1, totalInventory: 5,
    amenities: ['WiFi'], images: [], status: HotelRoomStatus.available,
  ),
  HotelRoom(
    id: 'rm_2_2', hotelId: 'htl_2', roomType: HotelRoomType.deluxe,
    pricePerNight: 3800, capacity: 3, totalInventory: 6,
    amenities: ['WiFi', 'Breakfast', 'AC'], images: [], status: HotelRoomStatus.available,
  ),
  // htl_3 — Patan Heritage Inn
  HotelRoom(
    id: 'rm_3_1', hotelId: 'htl_3', roomType: HotelRoomType.single,
    pricePerNight: 1800, capacity: 1, totalInventory: 4,
    amenities: ['WiFi'], images: [], status: HotelRoomStatus.available,
  ),
  HotelRoom(
    id: 'rm_3_2', hotelId: 'htl_3', roomType: HotelRoomType.deluxe,
    pricePerNight: 2900, capacity: 2, totalInventory: 5,
    amenities: ['WiFi', 'AC'], images: [], status: HotelRoomStatus.available,
  ),
  // htl_4 — Budget Stay Lodge
  HotelRoom(
    id: 'rm_4_1', hotelId: 'htl_4', roomType: HotelRoomType.single,
    pricePerNight: 900, capacity: 1, totalInventory: 10,
    amenities: [], images: [], status: HotelRoomStatus.available,
  ),
  HotelRoom(
    id: 'rm_4_2', hotelId: 'htl_4', roomType: HotelRoomType.deluxe,
    pricePerNight: 1500, capacity: 2, totalInventory: 6,
    amenities: ['WiFi'], images: [], status: HotelRoomStatus.available,
  ),
  // htl_5 — Pokhara Lakeside Resort
  HotelRoom(
    id: 'rm_5_1', hotelId: 'htl_5', roomType: HotelRoomType.deluxe,
    pricePerNight: 5200, capacity: 2, totalInventory: 7,
    amenities: ['WiFi', 'Breakfast', 'AC'], images: [], status: HotelRoomStatus.available,
  ),
  HotelRoom(
    id: 'rm_5_2', hotelId: 'htl_5', roomType: HotelRoomType.suite,
    pricePerNight: 9800, capacity: 4, totalInventory: 2,
    amenities: ['WiFi', 'Breakfast', 'AC', 'Pool'], images: [],
    status: HotelRoomStatus.available,
  ),
  // htl_6 — Durbar Square Suites
  HotelRoom(
    id: 'rm_6_1', hotelId: 'htl_6', roomType: HotelRoomType.single,
    pricePerNight: 3200, capacity: 1, totalInventory: 5,
    amenities: ['WiFi', 'AC'], images: [], status: HotelRoomStatus.available,
  ),
  HotelRoom(
    id: 'rm_6_2', hotelId: 'htl_6', roomType: HotelRoomType.deluxe,
    pricePerNight: 5400, capacity: 2, totalInventory: 6,
    amenities: ['WiFi', 'AC', 'Breakfast', 'Gym'], images: [],
    status: HotelRoomStatus.available,
  ),
];

List<HotelRoom> mockRoomsForHotel(String hotelId) =>
    mockRooms.where((r) => r.hotelId == hotelId).toList();

/// Real-Time Room Status Sync — guest Hotel Details स्क्रिनले यही लाइभ
/// Firestore stream प्रयोग गर्छ, `mockRoomsForHotel` (एकपटकको, in-memory
/// मात्र snapshot) होइन। पहिले partner ले (फरक device/session बाटै) कोठाको
/// status/दर/फोटो बदल्दा Firestore मा त्यो लेखिन्थ्यो, तर guest-साइडले
/// कहिल्यै फेरि नपढ्ने भएकोले (केवल app startup मा एकपटक `hydrateHotels
/// FromFirestore`, त्यो पनि पहिल्यै-चिनेको room id भए skip गर्ने) — guest
/// ले app पुनः नखोलेसम्म (र पुनः खोले पनि, hydration त्यही known-id भएकोले
/// skip भइहाल्ने) Occupied/Cleaning कोठा अझै "Available" नै देख्थे भन्ने
/// गुनासोको साँचो जड। अब Firestore doc जे भए पनि (seed रूम सहित, एकपटक
/// साँचो Firestore doc बनेपछि) live listen हुन्छ — सधैं authoritative।
/// सोही hotelId का seed room (अझै कुनै Firestore doc नभएका) भने उस्तै
/// in-memory मै रहन्छन्, overwrite हुँदैनन्।
Stream<List<HotelRoom>> roomsStreamForHotel(String hotelId) {
  return FirebaseFirestore.instance
      .collection('rooms')
      .where('hotelId', isEqualTo: hotelId)
      .snapshots()
      .map((snap) {
    final merged = <String, HotelRoom>{
      for (final r in mockRooms.where((r) => r.hotelId == hotelId)) r.id: r,
    };
    for (final doc in snap.docs) {
      merged[doc.id] = HotelRoom.fromDoc(doc);
    }
    return merged.values.toList();
  });
}

/// एउटा होटलको सबैभन्दा सस्तो सक्रिय कोठाको रात-मूल्य — सूची कार्डको
/// "from Rs. X/night" का लागि।
double? cheapestActiveRoomPrice(String hotelId) {
  final active = mockRoomsForHotel(hotelId).where((r) => r.isActive);
  if (active.isEmpty) return null;
  return active.map((r) => r.pricePerNight).reduce((a, b) => a < b ? a : b);
}

final List<HotelReview> mockReviews = [
  HotelReview(
    id: 'rv_1', hotelId: 'htl_1', userId: 'u1', rating: 5,
    comment: 'Excellent service and amazing rooftop view!',
    createdAt: DateTime.now().subtract(const Duration(days: 4)),
    reviewerName: 'Sarah M.', country: 'United Kingdom', featured: true,
  ),
  HotelReview(
    id: 'rv_2', hotelId: 'htl_1', userId: 'u2', rating: 4,
    comment: 'Great stay, breakfast could be better.',
    createdAt: DateTime.now().subtract(const Duration(days: 12)),
    reviewerName: 'Arjun P.', country: 'India',
  ),
  HotelReview(
    id: 'rv_3', hotelId: 'htl_2', userId: 'u3', rating: 4,
    comment: 'Peaceful location, friendly staff.',
    createdAt: DateTime.now().subtract(const Duration(days: 7)),
    reviewerName: 'Hana K.', country: 'Japan', featured: true,
  ),
  HotelReview(
    id: 'rv_4', hotelId: 'htl_3', userId: 'u4', rating: 5,
    comment: 'Loved the heritage architecture and location.',
    createdAt: DateTime.now().subtract(const Duration(days: 20)),
    reviewerName: 'Liam O.', country: 'Australia', featured: true,
  ),
  HotelReview(
    id: 'rv_5', hotelId: 'htl_5', userId: 'u5', rating: 5,
    comment: 'Best lakeside view in Pokhara, highly recommend!',
    createdAt: DateTime.now().subtract(const Duration(days: 2)),
    reviewerName: 'Nina F.', country: 'Germany', featured: true,
  ),
];

List<HotelReview> mockReviewsForHotel(String hotelId) =>
    mockReviews.where((r) => r.hotelId == hotelId).toList();

double averageRating(String hotelId) {
  final rs = mockReviewsForHotel(hotelId);
  if (rs.isEmpty) return 0;
  return rs.map((r) => r.rating).reduce((a, b) => a + b) / rs.length;
}
