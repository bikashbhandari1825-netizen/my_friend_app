// screens/salon_checkout_screen.dart
//
// Salon / Beauty Appointment Booking — ग्राहक विवरण + भुक्तानी + "Confirm"।
//
// ⚠️ भुक्तानी (hotel checkout जस्तै SANDBOX): यो app मा साँचो payment
// gateway (eSewa/Khalti merchant API) छैन। "Pay Online" ले ग्राहकले आफैं
// तिरेको eSewa/Khalti/QR reference declare गर्छ मात्र — हामी त्यो verify
// गर्दैनौँ। बुकिङ `paymentStatus: 'declared'` मा बन्छ र salon ले आफ्नै
// eSewa/Khalti statement हेरेर "Mark paid" थिचेपछि मात्र 'paid' हुन्छ।
// "Pay at Salon" मा सेवा पूरा हुँदा नगद लिइएको मानिन्छ।
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../models/salon_models.dart';
import '../services/salon_service.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_ui.dart';
import 'salon_common.dart';
import 'salon_pass_screen.dart';
import '../widgets/futuristic_ui.dart';

class SalonCheckoutScreen extends StatefulWidget {
  final Salon salon;
  final List<SalonService> services;
  final DateTime start;
  final String? staffId; // null = Any available (server ले छान्छ)
  const SalonCheckoutScreen({
    super.key,
    required this.salon,
    required this.services,
    required this.start,
    this.staffId,
  });

  @override
  State<SalonCheckoutScreen> createState() => _SalonCheckoutScreenState();
}

class _SalonCheckoutScreenState extends State<SalonCheckoutScreen> {
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _refCtrl = TextEditingController();

  String _paymentType = SalonPaymentType.paySalon;
  String _onlineMethod = 'esewa';
  String? _myEsewaId;
  String? _myKhaltiId;
  bool _submitting = false;

  double get _total => widget.services.fold(0, (a, s) => a + s.price);
  int get _minutes => widget.services.fold(0, (a, s) => a + s.durationMin);

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
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
        if (_nameCtrl.text.isEmpty) _nameCtrl.text = (d['name'] ?? '').toString();
        if (_phoneCtrl.text.isEmpty) {
          _phoneCtrl.text = (d['phone'] ?? '').toString();
        }
        _myEsewaId = (d['esewaId'] ?? '').toString();
        _myKhaltiId = (d['khaltiId'] ?? '').toString();
        _refCtrl.text = _myEsewaId ?? '';
      });
    } catch (_) {
      // prefill best-effort मात्र।
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

  // hotel checkout कै Test Mode — release APK मा कहिल्यै नदेखिने (kDebugMode)।
  void _debugAutoFillTestPayment() {
    setState(() {
      if (_nameCtrl.text.trim().isEmpty) _nameCtrl.text = 'Test Customer';
      if (_phoneCtrl.text.trim().isEmpty) _phoneCtrl.text = '9800000000';
      _paymentType = SalonPaymentType.online;
      _onlineMethod = 'esewa';
      _refCtrl.text = 'TEST-REF-9999';
    });
  }

  Future<void> _confirm() async {
    if (_nameCtrl.text.trim().isEmpty || _phoneCtrl.text.trim().isEmpty) {
      salonSnack(context, 'Please enter your name and phone number.');
      return;
    }
    final online = _paymentType == SalonPaymentType.online;
    if (online && _refCtrl.text.trim().isEmpty) {
      salonSnack(context, 'Please enter your payment reference/ID.');
      return;
    }
    setState(() => _submitting = true);
    try {
      final result = await bookSalonAppointment(
        salon: widget.salon,
        serviceIds: widget.services.map((s) => s.id).toList(),
        staffId: widget.staffId,
        start: widget.start,
        customerName: _nameCtrl.text.trim(),
        customerPhone: _phoneCtrl.text.trim(),
        paymentType: _paymentType,
        paymentMethod: online ? _onlineMethod : '',
        paymentRef: online ? _refCtrl.text.trim() : '',
      );
      if (!mounted) return;
      if (!result.success) {
        salonSnack(context, result.error ?? 'Booking failed. Please try again.');
        return;
      }
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => SalonPassScreen(appointmentId: result.appointmentId!),
        ),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final online = _paymentType == SalonPaymentType.online;
    return OledBackdrop(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Column(
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 16, 20, 0),
                child: KmScreenHeader(title: 'Confirm appointment'),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                  children: [
                    salonCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(widget.salon.name,
                              style: const TextStyle(
                                  color: AppColors.kmText,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 15)),
                          if (widget.salon.address.isNotEmpty)
                            Text(widget.salon.address,
                                style: const TextStyle(
                                    color: AppColors.kmMuted, fontSize: 12)),
                          Divider(height: 20, color: AppColors.kmGlassBorder),
                          for (final s in widget.services)
                            salonSummaryRow(s.name, formatHotelPrice(s.price)),
                          Divider(height: 20, color: AppColors.kmGlassBorder),
                          salonSummaryRow('When',
                              '${salonDateLabel(widget.start, widget.salon)}, ${salonClock(widget.start, widget.salon)}'),
                          salonSummaryRow('Duration', salonDurationLabel(_minutes)),
                          salonSummaryRow(
                              'With',
                              widget.staffId == null
                                  ? 'Any available'
                                  : 'Selected team member'),
                          Divider(height: 20, color: AppColors.kmGlassBorder),
                          salonSummaryRow('Total', formatHotelPrice(_total),
                              bold: true),
                        ],
                      ),
                    ),
                    salonSectionLabel('YOUR DETAILS'),
                    salonCard(
                      child: Column(
                        children: [
                          _textField(_nameCtrl, 'Full name', Icons.person_rounded),
                          const SizedBox(height: 10),
                          _textField(_phoneCtrl, 'Phone number',
                              Icons.phone_rounded,
                              keyboardType: TextInputType.phone),
                        ],
                      ),
                    ),
                    salonSectionLabel('PAYMENT'),
                    salonCard(
                      child: Column(
                        children: [
                          _paymentOption(
                            SalonPaymentType.paySalon,
                            Icons.storefront_rounded,
                            'Pay at Salon',
                            'Pay when your appointment is done',
                          ),
                          const SizedBox(height: 8),
                          _paymentOption(
                            SalonPaymentType.online,
                            Icons.credit_card_rounded,
                            'Pay Online',
                            'eSewa / Khalti / QR',
                          ),
                          if (online) ...[
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
                            const SizedBox(height: 10),
                            // भुक्तानी verify हुँदैन भन्ने कुरा स्पष्ट देखाउने।
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: AppColors.kmOrange.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(AppRadius.sm),
                                border: Border.all(
                                    color:
                                        AppColors.kmOrange.withValues(alpha: 0.3)),
                              ),
                              child: const Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(Icons.info_outline_rounded,
                                      color: AppColors.kmOrange, size: 16),
                                  SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'Pay the salon through your own eSewa/Khalti app, then enter the reference here. '
                                      'The app does not process or verify the payment — the salon confirms it on their side.',
                                      style: TextStyle(
                                          color: AppColors.kmText,
                                          fontSize: 11.5,
                                          height: 1.35),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (kDebugMode) ...[
                      const SizedBox(height: 4),
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
                    const SizedBox(height: 20),
                    KmCtaButton(
                      label: 'Confirm · ${formatHotelPrice(_total)}',
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
