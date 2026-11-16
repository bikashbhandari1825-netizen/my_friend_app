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

import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:flutter/material.dart';
import 'package:crypto/crypto.dart' show sha256;
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import '../config/app_config.dart';
import '../l10n/strings.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_ui.dart';

/// Release-notes body भित्र देखिने पाठ यति लामोसम्म मात्र — असीमित लामो/
/// malformed string ले dialog को layout (Column/RenderFlex) लाई कहिल्यै
/// bound-नभएको ठाउँमा धकेल्न नपाओस् भनेर (हेर्नुहोस् `_showUpdateDialog` कै
/// `ConstrainedBox` + `SingleChildScrollView` पनि, यो त्यही सुरक्षाको
/// अर्को तह मात्र हो)।
const int _kMaxReleaseNotesChars = 600;

class AppUpdateService {
  AppUpdateService._();

  /// app startup मा एकपटक बोलाउने (हेर्नुहोस् `main.dart`)। नेटवर्क/Firestore
  /// असफल भए पनि, वा Firestore मा भएको metadata (`apkUrl`, version fields)
  /// नमिलेको/खाली/malformed भए पनि — यहाँबाट कहिल्यै exception बाहिर
  /// निस्कँदैन र कुनै हालतमा सामान्य app चलाइ रोक्दैन/तोड्दैन। यो function
  /// आफैं `main.dart` बाट (auth/role resolve हुने अस्थिर सुरुवाती केही
  /// सेकेन्ड बितिसकेपछि मात्र) बोलाइन्छ — त्यो अवधिमा नै dialog देखाउँदा
  /// route/StreamBuilder transition सँग collide भएर black/खाली screen
  /// देखिने गुनासोको मूल कारण देखिएको थियो।
  static Future<void> checkForUpdate(BuildContext context) async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      final data = await AppUpdateConfig.readOnce();
      if (data == null) return;

      final latestCode = (data['latestVersionCode'] as num?)?.toInt() ?? 0;
      final apkUrlRaw = (data['apkUrl'] ?? '').toString().trim();
      // `http.get`/`open_filex` लाई पठाउनुअघि नै URL साँच्चै मान्य (scheme
      // भएको) हो कि जाँच्ने — Firestore मा गलत/खाली/relative-path जस्तो
      // string भेटिए dialog नै नदेखाउने, बरु बाँकी app सामान्य रूपमा चलोस्।
      final apkUri = Uri.tryParse(apkUrlRaw);
      if (latestCode <= 0 ||
          apkUrlRaw.isEmpty ||
          apkUri == null ||
          !apkUri.hasScheme) {
        return;
      }
      // सुरक्षा — APK केवल HTTPS र भरपर्दो Google Storage होस्टबाट, र admin ले
      // `apkSha256` (64-hex) दिएको हुनैपर्छ; नत्र (admin खाता कब्जा वा गलत
      // लिङ्कले) अर्को/नक्कली APK install गराउन नसकियोस्।
      final apkSha256 = (data['apkSha256'] ?? '').toString().trim().toLowerCase();
      if (!_isTrustedApkUri(apkUri) ||
          !RegExp(r'^[0-9a-f]{64}$').hasMatch(apkSha256)) {
        debugPrint('AppUpdateService: APK URL/hash not trusted — update ignored.');
        return;
      }

      final info = await PackageInfo.fromPlatform();
      final currentCode = int.tryParse(info.buildNumber) ?? 0;
      if (latestCode <= currentCode) return;

      var releaseNotes = (data['releaseNotes'] ?? '').toString().trim();
      if (releaseNotes.length > _kMaxReleaseNotesChars) {
        releaseNotes = '${releaseNotes.substring(0, _kMaxReleaseNotesChars)}…';
      }
      final versionName = (data['versionName'] ?? '').toString().trim();
      final forceUpdate = data['forceUpdate'] == true;

