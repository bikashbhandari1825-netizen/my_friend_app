// services/device_integrity_service.dart
//
// Root (Android)/jailbreak (iOS) भएको फोनमा एपको आफ्नै sandbox सुरक्षा
// भरपर्दो हुँदैन — अर्को app ले यो app को memory/local storage/Firebase
// Auth session समेत पढ्न सक्छ। यहाँ कडा (हार्ड-ब्लक, एप नै नचल्ने) होइन,
// बरु प्रस्ट चेतावनी मात्र राखिएको — किनकि Nepal जस्तो बजारमा धेरै
// प्रयोगकर्ताको फोन (पुरानो/custom ROM, वास्तविक दुर्भावनापूर्ण कारणले
// होइन) पहिल्यैदेखि root भएको हुनसक्छ, र root-detection आफैं पनि कहिलेकाहीं
// false-positive दिन सक्छ। हार्ड-ब्लक गरे साँच्चै वैध ग्राहक/कामदार नै
// गुम्न सक्छन्। warning ले जोखिम प्रस्ट देखाउँछ, तर "बुझेँ, जारी राख्नुहोस्"
// भनेर आफ्नै जोखिममा अगाडि बढ्न दिन्छ।
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:safe_device/safe_device.dart';

import '../l10n/strings.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_ui.dart';

class DeviceIntegrityService {
  DeviceIntegrityService._();

  static bool _warned = false;

  /// App startup मा एकपटक — root/jailbreak भेटिए चेतावनी देखाउने।
  /// `main.dart` कै AppUpdateService.checkForUpdate जस्तै ढाँचा (केही
  /// सेकेन्ड पर्खेर, ताकि सुरुवाती route/auth cascade सँग collide नहोस्)।
  static Future<void> checkOnce(BuildContext context) async {
    // Web मा "root/jailbreak" भन्ने अवधारणा नै लागू हुँदैन (यो त कुनै पनि
    // ब्राउजरमा चल्ने website हो), र `safe_device` package को वेबको लागि
    // कुनै platform implementation नै छैन — बोलाउनासाथ (`init` channel-कल
    // fire-and-forget भएकोले) uncaught `MissingPluginException` कन्सोलमा
    // देखिन्थ्यो। त्यसैले वेबमा यो जाँच सुरुमै छोड्ने।
    if (kIsWeb || _warned) return;
    bool compromised;
    try {
      compromised = await SafeDevice.isJailBroken;
    } catch (_) {
      // plugin नै असफल भए (unsupported platform/emulator) — चुपचाप बेवास्ता,
      // कुनै हालतमा यसले सामान्य app चलाइ रोक्दैन।
      return;
    }
    if (!compromised || !context.mounted) return;
    _warned = true;
    await showKmDialog<void>(
      context: context,
      title: S.deviceIntegrityWarningTitle,
      message: S.deviceIntegrityWarningBody,
      icon: Icons.warning_amber_rounded,
      iconBg: const LinearGradient(colors: [AppColors.danger, AppColors.kmRose]),
      barrierDismissible: false,
      actions: [
        KmDialogAction(
          label: S.deviceIntegrityContinueAnyway,
          filled: true,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}
