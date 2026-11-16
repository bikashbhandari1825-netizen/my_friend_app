// screens/salon_common.dart
//
// Salon / Beauty Appointment Booking — सबै salon screen (browse/detail/
// booking/pass/partner) ले साझा प्रयोग गर्ने सानो helper/widget —
// hotel_common.dart कै भूमिका। मूल्य/star-row hotel कै साझा function
// पुनः-प्रयोग (duplicate होइन)।
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart' show Uint8List;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../models/salon_models.dart';
import '../services/upload_validation.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_ui.dart';
import '../widgets/futuristic_ui.dart';

export 'hotel_common.dart' show formatHotelPrice, HotelStarRow;

/// गैलेरीबाट छानिएको, पहिल्यै जाँचिएको फोटो (अझै upload भएको होइन)।
class SalonPickedImage {
  final Uint8List bytes;
  final String name;
  const SalonPickedImage(this.bytes, this.name);
}

/// गैलेरीबाट एउटा फोटो छान्ने — साइज/प्रकार `UploadValidation` ले जाँच्छ;
/// गलत भए कारण देखाएर null फर्काउँछ।
Future<SalonPickedImage?> pickSalonImage(BuildContext context) async {
  try {
    final p = await ImagePicker()
        .pickImage(source: ImageSource.gallery, imageQuality: 80, maxWidth: 1600);
    if (p == null) return null;
    final bytes = await p.readAsBytes();
    final err = UploadValidation.validate(bytes, p.name);
    if (err != null) {
      if (context.mounted) salonSnack(context, UploadValidation.messageFor(err));
      return null;
    }
    return SalonPickedImage(bytes, p.name);
  } catch (e) {
    if (context.mounted) salonSnack(context, 'Could not open gallery: $e');
    return null;
  }
}

/// Salon logo / barber फोटो देखाउने गोलो-कुना चित्र; URL (वा [bytes]) नभए
/// [icon] को fallback।
class SalonAvatar extends StatelessWidget {
  final String url;
  final Uint8List? bytes;
  final IconData icon;
  final double size;
  final double radius;
  const SalonAvatar({
    super.key,
    this.url = '',
    this.bytes,
    required this.icon,
    this.size = 54,
    this.radius = 16,
  });

  @override
  Widget build(BuildContext context) {
    final fallback = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: AppColors.kmCtaGradient,
        borderRadius: BorderRadius.circular(radius),
      ),
      child: Icon(icon, color: AppColors.kmInk, size: size * 0.48),
    );
    Widget? image;
    if (bytes != null) {
      image = Image.memory(bytes!, width: size, height: size, fit: BoxFit.cover);
    } else if (url.isNotEmpty) {
      // डिस्क-क्यास (cached_network_image): एकपटक डाउनलोड भएपछि फोनमै बस्छ —
      // एप बन्द गरेर फेरि खोल्दा पनि बिना नेटवर्क/ढिलाइ तुरुन्तै देखिन्छ।
      image = CachedNetworkImage(
        imageUrl: url,
        width: size,
        height: size,
        fit: BoxFit.cover,
        memCacheWidth: (size * 3).round(),
        fadeInDuration: Duration.zero,
        fadeOutDuration: Duration.zero,
        placeholder: (_, __) => fallback,
        errorWidget: (_, __, ___) => fallback,
      );
    }
    if (image == null) return fallback;
    return ClipRRect(borderRadius: BorderRadius.circular(radius), child: image);
  }
}

/// विवरण पेजको माथिको फुल-विथ banner — [url] नभए category-आइकनसहित gradient।
class SalonCover extends StatelessWidget {
  final String url;
  final IconData icon;
  final double height;
  const SalonCover(
      {super.key, required this.url, required this.icon, this.height = 220});

  @override
  Widget build(BuildContext context) {
    final fallback = Container(
      height: height,
      width: double.infinity,
      decoration: const BoxDecoration(gradient: AppColors.kmCtaGradient),
      child: Icon(icon, color: AppColors.kmInk.withValues(alpha: 0.5), size: 64),
    );
    if (url.isEmpty) return fallback;
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CachedNetworkImage(
        imageUrl: url,
        fit: BoxFit.cover,
        fadeInDuration: Duration.zero,
        fadeOutDuration: Duration.zero,
        placeholder: (_, __) => Container(
          color: Colors.white.withValues(alpha: 0.05),
          alignment: Alignment.center,
          child: const CircularProgressIndicator(strokeWidth: 2),
        ),
        errorWidget: (_, __, ___) => fallback,
      ),
    );
  }
}

/// फारम भित्र फोटो छान्ने/बदल्ने/हटाउने पट्टी। [onChanged] ले नयाँ छानिएको
/// फोटो (वा null) र "हटाइयो" थाहा दिन्छ — upload चाहिँ caller ले save गर्दा गर्छ।
class SalonPhotoField extends StatefulWidget {
  final String label;
  final String currentUrl;
  final IconData icon;
  final void Function(SalonPickedImage? picked, bool removed) onChanged;
  const SalonPhotoField({
    super.key,
    required this.label,
    required this.currentUrl,
    required this.icon,
    required this.onChanged,
  });

  @override
  State<SalonPhotoField> createState() => _SalonPhotoFieldState();
}

