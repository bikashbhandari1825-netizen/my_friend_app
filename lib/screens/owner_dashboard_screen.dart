// screens/owner_dashboard_screen.dart
// Admin/Owner प्यानल — inDrive dark theme। 4 tab, हरेकले सही data देखाउँछ:
//   Pending  → नयाँ worker दर्ता (पूरा विवरण) + Accept/Decline
//   Reports  → user ले पठाएका report मात्र
//   Support  → user ले पठाएका help/सुझाव message मात्र
//   Users    → app का सबै user को list + status
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../admin_notifications_page.dart';
import '../config/app_config.dart';
import '../l10n/strings.dart';
import '../theme/app_theme.dart';
import '../widgets/app_ui.dart';
import '../widgets/status_badge.dart';

String _fmtTime(dynamic ts) {
  if (ts is Timestamp) {
    final d = ts.toDate();
    return '${d.day}/${d.month}/${d.year}  ${d.hour}:${d.minute.toString().padLeft(2, '0')}';
  }
  return '';
}

/// साना रातो delete icon — admin card को header मा।
class _DeleteBtn extends StatelessWidget {
  final VoidCallback onTap;
  const _DeleteBtn(this.onTap);

  @override
  Widget build(BuildContext context) {
    return IconButton(
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
      tooltip: S.delete,
      icon: const Icon(Icons.delete_outline_rounded,
          size: 20, color: AppColors.danger),
      onPressed: onTap,
    );
  }
}

/// सबै admin tab का लागि साझा: live stream + row-मा checkbox + "Select all"
/// master checkbox + "Delete selected" bulk delete — सबै safety confirm सहित।
/// एउटै delete code-path ([deleteOne]) single र bulk दुवैले चलाउँछ, त्यसैले
/// permission/cascade एकै ठाउँमा।
class _AdminSelectableList extends StatefulWidget {
  final Query<Map<String, dynamic>> query;
  final IconData emptyIcon;
  final String emptyText;

  /// confirm text मा प्रयोग हुने नाम ("report", "job request" …)।
  final String noun;

  /// एउटा doc मेट्ने (+ cascade)। single र bulk दुवैले यही बोलाउँछ।
  final Future<void> Function(String id, Map<String, dynamic> data) deleteOne;

  final Widget Function(
      BuildContext context,
      String id,
      Map<String, dynamic> data,
      Widget checkbox,
      VoidCallback deleteThis) rowBuilder;

  /// docs count दिएर बन्ने header (जस्तै Users को "Total users")।
  final Widget Function(int total)? headerBuilder;

  /// false भए त्यो row select गर्न मिल्दैन (जस्तै owner user)।
  final bool Function(String id, Map<String, dynamic> data)? selectable;

  /// नयाँ snapshot आउनेबित्तिकै (scroll हुनुअघि नै) चलाउन चाहेको कुनै काम —
  /// जस्तै Pending tab ले कागजातका तस्बिर सबैका लागि अगावै precache गर्न।
  /// अरू tab (Reports/Support/Users) ले यो चाहिँदैन, त्यसैले ऐच्छिक।
  final void Function(BuildContext context,
      List<QueryDocumentSnapshot<Map<String, dynamic>>> docs)? onData;

  const _AdminSelectableList({
    required this.query,
    required this.emptyIcon,
    required this.emptyText,
    required this.noun,
    required this.deleteOne,
    required this.rowBuilder,
    this.headerBuilder,
    this.selectable,
    this.onData,
  });

  @override
  State<_AdminSelectableList> createState() => _AdminSelectableListState();
}

class _AdminSelectableListState extends State<_AdminSelectableList> {
  final Set<String> _sel = {};
  bool _busy = false;
  Map<String, Map<String, dynamic>> _dataById = {};

  // stream एकपटक मात्र subscribe — checkbox tick / setState मा re-subscribe
  // नभएर list flash/reload नहोस्।
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _stream =
      widget.query.snapshots();

  bool _canSelect(String id, Map<String, dynamic> d) =>
      widget.selectable?.call(id, d) ?? true;

