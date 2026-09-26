// app.dart
// एपको root widget: लगइन स्थिति, Admin panel र Role अनुसार सही स्क्रिन देखाउने।
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'app_globals.dart';
import 'auth/dev_login.dart';
import 'config/app_config.dart' show kAdminEmail;
import 'driver_registration_flow.dart';
import 'employer_registration_page.dart';
import 'onboarding/onboarding_gate.dart';
import 'role_selection_page.dart';
import 'worker_registration_page.dart';
import 'screens/main_container.dart';
import 'screens/owner_dashboard_screen.dart';
import 'screens/worker_approved_celebration.dart';
import 'theme/app_theme.dart';
import 'widgets/glass_ui.dart';
import 'widgets/offline_banner.dart';
import 'worker_approval_pending_page.dart';

// एकपटक मात्र सिर्जना हुने, cache भएको auth stream — root StreamBuilder ले
// यही एउटै instance सधैँ प्रयोग गरोस् भनेर। `FirebaseAuth.instance.
// authStateChanges()` ले हरेक call मा फेरि-map गरिएको नयाँ Stream object
// फर्काउँछ (उही underlying auth state भए पनि); त्यो सिधै `build()` भित्रै
// (जस्तै अघि `StreamBuilder(stream: FirebaseAuth.instance.
// authStateChanges(), ...)` गरेर) बोलाइयो भने, KaamMitraApp जहिले पनि
// पुनः-build हुँदा (जस्तै themeNotifier/localeNotifier बदलिँदा, Prefs.load()
// पछि सुरुमै एकपटक हुने जस्तो) StreamBuilder ले पुरानो stream identity फरक
// भेट्छ र नयाँ subscription सुरु गर्छ — जसले snapshot लाई तुरुन्तै
// "no data" मा रिसेट गर्छ। यो नयाँ subscription ले हालको (पहिल्यै signed-in)
// user लाई फेरि replay गर्दैन — साँच्चै अर्को auth event नआएसम्म पर्खिरहन्छ,
// जुन कहिल्यै नआउन सक्छ। नतिजा: user साँच्चै signed-in भइरहे पनि app
// अनिश्चित कालसम्म PhoneLandingPage (welcome screen) मै अड्किन्छ — ठ्याक्कै
// यही थियो Android मा "login पछि केही सेकेन्डमा welcome screen मा फर्कने"
// बगको साँचो जड। Stream एकपटक मात्र (module load मा) बनाएर सधैँ उही
// instance प्रयोग गरे यो समस्या पूर्ण रूपमा हट्छ।
final Stream<User?> _authStateStream = FirebaseAuth.instance.authStateChanges();

