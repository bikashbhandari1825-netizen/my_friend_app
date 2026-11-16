// screens/owner_dashboard_screen.dart
// Admin/Owner प्यानल — inDrive dark theme। 4 tab, हरेकले सही data देखाउँछ:
//   Pending  → नयाँ worker दर्ता (पूरा विवरण) + Accept/Decline
//   Reports  → user ले पठाएका report मात्र
//   Support  → user ले पठाएका help/सुझाव message मात्र
//   Users    → app का सबै user को list + status
import 'dart:async' show unawaited;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:crypto/crypto.dart' show sha256;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../admin_notifications_page.dart';
import '../config/app_config.dart';
import '../l10n/strings.dart';
import '../services/kyc_url.dart';
import '../theme/app_theme.dart';
import '../widgets/app_ui.dart';
import '../widgets/glass_ui.dart';
import '../widgets/status_badge.dart';
import 'admin_settlement_screen.dart';
import 'fare_matrix_editor_screen.dart';
import 'help_content_editor_screen.dart';
import 'payment_config_editor_screen.dart';
import 'job_actions.dart'
    show
        currentQuotaMonthKey,
        monthlyOrderQuotaForRating,
        releaseWorkerActiveJob;

String _fmtTime(dynamic ts) {
  if (ts is Timestamp) {
    final d = ts.toDate();
    return '${d.day}/${d.month}/${d.year}  ${d.hour}:${d.minute.toString().padLeft(2, '0')}';
  }
  return '';
}

/// Gradient circle icon badge — admin card हरूको हेडरमा (नयाँ dark-glass डिजाइन)।
class _KmIconBadge extends StatelessWidget {
  final IconData icon;
  final double size;
  const _KmIconBadge(this.icon, {this.size = 44});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        gradient: AppColors.kmCtaGradient,
        shape: BoxShape.circle,
      ),
      child: Icon(icon, color: AppColors.kmInk, size: size * 0.5),
    );
  }
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
          size: 20, color: AppColors.kmRose),
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
    return await showKmDialog<bool>(
          context: context,
          title: S.deleteConfirmTitle,
          message: body,
          icon: Icons.delete_forever_rounded,
          iconBg: const LinearGradient(
              colors: [AppColors.kmRose, AppColors.kmPinkDeep]),
          actions: [
            KmDialogAction(
                label: S.cancel, onPressed: () => Navigator.pop(context, false)),
            KmDialogAction(
              label: actionLabel,
              destructive: true,
              filled: true,
              onPressed: () => Navigator.pop(context, true),
            ),
          ],
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
                          activeColor: AppColors.kmOrange,
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
        color: AppColors.kmGlassFill,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.kmGlassBorder),
      ),
      child: Row(
        children: [
          Checkbox(
            value: _sel.isEmpty ? false : (allSelected ? true : null),
            tristate: true,
            activeColor: AppColors.kmOrange,
            checkColor: AppColors.kmInk,
            side: const BorderSide(color: AppColors.kmMuted, width: 1.6),
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
                color: AppColors.kmText,
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
                  backgroundColor: AppColors.kmRose,
                  foregroundColor: AppColors.kmInk,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  minimumSize: const Size(0, 34),
                ),
                icon: _busy
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: AppColors.kmInk))
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
    // नयाँ worker सुरुमा ०-रेटिङ (कुनै साँचो review नभएकोले) — `rating`/
    // `reviews` static field होइन, यहीँबाट live गणना हुन्छ (हेर्नुहोस्
    // `complete_job_sheet.dart::_confirm()` ले हरेक review पछि यही
    // `ratingSum`/`ratingCount` बढाउने, र `syncWorkerRatingToRegisteredWorkers`
    // ले `registeredWorkers` कै display copy पनि ताजा राख्ने)।
    'ratingSum': 0,
    'ratingCount': 0,
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
    // नागरिकता/कागजातको लिङ्क यहाँ (सबै लग इन युजरले पढ्न मिल्ने सूचीमा) कहिल्यै
    // नकपी गर्ने — ती `pendingWorkers`/`users` मा Storage path मात्र हुन्
    // (हेर्नुहोस् `services/kyc_url.dart`)। सेल्फी (अवतार) र certificateUrls
    // (पोर्टफोलियो) मात्र सार्वजनिक प्रदर्शन-सामग्री हुन्।
    'selfieUrl': data['selfieUrl'] ?? '',
    'certificateUrls': data['certificateUrls'] ?? <String>[],
    if ((data['vehicleDetails'] ?? '').toString().isNotEmpty)
      'vehicleDetails': data['vehicleDetails'],
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
  final reason = await showKmDialog<String>(
    context: context,
    title: S.rejectReasonTitle,
    icon: Icons.close_rounded,
    iconBg: const LinearGradient(
        colors: [AppColors.kmRose, AppColors.kmPinkDeep]),
    content: TextField(
      controller: ctrl,
      maxLines: 3,
      style: const TextStyle(color: AppColors.kmText),
      decoration: kmInputDecoration(S.reasonLabel, hint: S.rejectReasonHint),
    ),
    actions: [
      KmDialogAction(
          label: S.cancel, onPressed: () => Navigator.pop(context)),
      KmDialogAction(
        label: S.reject,
        destructive: true,
        filled: true,
        onPressed: () => Navigator.pop(context, ctrl.text.trim()),
      ),
    ],
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
  // "Manage Workers" र "Reports & Stats" landing-page card दुवैले पहिले
  // यही एउटै screen खोल्थे तर कहिल्यै फरक tab मा नझर्ने (app.dart मा भेटिएको
  // bug) — अब हरेकले आफ्नै सम्बन्धित tab मा सिधै उघ्रोस् भनेर। बाँकी सबै
  // tab अझै tap/swipe गरेर पुग्न मिल्छ — यो केवल *सुरुको* tab मात्र हो।
  // (Driver-सम्बन्धी सबै नियन्त्रण अब यहाँ होइन, छुट्टै `DriversControlDashboard`
  // screen मा छ — admin home कै छुट्टै कार्डबाट पुग्ने।)
  final int initialTabIndex;
  const OwnerDashboardScreen({super.key, this.initialTabIndex = 0});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 7,
      initialIndex: initialTabIndex,
      child: AuroraBackground(
        orbs: const [
          KmOrb(Alignment.topRight, AppColors.kmTeal),
          KmOrb(Alignment.bottomLeft, AppColors.kmPurple),
        ],
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
                  child: Row(
                    children: [
                      const Expanded(
                        child: KmScreenHeader(title: 'Admin'),
                      ),
                      // सातवटा action icon (Support/Help/Fare/Payment/
                      // Settlement/AppUpdate/Notif) — साँघुरो/साना फोनमा
                      // यी सबै एकैचोटि Row मा नअटी दायाँतर्फ RenderFlex
                      // "RIGHT OVERFLOWED" पट्टी देखिने भएकोले (नयाँ
                      // Payment/Settlement बटन थपेपछि झन् बिग्रिएको),
                      // Flexible + horizontal-scroll भित्र राखेर जुनसुकै
                      // स्क्रिन चौडाइमा पनि कहिल्यै overflow नहोस् भनेर —
                      // साँघुरो फोनमा बाँकी icon स्वाइप गरेर भेटिन्छन्।
                      Flexible(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: IconTheme.merge(
                            data: const IconThemeData(color: AppColors.kmText),
                            child: const Row(children: [
                              _SupportNumberButton(),
                              _HelpContentButton(),
                              _FareMatrixButton(),
                              _PaymentConfigButton(),
                              _SettlementButton(),
                              _AppUpdateButton(),
                              _SocialLinksButton(),
                              _NotifBell(),
                            ]),
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                    ],
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 14, 16, 0),
                  child: GlassPanel(
                    radius: 22,
                    padding: EdgeInsets.all(4),
                    child: TabBar(
                      isScrollable: true,
                      dividerColor: Colors.transparent,
                      labelColor: AppColors.kmInk,
                      unselectedLabelColor: AppColors.kmMuted2,
                      indicatorSize: TabBarIndicatorSize.tab,
                      indicator: BoxDecoration(
                        color: AppColors.kmText,
                        borderRadius: BorderRadius.all(Radius.circular(18)),
                      ),
                      labelStyle:
                          TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5),
                      unselectedLabelStyle:
                          TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5),
                      tabs: [
                        Tab(
                            icon: Icon(Icons.how_to_reg_rounded, size: 19),
                            text: 'Pending'),
                        Tab(
                            icon: Icon(Icons.history_rounded, size: 19),
                            text: 'History'),
                        Tab(
                            icon: Icon(Icons.assignment_rounded, size: 19),
                            text: 'Requests'),
                        Tab(
                            icon: Icon(Icons.star_rounded, size: 19),
                            text: 'Ratings'),
                        Tab(
                            icon: Icon(Icons.flag_rounded, size: 19),
                            text: 'Reports'),
                        Tab(
                            icon: Icon(Icons.support_agent_rounded, size: 19),
                            text: 'Support'),
                        Tab(
                            icon: Icon(Icons.group_rounded, size: 19),
                            text: 'Users'),
                      ],
                    ),
                  ),
                ),
                const Expanded(
                  child: TabBarView(
                    children: [
                      _PendingTab(),
                      _HistoryTab(),
                      _RequestsTab(),
                      _WorkerRatingsTab(),
                      _ReportsTab(),
                      _SupportTab(),
                      _UsersTab(),
                    ],
                  ),
                ),
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
    await showKmDialog(
      context: context,
      title: S.editSupportNumber,
      icon: Icons.contact_phone_rounded,
      content: TextField(
        controller: ctrl,
        keyboardType: TextInputType.phone,
        style: const TextStyle(color: AppColors.kmText),
        decoration: kmInputDecoration(S.supportNumberLabel),
      ),
      actions: [
        KmDialogAction(
            label: S.cancel, onPressed: () => Navigator.pop(context)),
        KmDialogAction(
          label: S.save,
          filled: true,
          onPressed: () async {
            await SupportConfig.setPhone(ctrl.text);
            if (context.mounted) Navigator.pop(context);
          },
        ),
      ],
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

// ─────────────────────────────────────────────────────────────────────────────

/// सामाजिक सञ्जाल (Facebook/Instagram/TikTok/X) लिंक — home screen को
/// promo banner मा देखिने बटनले प्रयोग गर्छन् (`config/socialLinks`,
/// config/app_config.dart::SocialLinksConfig)। `_SupportNumberButton` कै
/// उस्तै ढाँचा, फरक यति मात्र — यहाँ एकै dialog भित्र ४ वटा field।
class _SocialLinksButton extends StatelessWidget {
  const _SocialLinksButton();

  Future<void> _edit(BuildContext context) async {
    final current = await SocialLinksConfig.readOnce();
    if (!context.mounted) return;
    final fbCtrl = TextEditingController(text: current['facebook']);
    final igCtrl = TextEditingController(text: current['instagram']);
    final ttCtrl = TextEditingController(text: current['tiktok']);
    final xCtrl = TextEditingController(text: current['twitter']);
    await showKmDialog(
      context: context,
      title: 'Social Links',
      icon: Icons.share_rounded,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: fbCtrl,
            keyboardType: TextInputType.url,
            style: const TextStyle(color: AppColors.kmText),
            decoration: kmInputDecoration('Facebook URL'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: igCtrl,
            keyboardType: TextInputType.url,
            style: const TextStyle(color: AppColors.kmText),
            decoration: kmInputDecoration('Instagram URL'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: ttCtrl,
            keyboardType: TextInputType.url,
            style: const TextStyle(color: AppColors.kmText),
            decoration: kmInputDecoration('TikTok URL'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: xCtrl,
            keyboardType: TextInputType.url,
            style: const TextStyle(color: AppColors.kmText),
            decoration: kmInputDecoration('X (Twitter) URL'),
          ),
        ],
      ),
      actions: [
        KmDialogAction(
            label: S.cancel, onPressed: () => Navigator.pop(context)),
        KmDialogAction(
          label: S.save,
          filled: true,
          onPressed: () async {
            await SocialLinksConfig.setLinks(
              facebook: fbCtrl.text,
              instagram: igCtrl.text,
              tiktok: ttCtrl.text,
              twitter: xCtrl.text,
            );
            if (context.mounted) Navigator.pop(context);
          },
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.share_rounded),
      tooltip: 'Social Links',
      onPressed: () => _edit(context),
    );
  }
}

/// Help & Support screen भित्रका सबै content (Service Standard, FAQ,
/// Privacy Policy, Data Security) — यहाँबाट HelpContentEditorScreen खोल्ने।
class _HelpContentButton extends StatelessWidget {
  const _HelpContentButton();

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.article_outlined),
      tooltip: 'Help Content',
      onPressed: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const HelpContentEditorScreen()),
      ),
    );
  }
}

