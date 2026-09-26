// role_selection_page.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'driver_registration_flow.dart';
import 'employer_registration_page.dart';
import 'onboarding/sahayatri_brand.dart';
import 'theme/app_theme.dart';
import 'widgets/glass_ui.dart';
import 'worker_registration_page.dart';

class RoleSelectionPage extends StatefulWidget {
  const RoleSelectionPage({super.key});

  @override
  State<RoleSelectionPage> createState() => _RoleSelectionPageState();
}

class _RoleSelectionPageState extends State<RoleSelectionPage> {
  bool _isSaving = false;

  Future<void> createAdminNotification(String title, String message) async {
    await FirebaseFirestore.instance.collection('adminNotifications').add({
      'title': title,
      'message': message,
      'timestamp': FieldValue.serverTimestamp(),
      'read': false,
    });
  }

  /// [driverEntry] — "Driver" कार्डबाट आएको हो भने, फारम सिधै Driver मोडमा
  /// खुल्छ (सामान्य "कुन सेवा?" dropdown मा Driver अब छैन — यो नै त्यसको
  /// छुट्टै प्रवेश-बिन्दु हो)। Backend मा भने अझै उही `role: 'worker'` —
  /// Driver पनि functionally एक worker नै हो (उही verification/job-feed/
  /// quota/rating pipeline साझा गर्छ), छुट्टै role infrastructure थपिएको छैन।
  Future<void> _selectRole(String role, {bool driverEntry = false}) async {
    setState(() => _isSaving = true);
    try {
      final user = FirebaseAuth.instance.currentUser!;
      final uid = user.uid;

      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'uid': uid,
        'role': role,
        'email': user.email,
        'phone': user.phoneNumber ?? '',
        'accountStatus': 'active',
        // customer/employer लाई verify चाहिँदैन; provider/worker ले फारम भर्दा 'pending' हुन्छ
        'verificationStatus': 'none',
        'isVerified': false,
        'createdAt': FieldValue.serverTimestamp(),
        // यही लेखाइ (Firestore write) ले तुरुन्तै root (`app.dart`) कै आफ्नै
        // live users/{uid} StreamBuilder लाई पनि ब्युँझाउँछ, जुन यहाँको
        // तल्लो explicit Navigator.pushReplacement सँगै दौडिन्छ (race) —
        // कुन पहिले पुग्छ भन्ने ग्यारेन्टी छैन। दुवैले एउटै टुंगो (driverEntry
        // हो कि होइन) निकालून् भनेर, यो `service: 'Driver'` placeholder पनि
        // यहीँ (उही लेखाइमा) राखिन्छ, ताकि root ले आफैं race जित्दा पनि सही
        // Driver फारम नै देखाओस् (`app.dart` को `wasDriver` जाँच हेर्नुहोस्)।
        // वास्तविक Bike/Car चयन पछि `worker_registration_page.dart`
        // कै `_submit()` ले यो placeholder लाई साँचो मानले overwrite गर्छ।
        if (driverEntry) 'service': 'Driver',
      }, SetOptions(merge: true));

      await createAdminNotification(
        'नयाँ User दर्ता',
        '${FirebaseAuth.instance.currentUser!.email} ले $role को रूपमा दर्ता गर्नुभयो।',
      );

      if (!mounted) return;
      // BUG FIX: पहिले यहाँ `Navigator.pushReplacement` थियो — यसले CURRENT
      // (root gate) route लाई नै हटाएर नयाँ route ले प्रतिस्थापन गर्छ। यो
      // RoleSelectionPage भने app.dart कै root StreamBuilder (`_UserGate`)
      // कै content को रूपमा (कुनै push बाट होइन) देखिएको हुन्छ — त्यसैले त्यो
      // pushReplacement ले वास्तवमा जीवितै रहेको root gate route (auth +
      // users-doc StreamBuilder सहित) लाई नै नष्ट गर्थ्यो, र नयाँ पेजलाई नै
      // एक्लो/पहिलो route बनाइदिन्थ्यो। अनि पछि WorkerRegistrationPage/
      // EmployerRegistrationPage/DriverRegistrationFlow कै `_submit()` ले
      // गर्ने `Navigator.of(context).popUntil((route) => route.isFirst)` ले
      // (root gate route पहिल्यै नष्ट भइसकेकोले) केही pop नै नगर्ने भई
      // उपयोगकर्ता उहीँ फारममा अड्किन्थ्यो/फेरि उहीँ स्क्रिनमा फर्किन्थ्यो —
      // ठ्याक्कै sign-in पछिको "navigation loop" गुनासोको जड। `push` ले भने
      // root gate route लाई तल्लो (जीवितै) राखेर माथि मात्र नयाँ पेज थप्छ,
      // ताकि पछि `popUntil(isFirst)` ले सही तरिकाले गेटमै फर्कोस्।
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => driverEntry
              ? const DriverRegistrationFlow()
              : role == 'worker'
                  ? const WorkerRegistrationPage()
                  : const EmployerRegistrationPage(),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("त्रुटि: $e")),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuroraBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SahayatriLogoMark(size: 84),
                const SizedBox(height: 18),
                const SahayatriWordmark(fontSize: 24),
                const SizedBox(height: 36),
                const Text(
                  'Are you looking to work?\nLooking to hire?',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: AppColors.kmText,
                      fontSize: 20,
                      fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 36),
                if (_isSaving)
                  const CircularProgressIndicator(color: AppColors.kmOrange)
                else ...[
                  _RoleCard(
                    icon: Icons.local_taxi_rounded,
                    title: 'Driver',
                    subtitle: 'गाडी/बाइक चलाउने',
                    onTap: () =>
                        _selectRole('worker', driverEntry: true),
                  ),
                  const SizedBox(height: 14),
                  _RoleCard(
                    icon: Icons.handyman_rounded,
                    title: 'Worker',
                    subtitle: 'काम गर्ने',
                    onTap: () => _selectRole('worker'),
                  ),
                  const SizedBox(height: 14),
                  _RoleCard(
                    icon: Icons.work_rounded,
                    title: 'Employer',
                    subtitle: 'काम गराउने',
                    onTap: () => _selectRole('employer'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RoleCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  const _RoleCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      radius: 18,
      padding: EdgeInsets.zero,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: const BoxDecoration(
                gradient: AppColors.kmCtaGradient,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: AppColors.kmInk, size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          color: AppColors.kmText,
                          fontSize: 17,
                          fontWeight: FontWeight.w800)),
                  Text(subtitle,
                      style: const TextStyle(
                          color: AppColors.kmMuted,
                          fontSize: 13,
                          fontWeight: FontWeight.w600)),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_rounded, color: AppColors.kmOrange),
          ],
        ),
      ),
    );
  }
}
