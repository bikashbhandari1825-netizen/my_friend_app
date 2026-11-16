package com.example.kaamMitra.app

import io.flutter.embedding.android.FlutterFragmentActivity

// FlutterActivity बाट FlutterFragmentActivity मा बदलियो — `local_auth`
// (Passkey/biometric login step) को Android BiometricPrompt लाई
// FragmentActivity host नै चाहिन्छ।
class MainActivity: FlutterFragmentActivity()
