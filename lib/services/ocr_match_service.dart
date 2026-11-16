// services/ocr_match_service.dart
// Strict Document Cross-Matching — KYC मा टाइप गरेको नाम/जन्ममिति/कागजात-नम्बर
// अपलोड गरेको ID फोटोमा छापिएको पाठसँग साँच्चै मिल्छ कि भनेर (on-device OCR,
// ML Kit Text Recognition — नेटवर्क/cloud मा डेटा कहिल्यै नजाने) जाँच्ने।
//
// Latin-Script-Only Limitation — ML Kit को standard Text Recognizer ले
// Latin-script पाठ मात्र भरपर्दो पढ्छ। नेपाली नागरिकता/लाइसेन्स प्रायः
// द्विभाषिक हुन्छन् (देवनागरी + Latin-script अंग्रेजी transliteration) —
// यो helper ले त्यो अंग्रेजी भागलाई मात्र जाँच्छ; देवनागरी खण्ड कहिल्यै
// पढिँदैन। यो जानाजान स्वीकारिएको सीमा हो, पूर्ण-कागजात शुद्धताको दाबी होइन।
//
// Client-Side-Only — यो एपकै बाँकी validation (upload_validation.dart) कै
// उस्तै, सर्भर-साइड होइन — एउटा UX-स्तरको गुणस्तर-गेट हो, सुरक्षा-सीमा होइन
// (admin कै मानव समीक्षा नै अन्तिम प्रमाणीकरण रहन्छ, यसले त्यो कहिल्यै
// प्रतिस्थापन गर्दैन)।
import 'dart:io';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:path_provider/path_provider.dart';

enum OcrFieldType { name, dob, documentNumber }

class OcrFieldExpectation {
  /// फारममा टाइप गरिएको/छानिएको मान पहिचान गर्ने आन्तरिक key (जस्तै
  /// 'firstName+lastName', 'dob', 'licenseNumber') — UI ले आफैं प्रयोग
  /// गर्दैन, caller ले आफ्नै तर्फबाट [OcrFieldResult.fieldKey] सँग
  /// दाँजेर कुन field मा गल्ती भयो भनेर पत्ता लगाउन।
  final String fieldKey;

  /// प्रयोगकर्तालाई देखाउने (mismatch सन्देशमा प्रयोग हुने) लेबल।
  final String label;

  /// हाल फारममा भएको/typed मान — DOB भए caller ले नै ISO/दृश्य-अनुकूल
  /// string मा convert गरेर पठाउनुपर्छ ([matchFields] आफैं DateTime लिँदैन,
  /// सबै caller तर्फबाटै already-formatted string)।
  final String expectedValue;
  final OcrFieldType type;

  const OcrFieldExpectation({
    required this.fieldKey,
    required this.label,
    required this.expectedValue,
    required this.type,
  });
}

class OcrFieldResult {
  final String fieldKey;
  final String label;
  final bool matched;
  const OcrFieldResult({
    required this.fieldKey,
    required this.label,
    required this.matched,
  });
}

class OcrMatchService {
  OcrMatchService._();

  /// DEBUG-ONLY TEST BYPASS — साँचो ID/license/vehicle-doc कागजात बिना पनि
  /// KYC flow (worker/driver/hotel) को हरेक OCR gate (License/VehicleDocs/
  /// Identity — तीनै step, एउटै shared flag) end-to-end test गर्न सकियोस्
  /// भनेर। डिफल्ट मान नै `kDebugMode` (debug build मा मात्र `true`) — ताकि
  /// पहिलो OCR gate (License step, Identity step भन्दा धेरै अघि आउने) मा नै
  /// कुनै थप बटन नखोजिकनै सिधै auto-pass होस् (नत्र पछिल्लो step सम्म
  /// नपुगी यो flag toggle गर्ने ठाउँ नै नभेटिने ordering-समस्या हुन्थ्यो)।
  /// तल `matchFields` भित्रैको जाँच भने `kDebugMode && debugAutoPassEnabled`
  /// नै हो, एक्लै यो flag होइन — release/profile build मा `kDebugMode` सधैँ
  /// `false` compile-time constant भएकोले यो सिंगो branch dead-code-
  /// eliminate हुन्छ (`false && x` सधैँ `false`) — यो flag आफैं (गल्तीले वा
  /// अन्यथा) `true` रहे पनि production मा कहिल्यै असर पार्न सक्दैन। साँचो
  /// OCR behaviour नै जाँच्न चाहने developer ले debug build भित्रै यसलाई
  /// `false` पार्न सक्छन् (`LivenessSelfieCapture`-कै "Mock Pass" बटनले
  /// यसलाई फेरि `true` बनाइदिन्छ — widgets/liveness_selfie_capture.dart)।
  static bool debugAutoPassEnabled = kDebugMode;

