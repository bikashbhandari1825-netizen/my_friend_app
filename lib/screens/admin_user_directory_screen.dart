// screens/admin_user_directory_screen.dart
//
// Admin User Directory — सबै `users` एकै ठाउँमा role अनुसार (Car/Bike/Auto
// Driver, Worker/Handyman, Customer, Other) छुट्याइएको, एउटै search bar ले
// नाम + फोन + इमेल तीनैमा खोज्ने सूची। केवल पढ्ने (read-only) हो; approve/
// block जस्ता नियन्त्रण पहिल्यैका Driver/Worker tab मै छन् (यहाँ दोहोर्याइएको छैन)।
//
// डेटा रणनीति: `users` collection `FieldPath.documentId` ले order गरेर २००
// को पेजमा तान्ने (कुनै composite index चाहिँदैन, `createdAt` नभएका पुराना
// doc पनि छुट्दैनन्), हल्का in-memory मोडेल (`_DirUser`) मा cache गर्ने, अनि
// search/tab filter पूरै memory मै — हरेक keystroke मा Firestore read शून्य।
// यो एपको अपेक्षित स्केल (हजारौं users) का लागि पर्याप्त छ; सुरक्षा-सीमा
// ५,००० doc (त्यसपछि "Load more" बाट अझ तान्न मिल्छ)। Refresh बटनले पुनः तान्छ।
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/kyc_scrub.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_ui.dart';

enum _Cat { all, car, bike, auto, worker, customer, other }

extension on _Cat {
  String get label => switch (this) {
        _Cat.all => 'All',
        _Cat.car => 'Car Drivers',
        _Cat.bike => 'Bike Drivers',
        _Cat.auto => 'Auto Drivers',
        _Cat.worker => 'Workers',
        _Cat.customer => 'Customers',
        _Cat.other => 'Other',
      };
}

/// एउटा user को हल्का, पहिल्यै-normalize गरिएको रूप — search हरेक पटक
/// string सफा गर्नु नपरोस् भनेर lowercase/digits एकपटक मात्र बनाइन्छ।
class _DirUser {
  final String uid;
  final String name;
  final String phone;
  final String email;
  final String role;
  final String service;
  final _Cat cat;
  final String status; // blocked | suspended | pending | rejected | verified | active
  final bool? online; // provider होइन भने null
  final Map<String, dynamic> raw;
  final String _nameLc;
  final String _emailLc;
  final String _phoneNorm;

  _DirUser._(this.uid, this.name, this.phone, this.email, this.role,
      this.service, this.cat, this.status, this.online, this.raw)
      : _nameLc = name.toLowerCase(),
        _emailLc = email.toLowerCase(),
        _phoneNorm = normalizePhone(phone);

  /// +977 / ०-prefix / space / dash हटाएर केवल अङ्क (नेपाली मोबाइल ९८XXXXXXXX)।
  static String normalizePhone(String s) {
    var d = s.replaceAll(RegExp(r'\D'), '');
    if (d.startsWith('977') && d.length > 10) d = d.substring(3);
    if (d.startsWith('0')) d = d.substring(1);
    return d;
  }

  factory _DirUser.from(String uid, Map<String, dynamic> d) {
    String s(String k) => (d[k] ?? '').toString().trim();
    final role = s('role').toLowerCase();
    final first = s('firstName');
    final last = s('lastName');
    var name = s('name');
    if (name.isEmpty) name = '$first $last'.trim();

    // Vehicle: `service` (users doc मा सधैँ भरिन्छ) → vehicleCategory →
    // vehicleType। तीनै 'Bike' | 'Car' | 'Auto' exact मान राख्छन्।
    String vehicle = '';
    for (final k in const ['service', 'vehicleCategory', 'vehicleType']) {
      final v = s(k).toLowerCase();
      if (v == 'bike' || v == 'car' || v == 'auto') {
        vehicle = v;
        break;
      }
    }

    final _Cat cat;
    if (vehicle == 'car') {
      cat = _Cat.car;
    } else if (vehicle == 'bike') {
      cat = _Cat.bike;
    } else if (vehicle == 'auto') {
      cat = _Cat.auto;
    } else if (role == 'worker' && s('service').isNotEmpty) {
      cat = _Cat.worker;
    } else if (role == 'employer' || role == 'customer' || role == 'user') {
      cat = _Cat.customer;
    } else {
      cat = _Cat.other; // role नभएको / अज्ञात / service नभएको worker
    }

    final acct = s('accountStatus').toLowerCase();
    final ver = s('verificationStatus').toLowerCase();
    final String status;
    if (acct == 'blocked') {
      status = 'blocked';
    } else if (acct == 'suspended') {
      status = 'suspended';
    } else if (ver == 'rejected') {
      status = 'rejected';
    } else if (ver == 'pending') {
      status = 'pending';
    } else if (d['isVerified'] == true || ver == 'approved' || ver == 'verified') {
      status = 'verified';
    } else {
      status = 'active';
    }

    final isProvider = cat != _Cat.customer && cat != _Cat.other;
    return _DirUser._(
      uid,
      name,
      s('phone'),
      s('email'),
      role,
      isProvider ? (s('service').isNotEmpty ? s('service') : vehicle) : '',
      cat,
      status,
      isProvider ? d['isOnline'] != false : null,
      d,
    );
  }

