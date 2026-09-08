// app.dart
// एपको root widget: लगइन स्थिति, Admin panel र Role अनुसार सही स्क्रिन देखाउने।
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'app_globals.dart';
import 'auth/phone_landing_page.dart';
import 'auth_page.dart';
import 'employer_registration_page.dart';
import 'role_selection_page.dart';
import 'worker_registration_page.dart';
import 'screens/main_container.dart';
import 'screens/owner_dashboard_screen.dart';
import 'theme/app_theme.dart';
import 'worker_approval_pending_page.dart';

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
          debugShowCheckedModeBanner: false,
          title: 'KaamMitra',
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
          home: StreamBuilder<User?>(
            stream: FirebaseAuth.instance.authStateChanges(),
            builder: (context, snapshot) {
              // १. लगइन छैन: /admin मा भए email login, नत्र Phone landing
              if (!snapshot.hasData) {
                final path =
                    '${Uri.base.path}${Uri.base.fragment}'.toLowerCase();
                if (path.contains('admin')) {
                  return const AuthPage();
                }
                return const PhoneLandingPage();
              }

              final user = snapshot.data;
              String adminEmail = "bikashbhandari1825@gmail.com";

              // एडमिन भए सिधै एडमिन प्यानल देखाउने
              if (user != null && user.email == adminEmail) {
                return Scaffold(
                  appBar: AppBar(
                    title: const Text("KaamMitra - Owner Dashboard"),
                    actions: [
                      IconButton(
                        icon: const Icon(Icons.logout),
                        tooltip: 'लगआउट गर्नुहोस्',
                        onPressed: () async {
                          await FirebaseAuth.instance.signOut();
                        },
                      ),
                    ],
                  ),
                  body: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          "स्वागत छ मालिक! (तपाईंको एडमिन विशेष प्यानल)",
                          style: TextStyle(
                              fontSize: 20, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 20),
                        Expanded(
                          child: GridView.count(
                            crossAxisCount: 2,
                            crossAxisSpacing: 16,
                            mainAxisSpacing: 16,
                            children: [
                              _adminCard(
                                context,
                                title: 'मुख्य एप (Main App) हेर्नुहोस्',
                                icon: Icons.apps,
                                color: Colors.green,
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                        builder: (context) =>
                                            const MainContainer()),
                                  );
                                },
                              ),
                              _adminCard(
                                context,
                                title: 'कामदारहरू म्यानेज गर्ने',
                                icon: Icons.people,
                                color: Colors.blue,
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                        builder: (context) =>
                                            const OwnerDashboardScreen()),
                                  );
                                },
                              ),
                              _adminCard(
                                context,
                                title: 'रिपोर्ट तथा तथ्याङ्क',
                                icon: Icons.bar_chart,
                                color: Colors.orange,
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                        builder: (context) =>
                                            const OwnerDashboardScreen()),
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              } else {
                // साधारण युजरको Role Firestore बाट जाँच्ने
                return FutureBuilder<DocumentSnapshot>(
                  future: FirebaseFirestore.instance
                      .collection('users')
                      .doc(user!.uid)
                      .get(),
                  builder: (context, roleSnapshot) {
                    if (roleSnapshot.connectionState ==
                        ConnectionState.waiting) {
                      return const Scaffold(
                        body: Center(child: CircularProgressIndicator()),
                      );
                    }

                    final userData =
                        roleSnapshot.data?.data() as Map<String, dynamic>? ??
                            {};

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
                                    await FirebaseAuth.instance.signOut();
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
                      // दर्ता अधूरो, वा कागजात rejected → फेरि upload गर्न
                      if (!profileComplete || vStatus == 'rejected') {
                        return const WorkerRegistrationPage();
                      }
                      if (vStatus != 'approved') {
                        return const WorkerApprovalPendingPage();
                      }
                    }

                    return const MainContainer();
                  },
                );
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

// Admin panel मा देखिने प्रत्येक कार्ड बनाउने सानो helper widget
Widget _adminCard(BuildContext context,
    {required String title,
    required IconData icon,
    required Color color,
    required VoidCallback onTap}) {
  return Card(
    elevation: 4,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 48, color: color),
            const SizedBox(height: 12),
            Text(title,
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    ),
  );
}
