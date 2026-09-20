// widgets/vehicle_type_picker.dart
// InDrive-Style Ride-Sharing — "Driver" home-tile आफैं कहिल्यै साँचो
// bookable/registrable service होइन। Tap गर्नेबित्तिकै यो sheet देखिन्छ —
// "Bike" वा "Car" मध्ये छानेपछि मात्र त्यो वास्तविक service value बनेर
// (Mechanic/Plumber जस्तै) बाँकी सबै (nearby search, negotiation, tracking,
// call/message) उही एउटै pipeline भित्र बग्छ — छुट्टै booking flow बनाइएको छैन।
import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../theme/app_theme.dart';

/// null फर्कन्छ यदि प्रयोगकर्ताले sheet बन्द गरे (छानेनन् भने)।
Future<String?> showVehicleTypePicker(BuildContext context) {
  return showModalBottomSheet<String>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (_) => const _VehicleTypeSheet(),
  );
}

class _VehicleTypeSheet extends StatelessWidget {
  const _VehicleTypeSheet();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Container(
        margin: const EdgeInsets.all(14),
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 22),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          boxShadow: const [
            BoxShadow(color: Colors.black38, blurRadius: 24),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.dividerColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text(S.selectVehicleType,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontWeight: FontWeight.w800, fontSize: 17)),
            const SizedBox(height: 18),
            Row(
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
          ],
        ),
      ),
    );
  }
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
    final theme = Theme.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 10),
          decoration: BoxDecoration(
            border: Border.all(color: theme.dividerColor),
            borderRadius: BorderRadius.circular(AppRadius.lg),
          ),
          child: Column(
            children: [
              Container(
                width: 58,
                height: 58,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  gradient: AppColors.buttonGradient,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: Colors.white, size: 30),
              ),
              const SizedBox(height: 10),
              Text(label,
                  style:
                      const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
              const SizedBox(height: 2),
              Text(hint,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall),
            ],
          ),
        ),
      ),
    );
  }
}
