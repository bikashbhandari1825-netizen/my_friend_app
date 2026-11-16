// screens/handyman_categories_screen.dart
// होम स्क्रिनको मुख्य ग्रिडको "Handyman" कार्ड थिचेपछि खुल्ने उप-पेज —
// Plumber/Electrician/Mechanic/... जस्ता trade-category छान्ने ग्रिड। हरेक
// category थिच्दा त्यही सेवामा पहिल्यै फिल्टर भएर `NearbyScreen` (provider
// directory, rating/price/दूरी सहित) खुल्छ — home_screen.dart कै पुरानो
// `_openServiceCategory` ले गर्थ्यो त्यही नेभिगेसन, अब यहाँ।
import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../widgets/glass_ui.dart';
import 'nearby_common.dart';
import 'nearby_screen.dart';

class HandymanCategoriesScreen extends StatelessWidget {
  const HandymanCategoriesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AuroraBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                child: KmScreenHeader(title: S.handymanCategoriesTitle),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
                  child: GridView.count(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisCount: 3,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: 0.95,
                    children: [
                      for (final s in serviceFilters)
                        if ((s['name'] as String) != 'Driver')
                          ServiceGridCard(
                            name: s['name'] as String,
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => NearbyScreen(
                                    initialFilter: s['name'] as String),
                              ),
                            ),
                          ),
                    ],
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