class KaamMitraApp extends StatelessWidget {
  const KaamMitraApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeNotifier,
      builder: (context, currentMode, _) {
        return ValueListenableBuilder<Locale>(
          valueListenable: localeNotifier,
          builder: (context, currentLocale, __) {
            return MaterialApp(
              navigatorKey: rootNavigatorKey,
              debugShowCheckedModeBanner: false,
              title: 'सहयात्री',
              theme: AppTheme.light,
              darkTheme: AppTheme.dark,
              themeMode: currentMode,
              locale: currentLocale,
              supportedLocales: const [Locale('en'), Locale('ne')],
              localizationsDelegates: const [
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              // हरेक स्क्रिनमाथि साझा "अफलाइन" ब्यानर — एकैचोटि यहीँ जडान
              // गरेर, कुनै पनि individual screen ले छुट्टै थप्नु नपरोस्।
              builder: (context, child) =>
                  OfflineBannerOverlay(child: child ?? const SizedBox.shrink()),
              home: StreamBuilder<User?>(
                stream: _authStateStream,
                builder: (context, snapshot) {
                  // १. लगइन छैन — सधैँ सामान्य Phone landing। Admin पहुँच
                  // पूर्ण रूपमा गुप्त छ (कुनै URL/search-bar सर्टकट होइन) —
                  // हेर्नुहोस् auth/admin_gate_page.dart।
                  if (!snapshot.hasData) {
                    return const OnboardingGate();
                  }

                  final user = snapshot.data;

                  // एडमिन भए सिधै एडमिन प्यानल देखाउने
                  if (user != null && user.email == kAdminEmail) {
                    return AuroraBackground(
                      orbs: const [
                        KmOrb(Alignment.topRight, AppColors.kmPurple),
                        KmOrb(Alignment.bottomLeft, AppColors.kmOrangeDeep),
                      ],
                      child: Scaffold(
                        backgroundColor: Colors.transparent,
                        body: SafeArea(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text('सहयात्री - Owner Dashboard',
                                          style: const TextStyle(
                                              color: AppColors.kmText,
                                              fontSize: 21,
                                              fontWeight: FontWeight.w700)),
                                    ),
                                    GlassIconButton(
                                      icon: Icons.logout_rounded,
                                      tooltip: 'लगआउट गर्नुहोस्',
                                      onTap: () async {
                                        await signOutClean();
                                      },
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 20),
                                const Text(
                                  "स्वागत छ मालिक!",
                                  style: TextStyle(
                                      color: AppColors.kmText,
                                      fontSize: 22,
                                      fontWeight: FontWeight.w800),
                                ),
                                const SizedBox(height: 4),
                                const Text(
                                  "तपाईंको एडमिन विशेष प्यानल",
                                  style: TextStyle(
                                      color: AppColors.kmMuted, fontSize: 13.5),
                                ),
                                const SizedBox(height: 20),
                                Expanded(
                                  child: GridView.count(
                                    crossAxisCount: 2,
                                    crossAxisSpacing: 14,
                                    mainAxisSpacing: 14,
                                    childAspectRatio: 0.98,
                                    children: [
                                      _AdminCard(
                                        title: 'मुख्य एप',
                                        subtitle: 'Main App हेर्नुहोस्',
                                        icon: Icons.apps_rounded,
                                        gradient: const LinearGradient(
                                            colors: [
                                              AppColors.kmPurple,
                                              AppColors.kmPurpleDeep
                                            ]),
                                        onTap: () => Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                              builder: (context) =>
                                                  const MainContainer()),
                                        ),
                                      ),
                                      _AdminCard(
                                        title: 'कामदार म्यानेज',
                                        subtitle: 'Verification/approval',
                                        icon: Icons.people_alt_rounded,
                                        gradient: const LinearGradient(
                                            colors: [
                                              AppColors.kmPink,
                                              AppColors.kmPinkDeep
                                            ]),
                                        // बाँकी रहेको (pending) verification count
                                        // — लगइन गर्नेबित्तिकै कति काम बाँकी छ
                                        // भनेर तुरुन्तै थाहा।
                                        countStream: FirebaseFirestore.instance
                                            .collection('pendingWorkers')
                                            .where('status', isEqualTo: 'pending')
                                            .snapshots()
                                            .map((s) => s.docs.length),
                                        onTap: () => Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                              builder: (context) =>
                                                  const OwnerDashboardScreen(
                                                      initialTabIndex: 0)),
                                        ),
                                      ),
                                      _AdminCard(
                                        title: 'ड्राइभर नियन्त्रण ड्यासबोर्ड',
                                        subtitle: 'Drivers Control Dashboard',
                                        icon: Icons.local_taxi_rounded,
                                        gradient: const LinearGradient(
                                            colors: [
                                              AppColors.kmOrange,
                                              AppColors.kmOrangeDeep
                                            ]),
                                        // कति driver को verification अझै pending
                                        // छ — त्यही यो dashboard भित्रैको सबैभन्दा
                                        // पहिला गर्नुपर्ने काम हो।
                                        countStream: FirebaseFirestore.instance
                                            .collection('users')
                                            .where('service',
                                                whereIn: ['Bike', 'Car'])
                                            .snapshots()
                                            .map((s) => s.docs.where((d) {
                                                  final data = d.data();
                                                  final vs = (data[
                                                              'verificationStatus'] ??
                                                          data['workerVerificationStatus'] ??
                                                          'pending')
                                                      .toString();
                                                  return vs == 'pending';
                                                }).length),
                                        onTap: () => Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                              builder: (context) =>
                                                  const DriversControlDashboard()),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  } else {
                    // साधारण युजर — users doc लाई LIVE सुन्ने (loop नहोस् भनेर)।
                    // Form submit वा admin approval हुँदा gate आफै अर्को screen मा जान्छ।
                    return _UserGate(uid: user!.uid);
                  }
                },
              ),
            );
          },
        );
      },
    );
  }
}

