// screens/owner_dashboard_screen.dart
// Admin/Owner प्यानल — inDrive dark theme। 4 tab, हरेकले सही data देखाउँछ:
//   Pending  → नयाँ worker दर्ता (पूरा विवरण) + Accept/Decline
//   Reports  → user ले पठाएका report मात्र
//   Support  → user ले पठाएका help/सुझाव message मात्र
//   Users    → app का सबै user को list + status
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../admin_notifications_page.dart';
import '../config/app_config.dart';
import '../l10n/strings.dart';
import '../theme/app_theme.dart';
import '../widgets/app_ui.dart';

String _fmtTime(dynamic ts) {
  if (ts is Timestamp) {
    final d = ts.toDate();
    return '${d.day}/${d.month}/${d.year}  ${d.hour}:${d.minute.toString().padLeft(2, '0')}';
  }
  return '';
}

Future<void> _acceptWorker(BuildContext context, String docId, String uid,
    Map<String, dynamic> data) async {
  await FirebaseFirestore.instance
      .collection('pendingWorkers')
      .doc(docId)
      .update({
    'status': 'approved',
    'verificationStatus': 'approved',
    'isVerified': true,
  });
  await FirebaseFirestore.instance.collection('users').doc(uid).set({
    'verificationStatus': 'approved',
    'isVerified': true,
    'workerVerificationStatus': 'approved',
    'rejectionReason': FieldValue.delete(),
  }, SetOptions(merge: true));
  await FirebaseFirestore.instance.collection('providers').doc(uid).set({
    'verificationStatus': 'approved',
    'isVerified': true,
    'rejectionReason': FieldValue.delete(),
  }, SetOptions(merge: true));

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
        TextButton(
            onPressed: () => Navigator.pop(ctx), child: Text(S.cancel)),
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
  await FirebaseFirestore.instance
      .collection('providers')
      .doc(uid)
      .set({'verificationStatus': 'rejected', 'rejectionReason': reason},
          SetOptions(merge: true));
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Rejected — provider must re-submit')));
}

