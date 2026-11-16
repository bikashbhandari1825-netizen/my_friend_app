// screens/salon_booking_screen.dart
//
// Salon / Beauty Appointment Booking — staff (वा "Any available") + मिति +
// समय-स्लट छान्ने। स्लट गणना server (Cloud Function `salonAvailableSlots`)
// ले गर्छ — staff को कामको समय, service अवधि र अरूका बुकिङ तीनै मिलाएर।
// यहाँ देखिएको स्लट अन्तिम होइन: "Confirm" थिच्दा `bookSalonAppointment`
// ले transaction भित्र फेरि जाँच्छ (अरूले बीचमा लिए "just taken" देखाउँछ)।
import 'package:flutter/material.dart';

import '../models/salon_models.dart';
import '../services/salon_service.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_ui.dart';
import 'salon_checkout_screen.dart';
import 'salon_common.dart';
import '../widgets/futuristic_ui.dart';
import '../widgets/skeleton.dart';

/// Re-book — पुरानो अपोइन्टमेन्टकै salon/service/staff पहिल्यै छानिएर सिधै
/// मिति-समय छान्ने स्क्रिनमा। service मेटिएको/निष्क्रिय भए, वा salon बन्द
/// भए सन्देश देखाउँछ (पुरानो बुकिङको दर सधैँ नयाँ दरमा चल्छ — server ले
/// हालको मूल्य नै लिन्छ)।
Future<void> rebookSalonAppointment(
    BuildContext context, SalonAppointment a) async {
  final messenger = ScaffoldMessenger.of(context);
  final navigator = Navigator.of(context);
  try {
    final salon = await salonStream(a.salonId).first;
    if (salon == null || !salon.isActive) {
      messenger.showSnackBar(const SnackBar(
          content: Text('This salon is not taking bookings right now.')));
      return;
    }
    final all = await salonServices(a.salonId).first;
    final picked = all.where((s) => a.serviceIds.contains(s.id)).toList();
    if (picked.length != a.serviceIds.length) {
      messenger.showSnackBar(const SnackBar(
          content: Text(
              'Some of those services are no longer offered. Please choose again.')));
      return;
    }
    navigator.push(MaterialPageRoute(
      builder: (_) => SalonBookingScreen(
          salon: salon, services: picked, initialStaffId: a.staffId),
    ));
  } catch (_) {
    messenger.showSnackBar(
        const SnackBar(content: Text('Could not open this salon. Try again.')));
  }
}

class SalonBookingScreen extends StatefulWidget {
  final Salon salon;
  final List<SalonService> services;
  final String? initialStaffId;
  const SalonBookingScreen({
    super.key,
    required this.salon,
    required this.services,
    this.initialStaffId,
  });

  @override
  State<SalonBookingScreen> createState() => _SalonBookingScreenState();
}

class _SalonBookingScreenState extends State<SalonBookingScreen> {
  static const _daysAhead = 14;

  late final _staffStream = salonStaff(widget.salon.id);
  late final DateTime _today = salonToday(widget.salon);
  late DateTime _date = _today;
  String? _staffId; // null = Any available
  SalonSlot? _slot;
  bool _loading = true;
  String? _error;
  List<SalonSlot> _slots = const [];
  int _requestSeq = 0;

  List<String> get _serviceIds => widget.services.map((s) => s.id).toList();
  int get _minutes => widget.services.fold(0, (a, s) => a + s.durationMin);
  double get _total => widget.services.fold(0, (a, s) => a + s.price);

  @override
  void initState() {
    super.initState();
    _staffId = widget.initialStaffId;
    _loadSlots();
  }

  Future<void> _loadSlots() async {
    // staff/मिति छिटो-छिटो बदलिँदा पुरानो response ले नयाँलाई नमेटोस्।
    final seq = ++_requestSeq;
    setState(() {
      _loading = true;
      _error = null;
      _slot = null;
    });
    final res = await fetchSalonSlots(
      salonId: widget.salon.id,
      date: _date,
      serviceIds: _serviceIds,
      staffId: _staffId,
    );
    if (!mounted || seq != _requestSeq) return;
    setState(() {
      _loading = false;
      _error = res.error;
      _slots = res.slots;
    });
  }