  Future<bool> _confirm(String body, String actionLabel) async {
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(S.deleteConfirmTitle),
            content: Text(body),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: Text(S.cancel)),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.danger,
                    foregroundColor: Colors.white),
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(actionLabel),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _deleteSingle(String id) async {
    final messenger = ScaffoldMessenger.of(context);
    if (!await _confirm(S.deleteConfirmBody(widget.noun), S.delete)) return;
    try {
      await widget.deleteOne(id, _dataById[id] ?? const {});
      _sel.remove(id);
      messenger.showSnackBar(SnackBar(content: Text(S.deletedWord)));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('${S.errorWord}: $e')));
    }
  }

  Future<void> _deleteBulk() async {
    final messenger = ScaffoldMessenger.of(context);
    final ids = _sel.toList();
    if (ids.isEmpty) return;
    if (!await _confirm(
        S.bulkDeleteBody(ids.length, widget.noun), S.deleteSelected)) {
      return;
    }
    setState(() => _busy = true);
    var done = 0, failed = 0;
    for (final id in ids) {
      try {
        await widget.deleteOne(id, _dataById[id] ?? const {});
        done++;
      } catch (_) {
        failed++;
      }
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _sel.clear();
    });
    messenger.showSnackBar(SnackBar(
      content: Text(failed == 0
          ? S.deletedNItems(done)
          : '${S.deletedNItems(done)}  ·  ${S.failedNItems(failed)}'),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _stream,
      builder: (context, snap) {
        if (!snap.hasData) {
          if (snap.hasError) {
            return _EmptyState(Icons.error_outline_rounded, '${snap.error}');
          }
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snap.data?.docs ?? [];
        if (docs.isNotEmpty) widget.onData?.call(context, docs);
        _dataById = {for (final d in docs) d.id: d.data()};
        final selectableIds = [
          for (final d in docs)
            if (_canSelect(d.id, d.data())) d.id
        ];
        _sel.removeWhere((id) => !selectableIds.contains(id));

        if (docs.isEmpty) {
          return Column(children: [
            if (widget.headerBuilder != null) widget.headerBuilder!(0),
            Expanded(child: _EmptyState(widget.emptyIcon, widget.emptyText)),
          ]);
        }

        final allSelected =
            selectableIds.isNotEmpty && _sel.length == selectableIds.length;

        return Column(
          children: [
            if (widget.headerBuilder != null)
              widget.headerBuilder!(docs.length),
            _bar(selectableIds, allSelected),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
                itemCount: docs.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, i) {
                  final id = docs[i].id;
                  final data = docs[i].data();
                  final Widget cb = _canSelect(id, data)
                      ? Checkbox(
                          value: _sel.contains(id),
                          activeColor: AppColors.igViolet,
                          onChanged: _busy
                              ? null
                              : (v) => setState(() =>
                                  v == true ? _sel.add(id) : _sel.remove(id)),
                        )
                      : const SizedBox(width: 8);
                  return widget.rowBuilder(
                      context, id, data, cb, () => _deleteSingle(id));
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _bar(List<String> selectableIds, bool allSelected) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      padding: const EdgeInsets.only(left: 4, right: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: Colors.white.withValues(alpha: 0.28)),
      ),
      child: Row(
        children: [
          Checkbox(
            value: _sel.isEmpty ? false : (allSelected ? true : null),
            tristate: true,
            activeColor: Colors.white,
            checkColor: AppColors.igViolet,
            side: const BorderSide(color: Colors.white, width: 1.6),
            onChanged: (_busy || selectableIds.isEmpty)
                ? null
                : (_) => setState(() {
                      if (allSelected) {
                        _sel.clear();
                      } else {
                        _sel
                          ..clear()
                          ..addAll(selectableIds);
                      }
                    }),
          ),
          Text(
            _sel.isEmpty ? S.selectAll : S.nSelected(_sel.length),
            style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 12.5),
          ),
          const Spacer(),
          if (_sel.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: ElevatedButton.icon(
                onPressed: _busy ? null : _deleteBulk,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.danger,
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  minimumSize: const Size(0, 34),
                ),
                icon: _busy
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.delete_sweep_rounded, size: 18),
                label: Text(S.deleteSelected,
                    style: const TextStyle(fontWeight: FontWeight.w800)),
              ),
            ),
        ],
      ),
    );
  }
}

