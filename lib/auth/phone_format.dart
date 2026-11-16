// auth/phone_format.dart
//
// फोन नम्बरलाई E.164 (`+<देश-कोड><अंकहरू>`) मा बनाउने/जाँच्ने एउटै साझा
// ठाउँ। यसअघि देश-कोड + टाइप गरेको नम्बर हरेक ठाउँमा हातहातै string जोडिन्थ्यो
// (जस्तै `'+${_country.dial}$digits'`) — त्यसले कतै '+' दोहोरिने, कतै खाली
// अंकमै पठाइने, कतै फरक regex ले फरक व्यवहार गर्ने जस्ता चुपचाप नबुझिने बग
// निम्त्याउन सक्थ्यो। अब यो फाइलकै दुई function मात्र प्रयोग गर्नुहोस्।
import 'package:country_picker/country_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../l10n/strings.dart';

/// टाइप गरेको जुनसुकै कच्चा टेक्स्ट (space/dash/bracket जे भए पनि) बाट
/// अंक-मात्र निकाल्ने — E.164 भित्र अंक बाहेक अरू केही रहँदैन।
String digitsOnly(String raw) => raw.replaceAll(RegExp(r'[^0-9]'), '');

/// छानिएको देशको dial code + प्रयोगकर्ताले टाइप गरेको नम्बर जोडेर सधैँ सही
/// E.164 (`+<countryCode><digits>`) फर्काउने। यही एउटा function ले मात्र यो
/// जोड्ने काम गर्नुपर्छ — फेरि कतै हातले `'+' + code + digits` नजोड्नुहोस्,
/// नत्र दुबैतिर फरक-फरक edge-case handling हुँदै दोहोरिने बग फर्किन्छ।
String toE164(Country country, String rawInput) =>
    '+${country.phoneCode}${digitsOnly(rawInput)}';

/// `toE164` भन्दा एक तह माथि — प्रयोगकर्ताले फिल्डमै सिधै पूरै
/// अन्तर्राष्ट्रिय नम्बर (`+` बाट सुरु हुने, जस्तै Firebase test number
/// `+48 574726831`) टाइप गरे, छानिएको देश-selector (अलग्गै default/
/// नबदलिएको हुन सक्छ) को dial code दोहोर्याएर नजोडी त्यसलाई जस्ताको-त्यस्तै
/// E.164 मान्ने — नत्र (राष्ट्रिय अंक मात्र टाइप गरेको सामान्य केसमा)
/// selector कै dial code + अंक जोड्ने। पहिले यो logic
/// `phone_input_page.dart`'s `_e164` getter भित्रै दोहोरिएको थियो (duplicate
/// "+48 combined with the number" parsing बगको जड) — अब यहीं एकै ठाउँमा,
/// unit-test गर्न मिल्ने गरी।
String resolveE164(Country country, String rawInput) {
  final trimmed = rawInput.trim();
  if (trimmed.startsWith('+')) {
    return '+${digitsOnly(trimmed)}';
  }
  return toE164(country, trimmed);
}

/// ITU E.164 मान्य दायरा — कुनै एक देशको national number लाई हार्डकोड
/// लम्बाइ/regex ले जाँच्दा त्यही regex अरू देशका पूर्ण मान्य नम्बरलाई गलत
/// रूपमा रोकिदिन सक्छ (जस्तै कुनै छोटो-नम्बर देश)। बरु ITU कै व्यापक
/// दायरा (देश-कोड बाहेकको national number ४ देखि १४ अंकसम्म — कुल जोड्दा
/// १५ भन्दा बढी कहिल्यै हुँदैन) प्रयोग गर्ने — "साँचो नम्बरलाई कहिल्यै
/// गलत रूपमा नरोक्ने" भन्ने सिद्धान्तमा।
bool isPlausiblePhoneDigits(String nationalDigits) {
  final len = nationalDigits.length;
  return len >= 4 && len <= 14;
}

/// साँचो Firebase Phone Auth त्रुटि (code पठाउँदा वा verify गर्दा, दुवै) लाई
/// प्रयोगकर्ताले बुझ्ने स्पष्ट सन्देशमा बदल्ने — एउटै ठाउँमा
/// (phone_input_page.dart र otp_verification_page.dart दुवैले प्रयोग
/// गर्छन्) ताकि कहिल्यै raw exception string (`[firebase_auth/xyz] ...`)
/// सिधै UI मा नदेखियोस्।
String friendlyPhoneAuthError(Object e) {
  if (e is FirebaseAuthException) {
    switch (e.code) {
      case 'too-many-requests':
        return S.phoneTooManyRequests;
      case 'invalid-phone-number':
        return S.phoneInvalidNumber;
      case 'quota-exceeded':
        return S.phoneQuotaExceeded;
      case 'admin-restricted-operation':
      case 'operation-not-allowed':
        return S.phoneAuthNotEnabled;
      case 'captcha-check-failed':
      case 'missing-recaptcha-token':
      case 'app-not-authorized':
        return S.phoneCaptchaFailed;
      default:
        return '${S.errorWord}: ${e.message ?? e.code}';
    }
  }
  return '${S.errorWord}: $e';
}
