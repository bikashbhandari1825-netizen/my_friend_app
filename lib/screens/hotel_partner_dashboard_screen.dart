// screens/hotel_partner_dashboard_screen.dart
//
// Hotel Partner & Receptionist Management System — Booking.com Extranet/
// Pulse जस्तै B2B dashboard। Profile tab को "List Your Property"/"Switch
// to Partner Dashboard" banner बाट यहाँ आइपुगिन्छ (होम/MainContainer को
// ठूलो/जटिल tab-structure नछोइकनै, छुट्टै पूरा-स्क्रिन route को रूपमा)।
import 'dart:typed_data' show Uint8List;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FilteringTextInputFormatter;
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/hotel_mock_data.dart';
import '../models/hotel_models.dart';
import '../services/hotel_partner_service.dart';
import '../services/upload_validation.dart' show UploadValidation;
import '../theme/app_theme.dart';
import '../widgets/dashboard_exit_bar.dart';
import '../widgets/glass_ui.dart';
import 'chat_screen.dart';
import 'hotel_common.dart';
import 'job_actions.dart' show startInAppCall;
import 'qr_scanner_screen.dart';
import '../widgets/futuristic_ui.dart';

/// Camera-vs-Gallery छनोट — यो dashboard भित्रका दुवै फोटो-अपलोड ठाउँ
/// (Add Room photos + Hotel Info gallery, `_HotelInfoTabState._addPhoto`)
/// ले यही साझा गर्छन् ताकि छनोट/error-ह्यान्डलिङ एकै ठाउँमा मात्र रहोस्।
/// `showKmSheet`/`KmSheetOption` (Appearance/Language picker कै उस्तै
/// dark-glass bottom sheet) प्रयोग गरिएको — नयाँ custom UI होइन।
Future<XFile?> pickPartnerImage(BuildContext context) async {
  final source = await showKmSheet<ImageSource>(
    context: context,
    title: 'Add Photo',
    children: [
      KmSheetOption(
        icon: Icons.photo_camera_rounded,
        label: 'Take Photo',
        selected: false,
        onTap: () => Navigator.pop(context, ImageSource.camera),
      ),
      KmSheetOption(
        icon: Icons.photo_library_rounded,
        label: 'Choose from Gallery',
        selected: false,
        onTap: () => Navigator.pop(context, ImageSource.gallery),
      ),
    ],
  );
  if (source == null) return null;
  try {
    return await ImagePicker().pickImage(source: source, imageQuality: 80);
  } catch (e) {
    if (!context.mounted) return null;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(source == ImageSource.camera
            ? 'Could not open camera: $e'
            : 'Could not open gallery: $e')));
    return null;
  }
}

/// Advanced Check-out — Settlement Confirmation Sheet। पहिले दुवै ठाउँ
/// (booking-row action chip र QR-scan result sheet) ले सिधै
/// `updatePartnerBookingStatus(..., completed)` बोलाउँथे, कुनै पुष्टि
/// बिना — त्यही "simple button click" लाई यहाँ एउटै ठाउँमा बदल्ने।
/// Confirm हुनेबित्तिकै उही core logic (status transition + housekeeping
/// room-status flip + guest notification, `hotel_partner_service.dart`)
/// अपरिवर्तित नै बोलाउँछ — केवल यो पुष्टिकरण step थपिएको।
Future<void> showCheckoutSettlementSheet(
    BuildContext context, HotelBooking booking, String hotelName) {
  return showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (ctx) =>
        _CheckoutSettlementSheet(booking: booking, hotelName: hotelName),
  );
}

class _CheckoutSettlementSheet extends StatefulWidget {
  final HotelBooking booking;
  final String hotelName;
  const _CheckoutSettlementSheet(
      {required this.booking, required this.hotelName});

  @override
  State<_CheckoutSettlementSheet> createState() =>
      _CheckoutSettlementSheetState();
}

class _CheckoutSettlementSheetState extends State<_CheckoutSettlementSheet> {
  final _chargesCtrl = TextEditingController(text: '0');
  bool _submitting = false;

  @override
  void dispose() {
    _chargesCtrl.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    final charges = double.tryParse(_chargesCtrl.text.trim()) ?? 0;
    setState(() => _submitting = true);
    final ok = await updatePartnerBookingStatus(
      widget.booking,
      HotelBookingStatus.completed,
      widget.hotelName,
      additionalCharges: charges,
    );
    if (!mounted) return;
    Navigator.pop(context);
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not complete check-out.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final b = widget.booking;
    return Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
        decoration: const BoxDecoration(
          color: AppColors.kmSurface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.fact_check_rounded,
                    color: AppColors.kmOrange, size: 20),
                SizedBox(width: 8),
                Text('Confirm Settlement & Check-out',
                    style: TextStyle(
                        color: AppColors.kmText,
                        fontWeight: FontWeight.w800,
                        fontSize: 15)),
              ],
            ),
            const SizedBox(height: 14),
            Text(b.guestName.isEmpty ? 'Guest' : b.guestName,
                style: const TextStyle(
                    color: AppColors.kmText,
                    fontWeight: FontWeight.w700,
                    fontSize: 14)),
            const SizedBox(height: 2),
            Text(
                '${widget.hotelName} · Room total ${formatHotelPrice(b.totalPrice)}',
                style:
                    const TextStyle(color: AppColors.kmMuted, fontSize: 12.5)),
            const SizedBox(height: 18),
            const Text('Additional charges (room service / incidentals)',
                style: TextStyle(
                    color: AppColors.kmMuted,
                    fontWeight: FontWeight.w700,
                    fontSize: 12)),
            const SizedBox(height: 4),
            const Text('Leave as 0 if nothing is pending.',
                style: TextStyle(color: AppColors.kmMuted, fontSize: 11.5)),
            const SizedBox(height: 10),
            TextField(
              controller: _chargesCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(color: AppColors.kmText),
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.payments_rounded,
                    color: AppColors.kmMuted, size: 18),
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.05),
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 20),
            KmCtaButton(
              label: 'Confirm Settlement & Check-out',
              icon: Icons.logout_rounded,
              loading: _submitting,
              onPressed: _submitting ? null : _confirm,
            ),
          ],
        ),
      ),
    );
  }
}

class HotelPartnerDashboardScreen extends StatefulWidget {
  final List<String> hotelIds;
  const HotelPartnerDashboardScreen({super.key, required this.hotelIds});

  @override
  State<HotelPartnerDashboardScreen> createState() =>
      _HotelPartnerDashboardScreenState();
}

