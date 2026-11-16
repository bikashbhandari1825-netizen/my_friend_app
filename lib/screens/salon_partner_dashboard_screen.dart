// screens/salon_partner_dashboard_screen.dart
//
// Salon / Beauty provider Dashboard — अपोइन्टमेन्ट (confirm/complete/cancel/
// no-show/mark-paid), service menu, team + साप्ताहिक समय, profile, र QR
// scan (check-in)। hotel_partner_dashboard_screen.dart कै भूमिका, तर सानो।
//
// अनुमति सबै firestore.rules (`isSalonOwner`) ले लागू गर्छ — यहाँको UI
// सुविधा मात्र। मूल्य/मिति/ग्राहक विवरण यहाँबाट बदल्न मिल्दैन (rules ले
// मालिकलाई `status`/`paymentStatus`/`completedAt` मात्र दिन्छ)।
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/salon_models.dart';
import '../services/salon_partner_service.dart';
import '../services/salon_service.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_ui.dart';
import 'qr_scanner_screen.dart';
import 'salon_common.dart';
import 'salon_inbox_screen.dart';
import '../widgets/futuristic_ui.dart';
import '../widgets/skeleton.dart';

class SalonPartnerDashboardScreen extends StatefulWidget {
  final String salonId;
  const SalonPartnerDashboardScreen({super.key, required this.salonId});

  @override
  State<SalonPartnerDashboardScreen> createState() =>
      _SalonPartnerDashboardScreenState();
}

class _SalonPartnerDashboardScreenState
    extends State<SalonPartnerDashboardScreen> {
  late final _salonStream = salonStream(widget.salonId);

  Future<void> _scan() async {
    final payload = await Navigator.push<String>(
      context,
      MaterialPageRoute(
          builder: (_) => const QrScannerScreen(title: 'Scan booking pass')),
    );
    if (payload == null || !mounted) return;
    final res = await checkInByQr(payload);
    if (!mounted) return;
    if (!res.ok) {
      await showKmDialog<void>(
        context: context,
        title: 'Check-in failed',
        message: res.error,
        icon: Icons.error_outline_rounded,
        iconBg: const LinearGradient(
            colors: [AppColors.kmRose, AppColors.kmPinkDeep]),
        actions: [
          KmDialogAction(
              label: 'OK', filled: true, onPressed: () => Navigator.pop(context)),
        ],
      );
      return;
    }
    await showKmDialog<void>(
      context: context,
      title: res.alreadyCheckedIn ? 'Already checked in' : 'Checked in ✓',
      icon: Icons.verified_rounded,
      iconBg:
          const LinearGradient(colors: [AppColors.kmTeal, AppColors.kmTealBlue]),
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          salonSummaryRow('Customer', res.customerName),
          salonSummaryRow('With', res.staffName),
          salonSummaryRow('Services', res.serviceNames.join(', ')),
          salonSummaryRow('Total', formatHotelPrice(res.totalPrice), bold: true),
          salonSummaryRow(
              'Payment',
              res.paymentStatus == 'paid'
                  ? 'Paid'
                  : res.paymentType == SalonPaymentType.online
                      ? 'Online — declared, verify it'
                      : 'Collect at salon'),
        ],
      ),
      actions: [
        KmDialogAction(
            label: 'OK', filled: true, onPressed: () => Navigator.pop(context)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Salon?>(
      stream: _salonStream,
      builder: (context, snap) {
        final salon = snap.data;
        return OledBackdrop(
          child: DefaultTabController(
            length: 4,
            child: Scaffold(
              backgroundColor: Colors.transparent,
              body: SafeArea(
                child: salon == null
                    ? const SkeletonList()
                    : Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                            child: KmScreenHeader(
                              title: salon.name,
                              actions: [
                                GlassIconButton(
                                  icon: Icons.chat_bubble_rounded,
                                  tooltip: 'Customer messages',
                                  onTap: () => Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          SalonInboxScreen(salonId: salon.id),
                                    ),
                                  ),
                                ),
                                GlassIconButton(
                                  icon: Icons.qr_code_scanner_rounded,
                                  tooltip: 'Scan booking pass',
                                  onTap: _scan,
                                ),
                              ],
                            ),
                          ),
                          if (!salon.isActive)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                              child: salonCard(
                                child: Text(
                                    salon.isPending
                                        ? 'Your salon is waiting for approval. Customers will see it and can book as soon as our team approves it. You can keep adding services, team and photos meanwhile.'
                                        : salon.isRejected
                                            ? 'Your salon was not approved${salon.rejectionReason.isEmpty ? '.' : ': ${salon.rejectionReason}'} Fix the details and contact support to be reviewed again.'
                                            : 'Your salon is paused — customers cannot see it or book. Turn it back on in the Profile tab.',
                                    style: TextStyle(
                                        color: salon.isRejected
                                            ? AppColors.kmRose
                                            : AppColors.kmOrange,
                                        fontSize: 12.5)),
                              ),
                            ),
                          const TabBar(
                            isScrollable: true,
                            tabAlignment: TabAlignment.start,
                            labelColor: AppColors.kmText,
                            unselectedLabelColor: AppColors.kmMuted,
                            indicatorColor: AppColors.kmOrange,
                            dividerColor: Colors.transparent,
                            tabs: [
                              Tab(text: 'Appointments'),
                              Tab(text: 'Services'),
                              Tab(text: 'Team'),
                              Tab(text: 'Profile'),
                            ],
                          ),
                          Expanded(
                            child: TabBarView(
                              children: [
                                _AppointmentsTab(salon: salon),
                                _ServicesTab(salon: salon),
                                _TeamTab(salon: salon),
                                _ProfileTab(salon: salon),
                              ],
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ),
        );
      },
    );
  }
}

// ─── shared sheet helper ─────────────────────────────────────────────────

Future<T?> _showFormSheet<T>(BuildContext context, Widget child) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        child: Container(
          constraints:
              BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.9),
          decoration: BoxDecoration(
            color: AppColors.kmSurface.withValues(alpha: 0.97),
            border: Border(top: BorderSide(color: AppColors.kmGlassBorder)),
          ),
          child: SafeArea(top: false, child: child),
        ),
      ),
    ),
  );
}