  /// [q] lowercase गरिसकेको; [phoneQ] phone-जस्तो query भए normalize गरिएको अङ्क।
  bool matches(String q, String phoneQ) {
    if (q.isEmpty) return true;
    if (_nameLc.contains(q) || _emailLc.contains(q)) return true;
    return phoneQ.isNotEmpty && _phoneNorm.contains(phoneQ);
  }
}

class AdminUserDirectoryScreen extends StatefulWidget {
  const AdminUserDirectoryScreen({super.key});

  @override
  State<AdminUserDirectoryScreen> createState() =>
      _AdminUserDirectoryScreenState();
}

class _AdminUserDirectoryScreenState extends State<AdminUserDirectoryScreen>
    with AutomaticKeepAliveClientMixin {
  static const _pageSize = 200;
  static const _hardCap = 5000;

  final _users = <_DirUser>[];
  DocumentSnapshot<Map<String, dynamic>>? _lastDoc;
  bool _loading = false;
  bool _hasMore = true;
  String? _error;

  final _searchCtrl = TextEditingController();
  Timer? _debounce;
  String _q = '';
  String _phoneQ = '';
  _Cat _tab = _Cat.all;

  // search/tab/load बदलिँदा यी notifier मात्र फेरिन्छन् — पूरै tree होइन।
  final _view = ValueNotifier<_ViewState>(_ViewState.empty);

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadMore();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    _view.dispose();
    super.dispose();
  }

  Future<void> _loadMore({bool reset = false}) async {
    if (_loading) return;
    if (reset) {
      _users.clear();
      _lastDoc = null;
      _hasMore = true;
    }
    if (!_hasMore) return;
    _loading = true;
    _error = null;
    _recompute();
    try {
      // आधारभूत सीमा: हरेक "Load more" ले अधिकतम _hardCap सम्म मात्र बढाउँछ।
      var fetched = 0;
      while (_hasMore && fetched < _hardCap) {
        var query = FirebaseFirestore.instance
            .collection('users')
            .orderBy(FieldPath.documentId)
            .limit(_pageSize);
        if (_lastDoc != null) query = query.startAfterDocument(_lastDoc!);
        final snap = await query.get();
        for (final d in snap.docs) {
          _users.add(_DirUser.from(d.id, d.data()));
        }
        fetched += snap.docs.length;
        if (snap.docs.isNotEmpty) _lastDoc = snap.docs.last;
        if (snap.docs.length < _pageSize) _hasMore = false;
        if (!mounted) return;
        _recompute(); // पहिलो पेज आउनेबित्तिकै UI देखिन्छ, बाँकी पछाडि थपिँदै
      }
    } catch (e) {
      _error = 'Could not load users: $e';
    } finally {
      _loading = false;
      if (mounted) _recompute();
    }
  }

  /// एक-पटकको सफाइ — पुराना KYC token-URL हरू Storage path मा बदल्ने र
  /// सार्वजनिक सूचीबाट हटाउने (हेर्नुहोस् `services/kyc_scrub.dart`)।
  Future<void> _secureKycLinks() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.kmSurface,
        title: const Text('Secure KYC links?',
            style: TextStyle(color: AppColors.kmText)),
        content: const Text(
            'Converts old document links (citizenship, license, vehicle papers, hotel documents) to private Storage paths and removes them from the public worker list. Run it once. Documents stay visible to you as admin.',
            style: TextStyle(color: AppColors.kmMuted, height: 1.4)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Run')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(const SnackBar(content: Text('Securing KYC links…')));
    try {
      final r = await scrubKycLinks();
      messenger.showSnackBar(SnackBar(
          content: Text(
              'Done: ${r.converted} converted, ${r.removed} removed from public list, ${r.failed} could not be converted.')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Failed: $e')));
    }
  }

  void _onSearchChanged(String raw) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      final q = raw.trim().toLowerCase();
      // फोन-जस्तो query (अङ्क, +, space, -, कोष्ठक मात्र) भए मात्र फोनमा खोज्ने।
      final phoneLike = RegExp(r'^[+\d\s\-()]+$').hasMatch(q);
      _q = q;
      _phoneQ = phoneLike ? _DirUser.normalizePhone(q) : '';
      _recompute();
    });
  }

  void _recompute() {
    if (!mounted) return;
    final counts = <_Cat, int>{for (final c in _Cat.values) c: 0};
    final rows = <_DirUser>[];
    for (final u in _users) {
      if (!u.matches(_q, _phoneQ)) continue;
      counts[_Cat.all] = counts[_Cat.all]! + 1;
      counts[u.cat] = counts[u.cat]! + 1;
      if (_tab == _Cat.all || u.cat == _tab) rows.add(u);
    }
    _view.value = _ViewState(
      rows: rows,
      counts: counts,
      loading: _loading,
      hasMore: _hasMore,
      total: _users.length,
      error: _error,
      searching: _q.isNotEmpty,
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return AuroraBackground(
      orbs: const [
        KmOrb(Alignment.topLeft, AppColors.kmTeal),
        KmOrb(Alignment.bottomRight, AppColors.kmPurple),
      ],
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: GlassPanel(
                        radius: 16,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: TextField(
                          controller: _searchCtrl,
                          onChanged: _onSearchChanged,
                          textInputAction: TextInputAction.search,
                          style: const TextStyle(color: AppColors.kmText),
                          decoration: InputDecoration(
                            border: InputBorder.none,
                            hintText: 'Search name, phone or email',
                            hintStyle:
                                const TextStyle(color: AppColors.kmMuted),
                            icon: const Icon(Icons.search_rounded,
                                color: AppColors.kmMuted),
                            suffixIcon: ValueListenableBuilder<TextEditingValue>(
                              valueListenable: _searchCtrl,
                              builder: (_, v, __) => v.text.isEmpty
                                  ? const SizedBox.shrink()
                                  : IconButton(
                                      icon: const Icon(Icons.close_rounded,
                                          color: AppColors.kmMuted),
                                      onPressed: () {
                                        _searchCtrl.clear();
                                        _onSearchChanged('');
                                      },
                                    ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    GlassIconButton(
                      icon: Icons.refresh_rounded,
                      tooltip: 'Reload users',
                      onTap: () => _loadMore(reset: true),
                    ),
                    const SizedBox(width: 8),
                    GlassIconButton(
                      icon: Icons.shield_rounded,
                      tooltip: 'Secure KYC links',
                      onTap: _secureKycLinks,
                    ),
                  ],
                ),
              ),
              // Role chips + live count — search बदलिँदा मात्र यो भाग rebuild हुन्छ।
              ValueListenableBuilder<_ViewState>(
                valueListenable: _view,
                builder: (_, s, __) => SizedBox(
                  height: 40,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: _Cat.values.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (_, i) {
                      final c = _Cat.values[i];
                      final sel = c == _tab;
                      return ChoiceChip(
                        selected: sel,
                        showCheckmark: false,
                        label: Text('${c.label} · ${s.counts[c] ?? 0}'),
                        labelStyle: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: sel ? Colors.white : AppColors.kmMuted,
                        ),
                        selectedColor: AppColors.kmPurple,
                        backgroundColor:
                            AppColors.kmSurface.withValues(alpha: 0.6),
                        side: BorderSide(
                            color: AppColors.kmPurple.withValues(alpha: 0.28)),
                        onSelected: (_) {
                          _tab = c;
                          _recompute();
                        },
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(height: 8),
              const _HeaderRow(),
              Expanded(
                child: ValueListenableBuilder<_ViewState>(
                  valueListenable: _view,
                  builder: (context, s, _) => _buildList(context, s),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildList(BuildContext context, _ViewState s) {
    if (s.error != null && s.rows.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(s.error!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.kmRose)),
        ),
      );
    }
    if (s.rows.isEmpty) {
      return Center(
        child: s.loading
            ? const CircularProgressIndicator()
            : Text(
                s.searching ? 'No users match your search' : 'No users here yet',
                style: const TextStyle(color: AppColors.kmMuted)),
      );
    }
    final footer = s.loading || s.hasMore || s.error != null ? 1 : 0;
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      itemCount: s.rows.length + footer,
      itemBuilder: (context, i) {
        if (i >= s.rows.length) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Center(
              child: s.loading
                  ? Text('Loading… ${s.total} users so far',
                      style: const TextStyle(
                          color: AppColors.kmMuted, fontSize: 12))
                  : TextButton(
                      onPressed: _loadMore,
                      child: Text(s.error ?? 'Load more users'),
                    ),
            ),
          );
        }
        return _UserRow(
          user: s.rows[i],
          onTap: () => _showDetails(context, s.rows[i]),
        );
      },
    );
  }

  void _showDetails(BuildContext context, _DirUser u) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.kmSurface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        builder: (ctx, scroll) => ListView(
          controller: scroll,
          padding: const EdgeInsets.all(20),
          children: [
            Text(u.name.isEmpty ? '(no name)' : u.name,
                style: const TextStyle(
                    color: AppColors.kmText,
                    fontSize: 18,
                    fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            _detail(ctx, 'UID', u.uid, copy: true),
            _detail(ctx, 'Phone', u.phone, copy: true),
            _detail(ctx, 'Email', u.email, copy: true),
            _detail(ctx, 'Group', u.cat.label),
            _detail(ctx, 'Role field', u.role),
            _detail(ctx, 'Service', u.service),
            _detail(ctx, 'Status', u.status),
            if (u.online != null)
              _detail(ctx, 'Online', u.online! ? 'Online' : 'Offline'),
            _detail(ctx, 'District', (u.raw['district'] ?? '').toString()),
            _detail(ctx, 'Joined', _fmtTs(u.raw['createdAt'])),
          ],
        ),
      ),
    );
  }

  static String _fmtTs(dynamic v) {
    if (v is! Timestamp) return '';
    final d = v.toDate();
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
  }

  Widget _detail(BuildContext ctx, String k, String v, {bool copy = false}) {
    if (v.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
            child: Text(k,
                style:
                    const TextStyle(color: AppColors.kmMuted, fontSize: 12)),
          ),
          Expanded(
            child: SelectableText(v,
                style: const TextStyle(color: AppColors.kmText, fontSize: 13)),
          ),
          if (copy)
            InkWell(
              onTap: () {
                Clipboard.setData(ClipboardData(text: v));
                ScaffoldMessenger.of(ctx).showSnackBar(
                    SnackBar(content: Text('$k copied')));
              },
              child: const Padding(
                padding: EdgeInsets.all(4),
                child: Icon(Icons.copy_rounded,
                    size: 16, color: AppColors.kmMuted),
              ),
            ),
        ],
      ),
    );
  }
}