class _HotelPartnerDashboardScreenState
    extends State<HotelPartnerDashboardScreen>
    with SingleTickerProviderStateMixin {
  late String _hotelId = widget.hotelIds.first;
  late final _tabs = TabController(length: 3, vsync: this);
  String _statusFilter = 'all';

  @override
  void initState() {
    super.initState();
    // Profile banner बाट सिधै (Search screen नगई) यहाँ आइपुग्न सकिने भएकोले
    // — नत्र भर्खरै registered होटल अझै hydrate नभई "Hotel not found"
    // देखिन सक्थ्यो।
    hydrateHotelsFromFirestore().then((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Hotel? get _hotel {
    for (final h in mockHotels) {
      if (h.id == _hotelId) return h;
    }
    return null;
  }

  Future<void> _scanQr() async {
    final raw = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const QrScannerScreen()),
    );
    if (raw == null || !mounted) return;
    final booking = await findBookingByQrData(raw);
    if (!mounted) return;
    if (booking == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No booking found for this QR code.')),
      );
      return;
    }
    if (booking.hotelId != _hotelId) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('This booking belongs to a different hotel.')),
      );
      return;
    }
    _showQrResultSheet(booking);
  }

  void _showQrResultSheet(HotelBooking b) {
    final h = _hotel;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(20),
        decoration: const BoxDecoration(
          color: AppColors.kmSurface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(b.guestName.isEmpty ? 'Guest' : b.guestName,
                style: const TextStyle(
                    color: AppColors.kmText,
                    fontWeight: FontWeight.w800,
                    fontSize: 17)),
            const SizedBox(height: 4),
            Text('${h?.name ?? b.hotelId} · Booking ${b.id.substring(0, 8)}…',
                style:
                    const TextStyle(color: AppColors.kmMuted, fontSize: 12.5)),
            // Guest Phone Number Visibility — QR Scan Verification Dialog
            // (check-in बेलैको "Guest Details" view) मा पनि सिधै देखिने,
            // Booking card कै उस्तै `booking.guestPhone` snapshot।
            if (b.guestPhone.isNotEmpty) ...[
              const SizedBox(height: 4),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.phone_rounded,
                      size: 13, color: AppColors.kmMuted),
                  const SizedBox(width: 4),
                  Text(b.guestPhone,
                      style: const TextStyle(
                          color: AppColors.kmText,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700)),
                ],
              ),
            ],
            const SizedBox(height: 4),
            Text('Status: ${_statusLabel(b.status)}',
                style: const TextStyle(
                    color: AppColors.kmOrange, fontWeight: FontWeight.w700)),
            if (_amenitiesForBooking(b).isNotEmpty) ...[
              const SizedBox(height: 14),
              const Text('Selected Amenities & Add-ons',
                  style: TextStyle(
                      color: AppColors.kmMuted,
                      fontWeight: FontWeight.w800,
                      fontSize: 11,
                      letterSpacing: 0.3)),
              const SizedBox(height: 8),
              hotelAmenityChips(_amenitiesForBooking(b)),
            ],
            const SizedBox(height: 18),
            if (b.status == HotelBookingStatus.confirmed ||
                b.status == HotelBookingStatus.pending)
              KmCtaButton(
                label: 'Check In',
                icon: Icons.login_rounded,
                onPressed: () {
                  Navigator.pop(ctx);
                  _updateStatus(b, HotelBookingStatus.checkedIn);
                },
              )
            else if (b.status == HotelBookingStatus.checkedIn)
              KmCtaButton(
                label: 'Check Out',
                icon: Icons.logout_rounded,
                onPressed: () {
                  Navigator.pop(ctx);
                  showCheckoutSettlementSheet(
                      context, b, h?.name ?? b.hotelId);
                },
              )
            else
              Text(
                  'This booking is ${_statusLabel(b.status).toLowerCase()} — no action available.',
                  style: const TextStyle(color: AppColors.kmMuted)),
          ],
        ),
      ),
    );
  }

  Future<void> _updateStatus(HotelBooking b, String status) async {
    final ok =
        await updatePartnerBookingStatus(b, status, _hotel?.name ?? b.hotelId);
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not update booking status.')),
      );
    }
  }

  String _statusLabel(String s) => switch (s) {
        HotelBookingStatus.pending => 'Pending',
        HotelBookingStatus.confirmed => 'Confirmed',
        HotelBookingStatus.checkedIn => 'Checked In',
        HotelBookingStatus.cancelled => 'Cancelled',
        HotelBookingStatus.noShow => 'No-Show',
        HotelBookingStatus.completed => 'Checked Out',
        _ => s,
      };

  Color _statusColor(String s) => switch (s) {
        HotelBookingStatus.pending => AppColors.kmPurple,
        HotelBookingStatus.confirmed => AppColors.kmTeal,
        HotelBookingStatus.checkedIn => AppColors.kmOrange,
        HotelBookingStatus.cancelled => AppColors.kmMuted,
        HotelBookingStatus.noShow => AppColors.kmPink,
        HotelBookingStatus.completed => AppColors.kmTeal,
        _ => AppColors.kmMuted,
      };

  @override
  Widget build(BuildContext context) {
    final h = _hotel;
    return PartnerDashboardGuard(
      child: OledBackdrop(
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                  child: KmScreenHeader(
                    title: h?.name ?? 'Partner Dashboard',
                    actions: const [GoHomeAction()],
                  ),
                ),
                if (widget.hotelIds.length > 1)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: DropdownButton<String>(
                        value: _hotelId,
                        dropdownColor: AppColors.kmSurface,
                        style: const TextStyle(color: AppColors.kmText),
                        items: widget.hotelIds
                            .map((id) => DropdownMenuItem(
                                  value: id,
                                  child: Text(mockHotels
                                      .firstWhere((h) => h.id == id,
                                          orElse: () => mockHotels.first)
                                      .name),
                                ))
                            .toList(),
                        onChanged: (v) =>
                            setState(() => _hotelId = v ?? _hotelId),
                      ),
                    ),
                  ),
                if (h != null && h.status != HotelVerificationStatus.approved)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                    child: _VerificationBanner(status: h.status),
                  ),
                if (h == null)
                  const Expanded(
                    child: Center(
                        child: Text('Hotel not found.',
                            style: TextStyle(color: AppColors.kmMuted))),
                  )
                else
                  Expanded(
                    child: StreamBuilder<List<HotelBooking>>(
                      stream: bookingsForHotel(h.id),
                      builder: (context, snap) {
                        final bookings = snap.data ?? const [];
                        final stats = computeLiveStats(bookings);
                        return Column(
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                              child: _LiveStatsRow(stats: stats),
                            ),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                              child: KmCtaButton(
                                label: 'Scan Guest QR',
                                icon: Icons.qr_code_scanner_rounded,
                                onPressed: _scanQr,
                              ),
                            ),
                            TabBar(
                              controller: _tabs,
                              labelColor: AppColors.kmOrange,
                              unselectedLabelColor: AppColors.kmMuted,
                              indicatorColor: AppColors.kmOrange,
                              tabs: const [
                                Tab(text: 'Bookings'),
                                Tab(text: 'Rooms'),
                                Tab(text: 'Info'),
                              ],
                            ),
                            Expanded(
                              child: TabBarView(
                                controller: _tabs,
                                children: [
                                  _BookingsTab(
                                    hotel: h,
                                    bookings: bookings,
                                    filter: _statusFilter,
                                    onFilterChanged: (v) =>
                                        setState(() => _statusFilter = v),
                                    statusLabel: _statusLabel,
                                    statusColor: _statusColor,
                                    onUpdateStatus: _updateStatus,
                                  ),
                                  _RoomsTab(hotel: h, bookings: bookings),
                                  _HotelInfoTab(hotel: h),
                                ],
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
          // Exit to Main Home — यो screen पनि MainContainer बाहिर push
          // गरिएको (job_feed_screen.dart/driver_dashboard_screen.dart कै
          // उस्तै "Dashboard-Stuck" जड भएन किनभने यहाँ drawer छैन, AppBar ले
          // आफैं back देखाउँछ — तर प्रयोगकर्ताले छुट्टै "Home" button नै
          // प्रस्टसँग खोजेको हुनाले यो bar पनि यहाँ थपियो)।
          bottomNavigationBar: DashboardExitBar(
            onMessagesTap: h == null
                ? null
                : () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => _HotelMessagesScreen(hotel: h),
                      ),
                    ),
          ),
        ),
      ),
    );
  }
}

/// Hotel Registration/Onboarding — Super-Admin verification अझै pending/
/// rejected रहेसम्म partner dashboard मा देखिने स्पष्ट सूचना (bookings
/// अझै खुल्दैनन् भन्ने कुरा पनि यहीं)।
class _VerificationBanner extends StatelessWidget {
  final String status;
  const _VerificationBanner({required this.status});

  @override
  Widget build(BuildContext context) {
    final rejected = status == HotelVerificationStatus.rejected;
    final color = rejected ? AppColors.kmRose : AppColors.kmOrange;
    final text = rejected
        ? 'Your hotel registration was rejected by Admin. Please review your documents and contact support.'
        : 'Your hotel registration is under verification by Admin. Guests will be able to find and book this hotel once it is approved.';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(rejected ? Icons.cancel_rounded : Icons.hourglass_top_rounded,
              color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text,
                style: TextStyle(
                    color: color, fontWeight: FontWeight.w700, fontSize: 12.5)),
          ),
        ],
      ),
    );
  }
}

class _LiveStatsRow extends StatelessWidget {
  final HotelLiveStats stats;
  const _LiveStatsRow({required this.stats});

  @override
  Widget build(BuildContext context) {
    Widget tile(String label, String value, IconData icon, Color color) =>
        Expanded(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 3),
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
            ),
            child: Column(
              children: [
                Icon(icon, color: color, size: 18),
                const SizedBox(height: 6),
                Text(value,
                    style: const TextStyle(
                        color: AppColors.kmText,
                        fontWeight: FontWeight.w800,
                        fontSize: 15)),
                const SizedBox(height: 2),
                Text(label,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: AppColors.kmMuted, fontSize: 9.5)),
              ],
            ),
          ),
        );
    return Row(
      children: [
        tile('Arrivals', '${stats.arrivalsToday}', Icons.flight_land_rounded,
            AppColors.kmTeal),
        tile('Departures', '${stats.departuresToday}',
            Icons.flight_takeoff_rounded, AppColors.kmOrange),
        tile('Active Stays', '${stats.activeStays}', Icons.hotel_rounded,
            AppColors.kmPurple),
        tile('Revenue', formatHotelPrice(stats.totalRevenue),
            Icons.payments_rounded, AppColors.kmPink),
      ],
    );
  }
}

class _BookingsTab extends StatelessWidget {
  final Hotel hotel;
  final List<HotelBooking> bookings;
  final String filter;
  final ValueChanged<String> onFilterChanged;
  final String Function(String) statusLabel;
  final Color Function(String) statusColor;
  final void Function(HotelBooking, String) onUpdateStatus;
  const _BookingsTab({
    required this.hotel,
    required this.bookings,
    required this.filter,
    required this.onFilterChanged,
    required this.statusLabel,
    required this.statusColor,
    required this.onUpdateStatus,
  });

