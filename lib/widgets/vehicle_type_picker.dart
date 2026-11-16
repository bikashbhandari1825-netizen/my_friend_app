// widgets/vehicle_type_picker.dart
// InDrive-Style Ride-Sharing — "Driver" home-tile आफैं कहिल्यै साँचो
// bookable/registrable service होइन। Tap गर्नेबित्तिकै यो sheet देखिन्छ —
// "Bike" वा "Car" मध्ये छानेपछि मात्र त्यो वास्तविक service value बनेर
// (Mechanic/Plumber जस्तै) बाँकी सबै (nearby search, negotiation, tracking,
// call/message) उही एउटै pipeline भित्र बग्छ — छुट्टै booking flow बनाइएको छैन।
import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../theme/app_theme.dart';
import 'glass_ui.dart';

/// null फर्कन्छ यदि प्रयोगकर्ताले sheet बन्द गरे (छानेनन् भने)।
Future<String?> showVehicleTypePicker(BuildContext context) {
  return showKmSheet<String>(
    context: context,
    title: S.selectVehicleType,
    children: [
      const SizedBox(height: 4),
      Padding(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
        child: Row(
          children: [
            Expanded(
              child: _VehicleOption(
                imagePath: 'assets/images/home_bike.png',
                glow: const Color(0xFF00BCD4),
                label: S.bikeWord,
                hint: S.bikeRideHint,
                onTap: () => Navigator.pop(context, 'Bike'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _VehicleOption(
                imagePath: 'assets/images/home_car.png',
                glow: const Color(0xFF3B82F6),
                label: S.carWord,
                hint: S.carRideHint,
                onTap: () => Navigator.pop(context, 'Car'),
              ),
            ),
          ],
        ),
      ),
    ],
  );
}

class _VehicleOption extends StatelessWidget {
  final String imagePath;
  final Color glow;
  final String label;
  final String hint;
  final VoidCallback onTap;
  const _VehicleOption({
    required this.imagePath,
    required this.glow,
    required this.label,
    required this.hint,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      radius: AppRadius.lg,
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 10),
      onTap: onTap,
      child: Column(
        children: [
          // Home screen कै उस्तै neon illustration (home_screen.dart::
          // _NeonServiceTile::_buildImageTile) — ती तस्बिरको आफ्नै गाढा/
          // कालो backdrop छ, पुरानो सेतो स्टुडियो-फोटो (bike_ride.png/
          // car_ride.png) सँग मिल्ने हल्का खरानी (kmVehiclePhotoBg) अब
          // बेमेल हुन्थ्यो — त्यसैले त्यो ठोस भरण हटाएर home tile कै
          // brand-रङको glow shadow मात्र, पृष्ठभूमि transparent।
          Container(
            height: 84,
            width: double.infinity,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.lg - 6),
              boxShadow: [
                BoxShadow(
                    color: glow.withValues(alpha: 0.45),
                    blurRadius: 16,
                    spreadRadius: 0.5),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: Image.asset(imagePath, fit: BoxFit.contain),
          ),
          const SizedBox(height: 10),
          Text(label,
              style: const TextStyle(
                  color: AppColors.kmText,
                  fontWeight: FontWeight.w800,
                  fontSize: 15)),
          const SizedBox(height: 2),
          Text(hint,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.kmMuted, fontSize: 12)),
        ],
      ),
    );
  }
}