/// भाडा दर (base/per-km/per-minute/minimum/round-to) — यहाँबाट
/// FareMatrixEditorScreen खोल्ने (`config/fareMatrix`,
/// config/app_config.dart::FareMatrixConfig)।
class _FareMatrixButton extends StatelessWidget {
  const _FareMatrixButton();

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.payments_outlined),
      tooltip: 'Fare Management',
      onPressed: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const FareMatrixEditorScreen()),
      ),
    );
  }
}

/// Commission % र gateway (eSewa/Khalti/Bank-ConnectIPS) enable/credential
/// सेटिङ — यहाँबाट PaymentConfigEditorScreen खोल्ने (`config/payments`,
/// config/app_config.dart::PaymentConfig)।
class _PaymentConfigButton extends StatelessWidget {
  const _PaymentConfigButton();

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.account_balance_outlined),
      tooltip: 'Payment & Commission',
      onPressed: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const PaymentConfigEditorScreen()),
      ),
    );
  }
}

/// Wallet & Commission Ledger — worker हरूको pending settlement हेर्ने/
/// settle गर्ने (`walletLedger`/`settlements` collection, हेर्नुहोस्
/// admin_settlement_screen.dart)।
class _SettlementButton extends StatelessWidget {
  const _SettlementButton();

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.account_balance_wallet_outlined),
      tooltip: 'Wallet Settlement',
      onPressed: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const AdminSettlementScreen()),
      ),
    );
  }
}

/// In-app auto-update — नयाँ APK release publish गर्ने (`config/appUpdate`,
/// `services/app_update_service.dart` ले app startup मा पढ्छ)। testerहरूले
/// यहाँ owner ले भरेको versionCode भन्दा पुरानो APK चलाइरहेको भेटिए, आफैं
/// एप भित्रैबाट download+install गर्न पाउँछन्।
class _AppUpdateButton extends StatelessWidget {
  const _AppUpdateButton();

  Future<void> _edit(BuildContext context) async {
    final current = await AppUpdateConfig.readOnce();
    if (!context.mounted) return;
    final codeCtrl = TextEditingController(
        text: (current?['latestVersionCode'] ?? '').toString());
    final nameCtrl =
        TextEditingController(text: (current?['versionName'] ?? '').toString());
    final urlCtrl =
        TextEditingController(text: (current?['apkUrl'] ?? '').toString());
    final shaCtrl = TextEditingController(
        text: (current?['apkSha256'] ?? '').toString());
    final notesCtrl = TextEditingController(
        text: (current?['releaseNotes'] ?? '').toString());
    var force = current?['forceUpdate'] == true;
    var uploading = false;

    await showKmDialog(
      context: context,
      title: 'App Update',
      icon: Icons.system_update_rounded,
      content: StatefulBuilder(
        builder: (ctx, setState) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ConstrainedBox(
              constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.5),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: codeCtrl,
                      keyboardType: TextInputType.number,
                      style: const TextStyle(color: AppColors.kmText),
                      decoration: kmInputDecoration(
                          'Latest version code (integer, e.g. 2)'),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: nameCtrl,
                      style: const TextStyle(color: AppColors.kmText),
                      decoration:
                          kmInputDecoration('Version name (e.g. 1.1.0)'),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: urlCtrl,
                      style: const TextStyle(color: AppColors.kmText),
                      decoration: kmInputDecoration('APK download URL'),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: shaCtrl,
                      style: const TextStyle(color: AppColors.kmText),
                      decoration: kmInputDecoration(
                          'APK SHA-256 (64 hex — required; auto-filled on upload)'),
                    ),
                    const SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.kmOrange,
                          side: BorderSide(color: AppColors.kmGlassBorder),
                        ),
                        onPressed: uploading
                            ? null
                            : () async {
                                final code =
                                    int.tryParse(codeCtrl.text.trim());
                                if (code == null) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                        content: Text(
                                            'Set the version code first, then upload.')),
                                  );
                                  return;
                                }
                                setState(() => uploading = true);
                                try {
                                  final up = await _uploadApkFromDevice(code);
                                  if (up != null) {
                                    urlCtrl.text = up.$1;
                                    shaCtrl.text = up.$2;
                                  }
                                } catch (e) {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context)
                                        .showSnackBar(
                                      SnackBar(
                                          content: Text('Upload failed: $e')),
                                    );
                                  }
                                } finally {
                                  setState(() => uploading = false);
                                }
                              },
                        icon: uploading
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: AppColors.kmOrange))
                            : const Icon(Icons.upload_file_rounded, size: 18),
                        label: Text(uploading
                            ? 'Uploading…'
                            : 'Upload APK from this device'),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: notesCtrl,
                      minLines: 2,
                      maxLines: 4,
                      style: const TextStyle(color: AppColors.kmText),
                      decoration:
                          kmInputDecoration('Release notes (optional)'),
                    ),
                    const SizedBox(height: 6),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: force,
                      activeColor: AppColors.kmOrange,
                      checkColor: AppColors.kmInk,
                      onChanged: (v) => setState(() => force = v ?? false),
                      title: const Text('Force update (block "Later")',
                          style: TextStyle(color: AppColors.kmText)),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                KmDialogAction(
                    label: S.cancel, onPressed: () => Navigator.pop(context)),
                const SizedBox(width: 8),
                KmDialogAction(
                  label: S.save,
                  filled: true,
                  onPressed: uploading
                      ? null
                      : () async {
                          final code = int.tryParse(codeCtrl.text.trim());
                          if (code == null || urlCtrl.text.trim().isEmpty) {
                            return;
                          }
                          if (!RegExp(r'^[0-9a-fA-F]{64}$')
                              .hasMatch(shaCtrl.text.trim())) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content: Text(
                                      'Enter the APK SHA-256 (64 hex characters).')),
                            );
                            return;
                          }
                          await AppUpdateConfig.publish(
                            latestVersionCode: code,
                            versionName: nameCtrl.text,
                            apkUrl: urlCtrl.text,
                            apkSha256: shaCtrl.text,
                            releaseNotes: notesCtrl.text,
                            forceUpdate: force,
                          );
                          if (context.mounted) Navigator.pop(context);
                        },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Firebase Storage `releases/{versionCode}.apk` मा upload गरेर public
  /// download URL फर्काउने — देखाउने APK Android device (सामान्यतया
  /// `flutter build apk --release` ले बनाएको `app-release.apk`) बाट छानिन्छ।
  Future<(String, String)?> _uploadApkFromDevice(int versionCode) async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const ['apk'],
    );
    if (file == null) return null;
    final bytes = await file.readAsBytes();
    final ref = FirebaseStorage.instance.ref('releases/app-v$versionCode.apk');
    await ref.putData(
      bytes,
      SettableMetadata(contentType: 'application/vnd.android.package-archive'),
    );
    // SHA-256 पनि निकालेर फर्काउने — एपले install अघि यही मिलाउँछ।
    return (await ref.getDownloadURL(), sha256.convert(bytes).toString());
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.system_update_rounded),
      tooltip: 'App update',
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
                      color: AppColors.kmRose, shape: BoxShape.circle),
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
        Icon(icon, size: 52, color: AppColors.kmMuted),
        const SizedBox(height: 12),
        Center(
            child: Text(text,
                style: const TextStyle(
                    color: AppColors.kmText, fontWeight: FontWeight.w600))),
      ],
    );
  }
}