  @override
  Widget build(BuildContext context) {
    final filtered = filter == 'all'
        ? bookings
        : bookings.where((b) => b.status == filter).toList();
    final filters = [
      'all',
      HotelBookingStatus.pending,
      HotelBookingStatus.confirmed,
      HotelBookingStatus.checkedIn,
      HotelBookingStatus.completed,
      HotelBookingStatus.cancelled,
      HotelBookingStatus.noShow,
    ];
    return Column(
      children: [
        SizedBox(
          height: 44,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
            children: filters
                .map((f) => Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(f == 'all' ? 'All' : statusLabel(f)),
                        selected: filter == f,
                        onSelected: (_) => onFilterChanged(f),
                        selectedColor: AppColors.kmOrange,
                        labelStyle: TextStyle(
                            color: filter == f
                                ? AppColors.kmInk
                                : AppColors.kmText,
                            fontWeight: FontWeight.w700,
                            fontSize: 12),
                        backgroundColor: Colors.white.withValues(alpha: 0.06),
                      ),
                    ))
                .toList(),
          ),
        ),
        Expanded(
          child: filtered.isEmpty
              ? const Center(
                  child: Text('No bookings here.',
                      style: TextStyle(color: AppColors.kmMuted)),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                  itemCount: filtered.length,
                  itemBuilder: (context, i) => _BookingRow(
                    booking: filtered[i],
                    statusLabel: statusLabel,
                    statusColor: statusColor,
                    onUpdateStatus: onUpdateStatus,
                  ),
                ),
        ),
      ],
    );
  }
}

class _BookingRow extends StatelessWidget {
  final HotelBooking booking;
  final String Function(String) statusLabel;
  final Color Function(String) statusColor;
  final void Function(HotelBooking, String) onUpdateStatus;
  const _BookingRow({
    required this.booking,
    required this.statusLabel,
    required this.statusColor,
    required this.onUpdateStatus,
  });

  String _fmt(DateTime d) => '${d.day}/${d.month}/${d.year}';

  @override
  Widget build(BuildContext context) {
    final color = statusColor(booking.status);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                    booking.guestName.isEmpty ? 'Guest' : booking.guestName,
                    style: const TextStyle(
                        color: AppColors.kmText,
                        fontWeight: FontWeight.w800,
                        fontSize: 14)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
                child: Text(statusLabel(booking.status),
                    style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.w700,
                        fontSize: 10.5)),
              ),
            ],
          ),
          // Guest Phone Number Visibility — counter staff ले check-in/
          // verification बेला सिधै यहीँबाट नम्बर देख्न सकोस् (Call बटन
          // थिच्नु नपरी पनि) — `booking.guestPhone` (checkout-बेलैको
          // snapshot, hotel_bookings/{id}.guestPhone, HotelBooking model)।
          if (booking.guestPhone.isNotEmpty) ...[
            const SizedBox(height: 2),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.phone_rounded,
                    size: 12, color: AppColors.kmMuted),
                const SizedBox(width: 4),
                Text(booking.guestPhone,
                    style: const TextStyle(
                        color: AppColors.kmMuted,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600)),
              ],
            ),
          ],
          if (_amenitiesForBooking(booking).isNotEmpty) ...[
            const SizedBox(height: 6),
            hotelAmenityChips(_amenitiesForBooking(booking),
                fontSize: 10, iconSize: 12, padV: 3),
          ],
          const SizedBox(height: 4),
          Text(
              '${_fmt(booking.checkInDate)} → ${_fmt(booking.checkOutDate)} · ${booking.guestsCount} guests · ${formatHotelPrice(booking.totalPrice)}',
              style: const TextStyle(color: AppColors.kmMuted, fontSize: 11.5)),
          // Fraud/No-Show Prevention — "Pay at Hotel" booking मा मात्र देखिने,
          // guest ले checkout मा advance token payment गरिसकेको भन्ने संकेत।
          if (booking.paymentType == HotelPaymentType.payAtHotel &&
              booking.depositReference.isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.verified_rounded,
                    color: AppColors.kmOrange, size: 13),
                const SizedBox(width: 4),
                Text(
                    'Token deposit paid · ${formatHotelPrice(booking.depositAmount)}',
                    style: const TextStyle(
                        color: AppColors.kmOrange,
                        fontWeight: FontWeight.w700,
                        fontSize: 10.5)),
              ],
            ),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (booking.status == HotelBookingStatus.pending)
                _actionChip(
                    'Confirm',
                    Icons.check_rounded,
                    () =>
                        onUpdateStatus(booking, HotelBookingStatus.confirmed)),
              if (booking.status == HotelBookingStatus.pending ||
                  booking.status == HotelBookingStatus.confirmed) ...[
                _actionChip(
                    'Check-In',
                    Icons.login_rounded,
                    () =>
                        onUpdateStatus(booking, HotelBookingStatus.checkedIn)),
                _actionChip('No-Show', Icons.person_off_rounded,
                    () => onUpdateStatus(booking, HotelBookingStatus.noShow)),
                _actionChip(
                    'Cancel',
                    Icons.close_rounded,
                    () =>
                        onUpdateStatus(booking, HotelBookingStatus.cancelled)),
              ],
              if (booking.status == HotelBookingStatus.checkedIn)
                _actionChip(
                    'Check-Out',
                    Icons.logout_rounded,
                    () => showCheckoutSettlementSheet(
                        context, booking, booking.hotelId)),
              // Acceptance-Gated Communication — booking confirmed/checked-in
              // भएकै क्षणदेखि (कुनै थप registration/gating बिना) Call/Video/
              // Message स्थायी रूपमा खुल्ला (`isHotelCommunicationUnlocked`,
              // hotel_models.dart)।
              if (isHotelCommunicationUnlocked(booking.status)) ...[
                _actionChip('Call', Icons.call_rounded,
                    () => _dialGuestPhone(context, booking.guestPhone)),
                _actionChip(
                    'Video',
                    Icons.videocam_rounded,
                    () => startInAppCall(
                          context,
                          requestId: booking.id,
                          otherName: booking.guestName.isEmpty
                              ? 'Guest'
                              : booking.guestName,
                          video: true,
                          otherUid: booking.userId,
                        )),
                _actionChip(
                    'Message',
                    Icons.chat_bubble_rounded,
                    () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ChatScreen(
                              requestId: booking.id,
                              workerName: booking.guestName.isEmpty
                                  ? 'Guest'
                                  : booking.guestName,
                              initialStatus: booking.status,
                              statusCollection: 'hotel_bookings',
                              otherUid: booking.userId,
                              unlockedStatuses: kActiveHotelBookingStatuses,
                            ),
                          ),
                        )),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _actionChip(String label, IconData icon, VoidCallback onTap) =>
      OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 14),
        label: Text(label, style: const TextStyle(fontSize: 11)),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.kmOrange,
          side: const BorderSide(color: AppColors.kmOrange),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          minimumSize: const Size(0, 32),
        ),
      );
}

/// "Call" बटनले अब in-app WebRTC होइन, सिधै native phone dialer (`tel:`)
/// खोलोस् — `booking.guestPhone` (checkout-बेलैको guest contact, HotelBooking
/// मा पहिल्यैदेखि छ) प्रयोग गरेर। "Video" भने अझै in-app नै (`startInAppCall`)।
Future<void> _dialGuestPhone(BuildContext context, String phone) async {
  final p = phone.trim();
  if (p.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('No phone number on file for this guest.')),
    );
    return;
  }
  try {
    await launchUrl(Uri(scheme: 'tel', path: p));
  } catch (_) {}
}

/// कुनै booking को assigned Room Number/type — `_HotelMessagesScreen` र
/// `_GuestLogbookScreen` दुवैले साझा गर्ने (duplicate नहोस् भनेर)।
String _roomLabelForBooking(String hotelId, String roomId) {
  for (final r in mockRoomsForHotel(hotelId)) {
    if (r.id == roomId) {
      return r.roomNumber.isEmpty ? r.roomType : r.roomNumber;
    }
  }
  return '';
}

/// बुकिङले आफैं स्नैपशट गरेको amenities (`HotelBooking.amenities`) छ भने
/// त्यही, नत्र (field थपिनुअघि सिर्जना भएका पुरानो बुकिङका लागि) त्यही
/// कोठाको हालको amenities मा fallback — `_BookingRow`/QR Scan Verification
/// Dialog दुवैले साझा गर्ने।
List<String> _amenitiesForBooking(HotelBooking b) {
  if (b.amenities.isNotEmpty) return b.amenities;
  for (final r in mockRoomsForHotel(b.hotelId)) {
    if (r.id == b.roomId) return r.amenities;
  }
  return const [];
}

/// Scoped Hotel Messages — DashboardExitBar को "Messages" ले यहाँ ल्याउने
/// (global ride/bike chat तिर होइन, पुरानो गुनासो: "Messages थिच्दा Home/
/// ride chat मा पुग्छ")। यही होटलका सबै guest booking मात्र — guest नाम,
/// कोठा, मिति र Call/Video/Message, Acceptance-Gated Communication
/// (`isHotelCommunicationUnlocked`) अझै लागू भई।
class _HotelMessagesScreen extends StatelessWidget {
  final Hotel hotel;
  const _HotelMessagesScreen({required this.hotel});

  String _roomLabel(String roomId) => _roomLabelForBooking(hotel.id, roomId);

