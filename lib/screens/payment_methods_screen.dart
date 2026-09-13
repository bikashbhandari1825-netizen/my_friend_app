// screens/payment_methods_screen.dart
// inDrive-style payment methods — QR (Scan & Pay), eSewa, Khalti।
// भुक्तानी app मार्फत हुँदैन; यहाँ user आफ्नो wallet ID राख्छ र QR देखाउँछ।
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../l10n/strings.dart';
import '../theme/app_theme.dart';
import '../widgets/app_ui.dart';

class PaymentMethodsScreen extends StatelessWidget {
  const PaymentMethodsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final uid = FirebaseAuth.instance.currentUser?.uid;

    return Scaffold(
      appBar: AppBar(title: Text(S.paymentsTitle)),
      body: uid == null
          ? const Center(child: Text('Login गर्नुहोस्'))
          : StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .doc(uid)
                  .snapshots(),
              builder: (context, snap) {
                final data = snap.data?.data() ?? {};
                final esewa = (data['esewaId'] ?? '').toString();
                final khalti = (data['khaltiId'] ?? '').toString();

                Future<void> save(String field, String value) =>
                    FirebaseFirestore.instance
                        .collection('users')
                        .doc(uid)
                        .set({field: value.trim()}, SetOptions(merge: true));

                return ListView(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
                  children: [
                    Text(S.paymentsSub, style: theme.textTheme.bodyMedium),
                    const SizedBox(height: 16),

                    // 1. QR — Scan & Pay
                    _MethodCard(
                      icon: Icons.qr_code_2_rounded,
                      title: S.payQr,
                      subtitle: S.payQrSub,
                      trailing: (esewa.isNotEmpty || khalti.isNotEmpty)
                          ? null
                          : Pill(S.notSetYet),
                      onTap: () => showModalBottomSheet(
                        context: context,
                        isScrollControlled: true,
                        backgroundColor: Colors.transparent,
                        builder: (_) => _QrSheet(
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
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // 2. eSewa
                    _MethodCard(
                      icon: Icons.account_balance_wallet_rounded,
                      title: S.payEsewa,
                      subtitle: esewa.isEmpty ? S.walletIdLabel : esewa,
                      accent: const Color(0xFF60BB46),
                      trailing: esewa.isEmpty ? Pill(S.notSetYet) : null,
                      onTap: () => _editWalletId(
                        context,
                        title: S.payEsewa,
                        current: esewa,
                        onSave: (v) => save('esewaId', v),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // 3. Khalti
                    _MethodCard(
                      icon: Icons.account_balance_wallet_rounded,
                      title: S.payKhalti,
                      subtitle: khalti.isEmpty ? S.walletIdLabel : khalti,
                      accent: const Color(0xFF5C2D91),
                      trailing: khalti.isEmpty ? Pill(S.notSetYet) : null,
                      onTap: () => _editWalletId(
                        context,
                        title: S.payKhalti,
                        current: khalti,
                        onSave: (v) => save('khaltiId', v),
                      ),
                    ),
                  ],
                );
              },
            ),
    );
  }

  void _editWalletId(
    BuildContext context, {
    required String title,
    required String current,
    required Future<void> Function(String) onSave,
  }) {
    final ctrl = TextEditingController(text: current);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return Padding(
          padding:
              EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: Container(
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(AppRadius.lg)),
            ),
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 16)),
                const SizedBox(height: 14),
                TextField(
                  controller: ctrl,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(labelText: S.walletIdLabel),
                ),
                const SizedBox(height: 16),
                PrimaryButton(
                  label: S.save,
                  onPressed: () async {
                    await onSave(ctrl.text);
                    if (ctx.mounted) Navigator.pop(ctx);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _MethodCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? trailing;
  final Color? accent;
  final VoidCallback onTap;

  const _MethodCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.trailing,
    this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      padding: const EdgeInsets.all(14),
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: (accent ?? AppColors.lime).withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: accent ?? AppColors.lime),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 15)),
                Text(subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall),
              ],
            ),
          ),
          if (trailing != null) trailing!,
          Icon(Icons.chevron_right_rounded,
              color: theme.colorScheme.onSurfaceVariant),
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
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius:
            const BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(S.scanToPay,
              style:
                  const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          const SizedBox(height: 16),
          if (payload.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text(S.notSetYet, style: theme.textTheme.bodyMedium),
            )
          else ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: QrImageView(
                data: payload,
                size: 200,
                backgroundColor: Colors.white,
              ),
            ),
            const SizedBox(height: 12),
            Text(label, style: theme.textTheme.bodySmall),
            const SizedBox(height: 12),
            SecondaryButton(
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
