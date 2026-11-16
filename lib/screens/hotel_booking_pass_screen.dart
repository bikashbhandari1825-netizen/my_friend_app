// screens/hotel_booking_pass_screen.dart
//
// Hotel Booking System — Phase 5: बुकिङ पूरा भएपछि देखिने Digital Booking
// Pass — QR कोड (होटल front-desk ले स्क्यान गरेर verify गर्ने भनेर
// कल्पना गरिएको, `booking.qrCodeData`), बुकिङ सारांश, रद्द (cancel), र
// booking confirmed/checked-in हुनेबित्तिकै स्वतः खुल्ने Call/Video/Message
// (Acceptance-Gated Communication — `isHotelCommunicationUnlocked`,
// hotel_models.dart)। `ChatScreen`/`startInAppCall` त्यही साझा इन्फ्रा
// हो जो ride/service job (request_tracking_screen.dart) ले प्रयोग गर्छ,
// `statusCollection: 'hotel_bookings'` र `otherUid: hotel.ownerId` दिएर।
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/hotel_models.dart';
import '../services/hotel_booking_service.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_ui.dart';
import 'chat_screen.dart';
import 'hotel_common.dart';
import 'job_actions.dart' show startInAppCall;
import '../widgets/futuristic_ui.dart';

class HotelBookingPassScreen extends StatefulWidget {
  final HotelBooking booking;
  final Hotel hotel;
  final HotelRoom room;
  const HotelBookingPassScreen({
    super.key,
    required this.booking,
    required this.hotel,
    required this.room,
  });

  @override
  State<HotelBookingPassScreen> createState() =>
      _HotelBookingPassScreenState();
}

class _HotelBookingPassScreenState extends State<HotelBookingPassScreen> {
  bool _cancelling = false;

  // Customer App Live Booking Pass Sync — Owner ले QR स्क्यानबाट Check-In/
  // Check-Out गर्दा (Partner Dashboard, फरक डिभाइस/session बाट) यही खुला
  // रहेको Booking Pass मा पनि तुरुन्तै देखियोस् भनेर स्थिर local state
  // (`_booking`) होइन, सिधै Firestore doc नै live listen गरिएको।
  Stream<HotelBooking> get _bookingStream => FirebaseFirestore.instance
      .collection('hotel_bookings')
      .doc(widget.booking.id)
      .snapshots()
      .map((doc) => doc.exists ? HotelBooking.fromDoc(doc) : widget.booking);

  bool _canCancel(HotelBooking b) =>
      b.status == HotelBookingStatus.pending ||
      b.status == HotelBookingStatus.confirmed;

  // Advanced Check-out — Digital Pass Deactivation। stay समाप्त भइसकेको
  // (checked out/cancelled/no-show) बुकिङको QR अब स्क्यान-योग्य देखिनु
  // हुँदैन — पहिले status जे भए पनि उही live QR सधैँ देखिन्थ्यो।
  bool _isPassDeactivated(HotelBooking b) =>
      b.status == HotelBookingStatus.completed ||
      b.status == HotelBookingStatus.cancelled ||
      b.status == HotelBookingStatus.noShow;

  Color _statusColor(HotelBooking b) => switch (b.status) {
        HotelBookingStatus.confirmed => AppColors.kmTeal,
        HotelBookingStatus.checkedIn => AppColors.kmOrange,
        HotelBookingStatus.completed => AppColors.kmTeal,
        HotelBookingStatus.cancelled => AppColors.kmMuted,
        _ => AppColors.kmPurple,
      };

  String _statusLabel(HotelBooking b) => switch (b.status) {
        HotelBookingStatus.confirmed => 'Confirmed',
        HotelBookingStatus.checkedIn => 'Checked In',
        HotelBookingStatus.completed => 'Checked Out',
        HotelBookingStatus.cancelled => 'Cancelled',
        _ => 'Pending',
      };