// ─── Appointments ────────────────────────────────────────────────────────

enum _ApptFilter { today, upcoming, history }

class _AppointmentsTab extends StatefulWidget {
  final Salon salon;
  const _AppointmentsTab({required this.salon});

  @override
  State<_AppointmentsTab> createState() => _AppointmentsTabState();
}

class _AppointmentsTabState extends State<_AppointmentsTab> {
  late final _stream = appointmentsForSalon(widget.salon.id);
  _ApptFilter _filter = _ApptFilter.today;

  String _localKey(DateTime instant) {
    final s =
        instant.toUtc().add(Duration(minutes: widget.salon.tzOffsetMin));
    return salonDateKey(DateTime(s.year, s.month, s.day));
  }

  bool _matches(SalonAppointment a, String todayKey) {
    final key = _localKey(a.startAt);
    return switch (_filter) {
      _ApptFilter.today => key == todayKey,
      _ApptFilter.upcoming =>
        key.compareTo(todayKey) > 0 && a.isActive,
      _ApptFilter.history => key.compareTo(todayKey) < 0 ||
          (key == todayKey && !a.isActive),
    };
  }

  Future<void> _setStatus(SalonAppointment a, String status) async {
    final err = await setAppointmentStatus(a, status);
    if (!mounted) return;
    if (err != null) salonSnack(context, err);
  }