Future<void> _acceptWorker(BuildContext context, String docId, String uid,
    Map<String, dynamic> data) async {
  final db = FirebaseFirestore.instance;
  final approvedFields = {
    'verificationStatus': 'approved',
    'isVerified': true,
    'workerVerificationStatus': 'approved',
    'rejectionReason': FieldValue.delete(),
    'approvedAt': FieldValue.serverTimestamp(),
  };

  await db.collection('pendingWorkers').doc(docId).update({
    'status': 'approved',
    'verificationStatus': 'approved',
    'isVerified': true,
  });
  await db
      .collection('users')
      .doc(uid)
      .set(approvedFields, SetOptions(merge: true));
  await db.collection('providers').doc(uid).set({
    'verificationStatus': 'approved',
    'isVerified': true,
    'rejectionReason': FieldValue.delete(),
  }, SetOptions(merge: true));

  // test phone-login ले session को uid फरक हुनसक्छ — त्यो पनि update गर्ने,
  // ताकि worker को app मा restart बिनै live approve देखियोस्।
  try {
    final digits =
        (data['phone'] ?? '').toString().replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isNotEmpty) {
      final idx = await db.collection('phoneAccounts').doc(digits).get();
      final sessUid = (idx.data()?['uid'] ?? '').toString();
      if (sessUid.isNotEmpty && sessUid != uid) {
        await db
            .collection('users')
            .doc(sessUid)
            .set(approvedFields, SetOptions(merge: true));
      }
    }
  } catch (_) {}

  await FirebaseFirestore.instance.collection('registeredWorkers').add({
    'uid': uid,
    'name': '${data['firstName'] ?? ''} ${data['lastName'] ?? ''}'.trim(),
    'service': data['service'] ?? 'General',
    'experience': data['experience'] ?? 'N/A',
    'email': data['email'] ?? '',
    'phone': data['phone'] ?? '',
    'rating': '5.0',
    'reviews': '0',
    'price': data['price'] ?? 'Rs. 500',
    'location': data['location'] ?? 'Kathmandu, Nepal',
    'district': data['district'] ?? '',
    'document': data['documentName'] ?? '',
    'documentUrl': data['documentUrl'] ?? '',
    'citizenshipFrontUrl': data['citizenshipFrontUrl'] ?? '',
    'certificateUrls': data['certificateUrls'] ?? <String>[],
    'isOnline': true,
    'approvedAt': FieldValue.serverTimestamp(),
    if (data['lat'] != null && data['lng'] != null) ...{
      'lat': data['lat'],
      'lng': data['lng'],
    },
  });

  if (!context.mounted) return;
  ScaffoldMessenger.of(context)
      .showSnackBar(const SnackBar(content: Text('Provider approved')));
}

Future<void> _rejectWorker(
    BuildContext context, String docId, String uid) async {
  final ctrl = TextEditingController();
  final reason = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(S.rejectReasonTitle),
      content: TextField(
        controller: ctrl,
        maxLines: 3,
        decoration: InputDecoration(
          labelText: S.reasonLabel,
          hintText: S.rejectReasonHint,
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: Text(S.cancel)),
        ElevatedButton(
          onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
          child: Text(S.reject),
        ),
      ],
    ),
  );
  if (reason == null) return; // cancelled

  await FirebaseFirestore.instance
      .collection('pendingWorkers')
      .doc(docId)
      .update({
    'status': 'rejected',
    'verificationStatus': 'rejected',
    'isVerified': false,
    'rejectionReason': reason,
  });
  final userUpdate = {
    'verificationStatus': 'rejected',
    'isVerified': false,
    'workerVerificationStatus': 'rejected',
    'rejectionReason': reason,
  };
  await FirebaseFirestore.instance
      .collection('users')
      .doc(uid)
      .set(userUpdate, SetOptions(merge: true));
  await FirebaseFirestore.instance.collection('providers').doc(uid).set(
      {'verificationStatus': 'rejected', 'rejectionReason': reason},
      SetOptions(merge: true));
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Rejected — provider must re-submit')));
}

class OwnerDashboardScreen extends StatelessWidget {
  const OwnerDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 6,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          title: const Text('Admin dashboard',
              style:
                  TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.white,
          elevation: 0,
          flexibleSpace: const DecoratedBox(
            decoration: BoxDecoration(gradient: AppColors.buttonGradient),
          ),
          actions: const [_SupportNumberButton(), _NotifBell()],
          bottom: const TabBar(
            isScrollable: true,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            indicatorColor: Colors.white,
            tabs: [
              Tab(text: 'Pending'),
              Tab(text: 'History'),
              Tab(text: 'Requests'),
              Tab(text: 'Reports'),
              Tab(text: 'Support'),
              Tab(text: 'Users'),
            ],
          ),
        ),
        body: const DecoratedBox(
          decoration: BoxDecoration(gradient: AppColors.igGradient),
          child: SafeArea(
            child: TabBarView(
              children: [
                _PendingTab(),
                _HistoryTab(),
                _RequestsTab(),
                _ReportsTab(),
                _SupportTab(),
                _UsersTab(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _SupportNumberButton extends StatelessWidget {
  const _SupportNumberButton();

  Future<void> _edit(BuildContext context) async {
    final current = await SupportConfig.phoneOnce();
    if (!context.mounted) return;
    final ctrl = TextEditingController(text: current);
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(S.editSupportNumber),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.phone,
          decoration: InputDecoration(labelText: S.supportNumberLabel),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: Text(S.cancel)),
          ElevatedButton(
            onPressed: () async {
              await SupportConfig.setPhone(ctrl.text);
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: Text(S.save),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.contact_phone_outlined),
      tooltip: S.editSupportNumber,
      onPressed: () => _edit(context),
    );
  }
}

class _NotifBell extends StatelessWidget {
  const _NotifBell();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('adminNotifications')
          .where('read', isEqualTo: false)
          .snapshots(),
      builder: (context, snapshot) {
        final count = snapshot.data?.docs.length ?? 0;
        return Stack(
          children: [
            IconButton(
              icon: const Icon(Icons.notifications_none_rounded),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const AdminNotificationsPage()),
              ),
            ),
            if (count > 0)
              Positioned(
                right: 6,
                top: 6,
                child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: const BoxDecoration(
                      color: AppColors.danger, shape: BoxShape.circle),
                  constraints:
                      const BoxConstraints(minWidth: 16, minHeight: 16),
                  child: Text('$count',
                      textAlign: TextAlign.center,
                      style:
                          const TextStyle(color: Colors.white, fontSize: 10)),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String text;
  const _EmptyState(this.icon, this.text);

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        const SizedBox(height: 100),
        Icon(icon, size: 52, color: Colors.white.withValues(alpha: 0.9)),
        const SizedBox(height: 12),
        Center(
            child: Text(text,
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w600))),
      ],
    );
  }
}

Widget _kv(BuildContext context, IconData icon, String value) {
  final muted = Theme.of(context).colorScheme.onSurfaceVariant;
  return Padding(
    padding: const EdgeInsets.only(top: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 14, color: muted),
        const SizedBox(width: 6),
        Expanded(
            child: Text(value, style: Theme.of(context).textTheme.bodySmall)),
      ],
    ),
  );
}

class _LabeledPreview extends StatelessWidget {
  final String label;
  final String url;
  const _LabeledPreview({required this.label, required this.url});