  @override
  Widget build(BuildContext context) {
    return OledBackdrop(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                child: KmScreenHeader(
                  title: 'Messages · ${hotel.name}',
                  actions: const [GoHomeAction()],
                ),
              ),
              Expanded(
                child: StreamBuilder<List<HotelBooking>>(
                  stream: bookingsForHotel(hotel.id),
                  builder: (context, snap) {
                    final bookings = snap.data ?? const [];
                    if (bookings.isEmpty) {
                      return const Center(
                        child: Text('No guest bookings to message yet.',
                            style: TextStyle(color: AppColors.kmMuted)),
                      );
                    }
                    return ListView.builder(
                      padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
                      itemCount: bookings.length,
                      itemBuilder: (context, i) => _HotelMessageRow(
                        booking: bookings[i],
                        roomLabel: _roomLabel(bookings[i].roomId),
                      ),
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
}

class _HotelMessageRow extends StatelessWidget {
  final HotelBooking booking;
  final String roomLabel;
  const _HotelMessageRow({required this.booking, required this.roomLabel});

  String _fmt(DateTime d) => '${d.day}/${d.month}/${d.year}';

  @override
  Widget build(BuildContext context) {
    final unlocked = isHotelCommunicationUnlocked(booking.status);
    final name = booking.guestName.isEmpty ? 'Guest' : booking.guestName;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(name,
                    style: const TextStyle(
                        color: AppColors.kmText,
                        fontWeight: FontWeight.w800,
                        fontSize: 14.5)),
              ),
              if (!unlocked)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.kmMuted.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                  child: const Text('Locked',
                      style: TextStyle(
                          color: AppColors.kmMuted,
                          fontWeight: FontWeight.w700,
                          fontSize: 10.5)),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
              '${roomLabel.isEmpty ? '' : '$roomLabel · '}'
              '${_fmt(booking.checkInDate)} → ${_fmt(booking.checkOutDate)}',
              style: const TextStyle(color: AppColors.kmMuted, fontSize: 11.5)),
          if (!unlocked) ...[
            const SizedBox(height: 8),
            const Text(
                'Available once the booking is confirmed or checked in.',
                style: TextStyle(color: AppColors.kmMuted, fontSize: 11)),
          ] else ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _chip('Call', Icons.call_rounded,
                    () => _dialGuestPhone(context, booking.guestPhone)),
                _chip('Video', Icons.videocam_rounded, () => startInAppCall(
                      context,
                      requestId: booking.id,
                      otherName: name,
                      video: true,
                      otherUid: booking.userId,
                    )),
                _chip('Message', Icons.chat_bubble_rounded, () =>
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ChatScreen(
                          requestId: booking.id,
                          workerName: name,
                          initialStatus: booking.status,
                          statusCollection: 'hotel_bookings',
                          otherUid: booking.userId,
                          unlockedStatuses: kActiveHotelBookingStatuses,
                        ),
                      ),
                    )),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _chip(String label, IconData icon, VoidCallback onTap) =>
      OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 14),
        label: Text(label, style: const TextStyle(fontSize: 11)),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.kmOrange,
          side: const BorderSide(color: AppColors.kmOrange),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          minimumSize: const Size(0, 32),
        ),
      );
}

/// Guest Logbook — Info tab को button ले यहाँ ल्याउने, पूरा past+present
/// guest ledger (`allBookingsForHotel` — filter नगरिएको, हरेक कहिल्यै बुक
/// भएको booking सधैँ देखिन्छ, Bookings tab कै "हाल-सक्रिय मात्र" भन्दा
/// फरक)। Name, Room Number, Check-In/Out timestamp, Payment Status, Total
/// Amount — owner को audit/history आवश्यकताका लागि।
class _GuestLogbookScreen extends StatelessWidget {
  final Hotel hotel;
  const _GuestLogbookScreen({required this.hotel});

  @override
  Widget build(BuildContext context) {
    return OledBackdrop(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                child: KmScreenHeader(
                  title: 'Guest Logbook · ${hotel.name}',
                  actions: const [GoHomeAction()],
                ),
              ),
              Expanded(
                child: StreamBuilder<List<HotelBooking>>(
                  stream: allBookingsForHotel(hotel.id),
                  builder: (context, snap) {
                    final bookings = snap.data ?? const [];
                    if (bookings.isEmpty) {
                      return const Center(
                        child: Text('No guests recorded yet.',
                            style: TextStyle(color: AppColors.kmMuted)),
                      );
                    }
                    return ListView.builder(
                      padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
                      itemCount: bookings.length,
                      itemBuilder: (context, i) => _GuestLogbookRow(
                        booking: bookings[i],
                        roomLabel:
                            _roomLabelForBooking(hotel.id, bookings[i].roomId),
                      ),
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
}

class _GuestLogbookRow extends StatelessWidget {
  final HotelBooking booking;
  final String roomLabel;
  const _GuestLogbookRow({required this.booking, required this.roomLabel});

  String _fmtDateTime(DateTime? d) {
    if (d == null) return '—';
    final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final ampm = d.hour >= 12 ? 'PM' : 'AM';
    final mm = d.minute.toString().padLeft(2, '0');
    return '${d.day}/${d.month}/${d.year} · $h:$mm $ampm';
  }

  Widget _stamp(String label, String value) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(
                  color: AppColors.kmMuted,
                  fontSize: 10,
                  fontWeight: FontWeight.w700)),
          Text(value,
              style: const TextStyle(color: AppColors.kmText, fontSize: 11.5)),
        ],
      );

  @override
  Widget build(BuildContext context) {
    final b = booking;
    final name = b.guestName.isEmpty ? 'Guest' : b.guestName;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(name,
                    style: const TextStyle(
                        color: AppColors.kmText,
                        fontWeight: FontWeight.w800,
                        fontSize: 14.5)),
              ),
              Text(formatHotelPrice(b.totalPrice),
                  style: const TextStyle(
                      color: AppColors.kmOrange,
                      fontWeight: FontWeight.w800,
                      fontSize: 13.5)),
            ],
          ),
          const SizedBox(height: 4),
          Text(
              '${roomLabel.isEmpty ? '' : '$roomLabel · '}'
              '${b.paymentType == HotelPaymentType.payAtHotel ? 'Pay at Hotel' : 'Paid Online'}',
              style:
                  const TextStyle(color: AppColors.kmMuted, fontSize: 11.5)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: _stamp('Check-In', _fmtDateTime(b.checkedInAt))),
              Expanded(
                  child: _stamp('Check-Out', _fmtDateTime(b.checkedOutAt))),
            ],
          ),
        ],
      ),
    );
  }
}

class _RoomsTab extends StatefulWidget {
  final Hotel hotel;
  final List<HotelBooking> bookings;
  const _RoomsTab({required this.hotel, required this.bookings});

  @override
  State<_RoomsTab> createState() => _RoomsTabState();
}

/// दिइएको कोठाको आज (अहिले) सक्रिय booking (pending/confirmed/checked_in
/// जुनसुकै, आजको मिति check-in/check-out बीच पर्ने) — भए फर्काउँछ, नत्र
/// null। Room Number Live Sync (बुकिङ भएपछि Owner Dashboard मा स्वतः
/// "Booked" देखिने) — `_RoomEditRow` ले यही प्रयोग गर्छ, कुनै छुट्टै
/// Firestore listener/per-night counter नचाहिकनै (माथि नै fetch भइसकेको
/// `bookings` स्ट्रिम पुनःप्रयोग)।
HotelBooking? _activeBookingForRoom(
    String roomId, List<HotelBooking> bookings) {
  final today = DateTime.now();
  for (final b in bookings) {
    if (b.roomId != roomId) continue;
    if (b.status != HotelBookingStatus.pending &&
        b.status != HotelBookingStatus.confirmed &&
        b.status != HotelBookingStatus.checkedIn) {
      continue;
    }
    if (!today.isBefore(b.checkInDate) && today.isBefore(b.checkOutDate)) {
      return b;
    }
  }
  return null;
}

/// Comprehensive Master Amenities List — "Add Room" को amenity चिप grid ले
/// देखाउने पूरा सूची: app-भरि साझा हुने ८ global amenity (`kHotelAmenities`,
/// hotel_common.dart — होटलको आफ्नै Info-tab amenity सँगै उस्तै) + कोठा-
/// विशेष comfort/luxury amenity। `HotelRoomType.defaultAmenities` (models
/// तहमा, जहाँ `kHotelAmenities` import गर्न मिल्दैन — screens ले models
/// import गर्ने हो, उल्टो होइन) सँग ठ्याक्कै मिल्ने गरी यहाँ राखिएको।
const _kRoomDetailedAmenities = [
  'Smart TV',
  'Coffee/Tea Maker',
  'Mini Fridge',
  'Balcony / Private Terrace',
  'Desk / Workspace',
  'Jacuzzi / Bathtub',
  'Mini Bar',
  'Living Area / Sofa',
];
const _kRoomAmenityMasterList = [
  ...kHotelAmenities,
  ..._kRoomDetailedAmenities
];

