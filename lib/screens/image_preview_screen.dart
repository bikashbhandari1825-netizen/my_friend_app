// screens/image_preview_screen.dart
// Camera/gallery बाट तस्बिर छानेपछि सिधै पठाउनुको सट्टा — यो preview screen
// देखाउने। "Send" थिचेपछि मात्र (true फर्काएर) chat_screen.dart ले साँच्चै
// अपलोड/पठाउने काम गर्छ — cancel/back थिचे केही पठाइँदैन।
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../theme/app_theme.dart';
import '../widgets/spring_tap.dart';

class ImagePreviewScreen extends StatelessWidget {
  final Uint8List bytes;
  const ImagePreviewScreen({super.key, required this.bytes});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: InteractiveViewer(
                minScale: 1,
                maxScale: 4,
                child: Center(
                  child: Image.memory(bytes, fit: BoxFit.contain),
                ),
              ),
            ),
            Positioned(
              left: 8,
              top: 8,
              child: SpringTap(
                onTap: () => Navigator.of(context).pop(false),
                pressedScale: 0.85,
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.black45,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Icon(Icons.close_rounded, color: Colors.white),
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 24,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => Navigator.of(context).pop(false),
                        icon: const Icon(Icons.delete_outline_rounded,
                            color: Colors.white),
                        label: Text(S.cancel,
                            style: const TextStyle(color: Colors.white)),
                        style: OutlinedButton.styleFrom(
                          padding:
                              const EdgeInsets.symmetric(vertical: 14),
                          side: const BorderSide(color: Colors.white38),
                          shape: RoundedRectangleBorder(
                              borderRadius:
                                  BorderRadius.circular(AppRadius.pill)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      flex: 2,
                      child: SpringTap(
                        onTap: () => Navigator.of(context).pop(true),
                        pressedScale: 0.95,
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          decoration: BoxDecoration(
                            gradient: AppColors.buttonGradient,
                            borderRadius:
                                BorderRadius.circular(AppRadius.pill),
                            boxShadow: [
                              BoxShadow(
                                  color:
                                      AppColors.igPink.withValues(alpha: 0.4),
                                  blurRadius: 14,
                                  offset: const Offset(0, 4)),
                            ],
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.send_rounded,
                                  color: Colors.white, size: 18),
                              const SizedBox(width: 8),
                              Text(S.send,
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w800)),
                            ],
                          ),
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
    );
  }
}