  @override
  Widget build(BuildContext context) {
    final todayKey = salonDateKey(salonToday(widget.salon));
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
          child: Row(
            children: [
              for (final f in _ApptFilter.values)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(switch (f) {
                      _ApptFilter.today => 'Today',
                      _ApptFilter.upcoming => 'Upcoming',
                      _ApptFilter.history => 'History',
                    }),
                    selected: _filter == f,
                    onSelected: (_) => setState(() => _filter = f),
                    selectedColor: AppColors.kmOrange,
                    backgroundColor: Colors.white.withValues(alpha: 0.06),
                    labelStyle: TextStyle(
                        color: _filter == f
                            ? AppColors.kmInk
                            : AppColors.kmText,
                        fontWeight: FontWeight.w700,
                        fontSize: 12.5),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: StreamBuilder<List<SalonAppointment>>(
            stream: _stream,
            builder: (context, snap) {
              if (snap.hasError) {
                return const Center(
                    child: Text('Could not load appointments.',
                        style: TextStyle(color: AppColors.kmMuted)));
              }
              if (!snap.hasData) {
                return const SkeletonList();
              }
              var list = snap.data!.where((a) => _matches(a, todayKey)).toList();
              if (_filter == _ApptFilter.history) {
                list = list.reversed.toList();
              }
              if (list.isEmpty) {
                return const Center(
                    child: Text('No appointments here.',
                        style: TextStyle(color: AppColors.kmMuted)));
              }
              return ListView.builder(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                itemCount: list.length,
                itemBuilder: (_, i) => _apptCard(list[i]),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _apptCard(SalonAppointment a) {
    final started = !a.startAt.isAfter(DateTime.now());
    final active = a.isActive;
    return salonCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                    '${salonDateLabel(a.startAt, widget.salon)} · ${salonClock(a.startAt, widget.salon)} – ${salonClock(a.endAt, widget.salon)}',
                    style: const TextStyle(
                        color: AppColors.kmText,
                        fontWeight: FontWeight.w800,
                        fontSize: 13.5)),
              ),
              salonStatusTag(a.status),
            ],
          ),
          const SizedBox(height: 6),
          Text(a.serviceNames.join(', '),
              style: const TextStyle(color: AppColors.kmText, fontSize: 12.5)),
          const SizedBox(height: 2),
          Text(
              '${a.customerName} · with ${a.staffName.isEmpty ? '—' : a.staffName} · ${formatHotelPrice(a.totalPrice)}',
              style: const TextStyle(color: AppColors.kmMuted, fontSize: 12)),
          const SizedBox(height: 2),
          Text(salonPaymentLabel(a),
              style: TextStyle(
                  color: a.paymentStatus == 'paid'
                      ? AppColors.kmTeal
                      : AppColors.kmOrange,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              if (a.customerPhone.isNotEmpty)
                _action('Call', Icons.phone_rounded, AppColors.kmTeal, () async {
                  try {
                    await launchUrl(Uri(scheme: 'tel', path: a.customerPhone));
                  } catch (_) {}
                }),
              if (a.paymentType == SalonPaymentType.online &&
                  a.paymentStatus != 'paid' &&
                  a.status != SalonAppointmentStatus.cancelled)
                _action('Mark paid', Icons.payments_rounded, AppColors.kmOrange,
                    () async {
                  final ok = await markAppointmentPaid(a.id);
                  if (!mounted) return;
                  if (!ok) salonSnack(context, 'Could not update payment.');
                }),
              if (active && started)
                _action('Complete', Icons.check_circle_rounded,
                    AppColors.kmTeal,
                    () => _setStatus(a, SalonAppointmentStatus.completed)),
              if (a.status == SalonAppointmentStatus.confirmed && started)
                _action('No-show', Icons.person_off_rounded,
                    AppColors.kmOrange,
                    () => _setStatus(a, SalonAppointmentStatus.noShow)),
              if (active)
                _action('Cancel', Icons.event_busy_rounded, AppColors.kmRose,
                    () async {
                  final ok = await showKmDialog<bool>(
                    context: context,
                    title: 'Cancel this appointment?',
                    message: '${a.customerName} will see it as cancelled.',
                    actions: [
                      KmDialogAction(
                          label: 'Back',
                          onPressed: () => Navigator.pop(context, false)),
                      KmDialogAction(
                          label: 'Cancel appointment',
                          destructive: true,
                          filled: true,
                          onPressed: () => Navigator.pop(context, true)),
                    ],
                  );
                  if (ok == true) {
                    _setStatus(a, SalonAppointmentStatus.cancelled);
                  }
                }),
            ],
          ),
        ],
      ),
    );
  }

  Widget _action(
          String label, IconData icon, Color color, VoidCallback onTap) =>
      TextButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 16),
        label: Text(label),
        style: TextButton.styleFrom(
          foregroundColor: color,
          visualDensity: VisualDensity.compact,
        ),
      );
}