const _kMaxRoomPhotos = 10;

class _RoomsTabState extends State<_RoomsTab> {
  /// Multi-Image Upload Support — पहिले एकपटकमा एउटै फोटो मात्र (tap दोहोर्‍याएर
  /// थप्नुपर्ने) थियो। अब hotel_registration_screen.dart::_addPhotos कै उस्तै
  /// `pickMultiImage` — partner ले एकैचोटि धेरै (बढीमा १०) फोटो छान्न सक्छन्।
  Future<void> _pickRoomImages(BuildContext dialogContext,
      ValueNotifier<List<_PickedRoomImage>> pickedImages) async {
    if (pickedImages.value.length >= _kMaxRoomPhotos) return;
    List<XFile> picked;
    try {
      picked = await ImagePicker().pickMultiImage(imageQuality: 80);
    } catch (e) {
      if (!dialogContext.mounted) return;
      ScaffoldMessenger.of(dialogContext).showSnackBar(
        SnackBar(content: Text('Could not open gallery: $e')),
      );
      return;
    }
    if (picked.isEmpty) return;
    final room = _kMaxRoomPhotos - pickedImages.value.length;
    final accepted = <_PickedRoomImage>[];
    for (final p in picked.take(room)) {
      final bytes = await p.readAsBytes();
      final err = UploadValidation.validate(bytes, p.name);
      if (err != null) {
        if (!dialogContext.mounted) return;
        ScaffoldMessenger.of(dialogContext).showSnackBar(
            SnackBar(content: Text(UploadValidation.messageFor(err))));
        continue;
      }
      accepted.add(_PickedRoomImage(bytes: bytes, name: p.name));
    }
    if (accepted.isNotEmpty) {
      pickedImages.value = [...pickedImages.value, ...accepted];
    }
  }

