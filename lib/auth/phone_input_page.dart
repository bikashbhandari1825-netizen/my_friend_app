// auth/phone_input_page.dart
// देश code छान्ने + फोन नम्बर → Firebase बाट OTP पठाउने।
import 'dart:async';

import 'package:country_picker/country_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../config/app_config.dart';
import '../l10n/strings.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_ui.dart';
import 'admin_gate_page.dart';
import 'dev_login.dart';
import 'otp_verification_page.dart';
import 'phone_format.dart';

class PhoneInputPage extends StatefulWidget {
  const PhoneInputPage({super.key});

  @override
  State<PhoneInputPage> createState() => _PhoneInputPageState();
}

class _PhoneInputPageState extends State<PhoneInputPage> {
  final _controller = TextEditingController();
  // देश ISO कोडबाट सुरुवाती मान (Nepal) — `country_picker` कै आफ्नै
  // ~195+ देशको सटीक flag/dial-code डेटाबेस, हामीले हातले टाइप गर्नु पर्दैन।
  Country _country =
      CountryService().findByCode('NP') ?? CountryService().getAll().first;
  bool _sending = false;
  // Watchdog — कुनै अनपेक्षित (uncaught) async त्रुटि/network black-hole ले
  // गर्दा `_sending` कहिल्यै सधैँको लागि `true` मै अडिन नपाओस् भन्ने अन्तिम
  // सुरक्षा-जाल। सामान्य बाटोमा यो कहिल्यै फायर हुँदैन (हरेक सफल/असफल बाटोले
  // आफैं `_disarmWatchdog()` गर्छ) — केवल साँच्चै अनपेक्षित/असीमित पर्खाइ
  // भएमा मात्र स्क्रिन जमेको जस्तो कहिल्यै नदेखियोस् भनेर।
  Timer? _watchdog;

