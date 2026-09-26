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
import 'package:url_launcher/url_launcher.dart';

import '../l10n/strings.dart';
import '../theme/app_theme.dart';
import '../widgets/app_ui.dart';
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
                            padding:
                                const EdgeInsets.fromLTRB(16, 14, 16, 28),
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
                                notSet: isWorker &&
                                    esewa.isEmpty &&
                                    khalti.isEmpty,
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

                              // 2. eSewa
                              _MethodCard(
                                icon: Icons.account_balance_wallet_rounded,
                                iconBg: const LinearGradient(colors: [
                                  AppColors.kmTeal,
                                  AppColors.kmTealBlue
                                ]),
                                title: S.payEsewa,
                                subtitle:
                                    esewa.isEmpty ? S.walletIdLabel : esewa,
                                notSet: isWorker && esewa.isEmpty,
                                onTap: () => isWorker
                                    ? _editWalletId(
                                        context,
                                        title: S.payEsewa,
                                        current: esewa,
                                        provider: 'esewa',
                                        onSave: (v) => save('esewaId', v),
                                      )
                                    : _showEmployerPaySheet(
                                        context,
                                        provider: 'esewa',
                                        label: S.payEsewa,
                                        accent: const Color(0xFF60BB46),
                                      ),
                              ),
                              const SizedBox(height: 12),

                              // 3. Khalti
                              _MethodCard(
                                icon: Icons.account_balance_wallet_rounded,
                                iconBg: const LinearGradient(colors: [
                                  AppColors.kmLilac,
                                  AppColors.kmPurple
                                ]),
                                title: S.payKhalti,
                                subtitle:
                                    khalti.isEmpty ? S.walletIdLabel : khalti,
                                notSet: isWorker && khalti.isEmpty,
                                onTap: () => isWorker
                                    ? _editWalletId(
                                        context,
                                        title: S.payKhalti,
                                        current: khalti,
                                        provider: 'khalti',
                                        onSave: (v) => save('khaltiId', v),
                                      )
                                    : _showEmployerPaySheet(
                                        context,
                                        provider: 'khalti',
                                        label: S.payKhalti,
                                        accent: const Color(0xFF5C2D91),
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

  /// Employer — eSewa/Khalti click गर्दा आफ्नै QR होइन, दुई विकल्प:
  /// आफ्नै app खोल्ने, वा worker कै QR स्क्यान गर्ने।
  void _showEmployerPaySheet(
    BuildContext context, {
    required String provider,
    required String label,
    required Color accent,
  }) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return Container(
          decoration: const BoxDecoration(
            color: AppColors.kmSurface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          padding: const EdgeInsets.fromLTRB(12, 18, 12, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(label,
                    style: const TextStyle(
                        color: AppColors.kmText,
                        fontWeight: FontWeight.w800,
                        fontSize: 17)),
              ),
              const SizedBox(height: 10),
              ListTile(
                leading: Icon(Icons.open_in_new_rounded, color: accent),
                title: Text('${S.openWallet} — $label',
                    style: const TextStyle(color: AppColors.kmText)),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _openWalletApp(context, provider);
                },
              ),
              ListTile(
                leading: Icon(Icons.qr_code_scanner_rounded, color: accent),
                title: Text(S.scanToPay,
                    style: const TextStyle(color: AppColors.kmText)),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _scanAndShowResult(context);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _scanAndShowResult(BuildContext context) async {
    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const QrScannerScreen()),
    );
    if (result == null || result.isEmpty || !context.mounted) return;
    final parts = result.split(':');
    final provider = parts.length > 1 ? parts.first : '';
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
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: SecondaryButton(
                      label: S.copyId,
                      icon: Icons.copy_rounded,
                      color: AppColors.kmText,
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: id));
                        ScaffoldMessenger.of(sheetContext).showSnackBar(
                          SnackBar(content: Text(S.idCopied)),
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: KmCtaButton(
                      label: S.openWallet,
                      onPressed: () {
                        Navigator.pop(sheetContext);
                        _openWalletApp(context, provider);
                      },
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

  /// eSewa/Khalti को कुनै साँचो merchant deep-link/API नभएकोले, तिनकै
  /// आधिकारिक domain खोल्ने कोसिस — ती app हरूले साधारणतया आफ्नै domain को
  /// universal/app link handle गर्ने भएकोले, install भएको फोनमा सिधै app
  /// खुल्छ (नत्र browser मा fallback हुन्छ)।
  Future<void> _openWalletApp(BuildContext context, String provider) async {
    final url = provider == 'khalti'
        ? 'https://khalti.com'
        : 'https://esewa.com.np';
    bool ok = false;
    try {
      ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {
      ok = false;
    }
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(S.walletAppNotFound)));
    }
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
                    style:
                        const TextStyle(color: AppColors.kmMuted, fontSize: 12.5)),
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
                style: const TextStyle(color: AppColors.kmMuted, fontSize: 12.5)),
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