  Future<void> _openAddRoomDialog() async {
    final roomNumberCtrl = TextEditingController();
    final typeCtrl = TextEditingController(text: HotelRoomType.single);
    final priceCtrl = TextEditingController();
    final capacityCtrl = TextEditingController(text: '2');
    final inventoryCtrl = TextEditingController(text: '1');
    // `StatefulBuilder` (तल) ले `content:` मात्र पुनः-build गर्छ, `actions:`
    // (छुट्टै top-level param, showKmDialog हेर्नुहोस्) होइन — त्यसैले
    // Add-बटनले आफैं upload-in-progress देखाउन सकोस् भनेर `ValueNotifier`
    // (content/actions दुवैले सुन्ने) प्रयोग गरिएको, local `setState` होइन।
    final pickedImages = ValueNotifier<List<_PickedRoomImage>>([]);
    final uploading = ValueNotifier<bool>(false);
    // Dynamic Smart Room Amenities — सुरुमा Single (डिफल्ट category) कै
    // preset सँग pre-check। category चिप बदलिँदा यही reset हुन्छ (तल
    // onSelected हेर्नुहोस्) — owner ले पछि आफैं कुनै पनि चिप थप्ने/
    // हटाउने गरी customize गर्न सक्छ।
    final amenities = ValueNotifier<Set<String>>(
        {...HotelRoomType.defaultAmenities[HotelRoomType.single]!});
    await showKmDialog(
      context: context,
      title: 'Add Room',
      icon: Icons.add_home_work_rounded,
      // Dynamic Smart Room Amenities ले content निकै अग्लो बनाइदिएको
      // (१६ amenity चिपसम्म) — `showKmDialog` कै बाँकी सबै साना dialog
      // (यहाँ सिवाय बाँकी जहाँ पनि scroll नचाहिने) लाई असर नपर्ने गरी,
      // यही एउटा dialog भित्र मात्र height-bound + scroll थपिएको, नत्र
      // तल्लो चिप/Cancel-Add बटन नै स्क्रिन बाहिर गएर अपुग हुन्थ्यो।
      content: SizedBox(
        width: double.maxFinite,
        child: ConstrainedBox(
          constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.55),
          child: SingleChildScrollView(
            child: StatefulBuilder(
              builder: (dialogContext, setDialogState) => Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Room Number Input — स्पष्ट रूपमा "Room No." भनेर label
                  // गरिएको, ताकि partner ले स्वाभाविक रूपमा ठ्याक्कै भौतिक
                  // कोठा-नम्बर (101, 134 आदि) भर्ने — Overbooking Prevention/
                  // Real-Time Availability Hide (hotel_detail_screen.dart)
                  // जस्ता specific-room-number फिचरका लागि यो नम्बर नै आधार हो।
                  TextField(
                    controller: roomNumberCtrl,
                    textCapitalization: TextCapitalization.words,
                    style: const TextStyle(color: AppColors.kmText),
                    decoration: kmInputDecoration('Room No.',
                        hint: 'e.g. 101, 102, 134'),
                  ),
                  const SizedBox(height: 14),
                  const Text('Photos',
                      style: TextStyle(
                          color: AppColors.kmMuted,
                          fontSize: 11,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  ValueListenableBuilder<List<_PickedRoomImage>>(
                    valueListenable: pickedImages,
                    builder: (context, images, __) => Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (var i = 0; i < images.length; i++)
                          _RoomImageThumb(
                            bytes: images[i].bytes,
                            onRemove: () {
                              final next = List<_PickedRoomImage>.from(
                                  pickedImages.value)
                                ..removeAt(i);
                              pickedImages.value = next;
                            },
                          ),
                        if (images.length < _kMaxRoomPhotos)
                          _AddRoomImageTile(
                              onTap: () =>
                                  _pickRoomImages(dialogContext, pickedImages)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: HotelRoomType.presets.map((t) {
                      final selected = typeCtrl.text == t;
                      return ChoiceChip(
                        label: Text(t),
                        selected: selected,
                        onSelected: (_) => setDialogState(() {
                          typeCtrl.text = t;
                          amenities.value = {
                            ...HotelRoomType.defaultAmenities[t]!
                          };
                        }),
                        selectedColor: AppColors.kmOrange,
                        labelStyle: TextStyle(
                            color:
                                selected ? AppColors.kmInk : AppColors.kmText,
                            fontWeight: FontWeight.w700),
                        backgroundColor: Colors.white.withValues(alpha: 0.06),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 14),
                  const Text('Amenities',
                      style: TextStyle(
                          color: AppColors.kmMuted,
                          fontSize: 11,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  const Text(
                      'Pre-selected for this category — tap to customize.',
                      style:
                          TextStyle(color: AppColors.kmMuted, fontSize: 10.5)),
                  const SizedBox(height: 6),
                  ValueListenableBuilder<Set<String>>(
                    valueListenable: amenities,
                    builder: (context, selectedAmenities, __) => Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _kRoomAmenityMasterList.map((a) {
                        final selected = selectedAmenities.contains(a);
                        return FilterChip(
                          avatar: Icon(hotelAmenityIcon(a),
                              size: 15,
                              color: selected
                                  ? AppColors.kmInk
                                  : AppColors.kmMuted),
                          label:
                              Text(a, style: const TextStyle(fontSize: 11.5)),
                          selected: selected,
                          onSelected: (v) {
                            final next = {...selectedAmenities};
                            v ? next.add(a) : next.remove(a);
                            amenities.value = next;
                          },
                          selectedColor: AppColors.kmOrange,
                          labelStyle: TextStyle(
                              color:
                                  selected ? AppColors.kmInk : AppColors.kmText,
                              fontWeight: FontWeight.w700),
                          backgroundColor: Colors.white.withValues(alpha: 0.06),
                        );
                      }).toList(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: priceCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                          RegExp(r'^\d*\.?\d{0,2}')),
                    ],
                    style: const TextStyle(color: AppColors.kmText),
                    decoration: kmInputDecoration('Price per night (Rs.)'),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: capacityCtrl,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly
                          ],
                          style: const TextStyle(color: AppColors.kmText),
                          decoration: kmInputDecoration('Capacity'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: inventoryCtrl,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly
                          ],
                          style: const TextStyle(color: AppColors.kmText),
                          decoration: kmInputDecoration('Total units'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      actions: [
        KmDialogAction(
          label: 'Cancel',
          onPressed: () {
            if (!context.mounted) return;
            Navigator.of(context).pop();
          },
        ),
        ValueListenableBuilder<bool>(
          valueListenable: uploading,
          // नोट: यो builder-को आफ्नै `context` भन्दा बाहिरको, स्क्रिनकै असली
          // `context` (`_openAddRoomDialog()` माथिकै, `_RoomsTabState.context`)
          // जानाजान यहाँ *प्रयोग गरिएको छैन* — दुवैको नाम `context` भए पनि
          // inner builder भित्र Dart-कै shadowing ले गल्तीले फरक-फरक context
          // मिसिने जोखिम हुन्थ्यो (कुन कहिले mounted/unmounted हुन्छ भन्ने
          // फरक हुन सक्ने)। त्यसैले यहाँ `_` (unused) राखेर सधैँ बाहिरको
          // `context` मात्र (closure capture) प्रयोग गरिएको — स्पष्ट/सुरक्षित।
          builder: (_, isUploading, __) => KmDialogAction(
            label: isUploading ? 'Adding…' : 'Add',
            filled: true,
            onPressed: isUploading
                ? null
                : () async {
                    final roomNumber = roomNumberCtrl.text.trim();
                    final price = double.tryParse(priceCtrl.text.trim());
                    final capacity = int.tryParse(capacityCtrl.text.trim());
                    final inventory = int.tryParse(inventoryCtrl.text.trim());
                    if (roomNumber.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                          content: Text(
                              'Enter a room number or name (e.g. Room 101).')));
                      return;
                    }
                    if (price == null ||
                        price <= 0 ||
                        capacity == null ||
                        capacity <= 0 ||
                        inventory == null ||
                        inventory <= 0) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                          content: Text(
                              'Enter a valid price, capacity and unit count.')));
                      return;
                    }
                    final images = pickedImages.value;
                    final roomId = newRoomId();
                    final urls = <String>[];
                    if (images.isNotEmpty) {
                      uploading.value = true;
                      final uid =
                          FirebaseAuth.instance.currentUser?.uid ?? 'unknown';
                      try {
                        for (var i = 0; i < images.length; i++) {
                          final img = images[i];
                          final ext = UploadValidation.safeExtension(img.name);
                          final ref = FirebaseStorage.instance.ref(
                              'hotel_photos/$uid/${widget.hotel.id}/room_${roomId}_$i.$ext');
                          final sniffed = UploadValidation.sniffMime(img.bytes);
                          await ref.putData(
                            img.bytes,
                            SettableMetadata(
                                contentType: sniffed.isNotEmpty
                                    ? sniffed
                                    : 'image/jpeg'),
                          );
                          urls.add(await ref.getDownloadURL());
                        }
                      } catch (e) {
                        uploading.value = false;
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Image upload failed: $e')));
                        return;
                      }
                    }
                    try {
                      await addRoomToHotel(
                        widget.hotel.id,
                        roomType: typeCtrl.text,
                        roomNumber: roomNumber,
                        pricePerNight: price,
                        capacity: capacity,
                        totalInventory: inventory,
                        amenities: amenities.value.toList(),
                        images: urls,
                        roomId: roomId,
                      );
                    } catch (e) {
                      uploading.value = false;
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Could not save room: $e')));
                      return;
                    }
                    if (!mounted) return;
                    Navigator.of(context).pop();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                          content:
                              Text('${typeCtrl.text} · $roomNumber added.')),
                    );
                  },
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: hotelCatalogVersion,
      builder: (context, _, __) {
        final rooms = mockRoomsForHotel(widget.hotel.id);
        // Category-अनुसार grouping — पहिले preset order (Single/Deluxe/
        // Suite), त्यसपछि partner ले कुनै अर्को नाम टाइप गरेको भए (पुरानो
        // डेटा) बाँकी जति सोही क्रममा।
        final grouped = <String, List<HotelRoom>>{};
        for (final type in HotelRoomType.presets) {
          grouped[type] = [];
        }
        for (final r in rooms) {
          grouped.putIfAbsent(r.roomType, () => []).add(r);
        }
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
          children: [
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _openAddRoomDialog,
                icon: const Icon(Icons.add_rounded),
                label: const Text('Add Room'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.kmOrange,
                  side: const BorderSide(color: AppColors.kmOrange),
                  padding: const EdgeInsets.symmetric(vertical: 11),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                const Icon(Icons.cloud_done_rounded,
                    color: AppColors.kmTeal, size: 18),
                const SizedBox(width: 6),
                const Text('Online Live Rooms',
                    style: TextStyle(
                        color: AppColors.kmText,
                        fontWeight: FontWeight.w800,
                        fontSize: 14.5)),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.kmTeal.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                  child: Text('${rooms.length}',
                      style: const TextStyle(
                          color: AppColors.kmTeal,
                          fontWeight: FontWeight.w700,
                          fontSize: 11.5)),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
                'Everything already uploaded to Firebase — check here first '
                'so you don\'t list the same room twice.',
                style: TextStyle(color: AppColors.kmMuted, fontSize: 11.5)),
            const SizedBox(height: 14),
            if (rooms.isEmpty)
              const Text(
                  'No rooms uploaded yet. Tap "Add Room" to get started.',
                  style: TextStyle(color: AppColors.kmMuted, fontSize: 12.5))
            else
              for (final entry in grouped.entries)
                if (entry.value.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.only(top: 6, bottom: 8),
                    child: Row(
                      children: [
                        Text(entry.key,
                            style: const TextStyle(
                                color: AppColors.kmOrange,
                                fontWeight: FontWeight.w800,
                                fontSize: 13)),
                        const SizedBox(width: 6),
                        Text('(${entry.value.length})',
                            style: const TextStyle(
                                color: AppColors.kmMuted, fontSize: 11.5)),
                      ],
                    ),
                  ),
                  for (final r in entry.value)
                    _RoomEditRow(
                      room: r,
                      activeBooking:
                          _activeBookingForRoom(r.id, widget.bookings),
                    ),
                ],
          ],
        );
      },
    );
  }
}

/// "Add Room" dialog भित्र gallery बाट छानिएको तर अझै upload नभएको फोटो —
/// bytes नै राखिन्छ (preview + पछि upload दुवैका लागि, फेरि disk/gallery
/// बाट पढ्नु नपरोस्)।
class _PickedRoomImage {
  final Uint8List bytes;
  final String name;
  const _PickedRoomImage({required this.bytes, required this.name});
}

/// छानिसकेको फोटोको सानो thumbnail — माथि-दायाँ कुनामा हटाउने (x) बटन सहित।
class _RoomImageThumb extends StatelessWidget {
  final Uint8List bytes;
  final VoidCallback onRemove;
  const _RoomImageThumb({required this.bytes, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 64,
      height: 64,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child:
                Image.memory(bytes, width: 64, height: 64, fit: BoxFit.cover),
          ),
          Positioned(
            top: -6,
            right: -6,
            child: GestureDetector(
              onTap: onRemove,
              child: Container(
                width: 20,
                height: 20,
                decoration: const BoxDecoration(
                    color: AppColors.kmRose, shape: BoxShape.circle),
                child: const Icon(Icons.close_rounded,
                    size: 14, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// फोटो थप्ने ट्याइल — ट्याप गर्दा gallery/file picker खुल्छ (मोबाइलमा
/// native gallery/camera chooser, web/desktop मा OS-कै file picker —
/// `image_picker` plugin ले platform अनुसार आफैं छान्छ, यहाँ छुट्टै
/// web/mobile शाखा चाहिँदैन)।
class _AddRoomImageTile extends StatelessWidget {
  final VoidCallback onTap;
  const _AddRoomImageTile({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: AppColors.kmOrange.withValues(alpha: 0.6), width: 1.2),
          color: Colors.white.withValues(alpha: 0.04),
        ),
        child: const Icon(Icons.add_a_photo_rounded,
            color: AppColors.kmOrange, size: 22),
      ),
    );
  }
}

class _RoomEditRow extends StatefulWidget {
  final HotelRoom room;
  // Automatic Live Booking Sync — आज सक्रिय (pending/confirmed/checked_in)
  // booking भए यही कोठाको लागि, नत्र null। कुनै manual toggle होइन —
  // `bookingsForHotel` स्ट्रिम बाटै प्रत्येक update मा स्वतः पुनर्गणना
  // (`_activeBookingForRoom` हेर्नुहोस्)।
  final HotelBooking? activeBooking;
  const _RoomEditRow({required this.room, this.activeBooking});

  @override
  State<_RoomEditRow> createState() => _RoomEditRowState();
}

class _RoomEditRowState extends State<_RoomEditRow> {
  late final _priceCtrl =
      TextEditingController(text: widget.room.pricePerNight.round().toString());

  @override
  void dispose() {
    _priceCtrl.dispose();
    super.dispose();
  }

  void _savePrice() {
    final v = double.tryParse(_priceCtrl.text.trim());
    if (v == null || v <= 0) return;
    updateMockRoomPrice(widget.room.id, v);
    FocusScope.of(context).unfocus();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${widget.room.roomType} rate updated.')),
    );
  }

  Color _statusColor(String s) => switch (s) {
        HotelRoomStatus.available => AppColors.kmTeal,
        HotelRoomStatus.occupied => AppColors.kmOrange,
        HotelRoomStatus.cleaning => AppColors.kmPurple,
        HotelRoomStatus.outOfOrder => AppColors.kmPink,
        _ => AppColors.kmMuted,
      };

  @override
  Widget build(BuildContext context) {
    final r = widget.room;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: r.coverImage.isEmpty
                    ? Container(
                        width: 44,
                        height: 44,
                        color: Colors.white.withValues(alpha: 0.08),
                        child: const Icon(Icons.hotel_rounded,
                            color: AppColors.kmMuted, size: 20),
                      )
                    : Image.network(r.coverImage,
                        width: 44,
                        height: 44,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                            width: 44,
                            height: 44,
                            color: Colors.white.withValues(alpha: 0.08))),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(r.roomNumber.isEmpty ? r.roomType : r.roomNumber,
                        style: const TextStyle(
                            color: AppColors.kmText,
                            fontWeight: FontWeight.w800,
                            fontSize: 14.5)),
                    Text(
                        '${r.roomType} · ${r.capacity} guest${r.capacity == 1 ? '' : 's'}',
                        style: const TextStyle(
                            color: AppColors.kmMuted, fontSize: 11.5)),
                  ],
                ),
              ),
              Text('${r.totalInventory} units',
                  style: const TextStyle(
                      color: AppColors.kmMuted, fontSize: 11.5)),
            ],
          ),
          if (widget.activeBooking != null) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: AppColors.kmOrange.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(AppRadius.sm),
                border: Border.all(
                    color: AppColors.kmOrange.withValues(alpha: 0.4)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.event_busy_rounded,
                      size: 14, color: AppColors.kmOrange),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                        'Booked — ${widget.activeBooking!.guestName.isEmpty ? "Guest" : widget.activeBooking!.guestName} '
                        'until ${widget.activeBooking!.checkOutDate.day}/${widget.activeBooking!.checkOutDate.month}',
                        style: const TextStyle(
                            color: AppColors.kmOrange,
                            fontWeight: FontWeight.w700,
                            fontSize: 11)),
                  ),
                ],
              ),
            ),
          ],
          // Admin Cleaning & Reset Flow — guest checkout हुनेबित्तिकै
          // (`updatePartnerBookingStatus`, hotel_partner_service.dart कै
          // `_roomStatusForBookingStatus`) यो कोठा स्वतः यहीँ आइपुग्छ —
          // guest-साइड search बाट त्यसैबेलादेखि नै हराइसकेको हुन्छ
          // (`HotelRoom.isActive`), staff ले तल "Cleaned & Ready" नथिचेसम्म।
          if (r.status == HotelRoomStatus.cleaning) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: AppColors.kmPurple.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(AppRadius.sm),
                border: Border.all(
                    color: AppColors.kmPurple.withValues(alpha: 0.4)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.cleaning_services_rounded,
                      size: 14, color: AppColors.kmPurple),
                  SizedBox(width: 6),
                  Expanded(
                    child: Text(
                        'Needs Cleaning / Ready for Inspection — hidden from '
                        'guest search until marked "Cleaned & Ready" below.',
                        style: TextStyle(
                            color: AppColors.kmPurple,
                            fontWeight: FontWeight.w700,
                            fontSize: 11)),
                  ),
                ],
              ),
            ),
          ],
          if (r.amenities.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 6,
              children: r.amenities
                  .map((a) => Tooltip(
                        message: a,
                        child: Icon(hotelAmenityIcon(a),
                            size: 15, color: AppColors.kmMuted),
                      ))
                  .toList(),
            ),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: HotelRoomStatus.presets.map((s) {
              final selected = r.status == s;
              final color = _statusColor(s);
              // Admin Cleaning & Reset Flow — "available" चिपले नै "Cleaned
              // & Ready" भनेर स्पष्ट action जनाउने, तर कोठा साँच्चै cleaning
              // बाहिर अन्य कुनै status मा छँदा मात्र (नत्र सामान्य "Available"
              // लाई पनि भ्रामक रूपमा "Cleaned & Ready" भनिरहन्छ)।
              final label = s == HotelRoomStatus.available
                  ? (r.status == HotelRoomStatus.cleaning
                      ? 'Cleaned & Ready'
                      : 'Available')
                  : s == HotelRoomStatus.cleaning
                      ? 'Needs Cleaning'
                      : s.replaceAll('_', ' ');
              return ChoiceChip(
                label: Text(label),
                selected: selected,
                onSelected: (_) {
                  updateMockRoomStatus(r.id, s);
                  setState(() {});
                },
                selectedColor: color,
                labelStyle: TextStyle(
                    color: selected ? AppColors.kmInk : AppColors.kmText,
                    fontWeight: FontWeight.w700,
                    fontSize: 11),
                backgroundColor: Colors.white.withValues(alpha: 0.06),
              );
            }).toList(),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Text('Rs.',
                  style: TextStyle(
                      color: AppColors.kmMuted, fontWeight: FontWeight.w700)),
              const SizedBox(width: 6),
              Expanded(
                child: TextField(
                  controller: _priceCtrl,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(color: AppColors.kmText),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'Price / night',
                    hintStyle: const TextStyle(color: AppColors.kmMuted),
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.05),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: _savePrice,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.kmOrange,
                  side: const BorderSide(color: AppColors.kmOrange),
                ),
                child: const Text('Save'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Preset amenity चिप — Hotel Owner/Partner ले आफ्नै होटलमा लागू हुने
/// छान्ने/हटाउने (hotel_registration_screen.dart कै दर्ता-बेलाकै उस्तै
/// सूची, यहाँ पछि सम्पादन गर्न)।
const _amenityPresets = [
  'WiFi',
  'Pool',
  'Spa',
  'Restaurant',
  'Parking',
  'Gym',
  'AC',
  'Breakfast'
];

/// Hotel Partner Dashboard — तेस्रो tab: Photo & Amenity Updates। Rooms/Rate
/// Management (`_RoomsTab`) र Check-in/Booking (`_BookingsTab`/QR scanner)
/// बाहेकको बाँकी "Booking.com parity" टुक्रा — होटलको आफ्नै जानकारी
/// (फोटो ग्यालरी + सुविधा) यहीँबाट अद्यावधिक।
class _HotelInfoTab extends StatefulWidget {
  final Hotel hotel;
  const _HotelInfoTab({required this.hotel});

  @override
  State<_HotelInfoTab> createState() => _HotelInfoTabState();
}

class _HotelInfoTabState extends State<_HotelInfoTab> {
  bool _uploading = false;
  late final _officialMobileCtrl =
      TextEditingController(text: widget.hotel.officialMobileNumber);
  late final _landlineCtrl =
      TextEditingController(text: widget.hotel.landlinePhone);

  @override
  void dispose() {
    _officialMobileCtrl.dispose();
    _landlineCtrl.dispose();
    super.dispose();
  }

  void _saveContactNumbers() {
    final mobile = _officialMobileCtrl.text.trim();
    if (mobile.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content:
              Text("Official contact mobile number can't be empty.")));
      return;
    }
    updateHotelContactNumbers(
        widget.hotel.id, mobile, _landlineCtrl.text.trim());
    FocusScope.of(context).unfocus();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Contact numbers updated.')),
    );
  }

  /// Two-Tier Admin Control (Partner side) — यो होटलको category rating
  /// breakdown (read-only, सेट/सच्याउने अधिकार Super Admin मात्रको) + यस
  /// होटलका review हरू, हरेकको "Guest Quote" featured-toggle सहित। Rating
  /// score आफैं यहाँबाट सम्पादन गर्न मिल्दैन (firestore.rules ले पनि partner
  /// लाई `hotels.categoryRatings` बदल्न रोक्दैन — तर यो UI जानाजान त्यो
  /// बटन नै नदेखाएर "view-only" राख्छ, user-expectation अनुसार)।
  Widget _guestRatingsSection(Hotel hotel) {
    final reviews = mockReviewsForHotel(hotel.id);
    final avg = averageRating(hotel.id);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Guest Ratings & Reviews',
            style: TextStyle(
                color: AppColors.kmText,
                fontWeight: FontWeight.w800,
                fontSize: 14.5)),
        const SizedBox(height: 2),
        const Text(
            'Rating breakdown is view-only here — only Super Admin can '
            'change the scores. You can choose which reviews to feature '
            'as "Guest Quotes" on your Hotel Details page.',
            style: TextStyle(color: AppColors.kmMuted, fontSize: 11.5)),
        const SizedBox(height: 10),
        if (reviews.isEmpty)
          const Text('No reviews yet.',
              style: TextStyle(color: AppColors.kmMuted, fontSize: 12.5))
        else ...[
          for (final category in kHotelRatingCategories) ...[
            hotelRatingBar(category, categoryRatingFor(hotel, avg, category)),
            const SizedBox(height: 8),
          ],
          const SizedBox(height: 8),
          for (final r in reviews) _reviewManageRow(r),
        ],
      ],
    );
  }

  Widget _reviewManageRow(HotelReview r) {
    final name = r.reviewerName.isEmpty ? 'Guest' : r.reviewerName;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (r.country.isNotEmpty) ...[
                      Text(countryFlagEmoji(r.country),
                          style: const TextStyle(fontSize: 13)),
                      const SizedBox(width: 4),
                    ],
                    Text(name,
                        style: const TextStyle(
                            color: AppColors.kmText,
                            fontWeight: FontWeight.w700,
                            fontSize: 12.5)),
                    const SizedBox(width: 6),
                    HotelStarRow(rating: r.rating, size: 11),
                  ],
                ),
                const SizedBox(height: 4),
                Text(r.comment,
                    style: const TextStyle(
                        color: AppColors.kmMuted, fontSize: 12)),
              ],
            ),
          ),
          IconButton(
            tooltip: r.featured
                ? 'Unfeature (remove from Guest Quotes)'
                : 'Feature as Guest Quote',
            onPressed: () {
              setReviewFeatured(r.id, !r.featured);
              setState(() {});
            },
            icon: Icon(
                r.featured ? Icons.star_rounded : Icons.star_border_rounded,
                color:
                    r.featured ? AppColors.kmOrange : AppColors.kmMuted),
          ),
        ],
      ),
    );
  }

  Future<void> _addPhoto() async {
    final picked = await pickPartnerImage(context);
    if (picked == null) return;
    if (!mounted) return;
    final bytes = await picked.readAsBytes();
    final err = UploadValidation.validate(bytes, picked.name);
    if (err != null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(UploadValidation.messageFor(err))));
      return;
    }
    final uid = FirebaseAuth.instance.currentUser?.uid ?? 'unknown';
    setState(() => _uploading = true);
    try {
      final ext = UploadValidation.safeExtension(picked.name);
      final ref = FirebaseStorage.instance.ref(
          'hotel_photos/$uid/${widget.hotel.id}/${DateTime.now().millisecondsSinceEpoch}.$ext');
      final sniffed = UploadValidation.sniffMime(bytes);
      await ref.putData(
        bytes,
        SettableMetadata(
            contentType: sniffed.isNotEmpty ? sniffed : 'image/jpeg'),
      );
      final url = await ref.getDownloadURL();
      addHotelPhoto(widget.hotel.id, url);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Upload failed: $e')));
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  void _toggleAmenity(String amenity) {
    final current = List<String>.from(widget.hotel.amenities);
    if (current.contains(amenity)) {
      current.remove(amenity);
    } else {
      current.add(amenity);
    }
    updateHotelAmenities(widget.hotel.id, current);
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: hotelCatalogVersion,
      builder: (context, _, __) {
        // listener ले catalog version मात्र दिने भएकोले ताजा hotel object
        // फेरि नै (mutated copy) `mockHotels` बाट लिने — widget.hotel
        // पुरानो snapshot हुन सक्छ।
        final hotel = mockHotels.firstWhere((h) => h.id == widget.hotel.id,
            orElse: () => widget.hotel);
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
          children: [
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => _GuestLogbookScreen(hotel: hotel),
                  ),
                ),
                icon: const Icon(Icons.menu_book_rounded),
                label: const Text('Guest Logbook'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.kmOrange,
                  side: const BorderSide(color: AppColors.kmOrange),
                  padding: const EdgeInsets.symmetric(vertical: 11),
                ),
              ),
            ),
            const SizedBox(height: 22),
            const Text('Contact Numbers',
                style: TextStyle(
                    color: AppColors.kmText,
                    fontWeight: FontWeight.w800,
                    fontSize: 14.5)),
            const SizedBox(height: 2),
            const Text(
                'Shown to guests on the Booking Pass & Hotel Details screen '
                'for direct dialing.',
                style: TextStyle(color: AppColors.kmMuted, fontSize: 11.5)),
            const SizedBox(height: 10),
            TextField(
              controller: _officialMobileCtrl,
              keyboardType: TextInputType.phone,
              style: const TextStyle(color: AppColors.kmText),
              decoration: kmInputDecoration('Official contact mobile number'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _landlineCtrl,
              keyboardType: TextInputType.phone,
              style: const TextStyle(color: AppColors.kmText),
              decoration: kmInputDecoration('Landline phone (optional)'),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _saveContactNumbers,
              icon: const Icon(Icons.save_rounded, size: 18),
              label: const Text('Save Contact Numbers'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.kmOrange,
                side: const BorderSide(color: AppColors.kmOrange),
                padding: const EdgeInsets.symmetric(vertical: 11),
              ),
            ),
            const SizedBox(height: 22),
            _guestRatingsSection(hotel),
            const SizedBox(height: 22),
            const Text('Amenities',
                style: TextStyle(
                    color: AppColors.kmText,
                    fontWeight: FontWeight.w800,
                    fontSize: 14.5)),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _amenityPresets.map((a) {
                final selected = hotel.amenities.contains(a);
                return FilterChip(
                  label: Text(a),
                  selected: selected,
                  onSelected: (_) => _toggleAmenity(a),
                  selectedColor: AppColors.kmOrange,
                  labelStyle: TextStyle(
                      color: selected ? AppColors.kmInk : AppColors.kmText,
                      fontWeight: FontWeight.w700),
                  backgroundColor: Colors.white.withValues(alpha: 0.06),
                );
              }).toList(),
            ),
            const SizedBox(height: 22),
            Row(
              children: [
                const Expanded(
                  child: Text('Update Hotel Photos',
                      style: TextStyle(
                          color: AppColors.kmText,
                          fontWeight: FontWeight.w800,
                          fontSize: 14.5)),
                ),
                TextButton.icon(
                  onPressed: _uploading ? null : _addPhoto,
                  icon: _uploading
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.add_a_photo_rounded, size: 18),
                  label: Text(_uploading ? 'Uploading…' : 'Add Photo'),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
                'General hotel photos only (exterior, lobby, parking, '
                'pool) — shown on the guest Hotel Details top banner. Add '
                'room-specific photos from "Add Room" in the Rooms tab '
                'instead.',
                style: TextStyle(color: AppColors.kmMuted, fontSize: 11.5)),
            const SizedBox(height: 8),
            if (hotel.images.isEmpty)
              const Text('No photos yet.',
                  style: TextStyle(color: AppColors.kmMuted, fontSize: 12.5))
            else
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                ),
                itemCount: hotel.images.length,
                itemBuilder: (context, i) {
                  final url = hotel.images[i];
                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.network(url,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                                color: Colors.white.withValues(alpha: 0.08))),
                      ),
                      Positioned(
                        top: 2,
                        right: 2,
                        child: GestureDetector(
                          onTap: () => removeHotelPhoto(hotel.id, url),
                          child: Container(
                            padding: const EdgeInsets.all(3),
                            decoration: const BoxDecoration(
                                color: Colors.black54, shape: BoxShape.circle),
                            child: const Icon(Icons.close_rounded,
                                size: 14, color: Colors.white),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            const SizedBox(height: 26),
            const Text('Uploaded Rooms & Live Inventory Profile',
                style: TextStyle(
                    color: AppColors.kmText,
                    fontWeight: FontWeight.w800,
                    fontSize: 14.5)),
            const SizedBox(height: 4),
            const Text(
                'Every room currently live online, with all its uploaded '
                'photos — exactly what guests see when browsing this hotel.',
                style: TextStyle(color: AppColors.kmMuted, fontSize: 11.5)),
            const SizedBox(height: 12),
            for (final r in mockRoomsForHotel(hotel.id))
              _RoomGalleryCard(room: r),
          ],
        );
      },
    );
  }
}

