// widgets/dashboard_exit_bar.dart
// Worker/Driver Dashboard (job_feed_screen.dart) जस्ता MainContainer को
// IndexedStack बाहिर (छुट्टै Navigator.push गरिएको full-screen route)
// देखिने screen हरूका लागि — MainContainer कै bottom nav बारसँग देखिनमा
// उस्तै, तर यहाँबाट ट्याप गर्दा MainContainer सम्मै popUntil गरेर फर्कने।
// (app_globals.dart::requestedMainTabIndex हेर्नुहोस् — त्यहाँ नै पूरा
// कारण/जड उल्लेख छ।)
import 'package:flutter/material.dart';

import '../app_globals.dart' show requestedMainTabIndex;
import '../l10n/strings.dart';
import '../theme/app_theme.dart';
import 'glass_ui.dart';

/// MainContainer सम्म (कुनै पनि गहिराइमा push भएको भए पनि) फर्केर त्यसको
/// `_currentIndex` लाई यही तोकिएको tab मा सेट गर्ने — [DashboardExitBar] र
/// [GoHomeAction] दुवैले प्रयोग गर्ने साझा तर्क।
void goToMainTab(BuildContext context, int tabIndex) {
  requestedMainTabIndex.value = tabIndex;
  Navigator.of(context).popUntil((r) => r.isFirst);
}

/// Strict Partner Dashboard Boundary — Hotel/Driver/Handyman partner
/// dashboard हरूले आफ्नो सबैभन्दा बाहिरी `Scaffold`/`AuroraBackground` यही
/// भित्र wrap गर्छन्। यसले प्रणाली back gesture/बटन (dashboard नै topmost
/// route हुँदा मात्र — भित्री dialog/chat/QR-scanner/preview जस्ता पछि
/// push गरिएका sub-route खुला छँदा होइन, ती आफैं पहिले pop हुन्छन्) लाई
/// सीधै customer Home तिर pop हुनबाट रोक्छ — बरु "Exit Dashboard?" confirm
/// देखाउँछ; "Exit" थिचेमा मात्र [goToMainTab] (माथि, GoHomeAction/
/// DashboardExitBar कै उस्तै सानुतिल बाटो) बाट Home मा जान्छ। TabBar/
/// internal tab स्विच, "Add Room" जस्ता dialog, वा status-chip जस्ता
/// in-dashboard action ले यहाँ कहिल्यै Navigator pop नै गर्दैनन् — ती
/// पहिल्यैदेखि TabController/dialog-local मात्र भएकोले यो guard ले तिनलाई
/// कुनै असर गर्दैन।
class PartnerDashboardGuard extends StatelessWidget {
  final Widget child;
  const PartnerDashboardGuard({super.key, required this.child});

  Future<void> _confirmExit(BuildContext context) async {
    final exit = await showKmDialog<bool>(
      context: context,
      title: 'Exit Dashboard?',
      message:
          "You'll leave the partner dashboard and return to the main Home screen.",
      actions: [
        KmDialogAction(
          label: 'Stay',
          onPressed: () => Navigator.of(context).pop(false),
        ),
        KmDialogAction(
          label: 'Exit',
          filled: true,
          onPressed: () => Navigator.of(context).pop(true),
        ),
      ],
    );
    if (exit == true && context.mounted) goToMainTab(context, 0);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _confirmExit(context);
      },
      child: child,
    );
  }
}

/// MainContainer कै tab index सँग मिल्दो (0=Home, 3=Messages, 4=Profile —
/// 2=Watchlist यहाँ देखाइँदैन, worker/driver dashboard सँग प्रत्यक्ष सम्बन्ध
/// नभएकोले)।
///
/// "Bookings" (tab 1, customer-कै ride-booking history) जानाजानी यहाँ
/// छैन — Hotel Partner Dashboard (`_BookingsTab`, top TabBar) र Driver
/// Dashboard (`WorkerRequestsPage`) दुवैको आफ्नै छुट्टै, साँचो partner-
/// booking list पहिले नै छ। यही exit-bar मा पनि उस्तै "Bookings" लेबल
/// राख्दा (customer-तर्फकै MainContainer मा नै लैजाने भए पनि) owner/driver
/// भ्रमित हुने — आफ्नै होटल/राइड बुकिङ देखिन्छ भनेर थिचेर एकैचोटि सिंगो
/// partner dashboard बाट बाहिरिने (गुनासो: "Bookings थिच्दा Home स्क्रिनमा
/// फर्काइदिन्छ") — गुनासोको साँचो जड। अब यो एकदमै confusing shortcut
/// हटाइएको — partner-तर्फको Bookings सधैँ त्यसैको dedicated ठाउँबाट मात्र।
class DashboardExitBar extends StatelessWidget {
  // Scoped Hotel Messages — Hotel Partner Dashboard ले मात्र पास गर्छ,
  // ताकि "Messages" ट्याप गर्दा global ride/bike chat तिर (जो hotel
  // dashboard सँग कुनै सम्बन्ध नभएको, confusing/cross-contamination) होइन
  // — यही होटलका guest booking सँगै scoped दृश्य खुलोस् (dashboard बाहिर
  // नपुगी, सिधै माथि push गरिने)। Driver/Handyman dashboard मा यो null
  // रहन्छ — तिनका लागि "Messages" अझै global tab नै (पुरानो, सहि व्यवहार)।
  final VoidCallback? onMessagesTap;
  const DashboardExitBar({super.key, this.onMessagesTap});

  @override
  Widget build(BuildContext context) {
    final items = <({IconData icon, String label, int tab})>[
      (icon: Icons.home_rounded, label: S.navHome, tab: 0),
      (icon: Icons.chat_bubble_rounded, label: S.navMessages, tab: 3),
      (icon: Icons.person_rounded, label: S.navProfile, tab: 4),
    ];
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 16),
        child: GlassPanel2(
          radius: 26,
          child: SizedBox(
            height: 62,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                for (final it in items)
                  Expanded(
                    child: InkWell(
                      onTap: () => it.tab == 3 && onMessagesTap != null
                          ? onMessagesTap!()
                          : goToMainTab(context, it.tab),
                      borderRadius: BorderRadius.circular(18),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(it.icon, size: 22, color: AppColors.kmMuted2),
                            const SizedBox(height: 3),
                            Text(it.label,
                                style: const TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.kmMuted2)),
                          ],
                        ),
                      ),
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

/// AppBar/`KmScreenHeader` कै `actions` मा राख्ने स्पष्ट लेबल भएको "Home"
/// बटन — JobFeedScreen जस्ता full-screen map + draggable bottom sheet भएका
/// dashboard मा [DashboardExitBar] (bottom bar) सिटले ढाकिदिन सक्छ (सिट
/// `_sheetMax` सम्म तानिँदा पूरै स्क्रिन ओगट्छ), त्यसैले त्यहाँ यो AppBar-
/// स्तरको बटन नै एकमात्र सधैँ-देखिने/सधैँ-tappable बाटो हो — Stack/sheet
/// जहिले पनि यसमुनि मात्र रहन्छ, कहिल्यै माथि आउँदैन।
class GoHomeAction extends StatelessWidget {
  const GoHomeAction({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Material(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: () => goToMainTab(context, 0),
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.home_rounded, size: 18, color: AppColors.kmInk),
                SizedBox(width: 5),
                Text('Home',
                    style: TextStyle(
                        color: AppColors.kmInk,
                        fontWeight: FontWeight.w800,
                        fontSize: 13)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
