// utils/price_input.dart
//
// मूल्य/काउन्टर-अफर इनपुटको साझा जाँच र देखाइ।
//   • अत्यधिक/अमान्य रकम (जस्तै Rs. 9000000) लाई पठाउनै नदिने।
//   • रकम हजार-विभाजक (९,०००) सहित, स्पष्ट देखाउने।

/// एउटा राइड/काम-मूल्यको अधिकतम सीमा (रुपैयाँ)।
const num kMaxFare = 100000;

/// टाइप गरिएको पाठबाट मान्य मूल्य; शून्य/ऋणात्मक/अत्यधिक/अमान्य भए null।
num? parseSanePrice(String raw) {
  final v = num.tryParse(raw.trim());
  if (v == null || v.isNaN || v.isInfinite || v <= 0 || v > kMaxFare) {
    return null;
  }
  return v;
}

/// 9000000 → "9,000,000"; दशमलव भए १ अंकसम्म।
String formatRs(num v) {
  final whole = v % 1 == 0;
  final s = whole ? v.toInt().toString() : v.toStringAsFixed(1);
  final parts = s.split('.');
  final digits = parts[0];
  final buf = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    final fromEnd = digits.length - i;
    buf.write(digits[i]);
    if (fromEnd > 1 && fromEnd % 3 == 1 && digits[i] != '-') buf.write(',');
  }
  return parts.length > 1 ? '$buf.${parts[1]}' : buf.toString();
}
