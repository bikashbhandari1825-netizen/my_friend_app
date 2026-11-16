// screens/qr_scanner_screen.dart
// Employer Payment View — eSewa/Khalti click गर्दा worker कै QR स्क्यान
// गर्ने साझा क्यामेरा स्क्रिन। भेटिएको QR text (payload ढाँचा `esewa:<id>`
// वा `khalti:<id>` — worker profile/complete_job_sheet.dart मा बनाइने
// उही ढाँचा) सिधै Navigator.pop(context, value) मार्फत caller लाई फर्काउँछ।
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../l10n/strings.dart';
import '../theme/app_theme.dart';

class QrScannerScreen extends StatefulWidget {
  // वैकल्पिक शीर्षक — default "Scan to pay"; salon check-in जस्ता अन्य
  // प्रयोगले आफ्नै शीर्षक दिन सक्छन्।
  final String? title;
  const QrScannerScreen({super.key, this.title});

  @override
  State<QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends State<QrScannerScreen> {
  final _controller = MobileScannerController();
  // पहिलो भेटिएको QR मात्र — त्यसपछि छिटो-छिटो थुप्रैपटक `onDetect`
  // फायर हुने भएकोले (हरेक frame मा), दोहोरो pop नहोस् भनेर।
  bool _handled = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    final barcodes = capture.barcodes;
    if (barcodes.isEmpty) return;
    final value = barcodes.first.rawValue;
    if (value == null || value.isEmpty) return;
    _handled = true;
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(widget.title ?? S.scanToPay),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        flexibleSpace: const DecoratedBox(
          decoration: BoxDecoration(gradient: AppColors.buttonGradient),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.flash_on_rounded),
            onPressed: () => _controller.toggleTorch(),
          ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(controller: _controller, onDetect: _onDetect),
          IgnorePointer(
            child: Center(
              child: Container(
                width: 240,
                height: 240,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.white70, width: 2),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
