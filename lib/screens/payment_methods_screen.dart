// screens/payment_methods_screen.dart
// inDrive-style payment methods — role अनुसार साँच्चै फरक व्यवहार:
//   Worker (receive गर्ने पक्ष)   → eSewa/Khalti number save गर्नेबित्तिकै
//                                   त्यसैको QR स्वतः देखिन्छ (अरूले स्क्यान
//                                   गरेर पैसा पठाउन)।
//   Employer (pay गर्ने पक्ष)     → eSewa/Khalti click गर्दा आफ्नै QR होइन,
//                                   "आफ्नै app खोल्ने" वा "worker कै QR
//                                   स्क्यान गर्ने" दुई विकल्प देखिन्छ।
// भुक्तानी app मार्फत हुँदैन; यहाँ user आफ्नो wallet ID राख्छ र QR देखाउँछ,
// वा अर्कोको QR स्क्यान गरेर आफ्नै eSewa/Khalti app मा पुगेर तिर्छ।
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../l10n/strings.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_ui.dart';
import 'qr_scanner_screen.dart';

class PaymentMethodsScreen extends StatelessWidget {
  const PaymentMethodsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;

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
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: KmScreenHeader(title: S.paymentsTitle),
              ),
              Expanded(
                child: uid == null
                    ? const Center(
                        child: Text('Login गर्नुहोस्',
                            style: TextStyle(color: AppColors.kmText)))
                    : StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                        stream: FirebaseFirestore.instance
                            .collection('users')
                            .doc(uid)
                            .snapshots(),
                        builder: (context, snap) {
                          final data = snap.data?.data() ?? {};
                          final esewa = (data['esewaId'] ?? '').toString();
                          final khalti = (data['khaltiId'] ?? '').toString();
                          final bankId = (data['bankId'] ?? '').toString();
                          // Worker/Employer व्यवहार फरक — `users/{uid}.role`
                          // बाटै, यही स्क्रिनले पहिल्यै पढेको doc मा भएकोले
                          // थप Firestore read नचाहिने।
                          final isWorker =
                              (data['role'] ?? '').toString() == 'worker';

                          Future<void> save(String field, String value) =>
                              FirebaseFirestore.instance
                                  .collection('users')
                                  .doc(uid)
                                  .set({field: value.trim()},
                                      SetOptions(merge: true));

                          return ListView(
                            padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
                            children: [
                              Text(S.paymentsSub,
                                  style: const TextStyle(
                                      color: AppColors.kmMuted,
                                      fontSize: 14,
                                      height: 1.4)),
                              const SizedBox(height: 16),

                              // 1. QR — worker को आफ्नै (receive), employer को
                              // scanner (pay)।
                              _MethodCard(
                                icon: Icons.qr_code_2_rounded,
                                iconBg: const LinearGradient(colors: [
                                  AppColors.kmRose,
                                  AppColors.kmPink
                                ]),
                                title: S.payQr,
                                subtitle: S.payQrSub,
                                highlighted: true,
                                notSet:
                                    isWorker && esewa.isEmpty && khalti.isEmpty,
                                onTap: () => isWorker
                                    ? _showOwnQr(
                                        context,
                                        payload: esewa.isNotEmpty
                                            ? 'esewa:$esewa'
                                            : khalti.isNotEmpty
                                                ? 'khalti:$khalti'
                                                : '',
                                        label: esewa.isNotEmpty
                                            ? '${S.payEsewa} · $esewa'
                                            : khalti.isNotEmpty
                                                ? '${S.payKhalti} · $khalti'
                                                : '',
                                      )
                                    : _scanAndShowResult(context),
                              ),
                              const SizedBox(height: 12),

                              // 2. eSewa — role जे भए पनि (worker/employer
                              // दुवै), tap गर्दा सिधै आफ्नै wallet ID/मोबाइल
                              // नम्बर टाइप गरेर save गर्ने सरल input-field
                              // sheet (पहिले employer को हकमा esewa.com.np
                              // कै raw लगइन पेज browser मा खोल्थ्यो, जसले
                              // "token expired" जस्ता भ्रामक त्रुटि देखाउँथ्यो
                              // — त्यो पूर्ण रूपमा हटाइयो)।
                              _MethodCard(
                                icon: Icons.account_balance_wallet_rounded,
                                iconBg: const LinearGradient(colors: [
                                  AppColors.kmTeal,
                                  AppColors.kmTealBlue
                                ]),
                                title: S.payEsewa,
                                subtitle:
                                    esewa.isEmpty ? S.walletIdLabel : esewa,
                                notSet: esewa.isEmpty,
                                onTap: () => _editWalletId(
                                  context,
                                  title: S.payEsewa,
                                  current: esewa,
                                  provider: 'esewa',
                                  onSave: (v) => save('esewaId', v),
                                ),
                              ),
                              const SizedBox(height: 12),

                              // 3. Khalti — उही, माथिकै जस्तै सिधै save।
                              _MethodCard(
                                icon: Icons.account_balance_wallet_rounded,
                                iconBg: const LinearGradient(colors: [
                                  AppColors.kmLilac,
                                  AppColors.kmPurple
                                ]),
                                title: S.payKhalti,
                                subtitle:
                                    khalti.isEmpty ? S.walletIdLabel : khalti,
                                notSet: khalti.isEmpty,
                                onTap: () => _editWalletId(
                                  context,
                                  title: S.payKhalti,
                                  current: khalti,
                                  provider: 'khalti',
                                  onSave: (v) => save('khaltiId', v),
                                ),
                              ),
                              const SizedBox(height: 12),

                              // 4. Mobile Banking / Bank — उही ढाँचा, आफ्नै
                              // bank account/mobile-banking ID save गर्ने।
                              _MethodCard(
                                icon: Icons.account_balance_rounded,
                                iconBg: const LinearGradient(colors: [
                                  Color(0xFF1E5AA8),
                                  Color(0xFF123B70)
                                ]),
                                title: S.payBank,
                                subtitle:
                                    bankId.isEmpty ? S.walletIdLabel : bankId,
                                notSet: bankId.isEmpty,
                                onTap: () => _editWalletId(
                                  context,
                                  title: S.payBank,
                                  current: bankId,
                                  provider: 'bank',
                                  onSave: (v) => save('bankId', v),
                                ),
                              ),
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

  /// Worker — number type गरेर Save थिचेपछि सम्पादन-sheet बन्द भई सिधै
  /// त्यही नयाँ नम्बरको QR स्वतः देखिने (छुट्टै फेरि tap गर्नु नपर्ने)।
  void _editWalletId(
    BuildContext context, {
    required String title,
    required String current,
    required String provider,
    required Future<void> Function(String) onSave,
  }) {
    final ctrl = TextEditingController(text: current);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Padding(
          padding:
              EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: Container(
            decoration: const BoxDecoration(
              color: AppColors.kmSurface,
              borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            ),
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title,
                    style: const TextStyle(
                        color: AppColors.kmText,
                        fontWeight: FontWeight.w800,
                        fontSize: 17)),
                const SizedBox(height: 14),
                TextField(
                  controller: ctrl,
                  keyboardType: TextInputType.phone,
                  style: const TextStyle(color: AppColors.kmText),
                  decoration: InputDecoration(
                    labelText: S.walletIdLabel,
                    labelStyle: const TextStyle(color: AppColors.kmMuted),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide(
                          color: Colors.white.withValues(alpha: 0.16)),
                    ),
                    focusedBorder: const OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(16)),
                      borderSide: BorderSide(color: AppColors.kmOrange),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                KmCtaButton(
                  label: S.save,
                  onPressed: () async {
                    final value = ctrl.text.trim();
                    await onSave(value);
                    if (!ctx.mounted) return;
                    Navigator.pop(ctx);
                    if (value.isNotEmpty && context.mounted) {
                      _showOwnQr(
                        context,
                        payload: '$provider:$value',
                        label: '$title · $value',
                      );
                    }
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showOwnQr(
    BuildContext context, {
    required String payload,
    required String label,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _QrSheet(payload: payload, label: label),
    );
  }

  Future<void> _scanAndShowResult(BuildContext context) async {
    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const QrScannerScreen()),
    );
    if (result == null || result.isEmpty || !context.mounted) return;
    final parts = result.split(':');
    final id = parts.length > 1 ? parts.sublist(1).join(':') : result;
    if (!context.mounted) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return Container(
          decoration: const BoxDecoration(
            color: AppColors.kmSurface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(S.scannedWalletId,
                  style: const TextStyle(
                      color: AppColors.kmText,
                      fontWeight: FontWeight.w800,
                      fontSize: 17)),
              const SizedBox(height: 10),
              SelectableText(id,
                  style: const TextStyle(
                      color: AppColors.kmText,
                      fontWeight: FontWeight.w700,
                      fontSize: 15)),
              const SizedBox(height: 10),
              // पहिले यहाँ "Open Wallet" बटनले सिधै esewa.com.np/khalti.com
              // कै raw लगइन पेज browser मा खोल्थ्यो (साँचो merchant checkout
              // session नभएकोले "token expired" जस्ता भ्रामक त्रुटि आउँथ्यो)।
              // अब त्यसको सट्टा — ID copy गरेर आफ्नै (पहिल्यै install भएको)
              // eSewa/Khalti app म्यानुअली खोलेर पठाउनुहोस् भन्ने स्पष्ट
              // निर्देशन मात्र।
              Text(S.copyIdThenOpenAppHint,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: AppColors.kmMuted, fontSize: 12.5)),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: KmCtaButton(
                  label: S.copyId,
                  icon: Icons.copy_rounded,
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: id));
                    ScaffoldMessenger.of(sheetContext).showSnackBar(
                      SnackBar(content: Text(S.idCopied)),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _MethodCard extends StatelessWidget {
  final IconData icon;
  final Gradient iconBg;
  final String title;
  final String subtitle;
  final bool notSet;
  final bool highlighted;
  final VoidCallback onTap;

  const _MethodCard({
    required this.icon,
    required this.iconBg,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.notSet = false,
    this.highlighted = false,
  });

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      radius: 26,
      padding: const EdgeInsets.all(18),
      border: highlighted
          ? AppColors.kmOrange.withValues(alpha: 0.55)
          : AppColors.kmGlassBorder,
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              gradient: iconBg,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Icon(icon, color: AppColors.kmInk),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        color: AppColors.kmText,
                        fontWeight: FontWeight.w700,
                        fontSize: 16)),
                const SizedBox(height: 3),
                Text(subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: AppColors.kmMuted, fontSize: 12.5)),
              ],
            ),
          ),
          if (notSet) ...[
            KmTag(S.notSetYet, color: AppColors.kmMuted),
            const SizedBox(width: 10),
          ],
          Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                  color: highlighted
                      ? AppColors.kmOrange
                      : Colors.white.withValues(alpha: 0.4),
                  width: 1.5),
              color: highlighted
                  ? AppColors.kmOrange.withValues(alpha: 0.9)
                  : null,
            ),
            child: highlighted
                ? const Icon(Icons.circle, size: 8, color: AppColors.kmInk)
                : null,
          ),
        ],
      ),
    );
  }
}

class _QrSheet extends StatelessWidget {
  final String payload;
  final String label;
  const _QrSheet({required this.payload, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.kmSurface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        border: Border(
            top: BorderSide(color: Color(0x24FFFFFF)),
            left: BorderSide(color: Color(0x24FFFFFF)),
            right: BorderSide(color: Color(0x24FFFFFF))),
      ),
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(S.scanToPay,
              style: const TextStyle(
                  color: AppColors.kmText,
                  fontWeight: FontWeight.w800,
                  fontSize: 17)),
          const SizedBox(height: 16),
          if (payload.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text(S.notSetYet,
                  style: const TextStyle(color: AppColors.kmMuted)),
            )
          else ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(22),
              ),
              child: QrImageView(
                data: payload,
                size: 200,
                backgroundColor: Colors.white,
              ),
            ),
            const SizedBox(height: 12),
            Text(label,
                style:
                    const TextStyle(color: AppColors.kmMuted, fontSize: 12.5)),
            const SizedBox(height: 14),
            KmCtaButton(
              label: S.save,
              icon: Icons.copy_rounded,
              onPressed: () {
                Clipboard.setData(ClipboardData(text: payload));
                Navigator.pop(context);
              },
            ),
          ],
        ],
      ),
    );
  }
}
