# KYC OCR — google_mlkit_text_recognition ले आफ्नो TextRecognizer.initialize()
# भित्र Chinese/Devanagari/Japanese/Korean script-specific recognizer options
# समेत (switch-जस्तो) उल्लेख गर्छ, तर यो app ले `TextRecognitionScript.latin`
# बाहेक अरू कुनै script dependency थपेको छैन (ocr_match_service.dart हेर्नुहोस्
# — Latin-script-only, जानाजान स्वीकारिएको सीमा)। ती class हरू कहिल्यै runtime
# मा चाहिँदैन, तर R8 ले तिनको absence लाई release/minified build मा
# "missing class" error (warning होइन, सिधै build failure) मान्छ — यी
# `-dontwarn` बिना release APK/App Bundle कहिल्यै बन्दैन।
-dontwarn com.google.mlkit.vision.text.chinese.ChineseTextRecognizerOptions$Builder
-dontwarn com.google.mlkit.vision.text.chinese.ChineseTextRecognizerOptions
-dontwarn com.google.mlkit.vision.text.devanagari.DevanagariTextRecognizerOptions$Builder
-dontwarn com.google.mlkit.vision.text.devanagari.DevanagariTextRecognizerOptions
-dontwarn com.google.mlkit.vision.text.japanese.JapaneseTextRecognizerOptions$Builder
-dontwarn com.google.mlkit.vision.text.japanese.JapaneseTextRecognizerOptions
-dontwarn com.google.mlkit.vision.text.korean.KoreanTextRecognizerOptions$Builder
-dontwarn com.google.mlkit.vision.text.korean.KoreanTextRecognizerOptions
