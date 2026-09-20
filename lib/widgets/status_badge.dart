// widgets/status_badge.dart
// एपभरि एउटै canonical job/KYC status रङ-कोड — सबै screen ले यही प्रयोग गर्छन्।
//  serviceRequests.status:  broadcasting → pending_worker → pending_employer_approval
//                           → accepted/confirmed → in_progress → completed
//                           (declined / cancelled / no_provider = अन्त्य)
import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../theme/app_theme.dart';

class StatusMeta {
  final Color color;
  final IconData icon;
  final String label;

  /// lifecycle मा यो चरणको क्रम (progress bar का लागि); -1 = अन्त्य/रद्द
  final int step;
  const StatusMeta(this.color, this.icon, this.label, this.step);
}

StatusMeta jobStatusMeta(String status) {
  switch (status) {
    case 'broadcasting':
      return StatusMeta(
          AppColors.igViolet, Icons.radar_rounded, S.statusSearching, 0);
    case 'pending_worker':
      return StatusMeta(
          const Color(0xFF3B82F6), Icons.fiber_new_rounded, S.statusNew, 0);
    case 'pending_employer_approval':
      return StatusMeta(
          AppColors.warning, Icons.sync_alt_rounded, S.statusCounter, 0);
    case 'pending_worker_counter':
      return StatusMeta(
          AppColors.igPink, Icons.local_offer_rounded, S.statusCounterOffer, 0);
    case 'accepted':
    case 'confirmed':
      return StatusMeta(
          AppColors.success, Icons.handshake_rounded, S.statusAccepted, 1);
    case 'in_progress':
      return StatusMeta(const Color(0xFF7C3AED), Icons.build_circle_rounded,
          S.statusInProgress, 2);
    case 'completed':
      return StatusMeta(
          AppColors.igOrange, Icons.verified_rounded, S.statusCompleted, 3);
    case 'declined':
    case 'cancelled':
    case 'no_provider':
      return StatusMeta(
          AppColors.danger, Icons.cancel_rounded, S.statusCancelled, -1);
    default:
      return StatusMeta(Colors.grey, Icons.info_outline_rounded, status, 0);
  }
}

/// रङ-कोडेड status pill (icon + label, tinted bg + colored border)।
class StatusBadge extends StatelessWidget {
  final String status;
  final bool large;
  const StatusBadge({super.key, required this.status, this.large = false});

  @override
  Widget build(BuildContext context) {
    final m = jobStatusMeta(status);
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: large ? 12 : 9, vertical: large ? 6 : 4),
      decoration: BoxDecoration(
        color: m.color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: m.color.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(m.icon, size: large ? 15 : 13, color: m.color),
          const SizedBox(width: 4),
          Text(m.label,
              style: TextStyle(
                  color: m.color,
                  fontWeight: FontWeight.w800,
                  fontSize: large ? 12.5 : 11)),
        ],
      ),
    );
  }
}

/// क्षैतिज lifecycle tracker: खोज्दै → स्वीकृत → काम भइरहेको → पूरा भयो।
class JobProgressBar extends StatelessWidget {
  final String status;

  /// gradient (dark) background मा राख्दा true।
  final bool onDark;
  const JobProgressBar({super.key, required this.status, this.onDark = false});

  @override
  Widget build(BuildContext context) {
    final current = jobStatusMeta(status).step;
    final ended = current < 0;
    final steps = [
      S.statusSearching,
      S.statusAccepted,
      S.statusInProgress,
      S.statusCompleted,
    ];
    final dim = onDark ? Colors.white38 : Colors.black26;
    final dimText = onDark ? Colors.white54 : Colors.black45;

    if (ended) {
      return Row(
        children: [
          const Icon(Icons.cancel_rounded, size: 16, color: AppColors.danger),
          const SizedBox(width: 6),
          Text(S.statusCancelled,
              style: const TextStyle(
                  color: AppColors.danger, fontWeight: FontWeight.w700)),
        ],
      );
    }

    return Row(
      children: [
        for (var i = 0; i < steps.length; i++) ...[
          Column(
            children: [
              Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: i <= current ? AppColors.success : dim,
                  shape: BoxShape.circle,
                ),
                child: i < current
                    ? const Icon(Icons.check_rounded,
                        size: 13, color: Colors.white)
                    : (i == current
                        ? const Icon(Icons.circle, size: 8, color: Colors.white)
                        : null),
              ),
              const SizedBox(height: 3),
              SizedBox(
                width: 58,
                child: Text(steps[i],
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 9,
                        fontWeight:
                            i == current ? FontWeight.w800 : FontWeight.w500,
                        color: i <= current
                            ? (onDark ? Colors.white : Colors.black87)
                            : dimText)),
              ),
            ],
          ),
          if (i < steps.length - 1)
            Expanded(
              child: Container(
                height: 2,
                margin: const EdgeInsets.only(bottom: 16),
                color: i < current ? AppColors.success : dim,
              ),
            ),
        ],
      ],
    );
  }
}
