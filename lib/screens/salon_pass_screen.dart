// screens/salon_pass_screen.dart
//
// Salon / Beauty Appointment Booking — बुकिङ Pass: QR (salon ले check-in मा
// scan गर्ने), अपोइन्टमेन्ट विवरण, रद्द, पूरा भएपछि 5-star review, र
// "Book again" (re-book)। hotel_booking_pass_screen.dart कै भूमिका।
//
// QR payload `KAAMMITRA-SALON:<appointmentId>:<गोप्य token>` — token server
// ले बनाउँछ र केवल यही ग्राहक + salon मालिकले पढ्न पाउँछन् (firestore.rules),
// त्यसैले id मात्र अनुमान गरेर नक्कली check-in हुँदैन। प्रमाणीकरण server
// (`salonCheckIn` function) ले गर्छ।
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/salon_models.dart';
import '../services/salon_service.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_ui.dart';
import 'salon_booking_screen.dart';
import 'salon_common.dart';
import '../widgets/futuristic_ui.dart';
import '../widgets/skeleton.dart';

class SalonPassScreen extends StatefulWidget {
  final String appointmentId;
  const SalonPassScreen({super.key, required this.appointmentId});

  @override
  State<SalonPassScreen> createState() => _SalonPassScreenState();
}

class _SalonPassScreenState extends State<SalonPassScreen> {
  late final _stream = appointmentStream(widget.appointmentId);
  Salon? _salon;
  String? _salonLoadedFor;
  bool _busy = false;

  // salon (टाइमजोन/फोन) एकपटक मात्र ल्याउने — appointment stream बदलिँदा होइन।
  void _ensureSalon(String salonId) {
    if (_salonLoadedFor == salonId) return;
    _salonLoadedFor = salonId;
    salonStream(salonId).first.then((s) {
      if (mounted) setState(() => _salon = s);
    }).catchError((_) {});
  }