  // फोन नम्बर फिल्डको आफ्नै FocusNode — तल `initState()` मा `autofocus: true`
  // को सट्टा किन: पहिलो frame पूरा भएपछि मात्र (route push-transition सँग
  // race नगरी) explicit रूपमा focus माग्ने। Flutter Web मा `autofocus`
  // (विशेष गरी pushed route मा) कहिलेकाहीं transition चलिरहेकै बेला DOM
  // `<input>` लाई ठ्याक्कै समयमा attach/focus गर्न चुक्थ्यो — त्यही क्षणमा
  // प्रयोगकर्ताले तुरुन्तै टाइप गरिहाले (Backspace सहित) कुनै पनि text
  // field ले नटिपी ब्राउजरले आफैं त्यो Backspace लाई आफ्नै "history back"
  // शर्टकटको रूपमा टिप्थ्यो — "नम्बर हाल्दा app आफैं back हुने" गुनासोको
  // साँचो कारण।
  final _phoneFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _phoneFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _phoneFocusNode.dispose();
    _watchdog?.cancel();
    super.dispose();
  }

  String get _e164 => toE164(_country, _controller.text);

  /// टाइप गरेको नम्बर submit गर्न लायक छ कि — देश-विशिष्ट कडा regex होइन,
  /// ITU कै फराकिलो दायरा (`isPlausiblePhoneDigits`) प्रयोग गरेर — ताकि
  /// स्थानीय regex बगले कुनै साँचो मान्य नम्बरलाई कहिल्यै ब्लक नगरोस्। ज्ञात
  /// टेस्ट नम्बर (`kTestPhoneHint`) सधैँ अनुमति — जुनसुकै देश छानिए पनि।
  bool get _canSubmit {
    final digits = digitsOnly(_controller.text);
    if (digits.isEmpty) return false;
    if (digits == digitsOnly(kTestPhoneHint)) return true;
    return isPlausiblePhoneDigits(digits);
  }

  void _armWatchdog() {
    _watchdog?.cancel();
    _watchdog = Timer(const Duration(seconds: 25), () {
      if (!mounted || !_sending) return;
      setState(() => _sending = false);
      _snack(S.phoneRequestTimedOut);
    });
  }

  void _disarmWatchdog() {
    _watchdog?.cancel();
    _watchdog = null;
  }

  /// Uber/inDrive-शैली — खोजी-सहितको full-screen-नजिकको bottom sheet,
  /// एपकै dark-glass टोनमा styled। `country_picker` ले आफैं भित्र
  /// `ListView.builder` प्रयोग गर्छ (195+ देश भए पनि lazy — कुनै lag/
  /// overflow छैन), खोजी नाम र dial-code दुवैमा काम गर्छ।
  void _pickCountry() {
    showCountryPicker(
      context: context,
      showPhoneCode: true,
      favorite: const ['NP', 'IN'],
      onSelect: (c) => setState(() => _country = c),
      countryListTheme: CountryListThemeData(
        backgroundColor: AppColors.kmSurface,
        bottomSheetHeight: MediaQuery.of(context).size.height * 0.82,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        textStyle: const TextStyle(color: AppColors.kmText, fontSize: 15),
        searchTextStyle:
            const TextStyle(color: AppColors.kmText, fontSize: 15),
        inputDecoration: InputDecoration(
          hintText: S.searchCountryHint,
          hintStyle: const TextStyle(color: AppColors.kmMuted),
          prefixIcon:
              const Icon(Icons.search_rounded, color: AppColors.kmMuted),
          filled: true,
          fillColor: Colors.white.withValues(alpha: 0.06),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(999),
            borderSide: BorderSide(color: AppColors.kmGlassBorder),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(999),
            borderSide: BorderSide(color: AppColors.kmGlassBorder),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(999),
            borderSide: const BorderSide(color: Colors.white),
          ),
        ),
      ),
    );
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  /// स्थायी नियम — यो पेजले आफैं कहिल्यै `signInWithCredential`/pop गर्दैन।
  /// फोन नम्बर पेश गरेपछिको हरेक सम्भावित नतिजा (test-mode, web confirmation,
  /// SMS auto-retrieval, वा manual code-entry) यहीं `_goOtp()` मार्फत सधैँ
  /// [OtpVerificationPage] मै पुग्छ — sign-in "पूरा भयो, home फर्कने" भन्ने
  /// अन्तिम निर्णय त्यही एउटै पेजले मात्र गर्छ। पहिले `verificationCompleted`
  /// (Android SMS auto-retrieval) ले यहीं सिधै sign-in + pop गर्थ्यो — त्यही
  /// नै "OTP screen कहिल्यै नदेखी फोन नम्बर पेश गरेकै क्षणमा सिधै welcome
  /// screen मा फर्कने" गुनासोको जड थियो। अब त्यो auto-credential पनि तल
  /// `autoCredential` मार्फत OTP पेजमै पठाइन्छ — त्यो पेजले नै (चाहे auto
  /// भए पनि) verify गरेर मात्र pop गर्छ, यसले कहिल्यै गर्दैन।
  void _goOtp({
    ConfirmationResult? confirmationResult,
    String? verificationId,
    PhoneAuthCredential? autoCredential,
    bool testMode = false,
    required bool existing,
    required String phone,
  }) {
    _disarmWatchdog();
    if (!mounted) return;
    setState(() => _sending = false);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => OtpVerificationPage(
          phone: phone,
          confirmationResult: confirmationResult,
          verificationId: verificationId,
          autoCredential: autoCredential,
          testMode: testMode,
          existingAccount: existing,
        ),
      ),
    );
  }

  Future<void> _continue() async {
    // बटन आफैं अमान्य नम्बरमा disabled हुन्छ (तल `_canSubmit`), तर keyboard
    // को "Done"/Enter (TextField.onSubmitted) ले जुनसुकै बेला यो function
    // सिधै बोलाउन सक्ने भएकोले यहाँ पनि उही जाँच दोहोर्याउने।
    if (!_canSubmit) {
      _snack(S.enterValidPhone);
      return;
    }
    if (_sending) return; // डबल-ट्याप/डबल-Enter बाट डुप्लिकेट request रोक्ने

    // ── गुप्त Admin Gate — यहीं सामान्य फिल्डमै, कुनै अलग UI/लिङ्क/बटन
    // बिना। देश-कोड जे भए पनि राष्ट्रिय अंक ठ्याक्कै मिले मात्र — सामान्य
    // phone-account लुकअप/OTP/test-mode जस्ता कुनै पनि सामान्य बाटोलाई
    // कहिल्यै नछुने, सिधै अलग गुप्त पेजमा।
    if (digitsOnly(_controller.text) == kAdminSecretPhoneDigits) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const AdminGatePage()),
      );
      return;
    }

    final phone = _e164;
    setState(() => _sending = true);
    _armWatchdog();

    try {
      // यो नम्बरसँग पहिले account छ कि? (login vs signup देखाउन) —
      // `phoneAccountExists` आफैं भित्र try/catch गरेर असफल भए `false`
      // फर्काउँछ, त्यसैले यहाँ छुट्टै catch नचाहिने — तर बाहिरको try/catch
      // कै अन्तर्गत राखिएको (defense-in-depth, भविष्यमा त्यो function
      // बदलिए पनि यो स्क्रिन कहिल्यै अड्किनु नपरोस्)।
      final existing = await phoneAccountExists(phone);
      if (!mounted) return;

      // टेस्टिङ चरणमा साँचो Firebase Phone Auth (SMS + web reCAPTCHA) सिधै
      // छुँदैनौं — त्यही नै "अड्किने/break वा loop हुने" गुनासोको मूल कारण
      // थियो (reCAPTCHA popup-block, unauthorized domain, दोस्रोपटक "already
      // rendered" त्रुटि आदि)। सिधै अन्तर्निहित नि:शुल्क test-mode मा जाने —
      // बटन/screen उस्तै काम गर्छन्, केवल SMS चाहिँदैन। kUseRealPhoneSms
      // (config/app_config.dart) लाई `true` पारेपछि मात्र तलको साँचो-SMS
      // बाटो फेरि प्रयोग हुन्छ।
      if (!kUseRealPhoneSms) {
        _goOtp(testMode: true, existing: existing, phone: phone);
        return;
      }

      if (kIsWeb) {
        final result = await FirebaseAuth.instance
            .signInWithPhoneNumber(phone)
            .timeout(const Duration(seconds: 20));
        _goOtp(confirmationResult: result, existing: existing, phone: phone);
        return;
      }
      await FirebaseAuth.instance.verifyPhoneNumber(
        phoneNumber: phone,
        timeout: const Duration(seconds: 60),
        // Android SMS auto-retrieval ले verification आफैं पूरा गरिदिन सक्छ
        // (प्रयोगकर्ताले केही टाइप नगरी नै) — यो credential यहीं सिधै sign-in
        // नगरी OTP पेजमै पठाउने (`autoCredential`), ताकि "sign-in पूरा भयो,
        // home फर्कने" निर्णय सधैँ त्यही एउटै पेजबाट मात्र होस् (माथिको
        // `_goOtp` doc-comment हेर्नुहोस्)।
        verificationCompleted: (cred) {
          if (!mounted) return;
          _goOtp(
              autoCredential: cred, existing: existing, phone: phone);
        },
        verificationFailed: (e) {
          if (!mounted) return;
          _snack('${S.errorWord}: ${e.message ?? e.code}');
          _goOtp(testMode: true, existing: existing, phone: phone);
        },
        codeSent: (verificationId, __) => _goOtp(
            verificationId: verificationId, existing: existing, phone: phone),
        codeAutoRetrievalTimeout: (_) {},
      );
    } catch (e) {
      if (!mounted) return;
      // माथिको कुनै पनि चरण (existing-check, reCAPTCHA, network, timeout...)
      // असफल भए पनि प्रयोगकर्ता कहिल्यै जमेको स्क्रिनमा नअड्कियोस् — प्रस्ट
      // त्रुटि देखाएर सधैँ नि:शुल्क test-mode मा अगाडि बढ्न दिने।
      _snack('${S.errorWord}: $e');
      _goOtp(testMode: true, existing: false, phone: phone);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuroraBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: GlassIconButton(
                    icon: Icons.arrow_back_rounded,
                    onTap: () => Navigator.maybePop(context),
                  ),
                ),
                const SizedBox(height: 16),
                Text(S.phoneInputTitle,
                    style: const TextStyle(
                        color: AppColors.kmText,
                        fontSize: 22,
                        fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                Text(S.phoneInputSub,
                    style: const TextStyle(
                        color: AppColors.kmMuted, fontSize: 13)),
                const SizedBox(height: 20),
                GlassPanel(
                  radius: AppRadius.lg,
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 118,
                            child: InkWell(
                              borderRadius:
                                  BorderRadius.circular(AppRadius.md),
                              onTap: _pickCountry,
                              child: InputDecorator(
                                decoration: kmInputDecoration(S.countryCode),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(_country.flagEmoji,
                                        style:
                                            const TextStyle(fontSize: 18)),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        '+${_country.phoneCode}',
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                            color: AppColors.kmText,
                                            fontSize: 14),
                                      ),
                                    ),
                                    const Icon(Icons.expand_more_rounded,
                                        color: AppColors.kmMuted, size: 18),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextField(
                              controller: _controller,
                              focusNode: _phoneFocusNode,
                              keyboardType: TextInputType.phone,
                              style: const TextStyle(color: AppColors.kmText),
                              decoration: kmInputDecoration(S.phoneNumberLabel),
                              onSubmitted: (_) => _continue(),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                            '${_country.name}  ·  +${_country.phoneCode}',
                            style: const TextStyle(
                                color: AppColors.kmMuted, fontSize: 12)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                GlassPanel(
                  radius: 12,
                  padding: const EdgeInsets.all(10),
                  child: const Text(
                    'Free test login → any number, code: $kTestCode\n'
                    'Same number always signs into the same account.',
                    style: TextStyle(color: AppColors.kmMuted, fontSize: 12),
                  ),
                ),
                const SizedBox(height: 20),
                // बटन "dynamically enable" हुनको लागि — यहीं मात्र
                // `_controller` सुन्ने (`ListenableBuilder`), पूरै पेज होइन।
                // पहिले हरेक अक्षरमा `setState(() {})` ले सिंगो `build()`
                // दोहोर्‍याउँथ्यो — Flutter Web मा यसले hidden text-input DOM
                // element लाई हरेक keystroke मा पुनः-attach गराउँदै गर्दा
                // (विशेष गरी छिटो-छिटो टाइप गर्दा) कहिलेकाहीं focus हल्का
                // क्षणभर हराउँथ्यो, र त्यही क्षणको Backspace ब्राउजरले "पछाडि
                // जाने" शर्टकटको रूपमा टिपेर सिधै अघिल्लो पेजमा पुर्‍याउँथ्यो
                // ("नम्बर हाल्दा app आफैं back हुने" गुनासो)। अब यहाँ मात्र
                // narrow rebuild हुँदा TextField आफैं (र त्यसको DOM focus)
                // कहिल्यै disturb हुँदैन।
                ListenableBuilder(
                  listenable: _controller,
                  builder: (context, _) => KmCtaButton(
                    label: S.continueWord,
                    icon: Icons.arrow_forward_rounded,
                    loading: _sending,
                    onPressed: _canSubmit ? _continue : null,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
