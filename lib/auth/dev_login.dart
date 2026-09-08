// auth/dev_login.dart
//
// नि:शुल्क testing को लागि। यो test नम्बर + code हाल्दा real SMS नपठाई
// Firebase Anonymous sign-in हुन्छ — Spark (free) plan मा चल्छ, Blaze चाहिँदैन।
//
// चाहिने: Firebase Console → Authentication → Sign-in method → Anonymous → Enable
//
// Production मा जानुअघि यो bypass हटाउनुहोला।
import 'package:firebase_auth/firebase_auth.dart';

const String kTestPhone = '+9779800000000';
const String kTestCode = '123456';

/// देखाउने hint (UI मा) — local part मात्र।
const String kTestPhoneHint = '9800000000';

bool isTestPhone(String e164) =>
    e164.replaceAll(RegExp(r'\s'), '') == kTestPhone;

/// Anonymous sign-in — real SMS/OTP बिना।
Future<void> devTestSignIn() => FirebaseAuth.instance.signInAnonymously();