  Future<void> _cancel(SalonAppointment a) async {
    final ok = await showKmDialog<bool>(
      context: context,
      title: 'Cancel appointment?',
      message:
          'Your time slot will be released for other customers. This cannot be undone.',
      icon: Icons.event_busy_rounded,
      iconBg: const LinearGradient(
          colors: [AppColors.kmRose, AppColors.kmPinkDeep]),
      actions: [
        KmDialogAction(
            label: 'Keep it', onPressed: () => Navigator.pop(context, false)),
        KmDialogAction(
            label: 'Cancel appointment',
            destructive: true,
            filled: true,
            onPressed: () => Navigator.pop(context, true)),
      ],
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    final done = await cancelSalonAppointment(a.id);
    if (!mounted) return;
    setState(() => _busy = false);
    salonSnack(context,
        done ? 'Appointment cancelled.' : 'Could not cancel. Please try again.');
  }

  Future<void> _review(SalonAppointment a) async {
    // content र actions अलग widget भएकोले दुवैले एउटै ValueNotifier हेर्ने।
    final rating = ValueNotifier<int>(0);
    final sending = ValueNotifier<bool>(false);
    final commentCtrl = TextEditingController();
    await showKmDialog<void>(
      context: context,
      title: 'Rate your visit',
      message: 'How was ${a.salonName}?',
      icon: Icons.star_rounded,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ValueListenableBuilder<int>(
            valueListenable: rating,
            builder: (_, r, __) => Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 1; i <= 5; i++)
                  IconButton(
                    onPressed: () => rating.value = i,
                    icon: Icon(
                        i <= r ? Icons.star_rounded : Icons.star_border_rounded,
                        size: 34,
                        color: AppColors.kmOrange),
                  ),
              ],
            ),
          ),
          TextField(
            controller: commentCtrl,
            maxLines: 3,
            maxLength: 500,
            style: const TextStyle(color: AppColors.kmText),
            decoration: kmInputDecoration('Write a review (optional)'),
          ),
        ],
      ),
      actions: [
        KmDialogAction(
            label: 'Not now', onPressed: () => Navigator.pop(context)),
        ListenableBuilder(
          listenable: Listenable.merge([rating, sending]),
          builder: (_, __) => KmDialogAction(
            label: sending.value ? 'Sending…' : 'Submit',
            filled: true,
            onPressed: rating.value == 0 || sending.value
                ? null
                : () async {
                    sending.value = true;
                    final err = await submitSalonReview(
                      appointmentId: a.id,
                      rating: rating.value,
                      comment: commentCtrl.text.trim(),
                    );
                    if (!mounted) return;
                    if (err == null) {
                      Navigator.pop(context);
                      salonSnack(context, 'Thanks for your review!');
                    } else {
                      sending.value = false;
                      salonSnack(context, err);
                    }
                  },
          ),
        ),
      ],
    );
    rating.dispose();
    sending.dispose();
    commentCtrl.dispose();
  }

  Future<void> _call(String phone) async {
    try {
      await launchUrl(Uri(scheme: 'tel', path: phone));
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return OledBackdrop(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Column(
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 16, 20, 0),
                child: KmScreenHeader(title: 'Booking pass'),
              ),
              Expanded(
                child: StreamBuilder<SalonAppointment?>(
                  stream: _stream,
                  builder: (context, snap) {
                    if (snap.hasError) {
                      return const Center(
                          child: Text('Could not load this booking.',
                              style: TextStyle(color: AppColors.kmMuted)));
                    }
                    if (!snap.hasData) {
                      if (snap.connectionState == ConnectionState.active) {
                        return const Center(
                            child: Text('Booking not found.',
                                style: TextStyle(color: AppColors.kmMuted)));
                      }
                      return const SkeletonList();
                    }
                    final a = snap.data!;
                    _ensureSalon(a.salonId);
                    return _body(a);
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _body(SalonAppointment a) {
    final upcoming = a.status == SalonAppointmentStatus.confirmed &&
        a.endAt.isAfter(DateTime.now());
    final canReview =
        a.status == SalonAppointmentStatus.completed && !a.reviewed;
    final past = !a.isActive;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
      children: [
        NeonCard(
          radius: 26,
          child: Column(
            children: [
              salonStatusTag(a.status),
              const SizedBox(height: 14),
              if (a.isActive)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: QrImageView(
                    data: a.qrPayload,
                    version: QrVersions.auto,
                    size: 190,
                    gapless: true,
                  ),
                )
              else
                Icon(
                    a.status == SalonAppointmentStatus.completed
                        ? Icons.check_circle_rounded
                        : Icons.event_busy_rounded,
                    size: 72,
                    color: salonStatusColor(a.status)),
              const SizedBox(height: 10),
              Text(
                  a.isActive
                      ? 'Show this QR to the salon when you arrive'
                      : 'This pass is no longer valid for check-in',
                  textAlign: TextAlign.center,
                  style:
                      const TextStyle(color: AppColors.kmMuted, fontSize: 12)),
              const SizedBox(height: 14),
              Text(a.salonName,
                  style: const TextStyle(
                      color: AppColors.kmText,
                      fontWeight: FontWeight.w800,
                      fontSize: 17)),
              const SizedBox(height: 10),
              salonSummaryRow('When',
                  '${salonDateLabel(a.startAt, _salon)}, ${salonClock(a.startAt, _salon)}'),
              salonSummaryRow('With', a.staffName.isEmpty ? '—' : a.staffName),
              salonSummaryRow('Services', a.serviceNames.join(', ')),
              salonSummaryRow('Duration', salonDurationLabel(a.durationMin)),
              salonSummaryRow('Total', formatHotelPrice(a.totalPrice),
                  bold: true),
              salonSummaryRow('Payment', salonPaymentLabel(a)),
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('Booking ID: ${a.id}',
                    style: const TextStyle(
                        color: AppColors.kmMuted, fontSize: 10.5)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        if (_salon != null && _salon!.phone.isNotEmpty)
          OutlinedButton.icon(
            onPressed: () => _call(_salon!.phone),
            icon: const Icon(Icons.phone_rounded, size: 18),
            label: const Text('Call salon'),
            style: _outlined(AppColors.kmTeal),
          ),
        if (canReview) ...[
          const SizedBox(height: 10),
          KmCtaButton(
            label: 'Rate & review',
            icon: Icons.star_rounded,
            onPressed: () => _review(a),
          ),
        ],
        if (past) ...[
          const SizedBox(height: 10),
          KmCtaButton(
            label: 'Book again',
            icon: Icons.replay_rounded,
            onPressed: () => rebookSalonAppointment(context, a),
          ),
        ],
        if (upcoming) ...[
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _busy ? null : () => _cancel(a),
            icon: const Icon(Icons.event_busy_rounded, size: 18),
            label: const Text('Cancel appointment'),
            style: _outlined(AppColors.kmRose),
          ),
        ],
      ],
    );
  }

  ButtonStyle _outlined(Color c) => OutlinedButton.styleFrom(
        foregroundColor: c,
        side: BorderSide(color: c.withValues(alpha: 0.5)),
        minimumSize: const Size.fromHeight(46),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      );
}
