// auth/auth_config.dart
// Testing-phase auth feature flags.
//
// Google Sign-In and Phone OTP are switched off for now so every account can
// be created and tested purely with email + password — no browser popups,
// no OS account picker, no SMS/reCAPTCHA redirect to get blocked on. Phone
// OTP verification is planned for production; flip these back to `true`
// (and remove the `if (kEnable...)` guards around the related buttons) once
// that flow is ready to ship.
const bool kEnableGoogleSignIn = false;
const bool kEnablePhoneAuth = false;