Widget _kv(BuildContext context, IconData icon, String value) {
  return Padding(
    padding: const EdgeInsets.only(top: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 14, color: AppColors.kmMuted),
        const SizedBox(width: 6),
        Expanded(
            child: Text(value,
                style: const TextStyle(
                    color: AppColors.kmMuted, fontSize: 12.5))),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(
                color: AppColors.kmMuted,
                fontSize: 12,
                fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        if (url.isEmpty)
          Container(
            height: 90,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(AppRadius.sm),
              border: Border.all(color: AppColors.kmGlassBorder),
            ),
            child: const Icon(Icons.image_not_supported_outlined,
                color: AppColors.kmMuted),
          )
        else if (_isImage)
          GestureDetector(
            onTap: () => showDialog(
              context: context,
              builder: (_) => Dialog(
                backgroundColor: Colors.black,
                insetPadding: const EdgeInsets.all(12),
                child: InteractiveViewer(
                  child: KycImage(
                    url: url,
                    fit: BoxFit.contain,
                    placeholder: const Padding(
                      padding: EdgeInsets.all(40),
                      child: CircularProgressIndicator(color: Colors.white),
                    ),
                  ),
                ),
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.sm),
              child: KycImage(
                url: url,
                height: 100,
                width: double.infinity,
                fit: BoxFit.cover,
                // Thumbnail मात्र देखाउने भएकोले सानो resolution मा नै
                // decode गर्ने — पूरा-resolution भन्दा छिटो पेन्ट हुन्छ।
                memCacheHeight: 200,
                placeholder: Container(
                  height: 100,
                  alignment: Alignment.center,
                  color: Colors.white.withValues(alpha: 0.06),
                  child: const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: AppColors.kmOrange),
                  ),
                ),
                errorWidget: Container(
                  height: 60,
                  alignment: Alignment.center,
                  color: Colors.white.withValues(alpha: 0.06),
                  child: Text(S.viewDocument,
                      style: const TextStyle(color: AppColors.kmMuted)),
                ),
              ),
            ),
          )
        else
          OutlinedButton.icon(
            icon: const Icon(Icons.description_outlined, size: 16),
            label: Text(S.viewDocument, overflow: TextOverflow.ellipsis),
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              try {
                final real = await resolveKycUrl(url);
                Clipboard.setData(ClipboardData(text: real));
                messenger.showSnackBar(SnackBar(content: Text(S.saved)));
              } catch (_) {
                messenger.showSnackBar(
                    const SnackBar(content: Text('Could not open document.')));
              }
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
        Text(
            'Driver documents (${data['vehicleType'] ?? data['service'] ?? ''})',
            style: const TextStyle(
                color: AppColors.kmMuted,
                fontSize: 12.5,
                fontWeight: FontWeight.w600)),
        if ((data['vehicleDetails'] ?? '').toString().isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text((data['vehicleDetails']).toString(),
                style: const TextStyle(
                    color: AppColors.kmMuted, fontSize: 12.5)),
          ),
        Builder(builder: (context) {
          final licenseNo = (data['licenseNumber'] ?? '').toString();
          final licenseCat = (data['licenseCategory'] ?? '').toString();
          final expiryRaw = (data['licenseExpiryDate'] ?? '').toString();
          final expiry = DateTime.tryParse(expiryRaw);
          final expired = expiry != null && expiry.isBefore(DateTime.now());
          if (licenseNo.isEmpty && expiry == null) {
            return const SizedBox.shrink();
          }
          return Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              [
                if (licenseNo.isNotEmpty) 'Lic# $licenseNo',
                if (licenseCat.isNotEmpty) licenseCat,
                if (expiry != null)
                  '${expired ? "EXPIRED" : "valid till"} ${expiry.day}/${expiry.month}/${expiry.year}',
              ].join(' · '),
              style: TextStyle(
                  color: expired ? AppColors.kmRose : AppColors.kmMuted,
                  fontSize: 12.5,
                  fontWeight: expired ? FontWeight.w700 : FontWeight.w400),
            ),
          );
        }),
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
            if ((data['vehicleInsuranceUrl'] ?? '').toString().isNotEmpty) ...[
              const SizedBox(width: 8),
              Expanded(
                child: _LabeledPreview(
                  label: S.vehicleInsuranceLabel,
                  url: (data['vehicleInsuranceUrl'] ?? '').toString(),
                ),
              ),
            ],
          ],
        ),
      ],
      if (((data['certificateUrls'] as List?) ?? const []).isNotEmpty) ...[
        const SizedBox(height: 10),
        Text(S.certificatesLabel,
            style: const TextStyle(
                color: AppColors.kmMuted,
                fontSize: 12.5,
                fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final c in ((data['certificateUrls'] as List?) ?? const []))
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
      (data['vehicleInsuranceUrl'] ?? '').toString(),
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
      // DATA-SYNC FIX — पहिले यहाँ `pendingWorkers` doc मात्र मेटिन्थ्यो,
      // सम्बन्धित `users/{uid}` कहिल्यै छोइँदैनथ्यो। Admin ले trash icon
      // (Reject बटन होइन) थिचेर entry हटाए, Pending tab मा "No pending
      // verifications" देखिन्थ्यो (entry गइसक्यो), तर worker को आफ्नै
      // `users` doc मा verificationStatus अझै 'pending' नै रहन्थ्यो —
      // त्यो worker अब कहिल्यै Pending tab मा नफर्किने भएकोले फोनमा सधैंको
      // लागि "Your registration is submitted" मै अडिन्थ्यो। अब यहाँ पनि
      // `_rejectWorker()` कै उस्तै `users/{uid}` लाई rejected मा सिंक गर्ने,
      // ताकि WorkerApprovalPendingPage को live listener ले तुरुन्तै rejected
      // UI देखाओस्।
      deleteOne: (id, data) async {
        final uid = (data['uid'] ?? '').toString();
        if (uid.isNotEmpty) {
          await FirebaseFirestore.instance.collection('users').doc(uid).set({
            'verificationStatus': 'rejected',
            'workerVerificationStatus': 'rejected',
            'isVerified': false,
            'rejectionReason': 'Application removed by admin — please register again.',
          }, SetOptions(merge: true));
        }
        await FirebaseFirestore.instance
            .collection('pendingWorkers')
            .doc(id)
            .delete();
      },
      rowBuilder: (context, docId, data, checkbox, deleteThis) {
        final uid = (data['uid'] ?? '').toString();
        final name =
            '${data['firstName'] ?? ''} ${data['lastName'] ?? ''}'.trim();
        return GlassPanel(
          radius: 20,
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  checkbox,
                  const _KmIconBadge(Icons.person, size: 44),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name.isEmpty ? '—' : name,
                            style: const TextStyle(
                                color: AppColors.kmText,
                                fontWeight: FontWeight.w700,
                                fontSize: 15.5)),
                        Text('${data['service'] ?? '—'}  ·  Pending',
                            style: const TextStyle(
                                color: AppColors.kmMuted, fontSize: 12)),
                      ],
                    ),
                  ),
                  const KmTag('NEW', color: AppColors.kmOrange),
                  _DeleteBtn(deleteThis),
                ],
              ),
              Divider(height: 20, color: AppColors.kmGlassBorder),
              _workerApplicationBody(context, data),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: SecondaryButton(
                      label: S.reject,
                      color: AppColors.kmRose,
                      onPressed: () => _rejectWorker(context, docId, uid),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: KmCtaButton(
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
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
          child: TextField(
            controller: _searchCtrl,
            onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
            style: const TextStyle(color: AppColors.kmText),
            decoration: kmInputDecoration(
              S.searchByEmailOrPhone,
              suffixIcon: _query.isEmpty
                  ? const Icon(Icons.search_rounded, color: AppColors.kmMuted)
                  : IconButton(
                      icon: const Icon(Icons.close_rounded,
                          color: AppColors.kmMuted),
                      onPressed: () {
                        _searchCtrl.clear();
                        setState(() => _query = '');
                      },
                    ),
            ).copyWith(
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.pill),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.pill),
                borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.14)),
              ),
              focusedBorder: const OutlineInputBorder(
                borderRadius: BorderRadius.all(Radius.circular(AppRadius.pill)),
                borderSide: BorderSide(color: AppColors.kmOrange, width: 1.4),
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
              var docs = [...snap.data!.docs]..sort(
                  (a, b) => _sortKey(b.data()).compareTo(_sortKey(a.data())));

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
                itemBuilder: (context, i) => _HistoryCard(data: docs[i].data()),
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
    final name = '${data['firstName'] ?? ''} ${data['lastName'] ?? ''}'.trim();
    final status =
        (data['status'] ?? data['verificationStatus'] ?? '—').toString();
    final Color pillColor = switch (status) {
      'approved' => AppColors.kmTeal,
      'rejected' => AppColors.kmRose,
      _ => AppColors.kmAmber,
    };
    final approvedAt = data['approvedAt'];
    final rejectionReason = (data['rejectionReason'] ?? '').toString();

    return GlassPanel(
      radius: 20,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const _KmIconBadge(Icons.person, size: 44),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name.isEmpty ? '—' : name,
                        style: const TextStyle(
                            color: AppColors.kmText,
                            fontWeight: FontWeight.w700,
                            fontSize: 15.5)),
                    Text((data['service'] ?? '—').toString(),
                        style: const TextStyle(
                            color: AppColors.kmMuted, fontSize: 12)),
                  ],
                ),
              ),
              Pill(status.toUpperCase(), bg: pillColor, fg: AppColors.kmInk),
            ],
          ),
          Divider(height: 20, color: AppColors.kmGlassBorder),
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
        final proposed = d['proposedPrice'];
        final counter = d['workerCounterPrice'];
        final finalPrice = d['finalPrice'];
        final km = d['distanceKm'];
        final status = (d['status'] ?? '').toString();
        final workerUid = (d['workerUid'] ?? '').toString();
        // साधारण Worker (Plumber/Electrician/... — Bike/Car ड्राइभर मात्र
        // देखिने Drivers Control Dashboard मा यिनी कहिल्यै आउँदैनन्) कै
        // सक्रिय काम पनि यहीँबाटै admin ले cancel गर्न सकून् — `_ActiveTaskRow`
        // (Drivers Control Dashboard कै उही widget, दोहोरिँदैन) पुनः-प्रयोग।
        final showCancelRow = workerUid.isNotEmpty &&
            {'accepted', 'confirmed', 'in_progress'}.contains(status);
        return GlassPanel(
          radius: 20,
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  checkbox,
                  const _KmIconBadge(Icons.assignment_rounded, size: 40),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${d['employerName'] ?? 'User'}  →  ${d['workerName'] ?? 'Worker'}',
                          style: const TextStyle(
                              color: AppColors.kmText,
                              fontWeight: FontWeight.w700,
                              fontSize: 14.5),
                        ),
                        Text(
                            '${d['service'] ?? '—'}'
                            '${km != null ? '  ·  ${(km as num).toStringAsFixed(1)} km' : ''}',
                            style: const TextStyle(
                                color: AppColors.kmMuted, fontSize: 12)),
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
                    style: const TextStyle(color: AppColors.kmMuted)),
              ],
              const SizedBox(height: 6),
              _kv(
                  context,
                  Icons.payments_outlined,
                  'Offered: Rs. ${proposed ?? '—'}'
                  '${counter != null ? '   ·   Worker: Rs. $counter' : ''}'
                  '${finalPrice != null ? '   ·   Final: Rs. $finalPrice' : ''}'),
              _kv(context, Icons.schedule_rounded, _fmtTime(d['createdAt'])),
              if (showCancelRow)
                _ActiveTaskRow(requestId: id, data: d, workerUid: workerUid),
            ],
          ),
        );
      },
    );
  }
}