/// `KaamMitraApp`'s साधारण-युजर gate — `users/{uid}` को live Firestore
/// listener राख्छ। यो छुट्टै StatefulWidget किन: माथिको outer
/// `StreamBuilder<User?>` जहिले पनि (theme/locale बदलिँदा, वा कुनै पनि auth
/// event आउँदा) rebuild हुन्छ, र त्यसले तल्लो सबै widget subtree लाई पनि
/// फेरि build गराउँछ। पहिले यहाँ inline `.snapshots()` कल गरिएको थियो —
/// `.snapshots()` ले हरेक कल मा नयाँ Stream object फर्काउने भएकोले,
/// `StreamBuilder` ले हरेक ancestor rebuild मा (widget.stream बदलिएको भेटेर)
/// पुरानो subscription फालेर नयाँ सुरु गर्थ्यो — जसले क्षणिक रूपमा snapshot
/// लाई "waiting/no data" मा रिसेट गर्थ्यो (लोडिङ स्पिनर flash, र sign-in
/// जस्तो धेरै rebuild हुने संवेदनशील क्षणमा UI अस्थिर देखिने)। ठ्याक्कै यही
/// समस्या माथिको auth-level stream मा पनि थियो (`_authStateStream` module-
/// level cache हेर्नुहोस्) — यहाँ पनि उही समाधान: stream लाई `initState`
/// मा एकपटक मात्र बनाएर State भित्रै (widget rebuild भन्दा बाँचेर) राख्ने।
class _UserGate extends StatefulWidget {
  final String uid;
  const _UserGate({required this.uid});

  @override
  State<_UserGate> createState() => _UserGateState();
}

class _UserGateState extends State<_UserGate> {
  late Stream<DocumentSnapshot<Map<String, dynamic>>> _userStream;

  @override
  void initState() {
    super.initState();
    _subscribe();
  }

  @override
  void didUpdateWidget(covariant _UserGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    // सामान्यतया uid कहिल्यै बदलिँदैन (नयाँ uid = नयाँ sign-in = यो widget
    // नै पूरै अर्को इन्स्टेन्स), तर defensively: बदलिए मात्र फेरि subscribe।
    if (oldWidget.uid != widget.uid) _subscribe();
  }

