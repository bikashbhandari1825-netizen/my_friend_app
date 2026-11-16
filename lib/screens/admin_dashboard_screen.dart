// screens/admin_dashboard_screen.dart
//
// Admin Dashboard भित्रैको Multi-Role Sub-Dashboard Tabs — Driver, Worker/
// Handyman, र Hotel Provider नियन्त्रण प्यानलहरू बीच एउटै screen भित्रै tap
// गरेर तुरुन्तै switch गर्न (कुनै logout/फेरि admin password चाहिँदैन, अनि
// स्क्रिनहरू बीच पुग्न Navigator back-stack पनि चाहिँदैन)। हरेक tab ले
// पहिल्यै अवस्थित पूर्ण स्क्रिन (`DriversControlDashboard`,
// `OwnerDashboardScreen`, `HotelAdminControlScreen`) नै ज्युँदो embed गर्छ —
// ती फाइलहरू यहाँ कतै परिवर्तन गरिएको छैन (zero side-effects)।
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../widgets/glass_ui.dart';
import 'admin_salons_screen.dart';
import 'admin_user_directory_screen.dart';
import 'hotel_admin_control_screen.dart';
import 'owner_dashboard_screen.dart';

class AdminDashboardScreen extends StatefulWidget {
  // app.dart कै grid-card बाट कुन role बाट खोल्यो भनेर सुरुको tab छान्न
  // (0=Driver, 1=Worker/Handyman, 2=Hotel Provider) — बाँकी दुवै tab पनि
  // यहीँबाट एक-tap मै पुग्न मिल्छ, छुट्टै screen खोल्नु पर्दैन।
  final int initialTabIndex;
  const AdminDashboardScreen({super.key, this.initialTabIndex = 0});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  static const _tabs = [
    _RoleTab(label: 'ड्राइभर', icon: Icons.local_taxi_rounded),
    _RoleTab(label: 'कामदार/ह्यान्डिम्यान', icon: Icons.handyman_rounded),
    _RoleTab(label: 'होटल प्रोभाइडर', icon: Icons.apartment_rounded),
    _RoleTab(label: 'All Users', icon: Icons.manage_search_rounded),
    _RoleTab(label: 'Salons', icon: Icons.content_cut_rounded),
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: _tabs.length,
      initialIndex: widget.initialTabIndex.clamp(0, _tabs.length - 1),
      vsync: this,
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AuroraBackground(
      orbs: const [
        KmOrb(Alignment.topRight, AppColors.kmPurple),
        KmOrb(Alignment.bottomLeft, AppColors.kmTeal),
      ],
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Row(
                  children: [
                    GlassIconButton(
                      icon: Icons.arrow_back_rounded,
                      tooltip: 'Back',
                      onTap: () => Navigator.of(context).pop(),
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'Multi-Role Admin Dashboard',
                        style: TextStyle(
                          color: AppColors.kmText,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              // तीनै role बीचको instant single-tap selector — tap गर्नेबित्तिकै
              // सोही screen भित्रै tab बदलिन्छ, कतै Navigator.push हुँदैन,
              // त्यसैले फेरि लगइन/password चाहिँदैन।
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: AppColors.kmSurface.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: AppColors.kmPurple.withValues(alpha: 0.28),
                    ),
                  ),
                  child: TabBar(
                    controller: _tabController,
                    isScrollable: true,
                    tabAlignment: TabAlignment.start,
                    indicator: BoxDecoration(
                      borderRadius: BorderRadius.circular(13),
                      gradient: AppColors.kmCtaGradient,
                    ),
                    indicatorSize: TabBarIndicatorSize.tab,
                    indicatorPadding: const EdgeInsets.symmetric(vertical: 2),
                    splashBorderRadius: BorderRadius.circular(13),
                    labelColor: Colors.white,
                    unselectedLabelColor: AppColors.kmMuted,
                    dividerColor: Colors.transparent,
                    labelStyle: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                    tabs: [
                      for (final t in _tabs)
                        Tab(
                          height: 48,
                          icon: Icon(t.icon, size: 18),
                          text: t.label,
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: const [
                    DriversControlDashboard(),
                    OwnerDashboardScreen(initialTabIndex: 0),
                    HotelAdminControlScreen(),
                    AdminUserDirectoryScreen(),
                    AdminSalonsScreen(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoleTab {
  final String label;
  final IconData icon;
  const _RoleTab({required this.label, required this.icon});
}
