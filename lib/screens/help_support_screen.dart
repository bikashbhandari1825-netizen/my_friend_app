// screens/help_support_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config/app_config.dart';
import '../content/legal_text.dart';
import '../l10n/strings.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_ui.dart';
import '../worker_no_response_page.dart';

class HelpSupportScreen extends StatelessWidget {
  const HelpSupportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    Widget row(IconData icon, Gradient bg, String title, String sub,
            VoidCallback onTap) =>
        KmListTile(
          icon: icon,
          iconBg: bg,
          title: title,
          subtitle: sub,
          onTap: onTap,
        );

    // Admin (Owner Dashboard → Help Content) ले सम्पादन गरेको भए त्यही
    // देखिने, नत्र `LegalText` कै मूल copy — कहिल्यै सम्पादन नगरे पनि
    // content कहिल्यै खाली नदेखियोस् भनेर।
    return StreamBuilder<Map<String, dynamic>>(
      stream: HelpContentConfig.stream(),
      builder: (context, snap) {
        final data = snap.data ?? const <String, dynamic>{};
        String pick(String key, String fallback) {
          final v = (data[key] ?? '').toString().trim();
          return v.isEmpty ? fallback : v;
        }

        final serviceStandard = pick(
            S.isNepali ? 'serviceStandardNe' : 'serviceStandardEn',
            LegalText.serviceStandard);
        final privacyPolicy = pick(
            S.isNepali ? 'privacyPolicyNe' : 'privacyPolicyEn',
            LegalText.privacyPolicy);
        final dataSecurity = pick(
            S.isNepali ? 'dataSecurityNe' : 'dataSecurityEn',
            LegalText.dataSecurity);

        final rawFaq = data['faq'];
        final faq = (rawFaq is List && rawFaq.isNotEmpty)
            ? rawFaq.map((e) {
                final m = Map<String, dynamic>.from(e as Map);
                // भाषा-विशिष्ट field पहिले, त्यो खाली भए अर्को भाषाकोमा
                // fallback (admin ले एक भाषा मात्र भरे पनि खाली नदेखियोस्)।
                String field(String suffix) {
                  final primary = S.isNepali ? 'Ne' : 'En';
                  final other = S.isNepali ? 'En' : 'Ne';
                  final v1 = (m['$suffix$primary'] ?? '').toString().trim();
                  if (v1.isNotEmpty) return v1;
                  return (m['$suffix$other'] ?? '').toString().trim();
                }

                return (field('q'), field('a'));
              }).toList()
            : LegalText.faq;

        return AuroraBackground(
          orbs: const [
            KmOrb(Alignment.topLeft, AppColors.kmPink),
            KmOrb(Alignment.bottomRight, AppColors.kmPurple),
          ],
          child: Scaffold(
            backgroundColor: Colors.transparent,
            body: SafeArea(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: KmScreenHeader(title: S.helpSupport),
                  ),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
                      children: [
                        row(
                            Icons.gavel_rounded,
                            KmListTile.gradients[1],
                            S.serviceStandard,
                            S.serviceStandardSub,
                            () => _openText(
                                context, S.serviceStandard, serviceStandard)),
                        const SizedBox(height: 10),
                        row(Icons.person_off_rounded, KmListTile.gradients[2],
                            S.workerNoResponse, S.workerNoResponseSub, () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => const WorkerNoResponsePage()),
                          );
                        }),
                        KmSectionLabel(S.faq),
                        const SizedBox(height: 8),
                        for (final qa in faq)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _FaqTile(question: qa.$1, answer: qa.$2),
                          ),
                        const SizedBox(height: 6),
                        const _ContactSupportCard(),
                        KmSectionLabel(S.privacyPolicy),
                        const SizedBox(height: 8),
                        row(Icons.privacy_tip_rounded, KmListTile.gradients[0],
                            S.privacyPolicy, S.dataSecureLine,
                            () => _openText(
                                context, S.privacyPolicy, privacyPolicy)),
                        const SizedBox(height: 10),
                        row(
                            Icons.verified_user_rounded,
                            KmListTile.gradients[3],
                            S.dataSecurity,
                            S.dataSecureLine,
                            () => _openText(
                                context, S.dataSecurity, dataSecurity)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _openText(BuildContext context, String title, String body) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => _LegalPage(title: title, body: body)),
    );
  }
}

/// FAQ प्रश्न — glass row, थिच्दा उत्तर तल खुल्छ (ExpansionTile कै व्यवहार)।
class _FaqTile extends StatefulWidget {
  final String question;
  final String answer;
  const _FaqTile({required this.question, required this.answer});

  @override
  State<_FaqTile> createState() => _FaqTileState();
}

class _FaqTileState extends State<_FaqTile> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      radius: 20,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      onTap: () => setState(() => _open = !_open),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(widget.question,
                    style: const TextStyle(
                        color: AppColors.kmText,
                        fontWeight: FontWeight.w600,
                        fontSize: 15)),
              ),
              AnimatedRotation(
                turns: _open ? 0.5 : 0,
                duration: const Duration(milliseconds: 200),
                child: const Icon(Icons.expand_more_rounded,
                    size: 18, color: AppColors.kmMuted),
              ),
            ],
          ),
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 200),
            crossFadeState:
                _open ? CrossFadeState.showFirst : CrossFadeState.showSecond,
            firstChild: Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(widget.answer,
                  style: const TextStyle(
                      color: AppColors.kmMuted, fontSize: 13, height: 1.45)),
            ),
            secondChild: const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

class _ContactSupportCard extends StatelessWidget {
  const _ContactSupportCard();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<String>(
      stream: SupportConfig.phoneStream(),
      builder: (context, snap) {
        final phone = (snap.data ?? '').trim();
        return GlassPanel(
          radius: 26,
          fill: AppColors.kmOrange.withValues(alpha: 0.08),
          border: AppColors.kmOrange.withValues(alpha: 0.4),
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                      colors: [AppColors.kmOrange, AppColors.kmOrangeDeep]),
                  borderRadius: BorderRadius.circular(17),
                ),
                child: const Icon(Icons.support_agent_rounded,
                    color: AppColors.kmInk),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(S.contactSupport,
                        style: const TextStyle(
                            color: AppColors.kmMuted,
                            fontWeight: FontWeight.w600,
                            fontSize: 13)),
                    const SizedBox(height: 2),
                    Text(
                      phone.isEmpty ? S.contactSupportUnset : phone,
                      style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: phone.isEmpty ? 14 : 19,
                          color: phone.isEmpty
                              ? AppColors.kmMuted
                              : AppColors.kmOrange),
                    ),
                  ],
                ),
              ),
              if (phone.isNotEmpty)
                GlassIconButton(
                  icon: Icons.copy_rounded,
                  size: 42,
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: phone));
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('$phone  ·  ${S.saved}')),
                    );
                  },
                ),
            ],
          ),
        );
      },
    );
  }
}

class _LegalPage extends StatelessWidget {
  final String title;
  final String body;
  const _LegalPage({required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    return AuroraBackground(
      orbs: const [
        KmOrb(Alignment.topLeft, AppColors.kmPink),
        KmOrb(Alignment.bottomRight, AppColors.kmPurple),
      ],
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: KmScreenHeader(title: title),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                  child: Text(
                    body,
                    style: const TextStyle(
                        color: AppColors.kmMuted, height: 1.55, fontSize: 14),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