// ── Worker Ratings & Monthly Order-Quota (Admin) ────────────────────────────
// Owner ले rating अनुसार worker list sort/filter गर्न, र आवश्यक परे कुनै
// पनि worker को rating वा order-limit म्यानुअली override गर्न सक्ने ठाउँ
// (`job_actions.dart::consumeOrderQuotaInTransaction` ले यही
// `ratingOverride`/`orderLimitOverride` लाई computed tier भन्दा पहिले पढ्छ)।
enum _RatingSort { highToLow, lowToHigh }

// ── Drivers Control Dashboard — Owner home कै छुट्टै कार्डबाट सिधै पुग्ने,
// आफैंमा पूर्ण independent admin screen। Driver सम्बन्धी सबै नियन्त्रण/
// व्यवस्थापन/सेटिङ (online स्थिति, verification approve/reject, account
// suspend/block, कागजात, ride history/stats) यहीँ मात्र — arku कुनै tab मा
// दोहोरिँदैन। सामान्य (non-driver) Worker का लागि Ratings/Reports भने
// आफ्नै छुट्टै tab मा जस्ताको त्यस्तै रहन्छन् (यो dashboard ले तिनलाई छुँदैन)।
class DriversControlDashboard extends StatelessWidget {
  const DriversControlDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    return const AuroraBackground(
      orbs: [
        KmOrb(Alignment.topLeft, AppColors.kmOrangeDeep),
        KmOrb(Alignment.bottomRight, AppColors.kmPurple),
      ],
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: KmScreenHeader(title: 'Drivers Control Dashboard'),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: _DriverDashboardQuickActions(),
              ),
              Expanded(child: _DriverControlHub()),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Payment/Fare/Wallet Quick Actions — Drivers Control Dashboard कै
// टुप्पोमा नै सिधै देखिने ठूला कार्ड (owner_dashboard_screen.dart कै
// 4-tab Admin panel को टुप्पोको सानो icon-row मा यी पहिल्यै थिए, तर
// त्यहाँ लुकेको/नदेखिने गुनासो आएपछि — Driver सम्बन्धी भुक्तानी/भाडा/
// वालेट नियन्त्रण सबै यहीं, छुट्टै screen खोज्नु नपरोस् भनेर)।
class _DriverDashboardQuickActions extends StatelessWidget {
  const _DriverDashboardQuickActions();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _QuickActionCard(
            icon: Icons.payments_outlined,
            label: 'Fare & Commission\nSettings',
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const FareMatrixEditorScreen())),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _QuickActionCard(
            icon: Icons.qr_code_2_rounded,
            label: 'Payment &\nQR Config',
            onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const PaymentConfigEditorScreen())),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _QuickActionCard(
            icon: Icons.account_balance_wallet_outlined,
            label: 'Driver Wallet &\nSettlements',
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const AdminSettlementScreen())),
          ),
        ),
      ],
    );
  }
}

class _QuickActionCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _QuickActionCard({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      radius: AppRadius.lg,
      padding: EdgeInsets.zero,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: AppColors.kmOrange, size: 24),
                const SizedBox(height: 8),
                Text(label,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 11, fontWeight: FontWeight.w700, height: 1.2)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Driver Control Hub — सबै Driver को list (online/offline, verification,
// rating), tap गरे पूरा नियन्त्रण (approve/reject/suspend/documents/ride
// history) खुल्ने _DriverAdminDetailPage मा जान्छ।
// ── साझा helper (card र detail page दुवैले प्रयोग गर्ने, दोहोरो नबनोस्) ──

Future<QueryDocumentSnapshot<Map<String, dynamic>>?> _findPendingDriverDoc(
    String uid) async {
  final snap = await FirebaseFirestore.instance
      .collection('pendingWorkers')
      .where('uid', isEqualTo: uid)
      .where('status', isEqualTo: 'pending')
      .limit(1)
      .get();
  return snap.docs.isEmpty ? null : snap.docs.first;
}

Future<void> _setDriverAccountStatus(String uid, String status) =>
    FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .set({'accountStatus': status}, SetOptions(merge: true));

void _viewDriverDoc(BuildContext context, String url) {
  if (url.isEmpty) return;
  showDialog(
    context: context,
    builder: (_) => Dialog(
      backgroundColor: Colors.black,
      child: InteractiveViewer(
        child: KycImage(url: url, fit: BoxFit.contain),
      ),
    ),
  );
}

/// सबै कागजात (citizenship/selfie/license/vehicle reg/insurance) एउटै
/// bottom sheet मा — "Documents" बटन थिच्दा (card भित्रैबाट, अर्को page नखोली)।
void _showDriverDocsSheet(BuildContext context, Map<String, dynamic> data) {
  final docs = <(String, String)>[
    ('Citizenship front', (data['citizenshipFrontUrl'] ?? '').toString()),
    ('Citizenship back', (data['citizenshipBackUrl'] ?? '').toString()),
    ('Selfie', (data['selfieUrl'] ?? '').toString()),
    ('License', (data['drivingLicenseUrl'] ?? '').toString()),
    ('Vehicle reg.', (data['vehicleRegistrationUrl'] ?? '').toString()),
    ('Insurance', (data['vehicleInsuranceUrl'] ?? '').toString()),
  ].where((d) => d.$2.isNotEmpty).toList();

  showKmSheet(
    context: context,
    title: 'Documents',
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(10, 4, 10, 16),
        child: docs.isEmpty
            ? const Text('No documents uploaded yet',
                style: TextStyle(color: AppColors.kmMuted))
            : Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final d in docs) _docThumbShared(context, d.$1, d.$2),
                ],
              ),
      ),
    ],
  );
}