// ─── Services ────────────────────────────────────────────────────────────

class _ServicesTab extends StatelessWidget {
  final Salon salon;
  const _ServicesTab({required this.salon});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<SalonService>>(
      stream: salonServices(salon.id, includeInactive: true),
      builder: (context, snap) {
        final list = snap.data ?? const <SalonService>[];
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
          children: [
            KmCtaButton(
              label: 'Add service',
              icon: Icons.add_rounded,
              onPressed: () =>
                  _showFormSheet(context, _ServiceForm(salon: salon)),
            ),
            const SizedBox(height: 14),
            if (snap.hasData && list.isEmpty)
              const Padding(
                padding: EdgeInsets.all(20),
                child: Text(
                    'No services yet. Add what you offer, with a price and how long it takes.',
                    style: TextStyle(color: AppColors.kmMuted)),
              ),
            for (final s in list)
              GestureDetector(
                onTap: () => _showFormSheet(
                    context, _ServiceForm(salon: salon, existing: s)),
                child: salonCard(
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(s.name,
                                style: TextStyle(
                                    color: s.active
                                        ? AppColors.kmText
                                        : AppColors.kmMuted,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14)),
                            Text(
                                '${salonDurationLabel(s.durationMin)}${s.active ? '' : ' · hidden'}',
                                style: const TextStyle(
                                    color: AppColors.kmMuted, fontSize: 12)),
                          ],
                        ),
                      ),
                      Text(formatHotelPrice(s.price),
                          style: const TextStyle(
                              color: AppColors.kmOrange,
                              fontWeight: FontWeight.w800)),
                      const SizedBox(width: 6),
                      const Icon(Icons.edit_rounded,
                          size: 16, color: AppColors.kmMuted),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _ServiceForm extends StatefulWidget {
  final Salon salon;
  final SalonService? existing;
  const _ServiceForm({required this.salon, this.existing});

  @override
  State<_ServiceForm> createState() => _ServiceFormState();
}

class _ServiceFormState extends State<_ServiceForm> {
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late final _desc =
      TextEditingController(text: widget.existing?.description ?? '');
  late final _price = TextEditingController(
      text: widget.existing == null
          ? ''
          : widget.existing!.price.round().toString());
  late final _dur = TextEditingController(
      text: (widget.existing?.durationMin ?? 30).toString());
  late bool _active = widget.existing?.active ?? true;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _desc.dispose();
    _price.dispose();
    _dur.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final price = double.tryParse(_price.text.trim());
    final dur = int.tryParse(_dur.text.trim());
    if (_name.text.trim().isEmpty ||
        price == null ||
        price < 0 ||
        dur == null ||
        dur < 5 ||
        dur > 600) {
      salonSnack(context,
          'Enter a name, a price, and a duration between 5 and 600 minutes.');
      return;
    }
    setState(() => _saving = true);
    try {
      await saveSalonService(
        widget.salon.id,
        serviceId: widget.existing?.id,
        name: _name.text,
        description: _desc.text,
        price: price,
        durationMin: dur,
        active: _active,
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      salonSnack(context, 'Could not save: $e');
    }
  }

  Future<void> _delete() async {
    setState(() => _saving = true);
    try {
      await deleteSalonService(widget.salon.id, widget.existing!.id);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      salonSnack(context, 'Could not delete: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.existing == null ? 'Add service' : 'Edit service',
              style: const TextStyle(
                  color: AppColors.kmText,
                  fontSize: 17,
                  fontWeight: FontWeight.w800)),
          const SizedBox(height: 14),
          TextField(
              controller: _name,
              style: const TextStyle(color: AppColors.kmText),
              decoration: kmInputDecoration('Service name')),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                    controller: _price,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(color: AppColors.kmText),
                    decoration: kmInputDecoration('Price (Rs.)')),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                    controller: _dur,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(color: AppColors.kmText),
                    decoration: kmInputDecoration('Minutes')),
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
              controller: _desc,
              maxLines: 2,
              style: const TextStyle(color: AppColors.kmText),
              decoration: kmInputDecoration('Description (optional)')),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _active,
            onChanged: (v) => setState(() => _active = v),
            title: const Text('Visible to customers',
                style: TextStyle(color: AppColors.kmText, fontSize: 13.5)),
          ),
          const SizedBox(height: 6),
          KmCtaButton(
              label: 'Save',
              icon: Icons.check_rounded,
              loading: _saving,
              onPressed: _saving ? null : _save),
          if (widget.existing != null)
            TextButton(
              onPressed: _saving ? null : _delete,
              style: TextButton.styleFrom(foregroundColor: AppColors.kmRose),
              child: const Text('Delete service'),
            ),
        ],
      ),
    );
  }
}

