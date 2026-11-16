// widgets/profile_hero_card.dart
//
// Profile को मुख्य "hero" card — cover gradient, ठूलो avatar (verified tick),
// नाम/role, तीन stat tile (रेटिङ · काम · वालेट) र profile-पूर्णता बार।
// केवल देखाइ; edit/फोटो छान्ने काम बाहिरबाट callback ले गर्छ।
import 'package:flutter/material.dart';

import '../app_globals.dart';
import '../l10n/strings.dart';
import '../theme/app_theme.dart';
import '../utils/price_input.dart';

class ProfileHeroCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final String fullName;
  final String email;
  final String dobFormatted;
  final bool isWorker;
  final String experience;
  final String selfieUrl;
  final bool workerVerified;

  /// नाम/role badge (role नभए null) र रेटिङ badge — बाहिरी screen का widget।
  final Widget? roleBadge;
  final Widget? ratingBadge;
  final VoidCallback onPhoto;
  final VoidCallback onEdit;

  const ProfileHeroCard({
    super.key,
    required this.data,
    required this.fullName,
    required this.email,
    required this.dobFormatted,
    required this.isWorker,
    required this.experience,
    required this.selfieUrl,
    required this.workerVerified,
    required this.roleBadge,
    required this.ratingBadge,
    required this.onPhoto,
    required this.onEdit,
  });

  num _n(String k) => (data[k] as num?) ?? 0;

  bool get _hasPhoto => sessionProfilePhoto != null || selfieUrl.isNotEmpty;

  /// नाम, इमेल, जन्ममिति, फोटो, फोन — कति भरिएको (०–१)।
  double get _completeness {
    final checks = [
      fullName.isNotEmpty,
      email.isNotEmpty,
      dobFormatted.isNotEmpty,
      _hasPhoto,
      (data['phone'] ?? '').toString().isNotEmpty,
    ];
    return checks.where((c) => c).length / checks.length;
  }

  @override
  Widget build(BuildContext context) {
    final ratingCount = _n('ratingCount');
    final avg = ratingCount > 0 ? _n('ratingSum') / ratingCount : 0;
    final done = _n('completedRidesCount');
    final wallet = _n('walletBalance');
    final pct = _completeness;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.kmGlassFillStrong,
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          _coverAndAvatar(),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        fullName.isEmpty ? S.profileNameNotSet : fullName,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: AppColors.kmText,
                            fontSize: 21,
                            fontWeight: FontWeight.w800),
                      ),
                    ),
                    if (isWorker && workerVerified) ...[
                      const SizedBox(width: 6),
                      const Icon(Icons.verified_rounded,
                          size: 20, color: AppColors.kmTealBlue),
                    ],
                  ],
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (roleBadge != null) roleBadge!,
                    if (ratingBadge != null) ratingBadge!,
                  ],
                ),
                const SizedBox(height: 10),
                if (email.isNotEmpty)
                  _line(Icons.mail_outline_rounded, email),
                if (dobFormatted.isNotEmpty)
                  _line(Icons.cake_outlined, '${S.dob}: $dobFormatted'),
                if (experience.isNotEmpty)
                  _line(Icons.workspace_premium_outlined,
                      'अनुभव: $experience'),
                if (isWorker) ...[
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      _stat(
                          Icons.star_rounded,
                          ratingCount > 0 ? avg.toStringAsFixed(1) : '—',
                          'Rating',
                          AppColors.kmOrange),
                      const SizedBox(width: 10),
                      _stat(Icons.check_circle_rounded,
                          done.toInt().toString(), 'Completed',
                          AppColors.kmTeal),
                      const SizedBox(width: 10),
                      _stat(
                          Icons.account_balance_wallet_rounded,
                          'Rs ${formatRs(wallet)}',
                          'Wallet',
                          wallet < 0
                              ? AppColors.kmRose
                              : AppColors.kmTealBlue),
                    ],
                  ),
                ],
                if (pct < 1) ...[
                  const SizedBox(height: 14),
                  _completenessBar(pct),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _coverAndAvatar() {
    return SizedBox(
      height: 128,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            bottom: 44,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    AppColors.kmPurple.withValues(alpha: 0.85),
                    AppColors.kmPink.withValues(alpha: 0.75),
                    AppColors.kmOrange.withValues(alpha: 0.75),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            top: 12,
            right: 12,
            child: GestureDetector(
              onTap: onEdit,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.28),
                  borderRadius: BorderRadius.circular(20),
                  border:
                      Border.all(color: Colors.white.withValues(alpha: 0.4)),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.edit_rounded, size: 14, color: Colors.white),
                    SizedBox(width: 5),
                    Text('Edit Profile',
                        style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 12)),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            left: 18,
            bottom: 0,
            child: GestureDetector(
              onTap: onPhoto,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 88,
                    height: 88,
                    padding: const EdgeInsets.all(3.5),
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: SweepGradient(colors: [
                        AppColors.kmOrange,
                        AppColors.kmPink,
                        AppColors.kmPurple,
                        AppColors.kmTeal,
                        AppColors.kmOrange,
                      ]),
                    ),
                    child: CircleAvatar(
                      backgroundColor: AppColors.kmSurface,
                      backgroundImage: sessionProfilePhoto != null
                          ? MemoryImage(sessionProfilePhoto!) as ImageProvider
                          : (selfieUrl.isNotEmpty
                              ? NetworkImage(selfieUrl)
                              : null),
                      child: _hasPhoto
                          ? null
                          : const Icon(Icons.person_rounded,
                              size: 38, color: AppColors.kmLilac),
                    ),
                  ),
                  Positioned(
                    right: -2,
                    bottom: -2,
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: AppColors.kmCtaGradient,
                        border:
                            Border.all(color: AppColors.kmSurface, width: 2.5),
                      ),
                      child: const Icon(Icons.camera_alt_rounded,
                          size: 13, color: AppColors.kmInk),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _completenessBar(double pct) {
    return GestureDetector(
      onTap: onEdit,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Profile ${(pct * 100).round()}% complete',
                    style: const TextStyle(
                        color: AppColors.kmText,
                        fontWeight: FontWeight.w700,
                        fontSize: 13),
                  ),
                ),
                const Icon(Icons.chevron_right_rounded,
                    color: AppColors.kmMuted, size: 20),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: pct,
                minHeight: 6,
                backgroundColor: Colors.white.withValues(alpha: 0.1),
                valueColor:
                    const AlwaysStoppedAnimation(AppColors.kmOrange),
              ),
            ),
            const SizedBox(height: 6),
            Text(S.profileEditHint,
                style:
                    const TextStyle(color: AppColors.kmMuted, fontSize: 11)),
          ],
        ),
      ),
    );
  }

  Widget _line(IconData icon, String text) => Padding(
        padding: const EdgeInsets.only(top: 3),
        child: Row(
          children: [
            Icon(icon, size: 14, color: AppColors.kmMuted),
            const SizedBox(width: 7),
            Flexible(
              child: Text(text,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: AppColors.kmMuted, fontSize: 12.5)),
            ),
          ],
        ),
      );

  Widget _stat(IconData icon, String value, String label, Color color) =>
      Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withValues(alpha: 0.35)),
          ),
          child: Column(
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(height: 4),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(value,
                    style: const TextStyle(
                        color: AppColors.kmText,
                        fontSize: 16,
                        fontWeight: FontWeight.w800)),
              ),
              Text(label,
                  style: const TextStyle(
                      color: AppColors.kmMuted,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      );
}