  /// [imageBytesList] (एउटै कागजातका एक वा बढी फोटो, जस्तै नागरिकताको
  /// अगाडि+पछाडि — दुवैको पाठ जोडेर एकैसाथ जाँचिन्छ) मा [expectations] मध्ये
  /// हरेक टाइप गरिएको मान छ/छैन जाँच्छ। OCR आफैं असफल भए वा कुनै पाठ नै
  /// नभेटिए (धमिलो/गलत फोटो) — कहिल्यै throw नगरी हरेक expectation लाई
  /// `matched: false` फर्काउँछ, ताकि caller ले चुपचाप pass नगरी स्पष्ट
  /// "कागजात पढ्न सकिएन" भनेर रोक्न सकोस्।
  static Future<List<OcrFieldResult>> matchFields({
    required List<List<int>> imageBytesList,
    required List<OcrFieldExpectation> expectations,
  }) async {
    if (kDebugMode && debugAutoPassEnabled) {
      return [
        for (final e in expectations)
          OcrFieldResult(fieldKey: e.fieldKey, label: e.label, matched: true),
      ];
    }
    final recognizedText = await _recognizeText(imageBytesList);
    if (recognizedText == null || recognizedText.trim().isEmpty) {
      return [
        for (final e in expectations)
          OcrFieldResult(fieldKey: e.fieldKey, label: e.label, matched: false),
      ];
    }
    final normalized = _normalizeForSearch(recognizedText);
    return [
      for (final e in expectations)
        OcrFieldResult(
          fieldKey: e.fieldKey,
          label: e.label,
          matched: _matchOne(normalized, e),
        ),
    ];
  }

  static Future<String?> _recognizeText(List<List<int>> imageBytesList) async {
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    final tempFiles = <File>[];
    try {
      final buffer = StringBuffer();
      final tempDir = await getTemporaryDirectory();
      for (var i = 0; i < imageBytesList.length; i++) {
        // Temp-File Bridge — ML Kit को `InputImage.fromBytes` लाई width/
        // height/rotation/format (raw YUV/NV21 स्तरको) metadata चाहिन्छ, जुन
        // पहिल्यै-encode भइसकेको (JPEG/PNG) bytes बाट भरपर्दो निकाल्न अप्ठ्यारो
        // हुन्छ — त्यसैले बरु एकपटक disk मा लेखेर `InputImage.fromFilePath`
        // (जसले आफैं decode गर्छ) प्रयोग गर्ने, अनि तुरुन्तै मेटाउने।
        final file = File(
            '${tempDir.path}/ocr_match_${DateTime.now().microsecondsSinceEpoch}_$i.jpg');
        await file.writeAsBytes(imageBytesList[i], flush: true);
        tempFiles.add(file);
        final input = InputImage.fromFilePath(file.path);
        final result = await recognizer.processImage(input);
        if (result.text.trim().isNotEmpty) {
          buffer.writeln(result.text);
        }
      }
      return buffer.toString();
    } catch (_) {
      return null;
    } finally {
      await recognizer.close();
      for (final f in tempFiles) {
        try {
          await f.delete();
        } catch (_) {}
      }
    }
  }

  static String _normalizeForSearch(String raw) =>
      raw.toLowerCase().replaceAll(RegExp(r'[^a-z0-9\s]'), ' ');