// ─── Team ────────────────────────────────────────────────────────────────

const _dayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

class _TeamTab extends StatelessWidget {
  final Salon salon;
  const _TeamTab({required this.salon});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<SalonStaff>>(
      stream: salonStaff(salon.id, includeInactive: true),
      builder: (context, snap) {
        final list = snap.data ?? const <SalonStaff>[];
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
          children: [
            KmCtaButton(
              label: 'Add team member',
              icon: Icons.person_add_alt_1_rounded,
              onPressed: () =>
                  _showFormSheet(context, _StaffForm(salon: salon)),
            ),
            const SizedBox(height: 14),
            if (snap.hasData && list.isEmpty)
              const Padding(
                padding: EdgeInsets.all(20),
                child: Text(
                    'Add at least one team member with working hours — customers can only book times when someone is working. (If you work alone, add yourself.)',
                    style: TextStyle(color: AppColors.kmMuted)),
              ),
            for (final s in list)
              GestureDetector(
                onTap: () => _showFormSheet(
                    context, _StaffForm(salon: salon, existing: s)),
                child: salonCard(
                  child: Row(
                    children: [
                      SalonAvatar(
                          url: s.photoUrl,
                          icon: Icons.person_rounded,
                          size: 44,
                          radius: 22),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                                s.title.isEmpty
                                    ? s.name
                                    : '${s.name} · ${s.title}',
                                style: TextStyle(
                                    color: s.active
                                        ? AppColors.kmText
                                        : AppColors.kmMuted,
                                    fontWeight: FontWeight.w700)),
                            Text(
                                s.hours.isEmpty
                                    ? 'No working hours set'
                                    : [
                                        for (var d = 1; d <= 7; d++)
                                          if (s.hours[d] != null) _dayNames[d - 1]
                                      ].join(', '),
                                style: const TextStyle(
                                    color: AppColors.kmMuted, fontSize: 12)),
                          ],
                        ),
                      ),
                      const Icon(Icons.edit_rounded,
                          size: 16, color: AppColors.kmMuted),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _StaffForm extends StatefulWidget {
  final Salon salon;
  final SalonStaff? existing;
  const _StaffForm({required this.salon, this.existing});

  @override
  State<_StaffForm> createState() => _StaffFormState();
}

class _StaffFormState extends State<_StaffForm> {
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late final _title = TextEditingController(text: widget.existing?.title ?? '');
  late bool _active = widget.existing?.active ?? true;
  late final Set<String> _serviceIds = {...?widget.existing?.serviceIds};
  // नयाँ staff को default = सोम–शनि 09:00–18:00 (आइतबार बिदा)।
  late final Map<int, SalonDayHours> _hours = widget.existing != null
      ? {...widget.existing!.hours}
      : {for (var d = 1; d <= 6; d++) d: const SalonDayHours('09:00', '18:00')};
  late final _servicesStream = salonServices(widget.salon.id);
  SalonPickedImage? _newPhoto;
  bool _photoRemoved = false;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _title.dispose();
    super.dispose();
  }

  String _fmt(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  TimeOfDay _parse(String s) {
    final p = s.split(':');
    return TimeOfDay(
        hour: int.tryParse(p.first) ?? 9, minute: int.tryParse(p.last) ?? 0);
  }

  int _mins(String s) {
    final t = _parse(s);
    return t.hour * 60 + t.minute;
  }

  Future<void> _pick(int day, bool isOpen) async {
    final cur = _hours[day]!;
    final picked = await showTimePicker(
        context: context, initialTime: _parse(isOpen ? cur.open : cur.close));
    if (picked == null) return;
    setState(() => _hours[day] = isOpen
        ? SalonDayHours(_fmt(picked), cur.close)
        : SalonDayHours(cur.open, _fmt(picked)));
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      salonSnack(context, 'Enter a name.');
      return;
    }
    for (final e in _hours.entries) {
      if (_mins(e.value.close) <= _mins(e.value.open)) {
        salonSnack(context,
            '${_dayNames[e.key - 1]}: closing time must be after opening time.');
        return;
      }
    }
    setState(() => _saving = true);
    try {
      var photoUrl = _photoRemoved ? '' : (widget.existing?.photoUrl ?? '');
      final np = _newPhoto;
      if (np != null) {
        photoUrl = await uploadSalonImage(
            widget.salon.id, 'staff', np.bytes, np.name);
      }
      await saveSalonStaff(
        widget.salon.id,
        staffId: widget.existing?.id,
        name: _name.text,
        title: _title.text,
        active: _active,
        serviceIds: _serviceIds.toList(),
        hours: _hours,
        photoUrl: photoUrl,
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      salonSnack(context, 'Could not save: $e');
    }
  }

  Future<void> _delete() async {
    setState(() => _saving = true);
    try {
      await deleteSalonStaff(widget.salon.id, widget.existing!.id);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      salonSnack(context, 'Could not delete: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.existing == null ? 'Add team member' : 'Edit team member',
              style: const TextStyle(
                  color: AppColors.kmText,
                  fontSize: 17,
                  fontWeight: FontWeight.w800)),
          const SizedBox(height: 14),
          SalonPhotoField(
            label: 'photo',
            currentUrl: widget.existing?.photoUrl ?? '',
            icon: Icons.person_rounded,
            onChanged: (p, removed) {
              _newPhoto = p;
              _photoRemoved = removed;
            },
          ),
          const SizedBox(height: 14),
          TextField(
              controller: _name,
              style: const TextStyle(color: AppColors.kmText),
              decoration: kmInputDecoration('Name')),
          const SizedBox(height: 10),
          TextField(
              controller: _title,
              style: const TextStyle(color: AppColors.kmText),
              decoration: kmInputDecoration('Role (e.g. Senior barber)')),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _active,
            onChanged: (v) => setState(() => _active = v),
            title: const Text('Accepting bookings',
                style: TextStyle(color: AppColors.kmText, fontSize: 13.5)),
          ),
          salonSectionLabel('SERVICES THEY PERFORM (none selected = all)'),
          StreamBuilder<List<SalonService>>(
            stream: _servicesStream,
            builder: (context, snap) => Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final s in snap.data ?? const <SalonService>[])
                  FilterChip(
                    label: Text(s.name),
                    selected: _serviceIds.contains(s.id),
                    onSelected: (v) => setState(() =>
                        v ? _serviceIds.add(s.id) : _serviceIds.remove(s.id)),
                    selectedColor: AppColors.kmTeal,
                    backgroundColor: Colors.white.withValues(alpha: 0.06),
                    labelStyle: TextStyle(
                        color: _serviceIds.contains(s.id)
                            ? AppColors.kmInk
                            : AppColors.kmText,
                        fontSize: 12),
                  ),
              ],
            ),
          ),
          salonSectionLabel('WORKING HOURS'),
          for (var d = 1; d <= 7; d++)
            Row(
              children: [
                SizedBox(
                  width: 44,
                  child: Text(_dayNames[d - 1],
                      style: const TextStyle(
                          color: AppColors.kmText,
                          fontWeight: FontWeight.w700)),
                ),
                Switch(
                  value: _hours.containsKey(d),
                  onChanged: (v) => setState(() {
                    if (v) {
                      _hours[d] = const SalonDayHours('09:00', '18:00');
                    } else {
                      _hours.remove(d);
                    }
                  }),
                ),
                const SizedBox(width: 6),
                if (_hours[d] != null) ...[
                  TextButton(
                      onPressed: () => _pick(d, true),
                      child: Text(_hours[d]!.open)),
                  const Text('–', style: TextStyle(color: AppColors.kmMuted)),
                  TextButton(
                      onPressed: () => _pick(d, false),
                      child: Text(_hours[d]!.close)),
                ] else
                  const Text('Day off',
                      style: TextStyle(color: AppColors.kmMuted, fontSize: 12.5)),
              ],
            ),
          const SizedBox(height: 10),
          KmCtaButton(
              label: 'Save',
              icon: Icons.check_rounded,
              loading: _saving,
              onPressed: _saving ? null : _save),
          if (widget.existing != null)
            TextButton(
              onPressed: _saving ? null : _delete,
              style: TextButton.styleFrom(foregroundColor: AppColors.kmRose),
              child: const Text('Remove team member'),
            ),
        ],
      ),
    );
  }
}

