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
                icon: Icons.two_wheeler_rounded,
                label: S.bikeWord,
                hint: S.bikeRideHint,
                onTap: () => Navigator.pop(context, 'Bike'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _VehicleOption(
                icon: Icons.local_taxi_rounded,
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
  final IconData icon;
  final String label;
  final String hint;
  final VoidCallback onTap;
  const _VehicleOption({
    required this.icon,
    required this.label,
    required this.hint,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      radius: AppRadius.lg,
      padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 10),
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 58,
            height: 58,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              gradient: AppColors.kmCtaGradient,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: AppColors.kmInk, size: 30),
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