class _SalonPhotoFieldState extends State<SalonPhotoField> {
  SalonPickedImage? _picked;
  bool _removed = false;

  Future<void> _pick() async {
    final p = await pickSalonImage(context);
    if (p == null || !mounted) return;
    setState(() {
      _picked = p;
      _removed = false;
    });
    widget.onChanged(p, false);
  }

  void _remove() {
    setState(() {
      _picked = null;
      _removed = true;
    });
    widget.onChanged(null, true);
  }

  @override
  Widget build(BuildContext context) {
    final hasImage =
        _picked != null || (!_removed && widget.currentUrl.isNotEmpty);
    return Row(
      children: [
        SalonAvatar(
          url: _removed ? '' : widget.currentUrl,
          bytes: _picked?.bytes,
          icon: widget.icon,
          size: 64,
          radius: 18,
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Wrap(
            spacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: _pick,
                icon: const Icon(Icons.photo_library_rounded, size: 16),
                label: Text(hasImage ? 'Change ${widget.label}' : 'Add ${widget.label}'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.kmOrange,
                  side: BorderSide(
                      color: AppColors.kmOrange.withValues(alpha: 0.4)),
                ),
              ),
              if (hasImage)
                TextButton(
                  onPressed: _remove,
                  style:
                      TextButton.styleFrom(foregroundColor: AppColors.kmRose),
                  child: const Text('Remove'),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

IconData salonCategoryIcon(String category) => switch (category) {
      'Barber' => Icons.content_cut_rounded,
      'Beauty & Makeup' => Icons.brush_rounded,
      'Spa & Massage' => Icons.spa_rounded,
      'Nails' => Icons.back_hand_rounded,
      'Salon' => Icons.face_retouching_natural_rounded,
      _ => Icons.storefront_rounded,
    };

/// `90` → `1 h 30 min`, `45` → `45 min`।
String salonDurationLabel(int min) {
  if (min < 60) return '$min min';
  final h = min ~/ 60;
  final m = min % 60;
  return m == 0 ? '$h h' : '$h h $m min';
}

String salonStatusLabel(String status) => switch (status) {
      SalonAppointmentStatus.confirmed => 'Confirmed',
      SalonAppointmentStatus.checkedIn => 'Checked in',
      SalonAppointmentStatus.completed => 'Completed',
      SalonAppointmentStatus.cancelled => 'Cancelled',
      SalonAppointmentStatus.noShow => 'No-show',
      _ => status,
    };

Color salonStatusColor(String status) => switch (status) {
      SalonAppointmentStatus.confirmed => AppColors.kmTeal,
      SalonAppointmentStatus.checkedIn => AppColors.kmTealBlue,
      SalonAppointmentStatus.completed => AppColors.kmLilac,
      SalonAppointmentStatus.cancelled => AppColors.kmRose,
      SalonAppointmentStatus.noShow => AppColors.kmOrange,
      _ => AppColors.kmMuted,
    };

/// Payment status को label — 'declared' = ग्राहकले reference दिएको तर
/// provider/gateway ले अझै verify नगरेको (यो app मा साँचो gateway छैन)।
String salonPaymentLabel(SalonAppointment a) {
  if (a.paymentStatus == 'paid') return 'Paid';
  if (a.paymentType == SalonPaymentType.online) {
    return 'Online payment declared (${a.paymentMethod.toUpperCase()} · ${a.paymentRef})';
  }
  return 'Pay at salon';
}

Widget salonStatusTag(String status) =>
    KmTag(salonStatusLabel(status), color: salonStatusColor(status));

/// Dark-glass card — checkout_screen कै `_card` शैली।
Widget salonCard({required Widget child, EdgeInsetsGeometry? padding}) =>
    Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: padding ?? const EdgeInsets.all(14),
      decoration: neonDecoration(accent: kNeonViolet, radius: AppRadius.lg),
      child: child,
    );

Widget salonSectionLabel(String text) => Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 8, left: 2),
      child: Text(text,
          style: const TextStyle(
              color: AppColors.kmMuted,
              fontWeight: FontWeight.w800,
              fontSize: 12,
              letterSpacing: 0.4)),
    );

Widget salonSummaryRow(String label, String value, {bool bold = false}) =>
    Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: const TextStyle(color: AppColors.kmMuted, fontSize: 12.5)),
          const SizedBox(width: 12),
          Flexible(
            child: Text(value,
                textAlign: TextAlign.right,
                style: TextStyle(
                    color: bold ? AppColors.kmOrange : AppColors.kmText,
                    fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
                    fontSize: bold ? 15 : 12.5)),
          ),
        ],
      ),
    );

void salonSnack(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

/// "4.8 (23)" वा नयाँ salon को लागि "New" — रेटिङ-पंक्ति।
Widget salonRatingLine(Salon s, {double size = 14}) {
  if (s.ratingCount == 0) {
    return const KmTag('New', color: AppColors.kmTeal);
  }
  return Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(Icons.star_rounded, size: size + 2, color: AppColors.kmOrange),
      const SizedBox(width: 3),
      Text(s.avgRating.toStringAsFixed(1),
          style: TextStyle(
              color: AppColors.kmText,
              fontWeight: FontWeight.w800,
              fontSize: size)),
      Text(' (${s.ratingCount})',
          style: TextStyle(color: AppColors.kmMuted, fontSize: size - 1)),
    ],
  );
}