  bool get _isImage {
    final u = url.toLowerCase();
    return !u.contains('.pdf') &&
        (u.contains('.png') ||
            u.contains('.jpg') ||
            u.contains('.jpeg') ||
            u.contains('.webp') ||
            u.contains('license.') ||
            u.contains('selfie.') ||
            u.contains('citizenship_front.') ||
            u.contains('citizenship_back.') ||
            u.contains('document.') ||
            u.contains('certificate'));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: theme.textTheme.bodySmall
                ?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        if (url.isEmpty)
          Container(
            height: 90,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Icon(Icons.image_not_supported_outlined,
                color: theme.colorScheme.onSurfaceVariant),
          )
        else if (_isImage)
          GestureDetector(
            onTap: () => showDialog(
              context: context,
              builder: (_) => Dialog(
                backgroundColor: Colors.black,
                insetPadding: const EdgeInsets.all(12),
                child: InteractiveViewer(
                  child: CachedNetworkImage(
                    imageUrl: url,
                    fit: BoxFit.contain,
                    placeholder: (_, __) => const Padding(
                      padding: EdgeInsets.all(40),
                      child: CircularProgressIndicator(color: Colors.white),
                    ),
                  ),
                ),
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.sm),
              child: CachedNetworkImage(
                imageUrl: url,
                height: 100,
                width: double.infinity,
                fit: BoxFit.cover,
                // Thumbnail मात्र देखाउने भएकोले सानो resolution मा नै
                // decode गर्ने — पूरा-resolution भन्दा छिटो पेन्ट हुन्छ।
                memCacheHeight: 200,
                fadeInDuration: const Duration(milliseconds: 150),
                placeholder: (_, __) => Container(
                  height: 100,
                  alignment: Alignment.center,
                  color: theme.colorScheme.surfaceContainerHighest,
                  child: const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
                errorWidget: (_, __, ___) => Container(
                  height: 60,
                  alignment: Alignment.center,
                  color: theme.colorScheme.surfaceContainerHighest,
                  child: Text(S.viewDocument),
                ),
              ),
            ),
          )
        else
          OutlinedButton.icon(
            icon: const Icon(Icons.description_outlined, size: 16),
            label: Text(S.viewDocument, overflow: TextOverflow.ellipsis),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: url));
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('${S.saved}: $url')),
              );
            },
          ),
      ],
    );
  }
}