Widget _docThumbShared(BuildContext context, String label, String url) {
  return GestureDetector(
    onTap: () => _viewDriverDoc(context, url),
    child: Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: KycImage(
            url: url,
            width: 76,
            height: 76,
            fit: BoxFit.cover,
            errorWidget: Container(
              width: 76,
              height: 76,
              color: Colors.white.withValues(alpha: 0.06),
              child: const Icon(Icons.insert_drive_file_rounded,
                  color: AppColors.kmMuted),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(label,
            style: const TextStyle(fontSize: 10, color: AppColors.kmMuted)),
      ],
    ),
  );
}

class _DriverControlHub extends StatelessWidget {
  const _DriverControlHub();

  @override
  Widget build(BuildContext context) {
    return _AdminSelectableList(
      query: FirebaseFirestore.instance
          .collection('users')
          .where('service', whereIn: ['Bike', 'Car', 'Auto']),
      emptyIcon: Icons.local_taxi_outlined,
      emptyText: 'No drivers registered yet',
      noun: 'driver',
      deleteOne: (id, data) => _UsersTab._deleteUser(id, data),
      rowBuilder: (context, uid, data, checkbox, deleteThis) => _DriverAdminCard(
        uid: uid,
        data: data,
        checkbox: checkbox,
        deleteThis: deleteThis,
      ),
    );
  }
}

/// Driver Control Hub को हरेक card — यहीँबाट सिधै (कुनै अर्को page नखोली)
/// सबै मुख्य नियन्त्रण: (१) Verification Approve/Reject, (२) Account
/// Active/Suspend/Block, (३) Documents view, (४) Ride/Earnings stats।
/// "पूरा विवरण" चाहिए मात्र (पछिल्ला राइडको लामो list जस्ता कुरा) detail
/// page मा जाने ऐच्छिक बटन छुट्टै छ।
class _DriverAdminCard extends StatefulWidget {
  final String uid;
  final Map<String, dynamic> data;
  final Widget checkbox;
  final VoidCallback deleteThis;
  const _DriverAdminCard({
    required this.uid,
    required this.data,
    required this.checkbox,
    required this.deleteThis,
  });

  @override
  State<_DriverAdminCard> createState() => _DriverAdminCardState();
}

class _DriverAdminCardState extends State<_DriverAdminCard> {
  bool _busy = false;

  static const _activeStatuses = {'accepted', 'confirmed', 'in_progress'};

  late final Stream<QuerySnapshot<Map<String, dynamic>>> _ridesStream =
      FirebaseFirestore.instance
          .collection('serviceRequests')
          .where('workerUid', isEqualTo: widget.uid)
          .snapshots();