// ─── Portfolio photos ────────────────────────────────────────────────────

class _PortfolioEditor extends StatefulWidget {
  final Salon salon;
  const _PortfolioEditor({required this.salon});

  @override
  State<_PortfolioEditor> createState() => _PortfolioEditorState();
}

class _PortfolioEditorState extends State<_PortfolioEditor> {
  static const _max = 12;
  bool _busy = false;

  Future<void> _add() async {
    if (widget.salon.photos.length >= _max) {
      salonSnack(context, 'You can add up to $_max portfolio photos.');
      return;
    }
    final p = await pickSalonImage(context);
    if (p == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final url =
          await uploadSalonImage(widget.salon.id, 'portfolio', p.bytes, p.name);
      await addSalonPortfolioPhoto(widget.salon.id, url);
    } catch (e) {
      if (mounted) salonSnack(context, 'Could not upload the photo: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove(String url) async {
    setState(() => _busy = true);
    try {
      await removeSalonPortfolioPhoto(widget.salon.id, url);
    } catch (e) {
      if (mounted) salonSnack(context, 'Could not remove the photo: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final photos = widget.salon.photos;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final url in photos)
          Stack(
            children: [
              SalonAvatar(
                  url: url,
                  icon: Icons.image_rounded,
                  size: 84,
                  radius: 14),
              Positioned(
                top: 2,
                right: 2,
                child: GestureDetector(
                  onTap: _busy ? null : () => _remove(url),
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
          ),
        GestureDetector(
          onTap: _busy ? null : _add,
          child: Container(
            width: 84,
            height: 84,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.kmOrange.withValues(alpha: 0.4)),
            ),
            child: _busy
                ? const Center(
                    child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2)))
                : const Icon(Icons.add_photo_alternate_rounded,
                    color: AppColors.kmOrange),
          ),
        ),
      ],
    );
  }
}

// ─── Profile ─────────────────────────────────────────────────────────────

class _ProfileTab extends StatefulWidget {
  final Salon salon;
  const _ProfileTab({required this.salon});