/// Pending tab (action लिन बाँकी) र History tab (approve/reject भइसकेको —
/// पढ्न मात्र) दुवैले उही details+photo layout देखाउँछन्, त्यसैले एकपटक
/// मात्र बनाइएको। हरेक tab ले आफ्नै header row (status pill फरक) र footer
/// (Approve/Reject बटन बनाम status/reason text) थप्छ।
Widget _workerApplicationBody(BuildContext context, Map<String, dynamic> data) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _kv(context, Icons.email_outlined, (data['email'] ?? '—').toString()),
      if ((data['phone'] ?? '').toString().isNotEmpty)
        _kv(context, Icons.phone_outlined, data['phone'].toString()),
      _kv(context, Icons.work_history_outlined,
          'Experience: ${data['experience'] ?? '—'}'),
      _kv(context, Icons.payments_outlined, 'Rate: ${data['price'] ?? '—'}'),
      _kv(
          context,
          Icons.place_outlined,
          (data['location'] ?? data['district'] ?? 'Location not set')
              .toString()),
      _kv(
          context,
          Icons.badge_outlined,
          'ID: Citizenship'
          '   ·   Exp: ${data['experience'] ?? '—'}'
          '   ·   Certs: ${((data['certificateUrls'] as List?) ?? const []).length}'),
      _kv(
          context,
          data['lat'] != null ? Icons.gps_fixed : Icons.gps_off,
          data['lat'] != null
              ? 'GPS shared (${(data['lat'] as num).toStringAsFixed(3)}, ${(data['lng'] as num).toStringAsFixed(3)})'
              : 'No GPS coordinates'),
      const SizedBox(height: 10),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: _LabeledPreview(
              label: S.citizenshipFrontShort,
              url: (data['citizenshipFrontUrl'] ??
                      data['documentUrl'] ??
                      data['licenseUrl'] ??
                      '')
                  .toString(),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _LabeledPreview(
              label: S.citizenshipBackShort,
              url: (data['citizenshipBackUrl'] ?? '').toString(),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _LabeledPreview(
              label: S.selfiePhoto,
              url: (data['selfieUrl'] ?? '').toString(),
            ),
          ),
        ],
      ),
      // Driver Verification & Registration — Bike/Car चालकका लागि मात्र,
      // सवारी चालक अनुमतिपत्र + सवारी दर्ता (ब्लु बुक) — Admin ले approve
      // गर्नुअघि यी पनि हेर्न पाओस्।
      if ((data['drivingLicenseUrl'] ?? '').toString().isNotEmpty ||
          (data['vehicleRegistrationUrl'] ?? '').toString().isNotEmpty) ...[
        const SizedBox(height: 10),
        Text('Driver documents (${data['vehicleType'] ?? data['service'] ?? ''})',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _LabeledPreview(
                label: S.drivingLicenseLabel,
                url: (data['drivingLicenseUrl'] ?? '').toString(),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _LabeledPreview(
                label: S.vehicleRegistrationLabel,
                url: (data['vehicleRegistrationUrl'] ?? '').toString(),
              ),
            ),
          ],
        ),
      ],
      if (((data['certificateUrls'] as List?) ?? const []).isNotEmpty) ...[
        const SizedBox(height: 10),
        Text(S.certificatesLabel,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final c
                in ((data['certificateUrls'] as List?) ?? const []))
              SizedBox(
                width: 90,
                child: _LabeledPreview(label: 'Cert', url: c.toString()),
              ),
          ],
        ),
      ],
    ],
  );
}

/// तीनवटै कागजातको तस्बिर अगावै (scroll गरेर row देखिनुअघि नै) download/
/// cache गरिदिने — admin ले tab खोल्दा row देख्नेबित्तिकै तस्बिर पहिल्यै
/// तयार भइसकोस् भनेर। पहिल्यै cache भइसकेको URL लाई `CachedNetworkImage`/
/// `precacheImage` दुवैले फेरि नतानी सिधै return गर्छन्, त्यसैले हरेक
/// snapshot मा दोहोर्‍याएर बोलाउँदा पनि हानि छैन। Pending र History दुवै
/// tab ले प्रयोग गर्छन्।
void _precacheWorkerDocs(BuildContext context,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
  for (final d in docs) {
    final data = d.data();
    final urls = [
      (data['citizenshipFrontUrl'] ??
              data['documentUrl'] ??
              data['licenseUrl'] ??
              '')
          .toString(),
      (data['citizenshipBackUrl'] ?? '').toString(),
      (data['selfieUrl'] ?? '').toString(),
      (data['drivingLicenseUrl'] ?? '').toString(),
      (data['vehicleRegistrationUrl'] ?? '').toString(),
    ];
    for (final url in urls) {
      if (url.isEmpty) continue;
      precacheImage(CachedNetworkImageProvider(url), context)
          .catchError((_) {});
    }
  }
}

// ── Pending workers ──────────────────────────────────────────────────────────

class _PendingTab extends StatelessWidget {
  const _PendingTab();

