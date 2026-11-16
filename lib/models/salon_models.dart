// models/salon_models.dart
//
// Salon / Beauty Appointment Booking (Booksy-style) — Firestore data models।
// hotel_models.dart कै उही ढाँचा: हरेक class मा `fromDoc` + `toMap`, status
// string-constant `abstract class` मा।
//
// Collections:
//   salons/{salonId}                      — provider profile (मालिक = ownerId)
//   salons/{salonId}/services/{serviceId} — service menu (मूल्य + अवधि)
//   salons/{salonId}/staff/{staffId}      — barber/stylist + साप्ताहिक समय
//   salon_appointments/{id}               — बुकिङ (Cloud Function मात्रले सिर्जना)
//   salon_reviews/{appointmentId}         — verified review (Cloud Function मात्र)
import 'package:cloud_firestore/cloud_firestore.dart';

/// Salon-प्रकार — provider दर्ता र browse filter दुवैमा यही सूची।
const List<String> kSalonCategories = [
  'Salon',
  'Barber',
  'Beauty & Makeup',
  'Spa & Massage',
  'Nails',
  'Other',
];

abstract class SalonStatus {
  static const active = 'active';
  // मालिकले अस्थायी रूपमा नयाँ बुकिङ बन्द गर्दा — browse list मा देखिँदैन।
  static const paused = 'paused';
  // नयाँ दर्ता — admin ले approve नगरेसम्म browse/बुकिङमा देखिँदैन।
  static const pending = 'pending';
  // admin ले अस्वीकार गरेको — मालिकले सुधारेर फेरि पठाउन सक्छ (admin ले मात्र approve)।
  static const rejected = 'rejected';
}

abstract class SalonAppointmentStatus {
  static const confirmed = 'confirmed';
  static const checkedIn = 'checked_in';
  static const completed = 'completed';
  static const cancelled = 'cancelled';
  static const noShow = 'no_show';

  /// समय-स्लट ओगट्ने (अरूले बुक गर्न नसक्ने) status हरू — cancelled/no_show
  /// ले स्लट फेरि खाली गर्छ। functions/index.js कै `SALON_ACTIVE_STATUSES`
  /// सँग सधैँ उस्तै हुनुपर्छ।
  static const active = [confirmed, checkedIn];
}

abstract class SalonPaymentType {
  static const paySalon = 'pay_at_salon';
  static const online = 'online_paid';
}

/// `YYYY-MM-DD` — Cloud Function लाई पठाइने मिति (salon को स्थानीय मिति)।
String salonDateKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

DateTime _ts(dynamic v) => v is Timestamp ? v.toDate() : DateTime.now();

/// फोटो URL सूची — खाली/गलत मान हटाएर, सफा `https` URL मात्र।
List<String> _urlList(dynamic v) => v is List
    ? v
        .map((e) => e.toString().trim())
        .where((u) => u.startsWith('http'))
        .toList()
    : const <String>[];

class Salon {
  final String id;
  final String ownerId;
  final String name;
  final String category;
  final String address;
  final String phone;
  final String description;
  final String status;
  final int slotStepMin;
  final int tzOffsetMin;
  final double ratingSum;
  final int ratingCount;
  final DateTime createdAt;

  /// Salon को logo/फोटो (Firebase Storage download URL); नभए खाली।
  final String logoUrl;

  /// विवरण पेजको माथिको ठूलो banner/कभर फोटो; नभए खाली।
  final String coverUrl;

  /// Portfolio — काम/सैलुनका फोटोहरू (Storage download URL हरू)।
  final List<String> photos;

  /// admin ले अस्वीकार गर्दा दिएको कारण (भए)।
  final String rejectionReason;

  const Salon({
    required this.id,
    required this.ownerId,
    required this.name,
    required this.category,
    required this.address,
    required this.phone,
    required this.description,
    required this.status,
    required this.slotStepMin,
    required this.tzOffsetMin,
    required this.ratingSum,
    required this.ratingCount,
    required this.createdAt,
    this.logoUrl = '',
    this.coverUrl = '',
    this.photos = const <String>[],
    this.rejectionReason = '',
  });

  double get avgRating => ratingCount == 0 ? 0 : ratingSum / ratingCount;
  bool get isActive => status == SalonStatus.active;
  bool get isPending => status == SalonStatus.pending;
  bool get isRejected => status == SalonStatus.rejected;

  /// मालिकले active ↔ paused बदल्न सक्ने (pending/rejected मा admin ले मात्र)।
  bool get ownerCanToggle =>
      status == SalonStatus.active || status == SalonStatus.paused;