class OwnerDashboardScreen extends StatelessWidget {
  const OwnerDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 5,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Admin dashboard'),
          actions: const [_SupportNumberButton(), _NotifBell()],
          bottom: const TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: 'Pending'),
              Tab(text: 'Requests'),
              Tab(text: 'Reports'),
              Tab(text: 'Support'),
              Tab(text: 'Users'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _PendingTab(),
            _RequestsTab(),
            _ReportsTab(),
            _SupportTab(),
            _UsersTab(),
          ],
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
                      style: const TextStyle(
                          color: Colors.white, fontSize: 10)),
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
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return ListView(
      children: [
        const SizedBox(height: 100),
        Icon(icon, size: 52, color: muted),
        const SizedBox(height: 12),
        Center(child: Text(text, style: TextStyle(color: muted))),
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
            child: Text(value,
                style: Theme.of(context).textTheme.bodySmall)),
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
            u.contains('license.') ||
            u.contains('selfie.') ||
            u.contains('document.') ||
            u.contains('certificate.'));
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
                  child: Image.network(url, fit: BoxFit.contain),
                ),
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.sm),
              child: Image.network(
                url,
                height: 100,
                width: double.infinity,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
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

// ── Pending workers ──────────────────────────────────────────────────────────

class _PendingTab extends StatelessWidget {
  const _PendingTab();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      // `status` सधैं लेखिन्छ (पुरानो + नयाँ doc), त्यसैले यही field ले filter —
      // rejected/approved हुँदा दुवै field एकैचोटि update हुन्छन्।
      stream: FirebaseFirestore.instance
          .collection('pendingWorkers')
          .where('status', isEqualTo: 'pending')
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return _EmptyState(
              Icons.error_outline_rounded, '${snapshot.error}');
        }
        final docs = snapshot.data?.docs ?? [];
        if (docs.isEmpty) {
          return const _EmptyState(
              Icons.how_to_reg_rounded, 'No pending verifications');
        }
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
          itemCount: docs.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, i) {
            final data = docs[i].data() as Map<String, dynamic>;
            final docId = docs[i].id;
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
                      const LimeIconBadge(Icons.person, size: 44),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(name.isEmpty ? '—' : name,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 15.5)),
                            Text('${data['service'] ?? '—'}  ·  Pending',
                                style: Theme.of(context).textTheme.bodySmall),
                          ],
                        ),
                      ),
                      const Pill('NEW',
                          bg: AppColors.lime, fg: AppColors.onLime),
                    ],
                  ),
                  const Divider(height: 20),
                  _kv(context, Icons.email_outlined,
                      (data['email'] ?? '—').toString()),
                  if ((data['phone'] ?? '').toString().isNotEmpty)
                    _kv(context, Icons.phone_outlined,
                        data['phone'].toString()),
                  _kv(context, Icons.work_history_outlined,
                      'Experience: ${data['experience'] ?? '—'}'),
                  _kv(context, Icons.payments_outlined,
                      'Rate: ${data['price'] ?? '—'}'),
                  _kv(
                      context,
                      Icons.place_outlined,
                      (data['location'] ??
                              data['district'] ??
                              'Location not set')
                          .toString()),
                  _kv(
                      context,
                      Icons.description_outlined,
                      'Doc: ${data['documentName'] ?? '—'}'
                      '   ·   Cert yr: ${data['certificateYear'] ?? '—'}'),
                  _kv(
                      context,
                      data['lat'] != null
                          ? Icons.gps_fixed
                          : Icons.gps_off,
                      data['lat'] != null
                          ? 'GPS shared (${(data['lat'] as num).toStringAsFixed(3)}, ${(data['lng'] as num).toStringAsFixed(3)})'
                          : 'No GPS coordinates'),
                  const SizedBox(height: 10),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: _LabeledPreview(
                          label: S.viewDocument,
                          url: (data['documentUrl'] ??
                                  data['licenseUrl'] ??
                                  '')
                              .toString(),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _LabeledPreview(
                          label: S.selfiePhoto,
                          url: (data['selfieUrl'] ?? '').toString(),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: SecondaryButton(
                          label: S.reject,
                          color: AppColors.danger,
                          onPressed: () =>
                              _rejectWorker(context, docId, uid),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: PrimaryButton(
                          label: S.approve,
                          icon: Icons.check_rounded,
                          onPressed: () =>
                              _acceptWorker(context, docId, uid, data),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

// ── Service / job requests (users → workers) ────────────────────────────────

class _RequestsTab extends StatelessWidget {
  const _RequestsTab();

  ({Color color, String label}) _status(String s) {
    switch (s) {
      case 'confirmed':
        return (color: AppColors.success, label: 'Confirmed');
      case 'pending_employer_approval':
        return (color: AppColors.warning, label: 'Counter-offer');
      case 'declined':
        return (color: AppColors.danger, label: 'Declined');
      default:
        return (color: const Color(0xFF3B82F6), label: 'Awaiting worker');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('serviceRequests')
          .orderBy('createdAt', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snapshot.data?.docs ?? [];
        if (docs.isEmpty) {
          return const _EmptyState(
              Icons.assignment_outlined, 'No job requests yet');
        }
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
          itemCount: docs.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, i) {
            final d = docs[i].data() as Map<String, dynamic>;
            final st = _status((d['status'] ?? '').toString());
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
                      Pill(st.label, bg: st.color, fg: Colors.white),
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
                  _kv(context, Icons.schedule_rounded,
                      _fmtTime(d['createdAt'])),
                ],
              ),
            );
          },
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
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('reports')
          .orderBy('createdAt', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snapshot.data?.docs ?? [];
        if (docs.isEmpty) {
          return const _EmptyState(
              Icons.flag_outlined, 'No reports submitted yet');
        }
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
          itemCount: docs.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, i) {
            final data = docs[i].data() as Map<String, dynamic>;
            return AppCard(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
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
                    ],
                  ),
                  const SizedBox(height: 6),
                  if ((data['email'] ?? '').toString().isNotEmpty)
                    _kv(context, Icons.person_outline,
                        data['email'].toString()),
                  const SizedBox(height: 4),
                  Text((data['details'] ?? '').toString(),
                      style: Theme.of(context).textTheme.bodyMedium),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

// ── Support messages ─────────────────────────────────────────────────────────

class _SupportTab extends StatelessWidget {
  const _SupportTab();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('supportMessages')
          .orderBy('createdAt', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snapshot.data?.docs ?? [];
        if (docs.isEmpty) {
          return const _EmptyState(Icons.forum_outlined,
              'No help or suggestion messages yet');
        }
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
          itemCount: docs.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, i) {
            final data = docs[i].data() as Map<String, dynamic>;
            return AppCard(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
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
                    ],
                  ),
                  const SizedBox(height: 6),
                  if ((data['email'] ?? '').toString().isNotEmpty)
                    _kv(context, Icons.person_outline,
                        data['email'].toString()),
                  const SizedBox(height: 4),
                  Text((data['message'] ?? '').toString(),
                      style: Theme.of(context).textTheme.bodyMedium),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

// ── Users ────────────────────────────────────────────────────────────────────

class _UsersTab extends StatelessWidget {
  const _UsersTab();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('users').snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snapshot.data?.docs ?? [];
        return Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              color: AppColors.lime.withValues(alpha: 0.12),
              child: Text('Total users: ${docs.length}',
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w800)),
            ),
            Expanded(
              child: docs.isEmpty
                  ? const _EmptyState(Icons.people_outline, 'No users yet')
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                      itemCount: docs.length,
                      separatorBuilder: (_, __) =>
                          const SizedBox(height: 10),
                      itemBuilder: (context, i) {
                        final data =
                            docs[i].data() as Map<String, dynamic>;
                        final uid = docs[i].id;
                        final status =
                            (data['accountStatus'] ?? 'active').toString();

                        Color sc;
                        switch (status) {
                          case 'suspended':
                            sc = AppColors.warning;
                            break;
                          case 'blocked':
                            sc = AppColors.danger;
                            break;
                          default:
                            sc = AppColors.success;
                        }

                        Future<void> setStatus(String s) =>
                            FirebaseFirestore.instance
                                .collection('users')
                                .doc(uid)
                                .set({'accountStatus': s},
                                    SetOptions(merge: true));

                        final name = '${data['firstName'] ?? ''} '
                                '${data['lastName'] ?? ''}'
                            .trim();

                        return AppCard(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                            name.isEmpty
                                                ? (data['email'] ??
                                                        'No email')
                                                    .toString()
                                                : name,
                                            style: const TextStyle(
                                                fontWeight:
                                                    FontWeight.w700)),
                                        Text(
                                            '${data['role'] ?? 'n/a'}'
                                            '${(data['email'] ?? '').toString().isNotEmpty && name.isNotEmpty ? '  ·  ${data['email']}' : ''}',
                                            style:
                                                theme.textTheme.bodySmall),
                                      ],
                                    ),
                                  ),
                                  Pill(status, bg: sc, fg: Colors.white),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  if (status != 'active')
                                    TextButton(
                                        onPressed: () => setStatus('active'),
                                        child: const Text('Activate')),
                                  if (status != 'suspended')
                                    TextButton(
                                        onPressed: () =>
                                            setStatus('suspended'),
                                        child: const Text('Suspend',
                                            style: TextStyle(
                                                color: AppColors.warning))),
                                  if (status != 'blocked')
                                    TextButton(
                                        onPressed: () =>
                                            setStatus('blocked'),
                                        child: const Text('Block',
                                            style: TextStyle(
                                                color: AppColors.danger))),
                                ],
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }
}