  @override
  Widget build(BuildContext context) {
    return _AdminSelectableList(
      // `status` सधैं लेखिन्छ (पुरानो + नयाँ doc), त्यसैले यही field ले filter।
      query: FirebaseFirestore.instance
          .collection('pendingWorkers')
          .where('status', isEqualTo: 'pending'),
      emptyIcon: Icons.how_to_reg_rounded,
      emptyText: 'No pending verifications',
      noun: S.pendingWorkerWord,
      onData: _precacheWorkerDocs,
      deleteOne: (id, _) => FirebaseFirestore.instance
          .collection('pendingWorkers')
          .doc(id)
          .delete(),
      rowBuilder: (context, docId, data, checkbox, deleteThis) {
        final uid = (data['uid'] ?? '').toString();
        final name =
            '${data['firstName'] ?? ''} ${data['lastName'] ?? ''}'.trim();
        return AppCard(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  checkbox,
                  const LimeIconBadge(Icons.person, size: 44),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name.isEmpty ? '—' : name,
                            style: const TextStyle(
                                fontWeight: FontWeight.w700, fontSize: 15.5)),
                        Text('${data['service'] ?? '—'}  ·  Pending',
                            style: Theme.of(context).textTheme.bodySmall),
                      ],
                    ),
                  ),
                  const Pill('NEW', bg: AppColors.lime, fg: AppColors.onLime),
                  _DeleteBtn(deleteThis),
                ],
              ),
              const Divider(height: 20),
              _workerApplicationBody(context, data),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: SecondaryButton(
                      label: S.reject,
                      color: AppColors.danger,
                      onPressed: () => _rejectWorker(context, docId, uid),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: PrimaryButton(
                      label: S.approve,
                      icon: Icons.check_rounded,
                      onPressed: () => _acceptWorker(context, docId, uid, data),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

// ── Worker application history (approved/rejected — searchable, read-only) ──
// Approve/Reject ले `pendingWorkers` doc कहिल्यै मेट्दैन — status field मात्र
// बदल्छ (हेर्नुहोस् `_acceptWorker`/`_rejectWorker`), त्यसैले सबै डाटा
// (कागजातका URL सहित) पहिल्यै सुरक्षित छ। यो tab ले त्यही doc लाई status
// जुनसुकै भए पनि देखाउँछ, र इमेल/फोन/नामले client-side search गर्न दिन्छ —
// Firestore ले substring search गर्न सक्दैन भनेर सबै doc तानेर यहीँ filter
// गरिन्छ (admin verification queue साना हुने भएकोले यो पर्याप्त छ)।
class _HistoryTab extends StatefulWidget {
  const _HistoryTab();

  @override
  State<_HistoryTab> createState() => _HistoryTabState();
}

class _HistoryTabState extends State<_HistoryTab> {
  final _searchCtrl = TextEditingController();
  String _query = '';

  late final Stream<QuerySnapshot<Map<String, dynamic>>> _stream =
      FirebaseFirestore.instance.collection('pendingWorkers').snapshots();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  DateTime _sortKey(Map<String, dynamic> data) {
    final v = data['approvedAt'] ?? data['rejectedAt'] ?? data['submittedAt'];
    return v is Timestamp ? v.toDate() : DateTime.fromMillisecondsSinceEpoch(0);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
          child: TextField(
            controller: _searchCtrl,
            onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
            decoration: InputDecoration(
              hintText: S.searchByEmailOrPhone,
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () {
                        _searchCtrl.clear();
                        setState(() => _query = '');
                      },
                    ),
              filled: true,
              fillColor: theme.colorScheme.surface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.pill),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        Expanded(
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _stream,
            builder: (context, snap) {
              if (!snap.hasData) {
                if (snap.hasError) {
                  return _EmptyState(
                      Icons.error_outline_rounded, '${snap.error}');
                }
                return const Center(child: CircularProgressIndicator());
              }
              var docs = [...snap.data!.docs]
                ..sort((a, b) => _sortKey(b.data()).compareTo(_sortKey(a.data())));

              if (_query.isNotEmpty) {
                docs = docs.where((d) {
                  final data = d.data();
                  final email = (data['email'] ?? '').toString().toLowerCase();
                  final phone = (data['phone'] ?? '').toString().toLowerCase();
                  final name =
                      '${data['firstName'] ?? ''} ${data['lastName'] ?? ''}'
                          .trim()
                          .toLowerCase();
                  return email.contains(_query) ||
                      phone.contains(_query) ||
                      name.contains(_query);
                }).toList();
              }

              if (docs.isEmpty) {
                return _EmptyState(
                  Icons.history_rounded,
                  _query.isEmpty
                      ? 'No worker history yet'
                      : 'No match for "${_searchCtrl.text.trim()}"',
                );
              }

              _precacheWorkerDocs(context, docs);

              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 24),
                itemCount: docs.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, i) =>
                    _HistoryCard(data: docs[i].data()),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _HistoryCard extends StatelessWidget {
  final Map<String, dynamic> data;
  const _HistoryCard({required this.data});

  @override
  Widget build(BuildContext context) {
    final name =
        '${data['firstName'] ?? ''} ${data['lastName'] ?? ''}'.trim();
    final status =
        (data['status'] ?? data['verificationStatus'] ?? '—').toString();
    final Color pillColor = switch (status) {
      'approved' => AppColors.success,
      'rejected' => AppColors.danger,
      _ => AppColors.warning,
    };
    final approvedAt = data['approvedAt'];
    final rejectionReason = (data['rejectionReason'] ?? '').toString();

    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const LimeIconBadge(Icons.person, size: 44),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name.isEmpty ? '—' : name,
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 15.5)),
                    Text((data['service'] ?? '—').toString(),
                        style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
              Pill(status.toUpperCase(), bg: pillColor, fg: Colors.white),
            ],
          ),
          const Divider(height: 20),
          _workerApplicationBody(context, data),
          if (status == 'rejected' && rejectionReason.isNotEmpty) ...[
            const SizedBox(height: 10),
            _kv(context, Icons.info_outline_rounded,
                'Reason: $rejectionReason'),
          ],
          if (status == 'approved' && approvedAt is Timestamp) ...[
            const SizedBox(height: 6),
            _kv(context, Icons.event_available_rounded,
                'Approved on ${_fmtTime(approvedAt)}'),
          ],
        ],
      ),
    );
  }
}