  void _subscribe() {
    _userStream = FirebaseFirestore.instance
        .collection('users')
        .doc(widget.uid)
        .snapshots();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _userStream,
      builder: (context, roleSnapshot) {
        if (roleSnapshot.connectionState == ConnectionState.waiting &&
            !roleSnapshot.hasData) {
                          return const Scaffold(
                            body: Center(child: CircularProgressIndicator()),
                          );
                        }

                        // ROBUSTNESS FIX: पहिले यहाँ Firestore listener कै
                        // त्रुटि (permission-denied, offline+no-cache, आदि)
                        // कहिल्यै जाँचिँदैनथ्यो — त्यसैले error आउनेबित्तिकै
                        // `roleSnapshot.data` सधैँ null भई तल्लो कोडले खाली
                        // `{}` मान्थ्यो, अनि पहिल्यै role भइसकेको (existing)
                        // worker/employer समेतलाई नयाँ प्रयोगकर्ता झैँ
                        // RoleSelectionPage देखाइदिन्थ्यो — गलत स्क्रिन/loop
                        // जस्तो देखिने अर्को सम्भावित कारण। अब यहाँ स्पष्ट
                        // retry UI (silent misroute होइन)।
                        if (roleSnapshot.hasError && !roleSnapshot.hasData) {
                          return Scaffold(
                            body: Center(
                              child: Padding(
                                padding: const EdgeInsets.all(24),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.cloud_off_rounded,
                                        size: 48, color: Colors.white70),
                                    const SizedBox(height: 16),
                                    const Text(
                                      'डाटा लोड गर्न सकिएन — इन्टरनेट जाँच्नुहोस्।\nCould not load your account — check your connection.',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(color: Colors.white),
                                    ),
                                    const SizedBox(height: 16),
                                    ElevatedButton.icon(
                                      onPressed: () =>
                                          setState(() => _subscribe()),
                                      icon: const Icon(Icons.refresh_rounded),
                                      label: const Text('फेरि प्रयास गर्नुहोस्'),
                                    ),
                                    const SizedBox(height: 8),
                                    TextButton(
                                      onPressed: () async {
                                        await signOutClean();
                                      },
                                      child: const Text('Logout',
                                          style:
                                              TextStyle(color: Colors.white70)),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        }

                        final userData = roleSnapshot.data?.data() ?? {};
                        final accountStatus = userData['accountStatus'];
                        if (accountStatus == 'suspended' ||
                            accountStatus == 'blocked') {
                          return Scaffold(
                            backgroundColor: Colors.red.shade700,
                            body: Center(
                              child: Padding(
                                padding: const EdgeInsets.all(24.0),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(Icons.block,
                                        size: 80, color: Colors.white),
                                    const SizedBox(height: 20),
                                    Text(
                                      accountStatus == 'blocked'
                                          ? 'तपाईंको Account Block गरिएको छ'
                                          : 'तपाईंको Account निलम्बित गरिएको छ',
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 20,
                                          fontWeight: FontWeight.bold),
                                    ),
                                    const SizedBox(height: 12),
                                    const Text(
                                      'थप जानकारीको लागि Admin लाई सम्पर्क गर्नुहोस्।',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(color: Colors.white70),
                                    ),
                                    const SizedBox(height: 24),
                                    ElevatedButton(
                                      onPressed: () async {
                                        await signOutClean();
                                      },
                                      style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.white),
                                      child: const Text('Logout',
                                          style: TextStyle(color: Colors.red)),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        }

                        final role = userData['role'];
                        final profileComplete =
                            userData['profileComplete'] == true;

                        if (role == null) {
                          return const RoleSelectionPage();
                        }

                        if (role == 'employer' && !profileComplete) {
                          return const EmployerRegistrationPage();
                        }

                        if (role == 'worker') {
                          final vStatus = (userData['verificationStatus'] ??
                                  userData['workerVerificationStatus'])
                              ?.toString();
                          // दर्ता अधूरो, वा कागजात rejected → फेरि upload गर्न।
                          // पहिले Driver (Bike/Car, वा अझै नछानिएको 'Driver'
                          // placeholder -- Role Selection बाट भर्खरै आएको तर
                          // फारमको step 1 नपुगिकनै यो gate ले race जितेको
                          // अवस्था) को रूपमा दर्ता भएको थियो भने फेरि पनि
                          // Driver मोडमै खोल्ने — नत्र 'Driver' अब सामान्य
                          // dropdown मा नभएकोले फेरि छान्नै नमिल्ने हुन्थ्यो।
                          if (!profileComplete || vStatus == 'rejected') {
                            final existingService =
                                userData['service']?.toString();
                            final wasDriver = existingService == 'Bike' ||
                                existingService == 'Car' ||
                                existingService == 'Driver';
                            return wasDriver
                                ? const DriverRegistrationFlow()
                                : const WorkerRegistrationPage();
                          }
                          if (vStatus != 'approved') {
                            return const WorkerApprovalPendingPage();
                          }
                          // भर्खरै approved भयो — एकपटक celebration देखाउने।
                          final approvedAt = userData['approvedAt'];
                          final justApproved = approvedAt is Timestamp &&
                              DateTime.now()
                                      .difference(approvedAt.toDate())
                                      .inSeconds <
                                  25;
                          if (justApproved &&
                              !celebrationShownFor.contains(widget.uid)) {
                            celebrationShownFor.add(widget.uid);
                            return const WorkerApprovedCelebration();
                          }
                        }

                        return const MainContainer();
                      },
                    );
  }
}

/// Admin home (3-card) मा देखिने प्रत्येक कार्ड — modern gradient icon
/// badge + subtitle + (भए) live count badge (जस्तै "३ बाँकी")।
class _AdminCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Gradient gradient;
  final VoidCallback onTap;
  final Stream<int>? countStream;

  const _AdminCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.gradient,
    required this.onTap,
    this.countStream,
  });

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      radius: 18,
      padding: const EdgeInsets.fromLTRB(14, 16, 14, 14),
      onTap: onTap,
      child: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  gradient: gradient,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: AppColors.kmInk, size: 26),
              ),
              const SizedBox(height: 14),
              Text(title,
                  style: const TextStyle(
                      color: AppColors.kmText,
                      fontWeight: FontWeight.w800,
                      fontSize: 15)),
              const SizedBox(height: 2),
              Text(subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 11.5, color: AppColors.kmMuted)),
            ],
          ),
          if (countStream != null)
            Positioned(
              top: 0,
              right: 0,
              child: StreamBuilder<int>(
                stream: countStream,
                builder: (context, snap) {
                  final n = snap.data ?? 0;
                  if (n <= 0) return const SizedBox.shrink();
                  return Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.kmRose,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      n > 99 ? '99+' : '$n',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w800),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