  factory Salon.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const <String, dynamic>{};
    return Salon(
      id: doc.id,
      ownerId: (d['ownerId'] ?? '').toString(),
      name: (d['name'] ?? '').toString(),
      category: (d['category'] ?? 'Salon').toString(),
      address: (d['address'] ?? '').toString(),
      phone: (d['phone'] ?? '').toString(),
      description: (d['description'] ?? '').toString(),
      status: (d['status'] ?? SalonStatus.active).toString(),
      slotStepMin: (d['slotStepMin'] as num?)?.toInt() ?? 30,
      // Nepal = UTC+5:45 = 345 मिनेट।
      tzOffsetMin: (d['tzOffsetMin'] as num?)?.toInt() ?? 345,
      ratingSum: (d['ratingSum'] as num?)?.toDouble() ?? 0,
      ratingCount: (d['ratingCount'] as num?)?.toInt() ?? 0,
      createdAt: _ts(d['createdAt']),
      logoUrl: (d['logoUrl'] ?? '').toString(),
      // `bannerUrl` / `portfolioImages` — Firebase Console मा हातले भरिएका
      // वैकल्पिक नाम पनि पढ्ने (एपले आफैं `coverUrl` / `photos` लेख्छ)।
      coverUrl: (d['coverUrl'] ?? d['bannerUrl'] ?? '').toString(),
      photos: _urlList(d['photos'] ?? d['portfolioImages']),
      rejectionReason: (d['rejectionReason'] ?? '').toString(),
    );
  }
}

class SalonService {
  final String id;
  final String salonId;
  final String name;
  final String description;
  final double price;
  final int durationMin;
  final bool active;

  const SalonService({
    required this.id,
    required this.salonId,
    required this.name,
    required this.description,
    required this.price,
    required this.durationMin,
    required this.active,
  });

  factory SalonService.fromDoc(
      String salonId, DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const <String, dynamic>{};
    return SalonService(
      id: doc.id,
      salonId: salonId,
      name: (d['name'] ?? '').toString(),
      description: (d['description'] ?? '').toString(),
      price: (d['price'] as num?)?.toDouble() ?? 0,
      durationMin: (d['durationMin'] as num?)?.toInt() ?? 30,
      active: d['active'] != false,
    );
  }
}

/// एक दिनको कामको समय (`HH:MM`, salon को स्थानीय समय)।
class SalonDayHours {
  final String open;
  final String close;
  const SalonDayHours(this.open, this.close);
}

class SalonStaff {
  final String id;
  final String salonId;
  final String name;
  final String title;
  final bool active;

  /// खाली = सबै service गर्न सक्ने।
  final List<String> serviceIds;

  /// `DateTime.weekday` (१=सोम … ७=आइत) → समय; नभएको दिन बिदा।
  final Map<int, SalonDayHours> hours;

  /// Barber/stylist को फोटो (Firebase Storage download URL); नभए खाली।
  final String photoUrl;

  const SalonStaff({
    required this.id,
    required this.salonId,
    required this.name,
    required this.title,
    required this.active,
    required this.serviceIds,
    required this.hours,
    this.photoUrl = '',
  });

  bool canDo(Iterable<String> ids) =>
      serviceIds.isEmpty || ids.every(serviceIds.contains);

  factory SalonStaff.fromDoc(
      String salonId, DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const <String, dynamic>{};
    final hours = <int, SalonDayHours>{};
    final raw = d['hours'];
    if (raw is Map) {
      raw.forEach((k, v) {
        final day = int.tryParse(k.toString());
        if (day != null && v is Map) {
          hours[day] =
              SalonDayHours((v['open'] ?? '').toString(), (v['close'] ?? '').toString());
        }
      });
    }
    return SalonStaff(
      id: doc.id,
      salonId: salonId,
      name: (d['name'] ?? '').toString(),
      title: (d['title'] ?? '').toString(),
      active: d['active'] != false,
      serviceIds: d['serviceIds'] is List
          ? List<String>.from(d['serviceIds'])
          : const <String>[],
      hours: hours,
      photoUrl: (d['photoUrl'] ?? '').toString(),
    );
  }

  static Map<String, dynamic> hoursToMap(Map<int, SalonDayHours> h) => {
        for (final e in h.entries)
          '${e.key}': {'open': e.value.open, 'close': e.value.close},
      };
}