// ── Service / job requests (users → workers) ────────────────────────────────

class _RequestsTab extends StatelessWidget {
  const _RequestsTab();

  static Future<void> _deleteRequest(String id) async {
    final db = FirebaseFirestore.instance;
    await db.collection('serviceRequests').doc(id).delete();
    // orphan chat + call signaling (best-effort)
    try {
      final msgs =
          await db.collection('chats').doc(id).collection('messages').get();
      for (final m in msgs.docs) {
        await m.reference.delete();
      }
      await db.collection('calls').doc(id).delete();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return _AdminSelectableList(
      query: FirebaseFirestore.instance
          .collection('serviceRequests')
          .orderBy('createdAt', descending: true),
      emptyIcon: Icons.assignment_outlined,
      emptyText: 'No job requests yet',
      noun: S.jobRequestWord,
      deleteOne: (id, _) => _deleteRequest(id),
      rowBuilder: (context, id, d, checkbox, deleteThis) {
        final theme = Theme.of(context);
        final proposed = d['proposedPrice'];
        final counter = d['workerCounterPrice'];
        final finalPrice = d['finalPrice'];
        final km = d['distanceKm'];
        return AppCard(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  checkbox,
                  const LimeIconBadge(Icons.assignment_rounded, size: 40),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${d['employerName'] ?? 'User'}  →  ${d['workerName'] ?? 'Worker'}',
                          style: const TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 14.5),
                        ),
                        Text(
                            '${d['service'] ?? '—'}'
                            '${km != null ? '  ·  ${(km as num).toStringAsFixed(1)} km' : ''}',
                            style: theme.textTheme.bodySmall),
                      ],
                    ),
                  ),
                  StatusBadge(
                      status: (d['status'] ?? '').toString(), large: true),
                  _DeleteBtn(deleteThis),
                ],
              ),
              if ((d['details'] ?? '').toString().isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(d['details'].toString(),
                    style: theme.textTheme.bodyMedium),
              ],
              const SizedBox(height: 6),
              _kv(
                  context,
                  Icons.payments_outlined,
                  'Offered: Rs. ${proposed ?? '—'}'
                  '${counter != null ? '   ·   Worker: Rs. $counter' : ''}'
                  '${finalPrice != null ? '   ·   Final: Rs. $finalPrice' : ''}'),
              _kv(context, Icons.schedule_rounded, _fmtTime(d['createdAt'])),
            ],
          ),
        );
      },
    );
  }
}

// ── Reports ──────────────────────────────────────────────────────────────────

class _ReportsTab extends StatelessWidget {
  const _ReportsTab();

  @override
  Widget build(BuildContext context) {
    return _AdminSelectableList(
      query: FirebaseFirestore.instance
          .collection('reports')
          .orderBy('createdAt', descending: true),
      emptyIcon: Icons.flag_outlined,
      emptyText: 'No reports submitted yet',
      noun: S.reportWord,
      deleteOne: (id, _) =>
          FirebaseFirestore.instance.collection('reports').doc(id).delete(),
      rowBuilder: (context, id, data, checkbox, deleteThis) => AppCard(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                checkbox,
                const Icon(Icons.report_problem_outlined,
                    color: AppColors.danger, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    (data['category'] ?? 'Report').toString(),
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 14.5),
                  ),
                ),
                Text(_fmtTime(data['createdAt']),
                    style: Theme.of(context).textTheme.bodySmall),
                _DeleteBtn(deleteThis),
              ],
            ),
            const SizedBox(height: 6),
            if ((data['email'] ?? '').toString().isNotEmpty)
              _kv(context, Icons.person_outline, data['email'].toString()),
            const SizedBox(height: 4),
            Text((data['details'] ?? '').toString(),
                style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }
}

