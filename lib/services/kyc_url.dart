// services/kyc_url.dart
//
// KYC कागजात (नागरिकता, लाइसेन्स, गाडी-कागज, होटल दर्ता आदि) को सुरक्षित
// सन्दर्भ। पहिले `getDownloadURL()` को token सहितको URL Firestore (`users`,
// `providers`, `registeredWorkers`, `hotels`) मा राखिन्थ्यो — ती doc सबै
// लग इन युजरले पढ्न मिल्ने भएकोले URL थाहा पाउने जोसुकैले Storage नियम
// (owner/admin मात्र) बेवास्ता गरेर कागजात खोल्न सक्थ्यो। अब यस्ता कागजातको
// *Storage path* (जस्तै `documents/<uid>/citizenship_front.jpg`) मात्र राखिन्छ;
// path आफैंमा केही खोल्दैन। हेर्दा (`resolveKycUrl`) Storage नियमले जाँच्छ —
// owner वा admin मात्रले मान्य URL पाउँछन्, अरूलाई permission-denied।
import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';

/// यी प्रकारका कागजात `path` को रूपमा मात्र राखिन्छन् (सार्वजनिक URL होइन)।
/// `selfie`/`profile_picture`/`certificate` अवतार/पोर्टफोलियोमा देखिने भएकोले
/// URL नै रहन्छन्।
bool isPrivateKycType(String type) {
  final t = type.toLowerCase();
  return t == 'license' ||
      t == 'document' ||
      t == 'id' ||
      t.startsWith('citizenship_') ||
      t == 'driving_license' ||
      t == 'vehicle_registration' ||
      t == 'vehicle_insurance' ||
      t == 'route_permit' ||
      t.startsWith('hotel_');
}

/// `http(s)` URL जस्तोतस्तै; नत्र Storage path लाई (नियम अनुमति दिए) URL मा।
Future<String> resolveKycUrl(String value) async {
  final v = value.trim();
  if (v.isEmpty || v.startsWith('http')) return v;
  return FirebaseStorage.instance.ref(v).getDownloadURL();
}

/// पुरानो token-URL बाट Storage path निकाल्छ (`gs://`/path भए जस्तोतस्तै);
/// चिन्न नसके null। एक-पटकको सफाइ (admin scrub) का लागि।
String? kycPathFromUrl(String value) {
  final v = value.trim();
  if (v.isEmpty || !v.startsWith('http')) return null;
  try {
    return FirebaseStorage.instance.refFromURL(v).fullPath;
  } catch (_) {
    return null;
  }
}

/// [url] (वा Storage path) लाई resolve गरेर देखाउने छवि — admin कागजात
/// thumbnail/पूरा-स्क्रिन दुवैमा।
class KycImage extends StatelessWidget {
  final String url;
  final double? width;
  final double? height;
  final BoxFit fit;
  final int? memCacheHeight;
  final Widget? placeholder;
  final Widget? errorWidget;
  const KycImage({
    super.key,
    required this.url,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.memCacheHeight,
    this.placeholder,
    this.errorWidget,
  });

  @override
  Widget build(BuildContext context) {
    final fallback = errorWidget ??
        Container(
          width: width,
          height: height,
          color: Colors.white.withValues(alpha: 0.06),
          child: const Icon(Icons.insert_drive_file_rounded, color: Colors.grey),
        );
    return FutureBuilder<String>(
      future: resolveKycUrl(url),
      builder: (context, snap) {
        if (snap.hasError) return fallback;
        if (!snap.hasData) {
          return placeholder ??
              SizedBox(
                width: width,
                height: height,
                child: const Center(
                    child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2))),
              );
        }
        return CachedNetworkImage(
          imageUrl: snap.data!,
          width: width,
          height: height,
          fit: fit,
          memCacheHeight: memCacheHeight,
          errorWidget: (_, __, ___) => fallback,
        );
      },
    );
  }
}
