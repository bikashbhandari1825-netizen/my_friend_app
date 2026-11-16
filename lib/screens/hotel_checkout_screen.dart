// screens/hotel_checkout_screen.dart
//
// Hotel Booking System — Phase 4: guest details form + payment method
// (Pay at Hotel / Pay Online — esewa/khalti/QR, बाँकी app कै उही informal
// "declare-your-payment-id" ढाँचा, complete_job_sheet.dart हेर्नुहोस्) +
// "Confirm Booking" ले `createHotelBooking()` (inventory फेरि-जाँचसहित)
// बोलाउँछ।
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../models/hotel_models.dart';
import '../services/hotel_booking_service.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_ui.dart';
import 'hotel_booking_pass_screen.dart';
import 'hotel_common.dart';
import '../widgets/futuristic_ui.dart';

class HotelCheckoutScreen extends StatefulWidget {
  final Hotel hotel;
  final HotelRoom room;
  final HotelSearchQuery query;
  final int unitsCount;
  const HotelCheckoutScreen(
      {super.key,
      required this.hotel,
      required this.room,
      required this.query,
      this.unitsCount = 1});

  @override
  State<HotelCheckoutScreen> createState() => _HotelCheckoutScreenState();
}

class _HotelCheckoutScreenState extends State<HotelCheckoutScreen> {
  // Fraud/No-Show Prevention — "Pay at Hotel" छानिँदा tिर्नैपर्ने token
  // advance को दर। यो app मा साँचो payment gateway कतै छैन (तलको "Pay
  // Online" पनि declare-your-own-reference sandbox मात्र हो) — त्यसैले यो
  // deposit पनि उस्तै sandbox pattern नै प्रयोग गर्छ, छुट्टै भुक्तानी
  // infrastructure नबनाई।
  static const double depositRate = 0.20;

  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _refCtrl = TextEditingController();