/// "Uploaded Rooms & Live Inventory Profile" (Hotel Info tab) को एक कोठा —
/// `_RoomEditRow` (Rooms tab, edit-केन्द्रित: status/दर बदल्ने) भन्दा फरक,
/// यो pure read-only profile/gallery card हो — ToT uploaded photo (cover
/// मात्र होइन) एकैचोटि देखाउन।
class _RoomGalleryCard extends StatelessWidget {
  final HotelRoom room;
  const _RoomGalleryCard({required this.room});

  @override
  Widget build(BuildContext context) {
    final r = room;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(r.roomNumber.isEmpty ? r.roomType : r.roomNumber,
                    style: const TextStyle(
                        color: AppColors.kmText,
                        fontWeight: FontWeight.w800,
                        fontSize: 14)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.kmOrange.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
                child: Text(r.roomType,
                    style: const TextStyle(
                        color: AppColors.kmOrange,
                        fontWeight: FontWeight.w700,
                        fontSize: 10.5)),
              ),
              const SizedBox(width: 8),
              Text(formatHotelPrice(r.pricePerNight),
                  style: const TextStyle(
                      color: AppColors.kmText,
                      fontWeight: FontWeight.w800,
                      fontSize: 12.5)),
              const Text(' /night',
                  style: TextStyle(color: AppColors.kmMuted, fontSize: 10.5)),
            ],
          ),
          if (r.amenities.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              runSpacing: 6,
              children: r.amenities
                  .map((a) => Tooltip(
                        message: a,
                        child: Icon(hotelAmenityIcon(a),
                            size: 15, color: AppColors.kmMuted),
                      ))
                  .toList(),
            ),
          ],
          const SizedBox(height: 10),
          if (r.images.isEmpty)
            const Text('No photos uploaded for this room yet.',
                style: TextStyle(color: AppColors.kmMuted, fontSize: 12))
          else
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4,
                crossAxisSpacing: 6,
                mainAxisSpacing: 6,
              ),
              itemCount: r.images.length,
              itemBuilder: (context, i) => ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(r.images[i],
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) =>
                        Container(color: Colors.white.withValues(alpha: 0.08))),
              ),
            ),
        ],
      ),
    );
  }
}
