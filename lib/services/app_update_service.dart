// services/app_update_service.dart
// In-app auto-update checker (Android APK, sideloaded testers) — app
// startup मा `config/appUpdate` (Firestore, हेर्नुहोस् config/app_config.dart
// कै AppUpdateConfig) पढेर हालको installed versionCode सँग तुलना गर्छ। नयाँ
// भेटिए full-screen-style dialog देखिन्छ — "Update Now" थिचेपछि APK सिधै
// यही एप भित्रै download हुन्छ (progress देखाउँदै), अनि Android को system
// package installer (`open_filex`, आफ्नै FileProvider सहित) मार्फत install
// intent ट्रिगर हुन्छ। यसरी testerहरूले हरेक पटक `flutter install`/manual
// APK sideload नगरी सिधै एप भित्रैबाट अपडेट गर्न सक्छन्।
//
// Android-मात्र — web/iOS मा यो सम्भवै छैन (web को "installed version"
// भन्ने हुँदैन, iOS ले App Store बाहिरको self-install अनुमति दिँदैन), त्यसैले
// [checkForUpdate] अरू platform मा तुरुन्तै चुपचाप फर्कन्छ।
import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import '../config/app_config.dart';
import '../l10n/strings.dart';
import '../theme/app_theme.dart';

class AppUpdateService {
  AppUpdateService._();

  /// app startup मा एकपटक बोलाउने (हेर्नुहोस् `main.dart`)। नेटवर्क/Firestore
  /// असफल भए पनि चुपचाप फर्कन्छ — update-check ले कहिल्यै सामान्य app चलाइ
  /// रोक्नु/तोड्नु हुँदैन।
  static Future<void> checkForUpdate(BuildContext context) async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      final data = await AppUpdateConfig.readOnce();
      if (data == null) return;
      final latestCode = (data['latestVersionCode'] as num?)?.toInt() ?? 0;
      final apkUrl = (data['apkUrl'] ?? '').toString().trim();
      if (latestCode <= 0 || apkUrl.isEmpty) return;

      final info = await PackageInfo.fromPlatform();
      final currentCode = int.tryParse(info.buildNumber) ?? 0;
      if (latestCode <= currentCode) return;

      if (!context.mounted) return;
      await _showUpdateDialog(
        context,
        apkUrl: apkUrl,
        versionName: (data['versionName'] ?? '').toString(),
        releaseNotes: (data['releaseNotes'] ?? '').toString(),
        forceUpdate: data['forceUpdate'] == true,
      );
    } catch (_) {
      // silent — network/permission जे भए पनि app सामान्य रूपमै चलिरहोस्।
    }
  }

  static Future<void> _showUpdateDialog(
    BuildContext context, {
    required String apkUrl,
    required String versionName,
    required String releaseNotes,
    required bool forceUpdate,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: !forceUpdate,
      builder: (dialogContext) => PopScope(
        canPop: !forceUpdate,
        child: AlertDialog(
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.lg)),
          title: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: const BoxDecoration(
                  gradient: AppColors.buttonGradient,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: const Icon(Icons.system_update_rounded,
                    color: Colors.white, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                  child: Text(S.updateAvailableTitle,
                      style: const TextStyle(fontSize: 17))),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(S.updateAvailableBody(versionName)),
              if (releaseNotes.trim().isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.igViolet.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                  child: Text(releaseNotes,
                      style: const TextStyle(fontSize: 12.5, height: 1.4)),
                ),
              ],
            ],
          ),
          actions: [
            if (!forceUpdate)
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: Text(S.updateLater),
              ),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.igViolet,
                  foregroundColor: Colors.white),
              onPressed: () {
                Navigator.pop(dialogContext);
                _downloadAndInstall(context, apkUrl);
              },
              icon: const Icon(Icons.download_rounded, size: 18),
              label: Text(S.updateNow),
            ),
          ],
        ),
      ),
    );
  }

  static Future<void> _downloadAndInstall(
      BuildContext context, String apkUrl) async {
    final progress = ValueNotifier<double?>(0);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: AlertDialog(
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.lg)),
          content: Row(
            children: [
              SizedBox(
                width: 22,
                height: 22,
                child: ValueListenableBuilder<double?>(
                  valueListenable: progress,
                  builder: (_, p, __) => CircularProgressIndicator(
                      value: p, strokeWidth: 2.6, color: AppColors.igViolet),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(child: Text(S.downloadingUpdate)),
            ],
          ),
        ),
      ),
    );

    try {
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/kaammitra_update.apk');
      final req = http.Request('GET', Uri.parse(apkUrl));
      final resp = await http.Client().send(req);
      if (resp.statusCode != 200) {
        throw HttpException('HTTP ${resp.statusCode}');
      }
      final total = resp.contentLength ?? 0;
      var received = 0;
      final sink = file.openWrite();
      await resp.stream.listen((chunk) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0) progress.value = received / total;
      }).asFuture<void>();
      await sink.close();

      if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
      await OpenFilex.open(file.path,
          type: 'application/vnd.android.package-archive');
    } catch (_) {
      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(S.updateDownloadFailed)),
        );
      }
    }
  }
}