  @override
  State<_ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends State<_ProfileTab> {
  late final _name = TextEditingController(text: widget.salon.name);
  late final _address = TextEditingController(text: widget.salon.address);
  late final _phone = TextEditingController(text: widget.salon.phone);
  late final _desc = TextEditingController(text: widget.salon.description);
  late String _category = kSalonCategories.contains(widget.salon.category)
      ? widget.salon.category
      : kSalonCategories.last;
  late int _step = const [15, 30, 45, 60].contains(widget.salon.slotStepMin)
      ? widget.salon.slotStepMin
      : 30;
  late bool _active = widget.salon.isActive;
  SalonPickedImage? _newLogo;
  bool _logoRemoved = false;
  SalonPickedImage? _newCover;
  bool _coverRemoved = false;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _address.dispose();
    _phone.dispose();
    _desc.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().length < 2) {
      salonSnack(context, 'Enter your business name.');
      return;
    }
    setState(() => _saving = true);
    try {
      String? logoUrl;
      final nl = _newLogo;
      if (nl != null) {
        logoUrl = await uploadSalonImage(
            widget.salon.id, 'logo', nl.bytes, nl.name);
      } else if (_logoRemoved) {
        logoUrl = '';
      }
      String? coverUrl;
      final nc = _newCover;
      if (nc != null) {
        coverUrl = await uploadSalonImage(
            widget.salon.id, 'cover', nc.bytes, nc.name);
      } else if (_coverRemoved) {
        coverUrl = '';
      }
      await updateSalonProfile(
        widget.salon.id,
        name: _name.text,
        category: _category,
        address: _address.text,
        phone: _phone.text,
        description: _desc.text,
        slotStepMin: _step,
        // pending/rejected salon को status मालिकले बदल्न पाउँदैन।
        active: widget.salon.ownerCanToggle ? _active : null,
        logoUrl: logoUrl,
        coverUrl: coverUrl,
      );
      _newLogo = null;
      _logoRemoved = false;
      _newCover = null;
      _coverRemoved = false;
      if (mounted) salonSnack(context, 'Profile saved.');
    } catch (e) {
      if (mounted) salonSnack(context, 'Could not save: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
      children: [
        SalonPhotoField(
          label: 'logo',
          currentUrl: widget.salon.logoUrl,
          icon: salonCategoryIcon(widget.salon.category),
          onChanged: (p, removed) {
            _newLogo = p;
            _logoRemoved = removed;
          },
        ),
        const SizedBox(height: 12),
        SalonPhotoField(
          label: 'cover / banner photo',
          currentUrl: widget.salon.coverUrl,
          icon: Icons.image_rounded,
          onChanged: (p, removed) {
            _newCover = p;
            _coverRemoved = removed;
          },
        ),
        salonSectionLabel('PORTFOLIO PHOTOS'),
        _PortfolioEditor(salon: widget.salon),
        const SizedBox(height: 14),
        TextField(
            controller: _name,
            style: const TextStyle(color: AppColors.kmText),
            decoration: kmInputDecoration('Business name')),
        salonSectionLabel('CATEGORY'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final c in kSalonCategories)
              ChoiceChip(
                label: Text(c),
                selected: _category == c,
                onSelected: (_) => setState(() => _category = c),
                selectedColor: AppColors.kmOrange,
                backgroundColor: Colors.white.withValues(alpha: 0.06),
                labelStyle: TextStyle(
                    color:
                        _category == c ? AppColors.kmInk : AppColors.kmText,
                    fontWeight: FontWeight.w700,
                    fontSize: 12.5),
              ),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
            controller: _address,
            style: const TextStyle(color: AppColors.kmText),
            decoration: kmInputDecoration('Address / area')),
        const SizedBox(height: 10),
        TextField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            style: const TextStyle(color: AppColors.kmText),
            decoration: kmInputDecoration('Contact phone')),
        const SizedBox(height: 10),
        TextField(
            controller: _desc,
            maxLines: 3,
            style: const TextStyle(color: AppColors.kmText),
            decoration: kmInputDecoration('About your business')),
        salonSectionLabel('TIME-SLOT INTERVAL'),
        Wrap(
          spacing: 8,
          children: [
            for (final m in const [15, 30, 45, 60])
              ChoiceChip(
                label: Text('$m min'),
                selected: _step == m,
                onSelected: (_) => setState(() => _step = m),
                selectedColor: AppColors.kmTeal,
                backgroundColor: Colors.white.withValues(alpha: 0.06),
                labelStyle: TextStyle(
                    color: _step == m ? AppColors.kmInk : AppColors.kmText,
                    fontWeight: FontWeight.w700,
                    fontSize: 12.5),
              ),
          ],
        ),
        if (widget.salon.ownerCanToggle)
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _active,
          onChanged: (v) => setState(() => _active = v),
          title: const Text('Accepting new bookings',
              style: TextStyle(color: AppColors.kmText, fontSize: 13.5)),
          subtitle: const Text('Turn off to hide the salon from customers.',
              style: TextStyle(color: AppColors.kmMuted, fontSize: 11.5)),
        ),
        const SizedBox(height: 10),
        KmCtaButton(
            label: 'Save profile',
            icon: Icons.check_rounded,
            loading: _saving,
            onPressed: _saving ? null : _save),
      ],
    );
  }
}