      if (!context.mounted) return;
      await _showUpdateDialog(
        context,
        apkUrl: apkUrlRaw,
        apkSha256: apkSha256,
        versionName: versionName,
        releaseNotes: releaseNotes,
        forceUpdate: forceUpdate,
      );
    } catch (e, st) {
      // silent to the user — network/permission/parse जे भए पनि app सामान्य
      // रूपमै चलिरहोस्; debug console मा मात्र देखिने ताकि पूर्ण रूपमा
      // silent (डिबग गर्नै नसकिने) नहोस्।
      debugPrint('AppUpdateService.checkForUpdate failed: $e\n$st');
    }
  }

  static Future<void> _showUpdateDialog(
    BuildContext context, {
    required String apkUrl,
    required String apkSha256,
    required String versionName,
    required String releaseNotes,
    required bool forceUpdate,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: !forceUpdate,
      barrierColor: Colors.black.withValues(alpha: 0.6),
      builder: (dialogContext) => PopScope(
        canPop: !forceUpdate,
        child: Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 28),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(26),
            child: glassBackdrop(sigma: 26, child: Container(
                padding: const EdgeInsets.fromLTRB(22, 24, 22, 16),
                decoration: BoxDecoration(
                  color: AppColors.kmSurface.withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(26),
                  border: Border.all(color: AppColors.kmGlassBorder),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withValues(alpha: 0.45),
                        blurRadius: 30,
                        offset: const Offset(0, 14)),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: const BoxDecoration(
                            gradient: AppColors.kmCtaGradient,
                            shape: BoxShape.circle,
                          ),
                          alignment: Alignment.center,
                          child: const Icon(Icons.system_update_rounded,
                              color: AppColors.kmInk, size: 22),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                            child: Text(S.updateAvailableTitle,
                                style: const TextStyle(
                                    color: AppColors.kmText,
                                    fontSize: 17,
                                    fontWeight: FontWeight.w700))),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // असीमित लामो release notes (वा अन्य malformed पाठ) ले यो
                    // dialog लाई screen भन्दा अग्लो बनाई layout नै तोड्न नपाओस्
                    // भनेर — bounded height भित्रै, चाहिए scroll हुने गरी।
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight:
                            MediaQuery.of(dialogContext).size.height * 0.6,
                      ),
                      child: SingleChildScrollView(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(S.updateAvailableBody(versionName),
                                style:
                                    const TextStyle(color: AppColors.kmMuted)),
                            if (releaseNotes.trim().isNotEmpty) ...[
                              const SizedBox(height: 12),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.06),
                                  borderRadius:
                                      BorderRadius.circular(AppRadius.md),
                                  border: Border.all(
                                      color: AppColors.kmGlassBorder),
                                ),
                                child: Text(releaseNotes,
                                    style: const TextStyle(
                                        color: AppColors.kmText,
                                        fontSize: 12.5,
                                        height: 1.4)),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        if (!forceUpdate) ...[
                          KmDialogAction(
                            label: S.updateLater,
                            onPressed: () => Navigator.pop(dialogContext),
                          ),
                          const SizedBox(width: 8),
                        ],
                        DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: AppColors.kmCtaGradient,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Material(
                            type: MaterialType.transparency,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(999),
                              onTap: () {
                                Navigator.pop(dialogContext);
                                _downloadAndInstall(context, apkUrl, apkSha256);
                              },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 18, vertical: 10),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.download_rounded,
                                        size: 18, color: AppColors.kmInk),
                                    const SizedBox(width: 6),
                                    Text(S.updateNow,
                                        style: const TextStyle(
                                            color: AppColors.kmInk,
                                            fontWeight: FontWeight.w700)),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// केवल HTTPS + Google Cloud/Firebase Storage होस्ट।
  static bool _isTrustedApkUri(Uri u) =>
      u.scheme == 'https' &&
      (u.host == 'firebasestorage.googleapis.com' ||
          u.host == 'storage.googleapis.com');

  static Future<void> _downloadAndInstall(
      BuildContext context, String apkUrl, String expectedSha256) async {
    if (!context.mounted) return;
    final progress = ValueNotifier<double?>(0);
    showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.6),
      builder: (_) => PopScope(
        canPop: false,
        child: Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 28),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(26),
            child: glassBackdrop(sigma: 26, child: Container(
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  color: AppColors.kmSurface.withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(26),
                  border: Border.all(color: AppColors.kmGlassBorder),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withValues(alpha: 0.45),
                        blurRadius: 30,
                        offset: const Offset(0, 14)),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 22,
                      height: 22,
                      child: ValueListenableBuilder<double?>(
                        valueListenable: progress,
                        builder: (_, p, __) => CircularProgressIndicator(
                            value: p,
                            strokeWidth: 2.6,
                            color: AppColors.kmOrange),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                        child: Text(S.downloadingUpdate,
                            style:
                                const TextStyle(color: AppColors.kmText))),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );

    try {
      final apkUri = Uri.tryParse(apkUrl);
      if (apkUri == null || !_isTrustedApkUri(apkUri)) {
        throw const FormatException('Invalid APK URL');
      }
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/kaammitra_update.apk');
      final req = http.Request('GET', apkUri);
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

      // अखण्डता — download भएको फाइलको SHA-256 admin ले दिएकोसँग नमिले install
      // नगर्ने (बीचमा बदलिएको/नक्कली APK रोक्न)।
      final digest = (await sha256.bind(file.openRead()).first).toString();
      if (digest != expectedSha256) {
        try {
          await file.delete();
        } catch (_) {}
        throw const FormatException('APK checksum mismatch');
      }

      if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
      final result = await OpenFilex.open(file.path,
          type: 'application/vnd.android.package-archive');
      if (result.type != ResultType.done) {
        debugPrint(
            'AppUpdateService: install intent did not launch cleanly — ${result.type}: ${result.message}');
      }
    } catch (e, st) {
      debugPrint('AppUpdateService.downloadAndInstall failed: $e\n$st');
      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(S.updateDownloadFailed)),
        );
      }
    }
  }
}