  Future<void> _confirmCancel(HotelBooking b) async {
    final ok = await showKmDialog<bool>(
      context: context,
      title: 'Cancel this booking?',
      message:
          'Free cancellation up to 24 hours before check-in. After that, '
          'the first night is non-refundable.',
      icon: Icons.cancel_rounded,
      actions: [
        KmDialogAction(
          label: 'Keep booking',
          onPressed: () => Navigator.pop(context, false),
        ),
        KmDialogAction(
          label: 'Cancel booking',
          destructive: true,
          onPressed: () => Navigator.pop(context, true),
        ),
      ],
    );
    if (ok != true || !mounted) return;
    setState(() => _cancelling = true);
    try {
      final cancelled = await cancelHotelBooking(b, widget.hotel.name);
      if (!mounted) return;
      if (!cancelled) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text(
                  'Could not cancel the booking. Please check your connection and try again.')),
        );
      }
      // सफल भए UI आफैं `_bookingStream` बाटै अद्यावधिक हुन्छ — यहाँ फेरि
      // local state पुनर्निर्माण गर्नु पर्दैन।
    } finally {
      if (mounted) setState(() => _cancelling = false);
    }
  }

  /// Admin-seeded mock होटल (htl_1..htl_6) मा `ownerId` खाली हुन्छ — त्यस्तो
  /// बेला साँचो partner खाता नै नभएकोले Call/Video/Message देखाउनु हुँदैन।
  bool _canCommunicate(HotelBooking b) =>
      widget.hotel.ownerId.isNotEmpty &&
      isHotelCommunicationUnlocked(b.status);

  void _messageHotel(HotelBooking b) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          requestId: b.id,
          workerName: widget.hotel.name,
          initialStatus: b.status,
          statusCollection: 'hotel_bookings',
          otherUid: widget.hotel.ownerId,
          unlockedStatuses: kActiveHotelBookingStatuses,
        ),
      ),
    );
  }

  // "Hotel Phone" — सिधै native phone dialer (`tel:`) खोल्छ। पहिले
  // owner को personal `users/{ownerId}.phone` मात्र प्रयोग हुन्थ्यो; अब
  // होटलकै आधिकारिक नम्बर (`hotel.officialMobileNumber`, registration/
  // profile edit बाट) भए त्यही प्राथमिकतामा — नभएको पुरानो/mock होटलका
  // लागि मात्र owner personal number मा fallback। "Call"/"Video" भने
  // दुवै अब in-app WebRTC (तल `_callHotel`) — Hotel Partner account
  // सिधै target गर्ने।
  Future<void> _dialHotelPhone() async {
    final mobile = widget.hotel.officialMobileNumber;
    final landline = widget.hotel.landlinePhone;
    String? phone;
    if (mobile.isNotEmpty && landline.isNotEmpty) {
      // दुवै नम्बर भए — कुन मा कल गर्ने guest आफैं छान्ने (sheet)।
      phone = await showKmSheet<String>(
        context: context,
        title: 'Call Hotel',
        children: [
          KmSheetOption(
            icon: Icons.phone_iphone_rounded,
            label: 'Mobile',
            subtitle: mobile,
            selected: false,
            onTap: () => Navigator.pop(context, mobile),
          ),
          KmSheetOption(
            icon: Icons.phone_rounded,
            label: 'Landline',
            subtitle: landline,
            selected: false,
            onTap: () => Navigator.pop(context, landline),
          ),
        ],
      );
      if (phone == null) return; // sheet dismiss नगरी छानिएन
    } else if (mobile.isNotEmpty) {
      phone = mobile;
    } else if (landline.isNotEmpty) {
      phone = landline;
    } else {
      phone = await hotelOwnerPhone(widget.hotel.ownerId);
    }
    if (!mounted) return;
    if (phone == null || phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('No phone number on file for this hotel.')),
      );
      return;
    }
    try {
      await launchUrl(Uri(scheme: 'tel', path: phone));
    } catch (_) {}
  }

  void _callHotel(HotelBooking b, {required bool video}) => startInAppCall(
        context,
        requestId: b.id,
        otherName: widget.hotel.name,
        video: video,
        otherUid: widget.hotel.ownerId,
      );

  @override
  Widget build(BuildContext context) {
    final h = widget.hotel;
    final r = widget.room;
    return OledBackdrop(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Column(
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 16, 20, 0),
                child: KmScreenHeader(title: 'Booking Pass'),
              ),
              Expanded(
                child: StreamBuilder<HotelBooking>(
                  stream: _bookingStream,
                  initialData: widget.booking,
                  builder: (context, snap) {
                    final b = snap.data ?? widget.booking;
                    return ListView(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                      children: [
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.06),
                            borderRadius: BorderRadius.circular(AppRadius.lg),
                            border: Border.all(
                                color: Colors.white.withValues(alpha: 0.14)),
                          ),
                          child: Column(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: _statusColor(b)
                                      .withValues(alpha: 0.16),
                                  borderRadius:
                                      BorderRadius.circular(AppRadius.pill),
                                ),
                                child: Text(_statusLabel(b),
                                    style: TextStyle(
                                        color: _statusColor(b),
                                        fontWeight: FontWeight.w800,
                                        fontSize: 12)),
                              ),
                              const SizedBox(height: 18),
                              _isPassDeactivated(b)
                                  ? Container(
                                      width: 190,
                                      height: 190,
                                      padding: const EdgeInsets.all(16),
                                      decoration: BoxDecoration(
                                        color: Colors.white
                                            .withValues(alpha: 0.05),
                                        borderRadius:
                                            BorderRadius.circular(16),
                                        border: Border.all(
                                            color: Colors.white
                                                .withValues(alpha: 0.12)),
                                      ),
                                      child: const Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Icon(Icons.qr_code_2_rounded,
                                              size: 48,
                                              color: AppColors.kmMuted),
                                          SizedBox(height: 10),
                                          Text('Pass no longer active',
                                              textAlign: TextAlign.center,
                                              style: TextStyle(
                                                  color: AppColors.kmMuted,
                                                  fontWeight: FontWeight.w700,
                                                  fontSize: 13)),
                                          SizedBox(height: 4),
                                          Text('This stay has ended',
                                              textAlign: TextAlign.center,
                                              style: TextStyle(
                                                  color: AppColors.kmMuted,
                                                  fontSize: 11.5)),
                                        ],
                                      ),
                                    )
                                  : Container(
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius:
                                            BorderRadius.circular(16),
                                      ),
                                      child: QrImageView(
                                        data: b.qrCodeData,
                                        version: QrVersions.auto,
                                        size: 190,
                                        gapless: true,
                                      ),
                                    ),
                              const SizedBox(height: 14),
                              Text(h.name,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                      color: AppColors.kmText,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 17)),
                              Text(h.address,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                      color: AppColors.kmMuted,
                                      fontSize: 12.5)),
                              // Hotel Contact Numbers — होटलकै आधिकारिक
                              // मोबाइल/landline (registration/profile edit
                              // बेला partner ले भरेको), सिधा tap-to-dial।
                              if (h.officialMobileNumber.isNotEmpty ||
                                  h.landlinePhone.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                Wrap(
                                  alignment: WrapAlignment.center,
                                  spacing: 14,
                                  runSpacing: 4,
                                  children: [
                                    if (h.officialMobileNumber.isNotEmpty)
                                      _contactNumberChip(
                                          Icons.phone_iphone_rounded,
                                          h.officialMobileNumber),
                                    if (h.landlinePhone.isNotEmpty)
                                      _contactNumberChip(
                                          Icons.phone_rounded,
                                          h.landlinePhone),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                        // Customer App Live Booking Pass Sync — owner ले
                        // QR स्क्यानबाट Check-In गरेपछि तुरुन्तै देखिने
                        // प्रस्ट बिल्ला (Room Number + साँचो entry-क्षण)।
                        if (b.status == HotelBookingStatus.checkedIn) ...[
                          const SizedBox(height: 14),
                          _checkedInBadge(b, r),
                        ],
                        const SizedBox(height: 18),
                        _detailsCard(b, r),
                        if (_amenitiesFor(b, r).isNotEmpty) ...[
                          const SizedBox(height: 18),
                          _amenitiesCard(_amenitiesFor(b, r)),
                        ],
                        const SizedBox(height: 18),
                        // Communication Never Locks — booking status जे भए
                        // पनि (completed/cancelled समेत) Call/Video/Message/
                        // Hotel Phone सधैं उपलब्ध, Hotel Partner account
                        // सिधै target गर्दै (`_callHotel`/`_messageHotel`
                        // माथि) — केवल त्यो होटलको साँचो partner खाता
                        // (`ownerId`) भए मात्र (`_canCommunicate`)।
                        if (_canCommunicate(b)) _communicationGrid(b),
                        if (_canCancel(b)) ...[
                          const SizedBox(height: 10),
                          OutlinedButton.icon(
                            onPressed:
                                _cancelling ? null : () => _confirmCancel(b),
                            icon: _cancelling
                                ? const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: AppColors.kmPink))
                                : const Icon(Icons.cancel_outlined,
                                    size: 18, color: AppColors.kmPink),
                            label: Text(
                                _cancelling
                                    ? 'Cancelling…'
                                    : 'Cancel Booking',
                                style:
                                    const TextStyle(color: AppColors.kmPink)),
                            style: OutlinedButton.styleFrom(
                              side: BorderSide(
                                  color:
                                      AppColors.kmPink.withValues(alpha: 0.4)),
                              padding:
                                  const EdgeInsets.symmetric(vertical: 13),
                            ),
                          ),
                        ],
                        const SizedBox(height: 18),
                        KmCtaButton(
                          label: 'Done',
                          onPressed: () =>
                              Navigator.popUntil(context, (r) => r.isFirst),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _contactNumberChip(IconData icon, String number) => InkWell(
        borderRadius: BorderRadius.circular(AppRadius.pill),
        onTap: () async {
          try {
            await launchUrl(Uri(scheme: 'tel', path: number));
          } catch (_) {}
        },
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: AppColors.kmTeal),
            const SizedBox(width: 4),
            Text(number,
                style: const TextStyle(
                    color: AppColors.kmTeal,
                    fontWeight: FontWeight.w700,
                    fontSize: 12)),
          ],
        ),
      );

  Widget _checkedInBadge(HotelBooking b, HotelRoom r) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.kmOrange.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: AppColors.kmOrange.withValues(alpha: 0.4)),
        ),
        child: Row(
          children: [
            const Icon(Icons.verified_rounded,
                color: AppColors.kmOrange, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                      'Currently Checked-In · Room '
                      '${r.roomNumber.isEmpty ? r.roomType : r.roomNumber}',
                      style: const TextStyle(
                          color: AppColors.kmOrange,
                          fontWeight: FontWeight.w800,
                          fontSize: 13.5)),
                  if (b.checkedInAt != null) ...[
                    const SizedBox(height: 2),
                    Text('Checked in at ${_fmtTime(b.checkedInAt!)}',
                        style: const TextStyle(
                            color: AppColors.kmMuted, fontSize: 11.5)),
                  ],
                ],
              ),
            ),
          ],
        ),
      );

  /// बुकिङमै स्नैपशट भएको amenities (`HotelBooking.amenities`) छ भने त्यही,
  /// नत्र पुरानो (field थपिनुअघि सिर्जना भएका) बुकिङका लागि room को हालको
  /// amenities मा fallback।
  List<String> _amenitiesFor(HotelBooking b, HotelRoom r) =>
      b.amenities.isNotEmpty ? b.amenities : r.amenities;

  Widget _amenitiesCard(List<String> amenities) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Selected Amenities & Included Services',
                style: TextStyle(
                    color: AppColors.kmMuted,
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                    letterSpacing: 0.3)),
            const SizedBox(height: 10),
            hotelAmenityChips(amenities),
          ],
        ),
      );

  /// Call/Video/Message/Hotel Phone — 2×2 grid, Selected Amenities कार्डको
  /// लगतै तल। "Call"/"Video" दुवै in-app WebRTC (Hotel Partner account
  /// सिधै target गर्दै); "Hotel Phone" मात्र native cellular dialer।
  Widget _communicationGrid(HotelBooking b) {
    Widget outlined(IconData icon, String label, VoidCallback onTap) =>
        Expanded(
          child: OutlinedButton.icon(
            onPressed: onTap,
            icon: Icon(icon, size: 18),
            label: Text(label),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.kmText,
              side: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
              padding: const EdgeInsets.symmetric(vertical: 13),
            ),
          ),
        );
    return Column(
      children: [
        Row(
          children: [
            outlined(Icons.call_rounded, 'Voice Call',
                () => _callHotel(b, video: false)),
            const SizedBox(width: 8),
            outlined(Icons.videocam_rounded, 'Video Call',
                () => _callHotel(b, video: true)),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () => _messageHotel(b),
                icon: const Icon(Icons.chat_bubble_rounded, size: 18),
                label: const Text('Message',
                    style: TextStyle(fontWeight: FontWeight.w800)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.kmOrange,
                  foregroundColor: AppColors.kmInk,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                ),
              ),
            ),
            const SizedBox(width: 8),
            outlined(Icons.phone_in_talk_rounded, 'Hotel Phone',
                _dialHotelPhone),
          ],
        ),
      ],
    );
  }

  Widget _detailsCard(HotelBooking b, HotelRoom r) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
        ),
        child: Column(
          children: [
            _row('Booking ID', b.id),
            _row('Guest', b.guestName.isEmpty ? '—' : b.guestName),
            _row('Room', r.roomType),
            _row('Check-in', _fmt(b.checkInDate)),
            _row('Check-out', _fmt(b.checkOutDate)),
            _row('Guests', '${b.guestsCount}'),
            _row('Payment',
                b.paymentType == HotelPaymentType.payAtHotel
                    ? 'Pay at Hotel'
                    : 'Paid Online'),
            Divider(height: 20, color: AppColors.kmGlassBorder),
            _row('Total Paid', formatHotelPrice(b.totalPrice), bold: true),
          ],
        ),
      );

  Widget _row(String label, String value, {bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label,
                style: const TextStyle(color: AppColors.kmMuted, fontSize: 12.5)),
            Flexible(
              child: Text(value,
                  textAlign: TextAlign.right,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: bold ? AppColors.kmOrange : AppColors.kmText,
                      fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
                      fontSize: bold ? 15 : 12.5)),
            ),
          ],
        ),
      );

  String _fmt(DateTime d) => '${d.day}/${d.month}/${d.year}';

  String _fmtTime(DateTime d) {
    final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final ampm = d.hour >= 12 ? 'PM' : 'AM';
    final mm = d.minute.toString().padLeft(2, '0');
    return '${d.day}/${d.month}/${d.year} · $h:$mm $ampm';
  }
}
