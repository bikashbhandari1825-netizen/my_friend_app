// screens/help_support_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config/app_config.dart';
import '../content/legal_text.dart';
import '../l10n/strings.dart';
import '../theme/app_theme.dart';
import '../widgets/app_ui.dart';
import '../worker_no_response_page.dart';

class HelpSupportScreen extends StatelessWidget {
  const HelpSupportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    Widget row(IconData icon, String title, String sub, VoidCallback onTap) =>
        AppCard(
          padding: const EdgeInsets.all(14),
          onTap: onTap,
          child: Row(
            children: [
              LimeIconBadge(icon),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 15)),
                    Text(sub, style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded,
                  color: theme.colorScheme.onSurfaceVariant),
            ],
          ),
        );

    return Scaffold(
      appBar: AppBar(title: Text(S.helpSupport)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
        children: [
          row(
              Icons.gavel_rounded,
              S.serviceStandard,
              S.serviceStandardSub,
              () => _openText(
                  context, S.serviceStandard, LegalText.serviceStandard)),
          const SizedBox(height: 10),
          row(Icons.person_off_rounded, S.workerNoResponse,
              S.workerNoResponseSub, () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const WorkerNoResponsePage()),
            );
          }),
          const SizedBox(height: 22),
          Text(S.faq,
              style:
                  const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          for (final qa in LegalText.faq)
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ExpansionTile(
                shape: const Border(),
                collapsedShape: const Border(),
                tilePadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
                childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                title: Text(qa.$1,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 14)),
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(qa.$2,
                        style:
                            theme.textTheme.bodyMedium?.copyWith(height: 1.45)),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 14),
          const _ContactSupportCard(),
          const SizedBox(height: 22),
          Text(S.privacyPolicy,
              style:
                  const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          row(
              Icons.privacy_tip_rounded,
              S.privacyPolicy,
              S.dataSecureLine,
              () =>
                  _openText(context, S.privacyPolicy, LegalText.privacyPolicy)),
          const SizedBox(height: 10),
          row(Icons.verified_user_rounded, S.dataSecurity, S.dataSecureLine,
              () => _openText(context, S.dataSecurity, LegalText.dataSecurity)),
        ],
      ),
    );
  }

  void _openText(BuildContext context, String title, String body) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => _LegalPage(title: title, body: body)),
    );
  }
}

class _ContactSupportCard extends StatelessWidget {
  const _ContactSupportCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return StreamBuilder<String>(
      stream: SupportConfig.phoneStream(),
      builder: (context, snap) {
        final phone = (snap.data ?? '').trim();
        return AppCard(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              const LimeIconBadge(Icons.support_agent_rounded),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(S.contactSupport,
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 15)),
                    Text(
                      phone.isEmpty ? S.contactSupportUnset : phone,
                      style: phone.isEmpty
                          ? theme.textTheme.bodySmall
                          : const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                              color: AppColors.lime),
                    ),
                  ],
                ),
              ),
              if (phone.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.copy_rounded, size: 18),
                  onPressed: () {
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
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        child: Text(
          body,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.5),
        ),
      ),
    );
  }
}