  static bool _matchOne(String normalizedOcrText, OcrFieldExpectation e) {
    switch (e.type) {
      case OcrFieldType.name:
        return _matchName(normalizedOcrText, e.expectedValue);
      case OcrFieldType.documentNumber:
        return _matchDocumentNumber(normalizedOcrText, e.expectedValue);
      case OcrFieldType.dob:
        return _matchDob(normalizedOcrText, e.expectedValue);
    }
  }

  /// टाइप गरिएको नामको हरेक शब्द (whole-word) OCR पाठभरि कतै न कतै भेटिनैपर्छ
  /// — OCR ले line-wrap/पङ्क्ति-क्रम फरक पार्न सक्छ भनेर सिधै substring होइन,
  /// token-by-token जाँच (नाम आफैं धेरै पटक दोहोरिएको/क्रम बदलिएको भए पनि सही)।
  static bool _matchName(String normalizedOcrText, String expectedName) {
    final ocrTokens = normalizedOcrText.split(RegExp(r'\s+')).toSet();
    final nameTokens = _normalizeForSearch(expectedName)
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty)
        .toList();
    if (nameTokens.isEmpty) return false;
    return nameTokens.every(ocrTokens.contains);
  }

  /// लाइसेन्स/प्लेट/ब्लुबुक नम्बर — दुवैतिरबाट dash/slash/space हटाएर
  /// (OCR र टाइपिङमा अलग-अलग punctuation हुन सक्ने) substring जाँच।
  static bool _matchDocumentNumber(
      String normalizedOcrText, String expectedNumber) {
    final cleanedOcr = normalizedOcrText.replaceAll(RegExp(r'\s+'), '');
    final cleanedExpected =
        expectedNumber.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    if (cleanedExpected.isEmpty) return false;
    return cleanedOcr.contains(cleanedExpected);
  }

  /// जन्ममिति — टाइप गरिएको मितिलाई केही सामान्य ढाँचामा (dd/mm/yyyy आदि)
  /// बनाएर सिधै खोज्ने प्रयास गर्छ, अनि साथै OCR पाठभित्रै मिति-आकारका
  /// substring खोजेर (day, month, year) tuple मा दाँजेर पनि जाँच्छ — OCR ले
  /// पङ्क्ति बीचमा अनपेक्षित खाली ठाउँ/नयाँ-लाइन हाल्दा पनि भरपर्दो।
  static bool _matchDob(String normalizedOcrText, String expectedDobIso) {
    final expected = DateTime.tryParse(expectedDobIso);
    if (expected == null) return false;

    final candidates = <String>[
      _fmt(expected.day, expected.month, expected.year, '/'),
      _fmt(expected.day, expected.month, expected.year, '-'),
      _fmt(expected.month, expected.day, expected.year, '/'),
      '${expected.year}-${_pad2(expected.month)}-${_pad2(expected.day)}',
    ];
    final cleanedOcr = normalizedOcrText.replaceAll(RegExp(r'\s+'), '');
    for (final c in candidates) {
      if (cleanedOcr.contains(c.replaceAll(RegExp(r'[/-]'), ''))) return true;
    }

    // Date-Shaped Substring Scan — OCR पाठमा dd mm yyyy (वा फरक क्रम) जस्ता
    // ढाँचा खोजेर numeric tuple मा सिधै दाँज्ने — ठ्याक्कै punctuation/क्रम
    // नमिले पनि दिन/महिना/वर्ष तीनै अंक ठीक भए मिलेको मान्ने।
    final dateMatches =
        RegExp(r'(\d{1,2})\D(\d{1,2})\D(\d{4})').allMatches(normalizedOcrText);
    for (final m in dateMatches) {
      final a = int.tryParse(m.group(1) ?? '');
      final b = int.tryParse(m.group(2) ?? '');
      final y = int.tryParse(m.group(3) ?? '');
      if (a == null || b == null || y == null || y != expected.year) continue;
      final asDmy = a == expected.day && b == expected.month;
      final asMdy = a == expected.month && b == expected.day;
      if (asDmy || asMdy) return true;
    }
    return false;
  }

  static String _fmt(int a, int b, int year, String sep) =>
      '${_pad2(a)}$sep${_pad2(b)}$sep$year';
  static String _pad2(int n) => n.toString().padLeft(2, '0');
}