  void _continue() {
    final slot = _slot;
    if (slot == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SalonCheckoutScreen(
          salon: widget.salon,
          services: widget.services,
          start: slot.start,
          staffId: _staffId,
        ),
      ),
    );
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
                child: KmScreenHeader(title: 'Choose time'),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
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
                          const SizedBox(height: 4),
                          Text(
                              widget.services.map((s) => s.name).join(' + '),
                              style: const TextStyle(
                                  color: AppColors.kmMuted, fontSize: 12.5)),
                          const SizedBox(height: 4),
                          Text(
                              '${salonDurationLabel(_minutes)} · ${formatHotelPrice(_total)}',
                              style: const TextStyle(
                                  color: AppColors.kmOrange,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12.5)),
                        ],
                      ),
                    ),
                    salonSectionLabel('WHO DO YOU WANT?'),
                    _staffPicker(),
                    salonSectionLabel('DATE'),
                    _dateStrip(),
                    salonSectionLabel('AVAILABLE TIMES'),
                    _slotGrid(),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 14),
                child: KmCtaButton(
                  label: _slot == null
                      ? 'Select a time'
                      : 'Continue · ${salonDateLabel(_slot!.start, widget.salon)}, ${salonClock(_slot!.start, widget.salon)}',
                  icon: Icons.arrow_forward_rounded,
                  onPressed: _slot == null ? null : _continue,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _staffPicker() {
    return StreamBuilder<List<SalonStaff>>(
      stream: _staffStream,
      builder: (context, snap) {
        // यी service गर्न सक्ने staff मात्र।
        final staff = (snap.data ?? const <SalonStaff>[])
            .where((s) => s.canDo(_serviceIds))
            .toList();
        // Re-book मा पुरानो staff अब छैन/निष्क्रिय भए "Any available" मा फर्कने।
        if (snap.hasData &&
            _staffId != null &&
            !staff.any((s) => s.id == _staffId)) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _staffId != null) {
              _staffId = null;
              _loadSlots();
            }
          });
        }
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _staffChip(null, 'Any available', Icons.groups_rounded),
            for (final s in staff)
              _staffChip(s.id, s.name, Icons.person_rounded,
                  photoUrl: s.photoUrl),
          ],
        );
      },
    );
  }

  Widget _staffChip(String? id, String label, IconData icon,
      {String photoUrl = ''}) {
    final selected = _staffId == id;
    return ChoiceChip(
      avatar: photoUrl.isNotEmpty
          ? SalonAvatar(url: photoUrl, icon: icon, size: 24, radius: 12)
          : Icon(icon,
              size: 16, color: selected ? AppColors.kmInk : AppColors.kmMuted),
      label: Text(label),
      selected: selected,
      onSelected: (_) {
        if (_staffId == id) return;
        _staffId = id;
        _loadSlots();
      },
      selectedColor: AppColors.kmOrange,
      backgroundColor: Colors.white.withValues(alpha: 0.06),
      labelStyle: TextStyle(
          color: selected ? AppColors.kmInk : AppColors.kmText,
          fontWeight: FontWeight.w700,
          fontSize: 12.5),
    );
  }

  Widget _dateStrip() {
    const wd = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return SizedBox(
      height: 70,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _daysAhead,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          // `add(Duration)` होइन, मिति-भाग — device मा DST भए पनि मध्यरात नखिसियोस्।
          final d = DateTime(_today.year, _today.month, _today.day + i);
          final selected = d == _date;
          return InkWell(
            borderRadius: BorderRadius.circular(AppRadius.md),
            onTap: () {
              if (selected) return;
              _date = d;
              _loadSlots();
            },
            child: Container(
              width: 56,
              decoration: BoxDecoration(
                color: selected
                    ? AppColors.kmOrange
                    : Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(
                    color: selected
                        ? AppColors.kmOrange
                        : Colors.white.withValues(alpha: 0.12)),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(i == 0 ? 'Today' : wd[d.weekday - 1],
                      style: TextStyle(
                          color: selected ? AppColors.kmInk : AppColors.kmMuted,
                          fontSize: 11,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text('${d.day}',
                      style: TextStyle(
                          color: selected ? AppColors.kmInk : AppColors.kmText,
                          fontSize: 18,
                          fontWeight: FontWeight.w800)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _slotGrid() {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: SkeletonList(),
      );
    }
    if (_error != null) {
      return salonCard(
        child: Row(
          children: [
            const Icon(Icons.error_outline_rounded, color: AppColors.kmRose),
            const SizedBox(width: 10),
            Expanded(
              child: Text(_error!,
                  style: const TextStyle(color: AppColors.kmText, fontSize: 12.5)),
            ),
            TextButton(onPressed: _loadSlots, child: const Text('Retry')),
          ],
        ),
      );
    }
    if (_slots.isEmpty) {
      return salonCard(
        child: const Text(
            'No free times on this day. Try another date or another team member.',
            style: TextStyle(color: AppColors.kmMuted, fontSize: 12.5)),
      );
    }
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final s in _slots)
          ChoiceChip(
            label: Text(salonClock(s.start, widget.salon)),
            selected: _slot?.start == s.start,
            onSelected: (_) => setState(() => _slot = s),
            selectedColor: AppColors.kmTeal,
            backgroundColor: Colors.white.withValues(alpha: 0.06),
            labelStyle: TextStyle(
                color: _slot?.start == s.start
                    ? AppColors.kmInk
                    : AppColors.kmText,
                fontWeight: FontWeight.w700,
                fontSize: 12.5),
          ),
      ],
    );
  }
}
