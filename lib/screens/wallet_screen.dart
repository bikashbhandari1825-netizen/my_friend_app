// screens/wallet_screen.dart
// Driver-facing Wallet — users/{uid}.walletBalance + isEligibleForJobs
// (widgets/complete_job_sheet.dart::_confirm() र
// admin_settlement_screen.dart::_markSettled() ले नै गणना/लेख्छन्) हेर्ने
// स्वतन्त्र screen। earnings_screen.dart कै `_SettlementCard` भन्दा फरक:
// त्यो unsettled-मात्र हो (earnings सारांश भित्रको एक टुक्रा), यो चाहिं
// पूरा ledger इतिहास + manual top-up निर्देशन/QR सहितको एकल-उद्देश्य screen।
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../config/app_config.dart' show PaymentConfig;
import '../l10n/strings.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_ui.dart';

class WalletScreen extends StatelessWidget {
  const WalletScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return AuroraBackground(
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
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: KmScreenHeader(title: S.walletScreenTitle),
              ),
              Expanded(
                child: uid == null
                    ? const SizedBox.shrink()
                    : StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                        stream: FirebaseFirestore.instance
                            .collection('users')
                            .doc(uid)
                            .snapshots(),
                        builder: (context, userSnap) {
                          final data = userSnap.data?.data() ?? {};
                          final balance =
                              ((data['walletBalance'] as num?) ?? 0)
                                  .toDouble();
                          final isEligible =
                              (data['isEligibleForJobs'] as bool?) ?? true;
                          return ListView(
                            padding:
                                const EdgeInsets.fromLTRB(16, 8, 16, 32),
                            children: [
                              _BalanceCard(
                                  balance: balance, isEligible: isEligible),
                              const SizedBox(height: 14),
                              _TopUpCard(uid: uid),
                              const SizedBox(height: 14),
                              _HistoryCard(uid: uid, currentBalance: balance),
                            ],
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

class _BalanceCard extends StatelessWidget {
  final double balance;
  final bool isEligible;
  const _BalanceCard({required this.balance, required this.isEligible});

  @override
  Widget build(BuildContext context) {
    final owed = balance < 0;
    final settled = balance == 0;
    final color = !isEligible
        ? AppColors.kmRose
        : (settled
            ? AppColors.kmMuted
            : (owed ? AppColors.kmAmber : AppColors.kmTeal));
    return Column(
      children: [
        GlassPanel(
          radius: AppRadius.lg,
          padding: const EdgeInsets.all(20),
          fill: color.withValues(alpha: 0.12),
          border: color,
          child: Column(
            children: [
              Icon(Icons.account_balance_wallet_rounded,
                  color: color, size: 32),
              const SizedBox(height: 10),
              Text(
                settled
                    ? S.fullySettledLabel
                    : (owed
                        ? S.youOwePlatformLabel((-balance).round())
                        : S.payoutPendingLabel(balance.round())),
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w800, color: color),
              ),
              const SizedBox(height: 16),
              Container(height: 1, color: AppColors.kmGlassBorder),
              const SizedBox(height: 14),
              // Current Balance + Platform Dues — दुवै कच्चा संख्या
              // छुट्टाछुट्टै, माथिको semantic वाक्य भन्दा स्पष्ट/प्रमुख
              // रूपमा।
              Row(
                children: [
                  Expanded(
                    child: _WalletStat(
                      label: 'Current Balance',
                      value:
                          '${balance < 0 ? '-' : ''}Rs. ${balance.abs().round()}',
                      color: color,
                    ),
                  ),
                  Container(
                    width: 1,
                    height: 30,
                    color: AppColors.kmGlassBorder,
                    margin: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                  Expanded(
                    child: _WalletStat(
                      label: 'Platform Dues',
                      value: 'Rs. ${owed ? (-balance).round() : 0}',
                      color: owed ? AppColors.kmRose : AppColors.kmMuted,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (!isEligible) ...[
          const SizedBox(height: 10),
          GlassPanel(
            radius: AppRadius.lg,
            padding: const EdgeInsets.all(14),
            fill: AppColors.kmRose.withValues(alpha: 0.12),
            border: AppColors.kmRose,
            child: Row(
              children: [
                const Icon(Icons.block_rounded,
                    color: AppColors.kmRose, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(S.walletBlockedBanner,
                      style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: AppColors.kmRose)),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// सानो label+value जोडी — Current Balance/Platform Dues स्तम्भ दुवैका
/// लागि एउटै साझा layout। (profile_screen.dart::_WalletStat कै उस्तै,
/// private widget भएकोले file-across share नमिल्ने — यहीँ छुट्टै सानो copy।)
class _WalletStat extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _WalletStat(
      {required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(label,
            style: const TextStyle(
                color: AppColors.kmMuted,
                fontSize: 10.5,
                fontWeight: FontWeight.w600)),
        const SizedBox(height: 2),
        Text(value,
            style: TextStyle(
                color: color, fontSize: 15, fontWeight: FontWeight.w800)),
      ],
    );
  }
}

/// Multi-method Top-Up — Card/eSewa/Khalti (Sandbox, instant simulated
/// credit — हेर्नुहोस् `_simulateTopUp()`) + Bank/QR (पुरानै manual flow,
/// admin ले पछि settle गर्नुपर्ने, तुरुन्तै credit हुँदैन)। एउटै ठाउँ,
/// `widgets/complete_job_sheet.dart`::`_onlinePaymentPanel`/
/// `_simulateOnlinePayment` कै उस्तै sandbox-honesty ढाँचा।
class _TopUpCard extends StatefulWidget {
  final String uid;
  const _TopUpCard({required this.uid});

  @override
  State<_TopUpCard> createState() => _TopUpCardState();
}

class _TopUpCardState extends State<_TopUpCard> {
  // 'card' | 'esewa' | 'khalti' | 'bank'
  String _method = 'card';
  final _amountCtrl = TextEditingController(text: '200');
  final _cardNumberCtrl = TextEditingController();
  final _cardExpiryCtrl = TextEditingController();
  final _cardCvvCtrl = TextEditingController();
  final _walletMobileCtrl = TextEditingController();
  final _mpinCtrl = TextEditingController();
  final bool _processing = false;

  @override
  void dispose() {
    _amountCtrl.dispose();
    _cardNumberCtrl.dispose();
    _cardExpiryCtrl.dispose();
    _cardCvvCtrl.dispose();
    _walletMobileCtrl.dispose();
    _mpinCtrl.dispose();
    super.dispose();
  }

  double get _amount => double.tryParse(_amountCtrl.text.trim()) ?? 0;

  bool get _canPay {
    if (_amount <= 0) return false;
    if (_method == 'card') {
      return _cardNumberCtrl.text.trim().length >= 12 &&
          _cardExpiryCtrl.text.trim().length >= 4 &&
          _cardCvvCtrl.text.trim().length == 3;
    }
    return _walletMobileCtrl.text.trim().isNotEmpty &&
        _mpinCtrl.text.trim().length == 6;
  }

  /// Online top-up (सुरक्षा कारणले बन्द) — पहिले यो "sandbox" ले क्लाइन्टबाटै
  /// `walletBalance` र `walletLedger` लेख्थ्यो, कुनै साँचो भुक्तानी प्रमाणित
  /// नगरी — जो कोहीले आफ्नै वालेटमा जति पनि रकम थप्न सक्थ्यो। अब वालेट
  /// केवल सर्भर (Cloud Function) ले लेख्छ, र साँचो gateway (eSewa/Khalti
  /// server-side verify) नजोडिएसम्म top-up उपलब्ध छैन।
  Future<void> _simulateTopUp() async {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text(
              'Online top-up is not available yet. Please settle your balance with the admin.')),
    );
  }

  Color _accentFor(String method) => switch (method) {
        'esewa' => const Color(0xFF60BB46),
        'khalti' => const Color(0xFF5C2D91),
        'bank' => const Color(0xFF1E5AA8),
        _ => AppColors.kmTealBlue, // card
      };

  String _labelFor(String method) => switch (method) {
        'esewa' => S.payEsewa,
        'khalti' => S.payKhalti,
        'bank' => S.manualDepositLabel,
        _ => S.payCard,
      };

  IconData _iconFor(String method) => switch (method) {
        'esewa' || 'khalti' => Icons.account_balance_wallet_rounded,
        'bank' => Icons.qr_code_2_rounded,
        _ => Icons.credit_card_rounded,
      };

  Widget _methodChip(String method) {
    final accent = _accentFor(method);
    final selected = _method == method;
    return Expanded(
      child: Material(
        color: selected
            ? accent.withValues(alpha: 0.14)
            : Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.md),
          onTap: () => setState(() => _method = method),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(
                  color: selected ? accent : Colors.white.withValues(alpha: 0.12),
                  width: selected ? 1.6 : 1),
            ),
            child: Column(
              children: [
                Icon(_iconFor(method),
                    color: selected ? accent : AppColors.kmMuted, size: 20),
                const SizedBox(height: 4),
                Text(_labelFor(method),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: selected ? accent : AppColors.kmMuted)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _amountChips() => Wrap(
        spacing: 8,
        children: [100, 200, 500, 1000].map((v) {
          final selected = _amountCtrl.text.trim() == v.toString();
          return ChoiceChip(
            label: Text('Rs. $v'),
            selected: selected,
            onSelected: (_) => setState(() => _amountCtrl.text = v.toString()),
          );
        }).toList(),
      );

  Widget _cardFields(Color accent) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _cardNumberCtrl,
            keyboardType: TextInputType.number,
            maxLength: 16,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              isDense: true,
              counterText: '',
              labelText: S.cardNumberLabel,
              hintText: '4242 4242 4242 4242',
              prefixIcon: const Icon(Icons.credit_card_rounded, size: 18),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.sm)),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _cardExpiryCtrl,
                  keyboardType: TextInputType.number,
                  maxLength: 5,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    isDense: true,
                    counterText: '',
                    labelText: S.cardExpiryLabel,
                    hintText: '12/29',
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppRadius.sm)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _cardCvvCtrl,
                  keyboardType: TextInputType.number,
                  maxLength: 3,
                  obscureText: true,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    isDense: true,
                    counterText: '',
                    labelText: S.cardCvvLabel,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppRadius.sm)),
                  ),
                ),
              ),
            ],
          ),
        ],
      );

  Widget _walletFields() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _walletMobileCtrl,
            keyboardType: TextInputType.phone,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              isDense: true,
              labelText: S.yourWalletMobileLabel(_labelFor(_method)),
              prefixIcon: const Icon(Icons.smartphone_rounded, size: 18),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.sm)),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _mpinCtrl,
            keyboardType: TextInputType.number,
            obscureText: true,
            maxLength: 6,
            textAlign: TextAlign.center,
            onChanged: (_) => setState(() {}),
            style: const TextStyle(fontSize: 18, letterSpacing: 10),
            decoration: InputDecoration(
              isDense: true,
              counterText: '',
              labelText: S.enterMpinLabel,
              prefixIcon: const Icon(Icons.lock_outline_rounded, size: 18),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.sm)),
            ),
          ),
        ],
      );

  Widget _manualDepositContent() {
    final esewa = PaymentConfig.esewaMerchantId;
    final khalti = PaymentConfig.khaltiMerchantId;
    final bankName = PaymentConfig.bankName;
    final bankAccountName = PaymentConfig.bankAccountName;
    final bankAccountNumber = PaymentConfig.bankAccountNumber;
    final connectIps = PaymentConfig.connectIpsId;
    final bankLine = [bankName, bankAccountName, bankAccountNumber]
        .where((s) => s.isNotEmpty)
        .join(' · ');
    // Company (admin) को आफ्नै merchant ID — worker कै payment_methods_screen.dart
    // मा बचत गरेको personal wallet ID होइन (त्यो उल्टो दिशाको payment, हेर्नुहोस्
    // complete_job_sheet.dart line ~613)।
    final qrPayload = esewa.isNotEmpty
        ? 'esewa:$esewa'
        : (khalti.isNotEmpty ? 'khalti:$khalti' : '');
    final anyConfigured = esewa.isNotEmpty ||
        khalti.isNotEmpty ||
        bankName.isNotEmpty ||
        connectIps.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(S.topUpInstructionsBody,
            style: const TextStyle(color: AppColors.kmMuted, fontSize: 12.5)),
        const SizedBox(height: 14),
        if (qrPayload.isNotEmpty) ...[
          Center(
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: QrImageView(data: qrPayload, size: 150),
            ),
          ),
          const SizedBox(height: 14),
        ],
        if (esewa.isNotEmpty) _row('eSewa', esewa),
        if (khalti.isNotEmpty) _row('Khalti', khalti),
        if (bankLine.isNotEmpty) _row('Bank', bankLine),
        if (connectIps.isNotEmpty) _row('ConnectIPS', connectIps),
        if (!anyConfigured)
          Text(S.notSetYet,
              style:
                  const TextStyle(color: AppColors.kmMuted, fontSize: 12.5)),
      ],
    );
  }

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
                width: 90,
                child: Text(label,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 12.5))),
            Expanded(
                child: Text(value, style: const TextStyle(fontSize: 12.5))),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final accent = _accentFor(_method);
    final isManual = _method == 'bank';

    return GlassPanel(
      radius: AppRadius.lg,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.add_card_rounded,
                  size: 18, color: AppColors.kmOrange),
              const SizedBox(width: 8),
              Text(S.topUpInstructionsTitle,
                  style: const TextStyle(fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _methodChip('card'),
              const SizedBox(width: 8),
              _methodChip('esewa'),
              const SizedBox(width: 8),
              _methodChip('khalti'),
              const SizedBox(width: 8),
              _methodChip('bank'),
            ],
          ),
          const SizedBox(height: 14),
          if (isManual)
            _manualDepositContent()
          else ...[
            Text(S.topUpAmountLabel,
                style: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            _amountChips(),
            const SizedBox(height: 10),
            TextField(
              controller: _amountCtrl,
              keyboardType: TextInputType.number,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                isDense: true,
                prefixText: 'Rs. ',
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.sm)),
              ),
            ),
            const SizedBox(height: 14),
            _method == 'card' ? _cardFields(accent) : _walletFields(),
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(Icons.info_outline_rounded, size: 16, color: accent),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(S.sandboxModeNotice,
                      style: TextStyle(fontSize: 11.5, color: accent)),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: (_processing || !_canPay) ? null : _simulateTopUp,
                icon: _processing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.lock_open_rounded, size: 18),
                label: Text(S.confirmAndPayLabel),
                style: ElevatedButton.styleFrom(
                    backgroundColor: accent, foregroundColor: Colors.white),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _HistoryCard extends StatelessWidget {
  final String uid;
  final double currentBalance;
  const _HistoryCard({required this.uid, required this.currentBalance});

  String _typeLabel(String type) => switch (type) {
        'cash_commission_due' => 'Cash — commission owed',
        'p2p_commission_due' => 'QR (P2P) — commission owed',
        'online_payout_pending' => 'Online — payout pending',
        'topup_card' => 'Top-Up — Card',
        'topup_esewa' => 'Top-Up — eSewa',
        'topup_khalti' => 'Top-Up — Khalti',
        _ => type,
      };

  String _dateLabel(dynamic ts) {
    if (ts is! Timestamp) return '';
    final d = ts.toDate();
    return '${d.day}/${d.month}/${d.year}';
  }

  // Fare/Commission/Net ब्रेकडाउन — complete_job_sheet.dart::_confirm() ले
  // हरेक ride/job commission entry मा grossAmount/commissionAmount/
  // workerPayoutAmount/commissionRate पहिल्यै लेख्छ (top-up entry हरूमा
  // commissionAmount सधैं ०, त्यसैले त्यहाँ यो पंक्ति नै नदेखिने)।
  Widget _entryRow(Map<String, dynamic> d, double balanceAfter) {
    final amount = ((d['amount'] as num?) ?? 0).toDouble();
    final gross = (d['grossAmount'] as num?)?.toDouble();
    final commission = (d['commissionAmount'] as num?)?.toDouble();
    final rate = (d['commissionRate'] as num?)?.toDouble() ?? 0;
    final settled = d['settled'] == true;
    final showBreakdown =
        gross != null && commission != null && commission > 0;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: AppColors.kmGlassBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_typeLabel((d['type'] ?? '').toString()),
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 13)),
                    Row(
                      children: [
                        Text(settled ? 'Settled' : 'Pending',
                            style: TextStyle(
                                fontSize: 11,
                                color: settled
                                    ? AppColors.kmTeal
                                    : AppColors.kmAmber)),
                        if (_dateLabel(d['createdAt']).isNotEmpty) ...[
                          const Text('  ·  ',
                              style: TextStyle(
                                  fontSize: 11, color: AppColors.kmMuted)),
                          Text(_dateLabel(d['createdAt']),
                              style: const TextStyle(
                                  fontSize: 11, color: AppColors.kmMuted)),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              Text(
                (amount >= 0 ? '+' : '') + amount.toStringAsFixed(0),
                style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                    color: amount >= 0 ? AppColors.success : Colors.red),
              ),
            ],
          ),
          if (showBreakdown) ...[
            const SizedBox(height: 8),
            Container(height: 1, color: AppColors.kmGlassBorder),
            const SizedBox(height: 6),
            _kv('Total Fare Earned', 'Rs. ${gross.round()}'),
            _kv('Platform Commission (${(rate * 100).round()}%)',
                '- Rs. ${commission.round()}'),
          ],
          const SizedBox(height: 4),
          _kv('Balance After', 'Rs. ${balanceAfter.round()}', bold: true),
        ],
      ),
    );
  }

  Widget _kv(String label, String value, {bool bold = false}) => Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label,
                style: TextStyle(
                    fontSize: 11.5,
                    color: AppColors.kmMuted,
                    fontWeight: bold ? FontWeight.w700 : FontWeight.w500)),
            Text(value,
                style: TextStyle(
                    fontSize: 11.5,
                    color: bold ? AppColors.kmText : AppColors.kmMuted,
                    fontWeight: bold ? FontWeight.w800 : FontWeight.w600)),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      radius: AppRadius.lg,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(S.walletTransactionHistoryTitle,
              style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('walletLedger')
                .where('workerUid', isEqualTo: uid)
                .snapshots(),
            builder: (context, snap) {
              final entries = (snap.data?.docs ?? []).toList()
                ..sort((a, b) {
                  final at = a.data()['createdAt'];
                  final bt = b.data()['createdAt'];
                  if (at is Timestamp && bt is Timestamp) {
                    return bt.compareTo(at);
                  }
                  return 0;
                });
              if (entries.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(S.noWalletTransactionsYet,
                      style: const TextStyle(color: AppColors.kmMuted)),
                );
              }
              // Running Balance — entries नयाँदेखि पुरानो क्रममा छन्;
              // सबैभन्दा नयाँ entry पछिको balance भनेकै हालको walletBalance
              // नै हो (मानेर, दुईबीच कुनै नयाँ entry नथपिएको), त्यसपछि
              // हरेक अघिल्लो (पुरानो) entry तिर जाँदा त्यही entry कै
              // amount फिर्ता घटाउँदै जाने।
              var runningBalance = currentBalance;
              final rows = <Widget>[];
              for (final e in entries) {
                final data = e.data();
                rows.add(_entryRow(data, runningBalance));
                final amount = (data['amount'] as num?)?.toDouble() ?? 0;
                runningBalance -= amount;
              }
              return Column(children: rows);
            },
          ),
        ],
      ),
    );
  }
}