class SalonAppointment {
  final String id;
  final String userId;
  final String salonId;
  final String ownerId;
  final String salonName;
  final String staffId;
  final String staffName;
  final List<String> serviceIds;
  final List<String> serviceNames;
  final double totalPrice;
  final int durationMin;
  final DateTime startAt;
  final DateTime endAt;
  final String status;
  final String paymentType;
  final String paymentMethod;
  final String paymentRef;
  // 'unpaid' | 'declared' (ग्राहकले reference दिएको, provider ले verify गरेको
  // होइन) | 'paid' (provider ले आफैं पुष्टि गरेपछि)।
  final String paymentStatus;
  final String customerName;
  final String customerPhone;
  final String qrToken;
  final bool reviewed;
  final DateTime createdAt;

  const SalonAppointment({
    required this.id,
    required this.userId,
    required this.salonId,
    required this.ownerId,
    required this.salonName,
    required this.staffId,
    required this.staffName,
    required this.serviceIds,
    required this.serviceNames,
    required this.totalPrice,
    required this.durationMin,
    required this.startAt,
    required this.endAt,
    required this.status,
    required this.paymentType,
    required this.paymentMethod,
    required this.paymentRef,
    required this.paymentStatus,
    required this.customerName,
    required this.customerPhone,
    required this.qrToken,
    required this.reviewed,
    required this.createdAt,
  });

  bool get isActive => SalonAppointmentStatus.active.contains(status);

  /// Provider ले scan गर्ने QR payload — `KAAMMITRA-SALON:<id>:<token>`।
  /// token गोप्य (random) हुने भएकोले id मात्र अनुमान गरेर check-in नक्कल हुँदैन।
  String get qrPayload => 'KAAMMITRA-SALON:$id:$qrToken';

  factory SalonAppointment.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const <String, dynamic>{};
    List<String> strs(dynamic v) =>
        v is List ? v.map((e) => e.toString()).toList() : const <String>[];
    return SalonAppointment(
      id: doc.id,
      userId: (d['userId'] ?? '').toString(),
      salonId: (d['salonId'] ?? '').toString(),
      ownerId: (d['ownerId'] ?? '').toString(),
      salonName: (d['salonName'] ?? '').toString(),
      staffId: (d['staffId'] ?? '').toString(),
      staffName: (d['staffName'] ?? '').toString(),
      serviceIds: strs(d['serviceIds']),
      serviceNames: strs(d['serviceNames']),
      totalPrice: (d['totalPrice'] as num?)?.toDouble() ?? 0,
      durationMin: (d['durationMin'] as num?)?.toInt() ?? 30,
      startAt: _ts(d['startAt']),
      endAt: _ts(d['endAt']),
      status: (d['status'] ?? SalonAppointmentStatus.confirmed).toString(),
      paymentType: (d['paymentType'] ?? SalonPaymentType.paySalon).toString(),
      paymentMethod: (d['paymentMethod'] ?? '').toString(),
      paymentRef: (d['paymentRef'] ?? '').toString(),
      paymentStatus: (d['paymentStatus'] ?? 'unpaid').toString(),
      customerName: (d['customerName'] ?? '').toString(),
      customerPhone: (d['customerPhone'] ?? '').toString(),
      qrToken: (d['qrToken'] ?? '').toString(),
      reviewed: d['reviewed'] == true,
      createdAt: _ts(d['createdAt']),
    );
  }
}

class SalonReview {
  final String id;
  final String salonId;
  final String userId;
  final String reviewerName;
  final double rating;
  final String comment;
  final DateTime createdAt;

  const SalonReview({
    required this.id,
    required this.salonId,
    required this.userId,
    required this.reviewerName,
    required this.rating,
    required this.comment,
    required this.createdAt,
  });

  factory SalonReview.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const <String, dynamic>{};
    return SalonReview(
      id: doc.id,
      salonId: (d['salonId'] ?? '').toString(),
      userId: (d['userId'] ?? '').toString(),
      reviewerName: (d['reviewerName'] ?? 'Customer').toString(),
      rating: (d['rating'] as num?)?.toDouble() ?? 0,
      comment: (d['comment'] ?? '').toString(),
      createdAt: _ts(d['createdAt']),
    );
  }
}

/// एउटा खाली समय-स्लट (Cloud Function `salonAvailableSlots` को नतिजा)।
class SalonSlot {
  final DateTime start;
  // यो समयमा खाली रहेका staff — "Any available" छानिँदा पहिलो प्रयोग हुन्छ।
  final List<String> staffIds;
  const SalonSlot(this.start, this.staffIds);
}