// ── Support messages ─────────────────────────────────────────────────────────

class _SupportTab extends StatelessWidget {
  const _SupportTab();

  @override
  Widget build(BuildContext context) {
    return _AdminSelectableList(
      query: FirebaseFirestore.instance
          .collection('supportMessages')
          .orderBy('createdAt', descending: true),
      emptyIcon: Icons.forum_outlined,
      emptyText: 'No help or suggestion messages yet',
      noun: S.supportTicketWord,
      deleteOne: (id, _) => FirebaseFirestore.instance
          .collection('supportMessages')
          .doc(id)
          .delete(),
      rowBuilder: (context, id, data, checkbox, deleteThis) => AppCard(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                checkbox,
                const Icon(Icons.support_agent_rounded,
                    color: AppColors.lime, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    (data['topic'] ?? 'Message').toString(),
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 14.5),
                  ),
                ),
                Text(_fmtTime(data['createdAt']),
                    style: Theme.of(context).textTheme.bodySmall),
                _DeleteBtn(deleteThis),
              ],
            ),
            const SizedBox(height: 6),
            if ((data['email'] ?? '').toString().isNotEmpty)
              _kv(context, Icons.person_outline, data['email'].toString()),
            const SizedBox(height: 4),
            Text((data['message'] ?? '').toString(),
                style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }
}

// ── Users ────────────────────────────────────────────────────────────────────

const String _ownerEmail = 'bikashbhandari1825@gmail.com';

class _UsersTab extends StatelessWidget {
  const _UsersTab();

  /// user + सम्बन्धित docs सबै मेटाउने (cascade)। owner लाई कहिल्यै मेट्दैन।
  static Future<void> _deleteUser(String uid, Map<String, dynamic> data) async {
    if ((data['email'] ?? '').toString() == _ownerEmail) return;
    final db = FirebaseFirestore.instance;
    await db.collection('users').doc(uid).delete();
    await db.collection('providers').doc(uid).delete();
    for (final c in ['registeredWorkers', 'pendingWorkers', 'notifications']) {
      final snap = await db.collection(c).where('uid', isEqualTo: uid).get();
      for (final d in snap.docs) {
        await d.reference.delete();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return _AdminSelectableList(
      query: FirebaseFirestore.instance.collection('users'),
      emptyIcon: Icons.people_outline,
      emptyText: 'No users yet',
      noun: S.userWord,
      selectable: (_, d) => (d['email'] ?? '').toString() != _ownerEmail,
      deleteOne: _deleteUser,
      headerBuilder: (total) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        color: AppColors.lime.withValues(alpha: 0.12),
        child: Text('Total users: $total',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
      ),
      rowBuilder: (context, uid, data, checkbox, deleteThis) {
        final theme = Theme.of(context);
        final status = (data['accountStatus'] ?? 'active').toString();
        final Color sc = switch (status) {
          'suspended' => AppColors.warning,
          'blocked' => AppColors.danger,
          _ => AppColors.success,
        };
        Future<void> setStatus(String s) => FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .set({'accountStatus': s}, SetOptions(merge: true));

        final email = (data['email'] ?? '').toString();
        final isOwner = email == _ownerEmail;
        final name =
            '${data['firstName'] ?? ''} ${data['lastName'] ?? ''}'.trim();

        return AppCard(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  checkbox,
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                            name.isEmpty
                                ? (data['email'] ?? 'No email').toString()
                                : name,
                            style:
                                const TextStyle(fontWeight: FontWeight.w700)),
                        Text(
                            '${data['role'] ?? 'n/a'}'
                            '${email.isNotEmpty && name.isNotEmpty ? '  ·  $email' : ''}',
                            style: theme.textTheme.bodySmall),
                      ],
                    ),
                  ),
                  Pill(status, bg: sc, fg: Colors.white),
                ],
              ),
              const SizedBox(height: 6),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (status != 'active')
                    TextButton(
                        onPressed: () => setStatus('active'),
                        child: const Text('Activate')),
                  if (status != 'suspended')
                    TextButton(
                        onPressed: () => setStatus('suspended'),
                        child: const Text('Suspend',
                            style: TextStyle(color: AppColors.warning))),
                  if (status != 'blocked')
                    TextButton(
                        onPressed: () => setStatus('blocked'),
                        child: const Text('Block',
                            style: TextStyle(color: AppColors.danger))),
                  if (!isOwner) _DeleteBtn(deleteThis),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