  String _paymentType = HotelPaymentType.payAtHotel;
  String _onlineMethod = 'esewa';
  String? _myEsewaId;
  String? _myKhaltiId;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _refCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    _nameCtrl.text = user.displayName ?? '';
    _phoneCtrl.text = user.phoneNumber ?? '';
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      final d = doc.data();
      if (d == null || !mounted) return;
      setState(() {
        if (_nameCtrl.text.isEmpty) {
          _nameCtrl.text = (d['name'] ?? '').toString();
        }
        if (_phoneCtrl.text.isEmpty) {
          _phoneCtrl.text = (d['phone'] ?? '').toString();
        }
        _myEsewaId = (d['esewaId'] ?? '').toString();
        _myKhaltiId = (d['khaltiId'] ?? '').toString();
        _refCtrl.text = _myEsewaId ?? '';
      });
    } catch (_) {
      // प्रोफाइल prefill best-effort मात्र — असफल भए खाली फारम नै देखिने।
    }
  }

  void _onOnlineMethodChanged(String method) {
    setState(() {
      _onlineMethod = method;
      _refCtrl.text = method == 'khalti'
          ? (_myKhaltiId ?? '')
          : method == 'esewa'
              ? (_myEsewaId ?? '')
              : '';
    });
  }

  // Test Mode — end-to-end flow (Booking Pass creation, Partner Dashboard
  // sync, QR Check-in, Settlement Check-out) लाई हरेकपटक साँचो नाम/फोन/
  // payment reference हात-ले नभरी छिटो जाँच्न। `kDebugMode` ले release
  // APK मा यो कहिल्यै नदेखिने सुनिश्चित गर्छ — कुनै थप flag/config चाहिँदैन।
  void _debugAutoFillTestPayment() {
    setState(() {
      if (_nameCtrl.text.trim().isEmpty) _nameCtrl.text = 'Test Guest';
      if (_phoneCtrl.text.trim().isEmpty) _phoneCtrl.text = '9800000000';
      _onlineMethod = 'esewa';
      _refCtrl.text = 'TEST-REF-9999';
    });
  }

  Future<void> _confirm() async {
    if (_nameCtrl.text.trim().isEmpty || _phoneCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter your name and phone number.')),
      );
      return;
    }
    final nights = widget.query.nights;
    final total = widget.room.pricePerNight * nights * widget.unitsCount;
    final depositAmount =
        _paymentType == HotelPaymentType.payAtHotel ? total * depositRate : 0.0;
    if (_paymentType == HotelPaymentType.payAtHotel &&
        _refCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                'Please enter your advance token payment reference to confirm this booking.')),
      );
      return;
    }
    setState(() => _submitting = true);
    // `createHotelBooking` आफैं कहिल्यै throw गर्दैन (hotel_booking_service.dart
    // हेर्नुहोस्) — तर यो try/finally यहाँ पनि defense-in-depth राखिएको, ताकि
    // साँच्चै अनपेक्षित कुनै त्रुटि आए पनि `_submitting` कहिल्यै loading मै
    // नअडोस् ("Confirm Booking" बटन अनन्तकालसम्म loading अड्किने बगको ठ्याक्कै
    // उही class)।
    try {
      final result = await createHotelBooking(
        hotel: widget.hotel,
        room: widget.room,
        checkIn: widget.query.checkIn,
        checkOut: widget.query.checkOut,
        guestsCount: widget.query.guestsCount,
        guestName: _nameCtrl.text.trim(),
        guestPhone: _phoneCtrl.text.trim(),
        guestEmail: _emailCtrl.text.trim(),
        paymentType: _paymentType,
        unitsCount: widget.unitsCount,
        depositAmount: depositAmount,
        depositReference:
            _paymentType == HotelPaymentType.payAtHotel ? _refCtrl.text.trim() : '',
      );
      if (!mounted) return;
      if (!result.success || result.booking == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(result.error ?? 'Booking failed. Please try again.')),
        );
        return;
      }
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => HotelBookingPassScreen(
            booking: result.booking!,
            hotel: widget.hotel,
            room: widget.room,
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Booking failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final nights = widget.query.nights;
    final total = widget.room.pricePerNight * nights * widget.unitsCount;
    return OledBackdrop(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Column(
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 16, 20, 0),
                child: KmScreenHeader(title: 'Checkout'),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                  children: [
                    _card(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(widget.hotel.name,
                              style: const TextStyle(
                                  color: AppColors.kmText,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 15)),
                          const SizedBox(height: 2),
                          Text(widget.hotel.address,
                              style: const TextStyle(
                                  color: AppColors.kmMuted, fontSize: 12)),
                          Divider(height: 20, color: AppColors.kmGlassBorder),
                          _summaryRow('Room', widget.room.roomType),
                          _summaryRow('Dates',
                              '${_fmt(widget.query.checkIn)} → ${_fmt(widget.query.checkOut)}'),
                          _summaryRow('Guests', '${widget.query.guestsCount}'),
                          _summaryRow('Nights', '$nights'),
                          if (widget.unitsCount > 1)
                            _summaryRow('Units', '${widget.unitsCount}'),
                          Divider(height: 20, color: AppColors.kmGlassBorder),
                          _summaryRow(
                              'Total', formatHotelPrice(total), bold: true),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    _sectionLabel('Guest details'),
                    _card(
                      child: Column(
                        children: [
                          _textField(_nameCtrl, 'Full name', Icons.person_rounded),
                          const SizedBox(height: 10),
                          _textField(_phoneCtrl, 'Phone number', Icons.phone_rounded,
                              keyboardType: TextInputType.phone),
                          const SizedBox(height: 10),
                          _textField(_emailCtrl, 'Email (optional)',
                              Icons.email_rounded,
                              keyboardType: TextInputType.emailAddress),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    _sectionLabel('Payment method'),
                    _card(
                      child: Column(
                        children: [
                          _paymentOption(
                            HotelPaymentType.payAtHotel,
                            Icons.home_work_rounded,
                            'Pay at Hotel',
                            'Pay with cash when you arrive',
                          ),
                          if (_paymentType == HotelPaymentType.payAtHotel) ...[
                            const SizedBox(height: 12),
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: AppColors.kmOrange.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(AppRadius.sm),
                                border: Border.all(
                                    color:
                                        AppColors.kmOrange.withValues(alpha: 0.3)),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.shield_rounded,
                                      color: AppColors.kmOrange, size: 16),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'A refundable ${(depositRate * 100).round()}% '
                                      'advance token payment of '
                                      '${formatHotelPrice(widget.room.pricePerNight * widget.query.nights * depositRate)} '
                                      'is required to confirm this booking and '
                                      'prevent no-shows.',
                                      style: const TextStyle(
                                          color: AppColors.kmText,
                                          fontSize: 11.5,
                                          height: 1.35),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 8,
                              children: [
                                _methodChip('esewa', S.payEsewa),
                                _methodChip('khalti', S.payKhalti),
                                _methodChip('qr', S.payQr),
                              ],
                            ),
                            const SizedBox(height: 10),
                            _textField(_refCtrl, 'Advance payment reference/ID',
                                Icons.tag_rounded),
                          ],
                          const SizedBox(height: 8),
                          _paymentOption(
                            HotelPaymentType.onlinePaid,
                            Icons.credit_card_rounded,
                            'Pay Online',
                            'eSewa / Khalti / QR',
                          ),
                          if (_paymentType == HotelPaymentType.onlinePaid) ...[
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 8,
                              children: [
                                _methodChip('esewa', S.payEsewa),
                                _methodChip('khalti', S.payKhalti),
                                _methodChip('qr', S.payQr),
                              ],
                            ),
                            const SizedBox(height: 10),
                            _textField(_refCtrl, 'Your payment reference/ID',
                                Icons.tag_rounded),
                          ],
                        ],
                      ),
                    ),
                    if (kDebugMode) ...[
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: _debugAutoFillTestPayment,
                        icon: const Text('🧪'),
                        label: const Text('Auto-Fill Test Payment (Debug Only)'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.kmOrange,
                          side: BorderSide(
                              color: AppColors.kmOrange.withValues(alpha: 0.4)),
                          minimumSize: const Size.fromHeight(44),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                    KmCtaButton(
                      label: 'Confirm Booking · ${formatHotelPrice(total)}',
                      icon: Icons.check_circle_rounded,
                      loading: _submitting,
                      onPressed: _submitting ? null : _confirm,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _fmt(DateTime d) => '${d.day}/${d.month}/${d.year}';

  Widget _sectionLabel(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8, left: 2),
        child: Text(text,
            style: const TextStyle(
                color: AppColors.kmMuted,
                fontWeight: FontWeight.w800,
                fontSize: 12,
                letterSpacing: 0.4)),
      );

  Widget _card({required Widget child}) => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
        ),
        child: child,
      );

  Widget _summaryRow(String label, String value, {bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label,
                style: const TextStyle(color: AppColors.kmMuted, fontSize: 12.5)),
            Text(value,
                style: TextStyle(
                    color: bold ? AppColors.kmOrange : AppColors.kmText,
                    fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
                    fontSize: bold ? 15 : 12.5)),
          ],
        ),
      );

  Widget _textField(TextEditingController c, String hint, IconData icon,
      {TextInputType? keyboardType}) {
    return TextField(
      controller: c,
      keyboardType: keyboardType,
      style: const TextStyle(color: AppColors.kmText),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: AppColors.kmMuted),
        prefixIcon: Icon(icon, color: AppColors.kmMuted, size: 18),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.05),
        contentPadding: const EdgeInsets.symmetric(vertical: 10),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  Widget _paymentOption(
      String value, IconData icon, String title, String subtitle) {
    final selected = _paymentType == value;
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.md),
      onTap: () => setState(() => _paymentType = value),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.kmOrange.withValues(alpha: 0.14)
              : Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(
              color: selected
                  ? AppColors.kmOrange
                  : Colors.white.withValues(alpha: 0.1)),
        ),
        child: Row(
          children: [
            Icon(icon,
                color: selected ? AppColors.kmOrange : AppColors.kmMuted,
                size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          color: AppColors.kmText,
                          fontWeight: FontWeight.w700,
                          fontSize: 13.5)),
                  Text(subtitle,
                      style: const TextStyle(
                          color: AppColors.kmMuted, fontSize: 11.5)),
                ],
              ),
            ),
            Icon(
                selected
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_off_rounded,
                color: selected ? AppColors.kmOrange : AppColors.kmMuted,
                size: 20),
          ],
        ),
      ),
    );
  }

  Widget _methodChip(String value, String label) {
    final selected = _onlineMethod == value;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => _onOnlineMethodChanged(value),
      selectedColor: AppColors.kmOrange,
      labelStyle: TextStyle(
          color: selected ? AppColors.kmInk : AppColors.kmText,
          fontWeight: FontWeight.w700,
          fontSize: 12),
      backgroundColor: Colors.white.withValues(alpha: 0.06),
    );
  }
}