class _ViewState {
  final List<_DirUser> rows;
  final Map<_Cat, int> counts;
  final bool loading;
  final bool hasMore;
  final int total;
  final String? error;
  final bool searching;
  const _ViewState({
    required this.rows,
    required this.counts,
    required this.loading,
    required this.hasMore,
    required this.total,
    required this.error,
    required this.searching,
  });

  static const empty = _ViewState(
    rows: [],
    counts: {},
    loading: true,
    hasMore: true,
    total: 0,
    error: null,
    searching: false,
  );
}

// ── Sticky column header (list को बाहिर, scroll नहुने) ───────────────────
class _HeaderRow extends StatelessWidget {
  const _HeaderRow();

  @override
  Widget build(BuildContext context) {
    const st = TextStyle(
        color: AppColors.kmMuted, fontSize: 11, fontWeight: FontWeight.w700);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.kmSurface.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Row(
        children: [
          Expanded(flex: 5, child: Text('NAME / ROLE', style: st)),
          Expanded(flex: 5, child: Text('PHONE / EMAIL', style: st)),
          SizedBox(
              width: 76,
              child: Text('STATUS', textAlign: TextAlign.end, style: st)),
        ],
      ),
    );
  }
}

class _UserRow extends StatelessWidget {
  final _DirUser user;
  final VoidCallback onTap;
  const _UserRow({required this.user, required this.onTap});