  Future<void> _approve() async {
    setState(() => _busy = true);
    try {
      final doc = await _findPendingDriverDoc(widget.uid);
      if (doc == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Pending application not found')));
        }
        return;
      }
      if (!mounted) return;
      await _acceptWorker(context, doc.id, widget.uid, doc.data());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reject() async {
    setState(() => _busy = true);
    try {
      final doc = await _findPendingDriverDoc(widget.uid);
      if (doc == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Pending application not found')));
        }
        return;
      }
      if (!mounted) return;
      await _rejectWorker(context, doc.id, widget.uid);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setStatus(String s) async {
    setState(() => _busy = true);
    try {
      await _setDriverAccountStatus(widget.uid, s);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final name = '${data['firstName'] ?? ''} ${data['lastName'] ?? ''}'.trim();
    final online = data['isOnline'] != false;
    final vStatus = (data['verificationStatus'] ??
            data['workerVerificationStatus'] ??
            'pending')
        .toString();
    final accountStatus = (data['accountStatus'] ?? 'active').toString();
    final service = (data['service'] ?? '').toString();
    final ratingCount = (data['ratingCount'] ?? 0) as num;
    final ratingSum = (data['ratingSum'] ?? 0) as num;
    final avgRating = ratingCount > 0 ? (ratingSum / ratingCount) : 0;

    final Color vColor = switch (vStatus) {
      'approved' => AppColors.kmTeal,
      'rejected' => AppColors.kmRose,
      _ => AppColors.kmAmber,
    };
    final Color aColor = switch (accountStatus) {
      'suspended' => AppColors.kmAmber,
      'blocked' => AppColors.kmRose,
      _ => AppColors.kmTeal,
    };

    return GlassPanel(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── हेडर: फोटो/अनलाइन डट + नाम + status pill हरू ──
          Row(
            children: [
              widget.checkbox,
              Stack(
                clipBehavior: Clip.none,
                children: [
                  const _KmIconBadge(Icons.local_taxi_rounded, size: 44),
                  Positioned(
                    right: -1,
                    bottom: -1,
                    child: Container(
                      width: 13,
                      height: 13,
                      decoration: BoxDecoration(
                        color: online ? AppColors.kmTeal : Colors.black38,
                        shape: BoxShape.circle,
                        border:
                            Border.all(color: AppColors.kmSurface, width: 2),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                        name.isEmpty
                            ? (data['email'] ?? '—').toString()
                            : name,
                        style: const TextStyle(
                            color: AppColors.kmText,
                            fontWeight: FontWeight.w700,
                            fontSize: 14.5)),
                    Text(
                        '${S.serviceName(service)} · ${online ? S.onlineNow : S.offlineWord}',
                        style: const TextStyle(
                            color: AppColors.kmMuted, fontSize: 12.5)),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.open_in_full_rounded,
                    size: 18, color: AppColors.kmMuted),
                tooltip: 'Full details',
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => _DriverAdminDetailPage(
                        uid: widget.uid, initialData: data),
                  ),
                ),
              ),
              _DeleteBtn(widget.deleteThis),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              Pill('Verification: $vStatus', bg: vColor, fg: AppColors.kmInk),
              Pill('Account: $accountStatus', bg: aColor, fg: AppColors.kmInk),
            ],
          ),
          Divider(height: 20, color: AppColors.kmGlassBorder),

          // ── (४) Ride & Earnings Stats — सधैँ प्रत्यक्ष देखिने, साथै हाल
          // सक्रिय काम (भए) माथि नै सिधै "Cancel Task" — Owner ले worker
          // सँग सिधै सम्पर्क नगरी नै तुरुन्तै काम रोक्न सकून्।
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _ridesStream,
            builder: (context, rideSnap) {
              final allDocs = rideSnap.data?.docs ?? [];
              final activeDocs = allDocs
                  .where((d) => _activeStatuses
                      .contains((d.data()['status'] ?? '').toString()))
                  .toList();
              final completedDocs = allDocs
                  .where((d) =>
                      (d.data()['status'] ?? '').toString() == 'completed')
                  .toList();
              final gross = completedDocs.fold<num>(
                  0,
                  (a, d) =>
                      a +
                      ((d.data()['finalPrice'] ?? d.data()['proposedPrice'] ?? 0)
                          as num));
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 16,
                    runSpacing: 6,
                    children: [
                      _miniStat('Active', '${activeDocs.length}'),
                      _miniStat('Completed', '${completedDocs.length}'),
                      _miniStat('Rating',
                          ratingCount > 0 ? avgRating.toStringAsFixed(1) : '—'),
                      _miniStat('Earned', 'Rs. ${gross.round()}'),
                    ],
                  ),
                  for (final rideDoc in activeDocs)
                    _ActiveTaskRow(
                      requestId: rideDoc.id,
                      data: rideDoc.data(),
                      workerUid: widget.uid,
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 12),

          // ── (३) Documents — प्रत्यक्ष link/बटन ──
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _showDriverDocsSheet(context, data),
              icon: const Icon(Icons.folder_open_rounded, size: 18),
              label: const Text('Documents'),
            ),
          ),
          const SizedBox(height: 10),

          // ── (१) Verification Approve/Reject — pending भए प्रत्यक्ष ──
          if (vStatus == 'pending') ...[
            Row(
              children: [
                Expanded(
                  child: SecondaryButton(
                    label: S.reject,
                    color: AppColors.kmRose,
                    onPressed: _busy ? null : _reject,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: PrimaryButton(
                    label: S.approve,
                    icon: Icons.check_rounded,
                    loading: _busy,
                    onPressed: _approve,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
          ],

          // ── (२) Account Management — सधैँ प्रत्यक्ष ──
          Wrap(
            spacing: 8,
            children: [
              if (accountStatus != 'active')
                OutlinedButton(
                  onPressed: _busy ? null : () => _setStatus('active'),
                  child: const Text('Activate'),
                ),
              if (accountStatus != 'suspended')
                OutlinedButton(
                  onPressed: _busy ? null : () => _setStatus('suspended'),
                  child: const Text('Suspend',
                      style: TextStyle(color: AppColors.kmAmber)),
                ),
              if (accountStatus != 'blocked')
                OutlinedButton(
                  onPressed: _busy ? null : () => _setStatus('blocked'),
                  child: const Text('Block',
                      style: TextStyle(color: AppColors.kmRose)),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _miniStat(String label, String value) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value,
              style: const TextStyle(
                  color: AppColors.kmText,
                  fontWeight: FontWeight.w900,
                  fontSize: 14)),
          Text(label,
              style: const TextStyle(fontSize: 10, color: AppColors.kmMuted)),
        ],
      );
}

/// Driver Control Hub कार्ड भित्रै — हाल सक्रिय (`accepted`/`confirmed`/
/// `in_progress`) एउटा काम, सिधै "Cancel Task" सहित। Owner ले Firestore
/// कन्सोल नखोली नै, यहीँबाट तुरुन्तै रोक्न सक्छन्:
///   १. `serviceRequests/{requestId}.status` → `cancelled_by_admin`
///      (deliberately DELETE होइन — सामान्य employer/worker cancel जस्तो
///      होइन, admin action को audit trail कायमै रहनुपर्छ)।
///   २. `releaseWorkerActiveJob()` — worker फेरि नयाँ काम स्वीकार्न free।
///   ३. worker को [job_route_screen.dart] ले यही status लाइभ सुन्दै
///      (Firestore stream) तुरुन्तै "Task cancelled" देखाएर आफैं फर्किन्छ —
///      real-time sync छुट्टै polling/notification बिना।
class _ActiveTaskRow extends StatefulWidget {
  final String requestId;
  final Map<String, dynamic> data;
  final String workerUid;
  const _ActiveTaskRow({
    required this.requestId,
    required this.data,
    required this.workerUid,
  });

  @override
  State<_ActiveTaskRow> createState() => _ActiveTaskRowState();
}

class _ActiveTaskRowState extends State<_ActiveTaskRow> {
  bool _cancelling = false;

  Future<void> _confirmAndCancel() async {
    final confirmed = await showKmDialog<bool>(
      context: context,
      title: 'Cancel this task?',
      message:
          'This immediately ends the ride/job for both the worker and the '
          'customer. This cannot be undone.',
      icon: Icons.cancel_rounded,
      iconBg: const LinearGradient(colors: [AppColors.danger, AppColors.kmRose]),
      actions: [
        KmDialogAction(
          label: S.cancel,
          onPressed: () => Navigator.pop(context, false),
        ),
        KmDialogAction(
          label: S.confirm,
          filled: true,
          onPressed: () => Navigator.pop(context, true),
        ),
      ],
    );
    if (confirmed != true || !mounted) return;

    setState(() => _cancelling = true);
    try {
      final db = FirebaseFirestore.instance;
      await db.collection('serviceRequests').doc(widget.requestId).update({
        'status': 'cancelled_by_admin',
        'cancelledBy': 'admin',
        'cancelledAt': FieldValue.serverTimestamp(),
      });
      // सामान्य employer/worker cancel कै उही हल्का log (job_actions.dart::
      // deleteCancelledBooking हेर्नुहोस्) — admin बाट भएको छुट्याउन।
      unawaited(db.collection('cancellations').add({
        'requestId': widget.requestId,
        'reason': 'Cancelled by admin',
        'cancelledByAdmin': true,
        'workerUid': widget.workerUid,
        'uid': FirebaseAuth.instance.currentUser?.uid ?? '',
        'createdAt': FieldValue.serverTimestamp(),
      }));
      await releaseWorkerActiveJob(widget.workerUid, widget.requestId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Task cancelled — worker notified.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not cancel: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _cancelling = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.data;
    final service = (d['service'] ?? '').toString();
    final employerName = (d['employerName'] ?? S.customerWord).toString();
    final status = (d['status'] ?? '').toString();
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.kmTeal.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.kmTeal.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.directions_run_rounded,
              size: 18, color: AppColors.kmTeal),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${service.isEmpty ? 'Job' : service} · $employerName',
                    style: const TextStyle(
                        color: AppColors.kmText,
                        fontWeight: FontWeight.w700,
                        fontSize: 13)),
                Text(status,
                    style: const TextStyle(
                        color: AppColors.kmMuted, fontSize: 11)),
              ],
            ),
          ),
          SecondaryButton(
            label: _cancelling ? '…' : 'Cancel Task',
            color: AppColors.kmRose,
            expand: false,
            onPressed: _cancelling ? null : _confirmAndCancel,
          ),
        ],
      ),
    );
  }
}

class _DriverAdminDetailPage extends StatefulWidget {
  final String uid;
  final Map<String, dynamic> initialData;
  const _DriverAdminDetailPage(
      {required this.uid, required this.initialData});

  @override
  State<_DriverAdminDetailPage> createState() =>
      _DriverAdminDetailPageState();
}

class _DriverAdminDetailPageState extends State<_DriverAdminDetailPage> {
  late final Stream<DocumentSnapshot<Map<String, dynamic>>> _userStream =
      FirebaseFirestore.instance.collection('users').doc(widget.uid).snapshots();
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _ridesStream =
      FirebaseFirestore.instance
          .collection('serviceRequests')
          .where('workerUid', isEqualTo: widget.uid)
          .snapshots();

  bool _busy = false;

  static const _activeStatuses = {'accepted', 'confirmed', 'in_progress'};

  Future<void> _setAccountStatus(String s) async {
    setState(() => _busy = true);
    try {
      await _setDriverAccountStatus(widget.uid, s);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _approve(Map<String, dynamic> data) async {
    setState(() => _busy = true);
    try {
      final doc = await _findPendingDriverDoc(widget.uid);
      if (doc == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Pending application not found')));
        }
        return;
      }
      if (!mounted) return;
      await _acceptWorker(context, doc.id, widget.uid, doc.data());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reject() async {
    setState(() => _busy = true);
    try {
      final doc = await _findPendingDriverDoc(widget.uid);
      if (doc == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Pending application not found')));
        }
        return;
      }
      if (!mounted) return;
      await _rejectWorker(context, doc.id, widget.uid);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _docThumb(String label, String url) {
    if (url.isEmpty) return const SizedBox.shrink();
    return _docThumbShared(context, label, url);
  }

  @override
  Widget build(BuildContext context) {
    return AuroraBackground(
      child: Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('Driver details',
            style: TextStyle(
                color: AppColors.kmText, fontWeight: FontWeight.w800)),
        backgroundColor: Colors.transparent,
        foregroundColor: AppColors.kmText,
        elevation: 0,
      ),
      body: SafeArea(
          child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: _userStream,
            builder: (context, userSnap) {
              final data = userSnap.data?.data() ?? widget.initialData;
              final name =
                  '${data['firstName'] ?? ''} ${data['lastName'] ?? ''}'.trim();
              final online = data['isOnline'] != false;
              final accountStatus = (data['accountStatus'] ?? 'active').toString();
              final vStatus = (data['verificationStatus'] ??
                      data['workerVerificationStatus'] ??
                      'pending')
                  .toString();
              final rejectionReason = (data['rejectionReason'] ?? '').toString();
              final ratingCount = (data['ratingCount'] ?? 0) as num;
              final ratingSum = (data['ratingSum'] ?? 0) as num;
              final avgRating =
                  ratingCount > 0 ? (ratingSum / ratingCount) : 0;

              return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: _ridesStream,
                builder: (context, rideSnap) {
                  final docs = (rideSnap.data?.docs ?? [])
                      .map((d) => d.data())
                      .toList();
                  final active = docs
                      .where((d) => _activeStatuses
                          .contains((d['status'] ?? '').toString()))
                      .length;
                  final completed = docs
                      .where((d) => (d['status'] ?? '').toString() == 'completed')
                      .toList()
                    ..sort((a, b) {
                      final ta = a['completedAt'];
                      final tb = b['completedAt'];
                      if (ta is Timestamp && tb is Timestamp) {
                        return tb.compareTo(ta);
                      }
                      return 0;
                    });
                  final gross = completed.fold<num>(
                      0, (a, d) => a + ((d['finalPrice'] ?? d['proposedPrice'] ?? 0) as num));

                  final locUpdated = data['locationUpdatedAt'];
                  String lastSeen = '—';
                  if (locUpdated is Timestamp) {
                    lastSeen = _fmtTime(locUpdated);
                  }

                  return ListView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                    children: [
                      // ── प्रोफाइल हेडर ──
                      GlassPanel(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            const _KmIconBadge(Icons.local_taxi_rounded, size: 52),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(name.isEmpty ? '—' : name,
                                      style: const TextStyle(
                                          color: AppColors.kmText,
                                          fontWeight: FontWeight.w800,
                                          fontSize: 17)),
                                  Text(
                                      '${data['phone'] ?? ''}  ·  ${data['email'] ?? ''}',
                                      style: const TextStyle(
                                          color: AppColors.kmMuted,
                                          fontSize: 12.5)),
                                  if ((data['vehicleDetails'] ?? '')
                                      .toString()
                                      .isNotEmpty)
                                    Text(data['vehicleDetails'].toString(),
                                        style: const TextStyle(
                                            color: AppColors.kmMuted,
                                            fontSize: 12)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),

                      // ── (१) Verification Control — Approvals/Documents ──
                      _sectionLabel('① Verification Control'),
                      GlassPanel(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Text('Verification status',
                                    style: TextStyle(
                                        color: AppColors.kmText,
                                        fontWeight: FontWeight.w700)),
                                const Spacer(),
                                Pill(vStatus,
                                    bg: vStatus == 'approved'
                                        ? AppColors.kmTeal
                                        : vStatus == 'rejected'
                                            ? AppColors.kmRose
                                            : AppColors.kmAmber,
                                    fg: AppColors.kmInk),
                              ],
                            ),
                            if (rejectionReason.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Text('${S.reasonLabel}: $rejectionReason',
                                  style: const TextStyle(
                                      color: AppColors.kmRose, fontSize: 12.5)),
                            ],
                            if (vStatus == 'pending') ...[
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Expanded(
                                    child: SecondaryButton(
                                      label: S.reject,
                                      color: AppColors.kmRose,
                                      onPressed: _busy ? null : _reject,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: PrimaryButton(
                                      label: S.approve,
                                      icon: Icons.check_rounded,
                                      loading: _busy,
                                      onPressed: () => _approve(data),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                            const SizedBox(height: 16),
                            const Text('Documents',
                                style: TextStyle(
                                    color: AppColors.kmText,
                                    fontWeight: FontWeight.w700)),
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 12,
                              runSpacing: 12,
                              children: [
                                _docThumb('Citizenship front',
                                    (data['citizenshipFrontUrl'] ?? '').toString()),
                                _docThumb('Citizenship back',
                                    (data['citizenshipBackUrl'] ?? '').toString()),
                                _docThumb(
                                    'Selfie', (data['selfieUrl'] ?? '').toString()),
                                _docThumb('License',
                                    (data['drivingLicenseUrl'] ?? '').toString()),
                                _docThumb('Vehicle reg.',
                                    (data['vehicleRegistrationUrl'] ?? '').toString()),
                                _docThumb('Insurance',
                                    (data['vehicleInsuranceUrl'] ?? '').toString()),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),

                      // ── (२) Online/Offline Status Monitoring ──
                      _sectionLabel('② Online/Offline Status'),
                      GlassPanel(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            Container(
                              width: 14,
                              height: 14,
                              decoration: BoxDecoration(
                                color: online
                                    ? AppColors.kmTeal
                                    : Colors.black38,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(online ? 'Online now' : 'Offline',
                                      style: TextStyle(
                                          fontWeight: FontWeight.w800,
                                          fontSize: 14.5,
                                          color: online
                                              ? AppColors.kmTeal
                                              : AppColors.kmMuted)),
                                  Text('Last location update: $lastSeen',
                                      style: const TextStyle(
                                          fontSize: 11,
                                          color: AppColors.kmMuted)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),

                      // ── (३) Account Management ──
                      _sectionLabel('③ Account Management'),
                      GlassPanel(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Text('Account status',
                                    style: TextStyle(
                                        color: AppColors.kmText,
                                        fontWeight: FontWeight.w700)),
                                const Spacer(),
                                Pill(accountStatus,
                                    bg: accountStatus == 'active'
                                        ? AppColors.kmTeal
                                        : accountStatus == 'suspended'
                                            ? AppColors.kmAmber
                                            : AppColors.kmRose,
                                    fg: AppColors.kmInk),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 8,
                              children: [
                                if (accountStatus != 'active')
                                  OutlinedButton(
                                    onPressed:
                                        _busy ? null : () => _setAccountStatus('active'),
                                    child: const Text('Activate'),
                                  ),
                                if (accountStatus != 'suspended')
                                  OutlinedButton(
                                    onPressed: _busy
                                        ? null
                                        : () => _setAccountStatus('suspended'),
                                    child: const Text('Suspend',
                                        style: TextStyle(color: AppColors.kmAmber)),
                                  ),
                                if (accountStatus != 'blocked')
                                  OutlinedButton(
                                    onPressed:
                                        _busy ? null : () => _setAccountStatus('blocked'),
                                    child: const Text('Block',
                                        style: TextStyle(color: AppColors.kmRose)),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),

                      // ── (४) Ride & Earnings History ──
                      _sectionLabel('④ Ride & Earnings History'),
                      GlassPanel(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Wrap(
                              spacing: 16,
                              runSpacing: 8,
                              children: [
                                _statChip('Active rides', '$active'),
                                _statChip('Completed', '${completed.length}'),
                                _statChip('Rating',
                                    ratingCount > 0 ? avgRating.toStringAsFixed(1) : '—'),
                                _statChip('Gross earned', 'Rs. ${gross.round()}'),
                              ],
                            ),
                            Divider(height: 24, color: AppColors.kmGlassBorder),
                            const Text('Recent rides',
                                style: TextStyle(
                                    color: AppColors.kmText,
                                    fontWeight: FontWeight.w700)),
                            const SizedBox(height: 8),
                            if (completed.isEmpty)
                              const Text('No completed rides yet',
                                  style: TextStyle(
                                      fontSize: 12.5, color: AppColors.kmMuted))
                            else
                              for (final r in completed.take(10)) _rideRow(r),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _sectionLabel(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8, left: 2),
        child: Text(text,
            style: const TextStyle(
                color: AppColors.kmText,
                fontWeight: FontWeight.w800,
                fontSize: 13.5)),
      );

  Widget _statChip(String label, String value) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value,
              style: const TextStyle(
                  color: AppColors.kmText,
                  fontWeight: FontWeight.w900,
                  fontSize: 15)),
          Text(label,
              style: const TextStyle(fontSize: 10.5, color: AppColors.kmMuted)),
        ],
      );

  Widget _rideRow(Map<String, dynamic> d) {
    final service = (d['service'] ?? '').toString();
    final amount = (d['finalPrice'] ?? d['proposedPrice'] ?? 0) as num;
    final employer = (d['employerName'] ?? '').toString();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text('${S.serviceName(service)} · $employer',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: AppColors.kmMuted, fontSize: 12.5)),
          ),
          Text('Rs. ${amount.round()}',
              style: const TextStyle(
                  color: AppColors.kmText,
                  fontSize: 12,
                  fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _WorkerRatingsTab extends StatefulWidget {
  const _WorkerRatingsTab();

  @override
  State<_WorkerRatingsTab> createState() => _WorkerRatingsTabState();
}

class _WorkerRatingsTabState extends State<_WorkerRatingsTab> {
  _RatingSort _sort = _RatingSort.highToLow;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
          child: Row(
            children: [
              const Icon(Icons.star_rounded,
                  color: AppColors.kmOrange, size: 18),
              const SizedBox(width: 6),
              const Expanded(
                child: Text('Rating → monthly order quota',
                    style: TextStyle(
                        color: AppColors.kmText,
                        fontWeight: FontWeight.w700,
                        fontSize: 13)),
              ),
              DropdownButton<_RatingSort>(
                value: _sort,
                dropdownColor: AppColors.kmSurface,
                underline: const SizedBox.shrink(),
                iconEnabledColor: AppColors.kmMuted,
                style: const TextStyle(color: AppColors.kmText, fontSize: 12.5),
                items: const [
                  DropdownMenuItem(
                      value: _RatingSort.highToLow,
                      child: Text('High → Low')),
                  DropdownMenuItem(
                      value: _RatingSort.lowToHigh,
                      child: Text('Low → High')),
                ],
                onChanged: (v) =>
                    setState(() => _sort = v ?? _RatingSort.highToLow),
              ),
            ],
          ),
        ),
        Expanded(
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('registeredWorkers')
                .limit(500)
                .snapshots(),
            builder: (context, snap) {
              final docs = [
                ...(snap.data?.docs ??
                    const <QueryDocumentSnapshot<Map<String, dynamic>>>[])
              ];
              if (docs.isEmpty) {
                return const _EmptyState(
                    Icons.star_border_rounded, 'No workers yet');
              }
              docs.sort((a, b) {
                final ra =
                    double.tryParse((a.data()['rating'] ?? '0').toString()) ??
                        0;
                final rb =
                    double.tryParse((b.data()['rating'] ?? '0').toString()) ??
                        0;
                return _sort == _RatingSort.highToLow
                    ? rb.compareTo(ra)
                    : ra.compareTo(rb);
              });
              return ListView.builder(
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 20),
                itemCount: docs.length,
                itemBuilder: (context, i) => _WorkerRatingCard(doc: docs[i]),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _WorkerRatingCard extends StatelessWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  const _WorkerRatingCard({required this.doc});

  @override
  Widget build(BuildContext context) {
    final data = doc.data();
    final uid = (data['uid'] ?? '').toString();
    final name = (data['name'] ?? '—').toString();
    final service = (data['service'] ?? '').toString();
    final rating = (data['rating'] ?? '0.0').toString();
    final reviews = (data['reviews'] ?? '0').toString();

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassPanel(
        radius: 22,
        padding: const EdgeInsets.all(14),
        child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: uid.isEmpty
            ? null
            : FirebaseFirestore.instance.collection('users').doc(uid).snapshots(),
        builder: (context, userSnap) {
          final u = userSnap.data?.data();
          final ratingOverride = (u?['ratingOverride'] as num?);
          final orderLimitOverride = (u?['orderLimitOverride'] as num?);
          final ratingSum = (u?['ratingSum'] as num?) ?? 0;
          final ratingCount = ((u?['ratingCount'] as num?) ?? 0).toInt();
          final computedLimit = orderLimitOverride?.toInt() ??
              (ratingOverride != null
                  ? monthlyOrderQuotaForRating(
                      ratingSum: ratingOverride, reviewCount: 1)
                  : monthlyOrderQuotaForRating(
                      ratingSum: ratingSum, reviewCount: ratingCount));
          final storedMonth = (u?['orderQuotaMonth'] ?? '').toString();
          final used = storedMonth == currentQuotaMonthKey()
              ? ((u?['orderQuotaUsed'] as num?) ?? 0).toInt()
              : 0;
          final hasOverride =
              ratingOverride != null || orderLimitOverride != null;

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(name,
                            style: const TextStyle(
                                color: AppColors.kmText,
                                fontWeight: FontWeight.w800,
                                fontSize: 14.5)),
                        if (hasOverride) ...[
                          const SizedBox(width: 6),
                          const Icon(Icons.edit_note_rounded,
                              size: 15, color: AppColors.kmLilac),
                        ],
                      ],
                    ),
                    Text(service,
                        style: const TextStyle(
                            color: AppColors.kmMuted, fontSize: 12.5)),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Icon(Icons.star_rounded,
                            size: 15, color: AppColors.kmOrange),
                        const SizedBox(width: 3),
                        Text('$rating  ($reviews reviews)',
                            style: const TextStyle(
                                color: AppColors.kmText,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700)),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text('This month: $used / $computedLimit orders used',
                        style: const TextStyle(
                            color: AppColors.kmMuted, fontSize: 12.5)),
                  ],
                ),
              ),
              GestureDetector(
                onTap: uid.isEmpty
                    ? null
                    : () => _showOverrideSheet(
                          context,
                          uid: uid,
                          name: name,
                          ratingOverride: ratingOverride,
                          orderLimitOverride: orderLimitOverride,
                        ),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.kmOrange.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                        color: AppColors.kmOrange.withValues(alpha: 0.5)),
                  ),
                  child: const Text('Manage',
                      style: TextStyle(
                          color: AppColors.kmOrange,
                          fontWeight: FontWeight.w700,
                          fontSize: 12.5)),
                ),
              ),
            ],
          );
        },
        ),
      ),
    );
  }
}

void _showOverrideSheet(
  BuildContext context, {
  required String uid,
  required String name,
  required num? ratingOverride,
  required num? orderLimitOverride,
}) {
  final ratingCtrl =
      TextEditingController(text: ratingOverride?.toString() ?? '');
  final limitCtrl =
      TextEditingController(text: orderLimitOverride?.toString() ?? '');
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) => Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(sheetContext).viewInsets.bottom),
      child: ClipRRect(
        borderRadius:
            const BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
        child: glassBackdrop(sigma: 26, child: Container(
            decoration: BoxDecoration(
              color: AppColors.kmSurface.withValues(alpha: 0.94),
              borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(AppRadius.lg)),
              border: Border(top: BorderSide(color: AppColors.kmGlassBorder)),
            ),
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Manage $name',
                    style: const TextStyle(
                        color: AppColors.kmText,
                        fontWeight: FontWeight.w800,
                        fontSize: 16)),
                const SizedBox(height: 4),
                const Text(
                  'Leave blank to use the automatic rating/quota. '
                  'Set a value to override it for this worker only.',
                  style: TextStyle(color: AppColors.kmMuted, fontSize: 12.5),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: ratingCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  style: const TextStyle(color: AppColors.kmText),
                  decoration: kmInputDecoration('Rating override (0-5)',
                      hint: 'e.g. 3 — starter grace period'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: limitCtrl,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(color: AppColors.kmText),
                  decoration: kmInputDecoration(
                      'Order limit override (per month)',
                      hint: 'e.g. 0 to block, or a custom cap'),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: KmDialogAction(
                        label: 'Clear overrides',
                        onPressed: () async {
                          await FirebaseFirestore.instance
                              .collection('users')
                              .doc(uid)
                              .set({
                            'ratingOverride': FieldValue.delete(),
                            'orderLimitOverride': FieldValue.delete(),
                          }, SetOptions(merge: true));
                          if (sheetContext.mounted) {
                            Navigator.pop(sheetContext);
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: KmCtaButton(
                        label: 'Save',
                        onPressed: () async {
                          final ratingVal =
                              double.tryParse(ratingCtrl.text.trim());
                          final limitVal =
                              int.tryParse(limitCtrl.text.trim());
                          await FirebaseFirestore.instance
                              .collection('users')
                              .doc(uid)
                              .set({
                            'ratingOverride': ratingVal ?? FieldValue.delete(),
                            'orderLimitOverride':
                                limitVal ?? FieldValue.delete(),
                          }, SetOptions(merge: true));
                          if (sheetContext.mounted) {
                            Navigator.pop(sheetContext);
                          }
                        },
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
  );
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
      rowBuilder: (context, id, data, checkbox, deleteThis) => GlassPanel(
        radius: 20,
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                checkbox,
                const Icon(Icons.report_problem_outlined,
                    color: AppColors.kmRose, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    (data['category'] ?? 'Report').toString(),
                    style: const TextStyle(
                        color: AppColors.kmText,
                        fontWeight: FontWeight.w700,
                        fontSize: 14.5),
                  ),
                ),
                Text(_fmtTime(data['createdAt']),
                    style: const TextStyle(
                        color: AppColors.kmMuted, fontSize: 11)),
                _DeleteBtn(deleteThis),
              ],
            ),
            const SizedBox(height: 6),
            if ((data['email'] ?? '').toString().isNotEmpty)
              _kv(context, Icons.person_outline, data['email'].toString()),
            const SizedBox(height: 4),
            Text((data['details'] ?? '').toString(),
                style: const TextStyle(color: AppColors.kmMuted)),
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
      rowBuilder: (context, id, data, checkbox, deleteThis) => GlassPanel(
        radius: 20,
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                checkbox,
                const Icon(Icons.support_agent_rounded,
                    color: AppColors.kmOrange, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    (data['topic'] ?? 'Message').toString(),
                    style: const TextStyle(
                        color: AppColors.kmText,
                        fontWeight: FontWeight.w700,
                        fontSize: 14.5),
                  ),
                ),
                Text(_fmtTime(data['createdAt']),
                    style: const TextStyle(
                        color: AppColors.kmMuted, fontSize: 11)),
                _DeleteBtn(deleteThis),
              ],
            ),
            const SizedBox(height: 6),
            if ((data['email'] ?? '').toString().isNotEmpty)
              _kv(context, Icons.person_outline, data['email'].toString()),
            const SizedBox(height: 4),
            Text((data['message'] ?? '').toString(),
                style: const TextStyle(color: AppColors.kmMuted)),
          ],
        ),
      ),
    );
  }
}

// ── Users ────────────────────────────────────────────────────────────────────

class _UsersTab extends StatelessWidget {
  const _UsersTab();

  /// user + सम्बन्धित docs सबै मेटाउने (cascade)। owner लाई कहिल्यै मेट्दैन।
  static Future<void> _deleteUser(String uid, Map<String, dynamic> data) async {
    if ((data['email'] ?? '').toString() == kAdminEmail) return;
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
      selectable: (_, d) => (d['email'] ?? '').toString() != kAdminEmail,
      deleteOne: _deleteUser,
      headerBuilder: (total) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        color: AppColors.kmOrange.withValues(alpha: 0.14),
        child: Text('Total users: $total',
            style: const TextStyle(
                color: AppColors.kmText,
                fontSize: 16,
                fontWeight: FontWeight.w800)),
      ),
      rowBuilder: (context, uid, data, checkbox, deleteThis) {
        final status = (data['accountStatus'] ?? 'active').toString();
        final Color sc = switch (status) {
          'suspended' => AppColors.kmAmber,
          'blocked' => AppColors.kmRose,
          _ => AppColors.kmTeal,
        };
        Future<void> setStatus(String s) => FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .set({'accountStatus': s}, SetOptions(merge: true));

        final email = (data['email'] ?? '').toString();
        final isOwner = email == kAdminEmail;
        final name =
            '${data['firstName'] ?? ''} ${data['lastName'] ?? ''}'.trim();

        return GlassPanel(
          radius: 20,
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
                            style: const TextStyle(
                                color: AppColors.kmText,
                                fontWeight: FontWeight.w700)),
                        Text(
                            '${data['role'] ?? 'n/a'}'
                            '${email.isNotEmpty && name.isNotEmpty ? '  ·  $email' : ''}',
                            style: const TextStyle(
                                color: AppColors.kmMuted, fontSize: 12)),
                      ],
                    ),
                  ),
                  Pill(status, bg: sc, fg: AppColors.kmInk),
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
                        child: const Text('Activate',
                            style: TextStyle(color: AppColors.kmTeal))),
                  if (status != 'suspended')
                    TextButton(
                        onPressed: () => setStatus('suspended'),
                        child: const Text('Suspend',
                            style: TextStyle(color: AppColors.kmAmber))),
                  if (status != 'blocked')
                    TextButton(
                        onPressed: () => setStatus('blocked'),
                        child: const Text('Block',
                            style: TextStyle(color: AppColors.kmRose))),
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