  static Color _statusColor(String s) => switch (s) {
        'blocked' || 'rejected' => AppColors.kmRose,
        'suspended' => AppColors.kmOrange,
        'pending' => AppColors.kmAmber,
        'verified' => AppColors.kmTeal,
        _ => AppColors.kmMuted,
      };

  @override
  Widget build(BuildContext context) {
    final u = user;
    final sc = _statusColor(u.status);
    final roleText = u.service.isNotEmpty ? '${u.cat.label} · ${u.service}' : u.cat.label;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          border: Border(
              bottom: BorderSide(color: Colors.white.withValues(alpha: 0.06))),
        ),
        child: Row(
          children: [
            Expanded(
              flex: 5,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(u.name.isEmpty ? '(no name)' : u.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: AppColors.kmText,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(roleText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: AppColors.kmLilac, fontSize: 11)),
                ],
              ),
            ),
            Expanded(
              flex: 5,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(u.phone.isEmpty ? '—' : u.phone,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: AppColors.kmText, fontSize: 12)),
                  const SizedBox(height: 2),
                  Text(u.email.isEmpty ? '—' : u.email,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: AppColors.kmMuted, fontSize: 11)),
                ],
              ),
            ),
            SizedBox(
              width: 76,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: sc.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(u.status,
                        style: TextStyle(
                            color: sc,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700)),
                  ),
                  if (u.online != null) ...[
                    const SizedBox(height: 4),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.circle,
                            size: 8,
                            color: u.online!
                                ? AppColors.kmTeal
                                : AppColors.kmMuted),
                        const SizedBox(width: 4),
                        Text(u.online! ? 'online' : 'offline',
                            style: const TextStyle(
                                color: AppColors.kmMuted, fontSize: 10)),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
