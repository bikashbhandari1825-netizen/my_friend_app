// auth/phone_input_page.dart
// देश code छान्ने + फोन नम्बर → Firebase बाट OTP पठाउने।
import 'dart:async';

import 'package:country_picker/country_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
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
  // ANR FIX — `_sending` मात्र भरमा rapid-tap debounce गर्दा पर्याप्त
  // हुँदैन: कुनै पनि async चरण छिटो फर्के (वा असफल भई `_sending` तुरुन्तै
  // `false` मा रिसेट भए) प्रयोगकर्ताले हतारमा Continue धेरैपटक (६-७ पटकसम्म) छिटो-छिटो थिचे
  // (केहि नभएको जस्तो लागेर) — हरेक ट्याप आफ्नै छुट्टै सफल कल भई छुट्टाछुट्टै
  // OTP page एकैचोटि एकमाथि अर्को push हुँदै गयो, धेरै गाढा glass-blur
  // screen एकैचोटि build/animate हुँदा ठ्याक्कै logcat मा देखिएको
  // `ANR_LOG`/"msg's executing time is too long" निम्त्यायो। अब यो
  // timestamp-based debounce ले `_sending` को अवस्था जे भए पनि, एउटै
  // tap-burst बाट आएको दोहोरिएको कल सधैँ रोक्छ।
  DateTime? _lastContinueTap;

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
    // Capsule-card ले focus आए/गए glow outline देखाउनको लागि मात्र — narrow
    // rebuild (माथिको `ListenableBuilder` जस्तै सिद्धान्त), TextField आफैं
    // कहिल्यै re-mount हुँदैन, dispose() मै node आफैं dispose हुन्छ।
    _phoneFocusNode.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _phoneFocusNode.dispose();
    _watchdog?.cancel();
    super.dispose();
  }

  /// EMERGENCY FIX — पहिले यहाँ जुनसुकै बेला छानिएको देश-selector (`_country`)
  /// कै dial code सधैँ जबरजस्ती अगाडि जोडिन्थ्यो। प्रयोगकर्ताले selector
  /// नबदली सिधै फिल्डमै पूरै अन्तर्राष्ट्रिय नम्बर (जस्तै Firebase test
  /// number `+48 574726831`, Nepal selector डिफल्टमै छँदाछँदै) टाइप गरे,
  /// डिफल्ट देशको कोड (+977) त्यही नम्बरको अगाडि दोहोरिएर टाँसिन्थ्यो
  /// (`+97748574726831` — सर्वथा अमान्य) — ठ्याक्कै "+48 combined with the
  /// number" भनेको parsing बग, र Firebase ले त्यो अमान्य नम्बर कहिल्यै
  /// स्वीकार नगर्ने भएकोले Continue थिचेपछि कुनै callback नआई अडिने।
  /// अब फिल्डमा टाइप गरेको टेक्स्ट आफैं `+` बाट सुरु भए त्यसलाई पहिल्यै
  /// पूरा E.164 मानेर सिधै प्रयोग गर्ने — देश-selector dial code फेरि
  /// नथोपिने।
  String get _e164 => resolveE164(_country, _controller.text);

  /// टाइप गरेको नम्बर submit गर्न लायक छ कि — देश-विशिष्ट कडा regex होइन,
  /// ITU कै फराकिलो दायरा (`isPlausiblePhoneDigits`) प्रयोग गरेर — ताकि
  /// स्थानीय regex बगले कुनै साँचो मान्य नम्बरलाई कहिल्यै ब्लक नगरोस्।
  bool get _canSubmit {
    final digits = digitsOnly(_controller.text);
    if (digits.isEmpty) return false;
    return isPlausiblePhoneDigits(digits);
  }

  void _armWatchdog() {
    _watchdog?.cancel();
    _watchdog = Timer(const Duration(seconds: 25), () {
      if (!mounted || !_sending) return;
      // साँचो Firebase Phone Auth (reCAPTCHA/SMS/network/Console-config)
      // 25 सेकेन्डसम्म codeSent/verificationCompleted/verificationFailed
      // मध्ये कुनै पनि नदिए — बटन फेरि सक्रिय गरेर प्रयोगकर्तालाई फेरि
      // Continue थिच्न दिने (कुनै बाइपास होइन, OTP screen तबसम्म खुल्दैन
      // जबसम्म साँचो Firebase ले codeSent/verificationCompleted दिँदैन)।
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
  /// फोन नम्बर पेश गरेपछिको हरेक सम्भावित नतिजा (web confirmation,
  /// SMS auto-retrieval, वा manual code-entry) यहीं `_goOtp()` मार्फत सधैँ
  /// [OtpVerificationPage] मै पुग्छ — sign-in "पूरा भयो, home फर्कने" भन्ने
  /// अन्तिम निर्णय त्यही एउटै पेजले मात्र गर्छ। पहिले `verificationCompleted`
  /// (Android SMS auto-retrieval) ले यहीं सिधै sign-in + pop गर्थ्यो — त्यही
  /// नै "OTP screen कहिल्यै नदेखी फोन नम्बर पेश गरेकै क्षणमा सिधै welcome
  /// screen मा फर्कने" गुनासोको जड थियो। अब त्यो auto-credential पनि तल
  /// `autoCredential` मार्फत OTP पेजमै पठाइन्छ — त्यो पेजले नै (चाहे auto
  /// भए पनि) verify गरेर मात्र pop गर्छ, यसले कहिल्यै गर्दैन।
  // ANR FIX — एउटै tap-burst बाट `_goOtp()` एकभन्दा बढीपटक पुगे पनि (माथिको
  // debounce कुनै किनारे-केसमा चुक्यो भने) Navigator.push एकपटक मात्र
  // हुन्छ भनेर अन्तिम सुरक्षा-जाल — एकैचोटि धेरै OTP page एकमाथि अर्को
  // push हुनबाट (ठ्याक्कै ANR को जड) जोगाउने। OTP page बाट फेरि यो page
  // मा फर्केपछि (`.then`) मात्र फेरि अर्को push अनुमति हुन्छ।
  bool _otpPushScheduled = false;

  void _goOtp({
    ConfirmationResult? confirmationResult,
    String? verificationId,
    PhoneAuthCredential? autoCredential,
    required bool existing,
    required String phone,
  }) {
    _disarmWatchdog();
    if (!mounted || _otpPushScheduled) return;
    _otpPushScheduled = true;
    debugPrint('DEBUG: Initiating OTP routing');
    setState(() => _sending = false);
    // हालको frame को बीचमै होइन, अर्को frame सुरु भएपछि मात्र push —
    // Continue tap कै gesture-handling frame सँग टक्राएर कुनै jank/double-
    // trigger नहोस् भनेर।
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _pushOtpPage(
        confirmationResult: confirmationResult,
        verificationId: verificationId,
        autoCredential: autoCredential,
        existing: existing,
        phone: phone,
      );
    });
  }

  void _pushOtpPage({
    ConfirmationResult? confirmationResult,
    String? verificationId,
    PhoneAuthCredential? autoCredential,
    required bool existing,
    required String phone,
  }) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => OtpVerificationPage(
          phone: phone,
          confirmationResult: confirmationResult,
          verificationId: verificationId,
          autoCredential: autoCredential,
          existingAccount: existing,
        ),
      ),
    ).then((_) {
      // OTP page बाट फर्केपछि मात्र — अर्को Continue tap फेरि अनुमति।
      if (mounted) _otpPushScheduled = false;
    });
  }

  Future<void> _continue() async {
    // EMERGENCY FIX — पहिले यो try-catch भित्र केवल network/Firebase call
    // हरू मात्र थिए; `_canSubmit`/admin-gate/`_e164` जस्ता सिंक्रोनस step
    // मा कतै अनपेक्षित त्रुटि आए (जस्तै अमान्य country data) पूरै function
    // नै uncaught exception ले बीचमै रोकिन सक्थ्यो — बटन फेरि कहिल्यै
    // सक्रिय नहुने गरी। अब सिंगो function body यही एउटै try-catch भित्र,
    // र हरेक catch ले त्रुटि debug console मा प्रस्ट प्रिन्ट गर्छ (चुपचाप
    // नस्वाल्ने) अनि बटन फेरि सक्रिय गरेर प्रयोगकर्तालाई साँचो त्रुटि
    // snackbar मा देखाउँछ (कुनै बाइपास होइन) — फेरि Continue थिचेर retry
    // गर्न सकिन्छ।
    debugPrint('DEBUG: Continue tapped');
    try {
      // ANR FIX — `_sending`/अन्य सबै जाँच भन्दा पनि पहिले नै: यो tap
      // अघिल्लो सफल tap को ८०० ms भित्रै आएको हो भने सिधै बेवास्ता
      // (माथिको field-doc टिप्पणी हेर्नुहोस् — multi-tap बाट धेरै OTP
      // screen एकैचोटि push हुने ANR को साँचो जड)।
      final now = DateTime.now();
      if (_lastContinueTap != null &&
          now.difference(_lastContinueTap!) < const Duration(milliseconds: 800)) {
        debugPrint('DEBUG: Continue tap ignored (debounce)');
        return;
      }
      _lastContinueTap = now;

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
      // phone-account लुकअप/OTP जस्ता कुनै पनि सामान्य बाटोलाई कहिल्यै
      // नछुने, सिधै अलग गुप्त पेजमा।
      if (isAdminGatePhone(digitsOnly(_controller.text))) {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const AdminGatePage()),
        );
        return;
      }

      final phone = _e164;
      debugPrint('[PhoneInputPage] _continue() → sending OTP');
      setState(() => _sending = true);
      _armWatchdog();

      // यो नम्बरसँग पहिले account छ कि? (login vs signup देखाउन) —
      // `phoneAccountExists` आफैं भित्र try/catch गरेर असफल भए `false`
      // फर्काउँछ, त्यसैले यहाँ छुट्टै catch नचाहिने — तर बाहिरको try/catch
      // कै अन्तर्गत राखिएको (defense-in-depth, भविष्यमा त्यो function
      // बदलिए पनि यो स्क्रिन कहिल्यै अड्किनु नपरोस्)।
      final existing = await phoneAccountExists(phone);
      if (!mounted) return;

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
          debugPrint(
              '[PhoneInputPage] verificationFailed: ${e.code} — ${e.message}');
          _disarmWatchdog();
          setState(() => _sending = false);
          _snack(friendlyPhoneAuthError(e));
        },
        codeSent: (verificationId, __) {
          debugPrint('[PhoneInputPage] codeSent → verificationId received');
          _goOtp(
              verificationId: verificationId, existing: existing, phone: phone);
        },
        codeAutoRetrievalTimeout: (_) {},
      );
    } catch (e, st) {
      // माथिको कुनै पनि चरण (existing-check, reCAPTCHA, network, timeout,
      // अमान्य/combined country-code parsing...) असफल भए पनि प्रयोगकर्ता
      // कहिल्यै जमेको स्क्रिनमा नअड्कियोस् — त्रुटि debug console मा प्रस्ट
      // प्रिन्ट (चुपचाप नस्वाल्ने) गरेर बटन फेरि सक्रिय, साँचो त्रुटि
      // snackbar मा — कुनै बाइपास होइन, Continue फेरि थिचेर retry गर्न सकिन्छ।
      debugPrint('[PhoneInputPage] _continue() failed: $e\n$st');
      if (!mounted) return;
      _disarmWatchdog();
      setState(() => _sending = false);
      _snack(friendlyPhoneAuthError(e));
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
                // Combined Floating Capsule Card — पहिले देश-selector र
                // फोन-नम्बर दुई छुट्टै boxed field जस्ता देखिन्थे (बीचमा
                // gap)। अब एउटै frosted capsule (radius 999 — pill), बीचमा
                // हल्का vertical divider मात्र — modern "country flag
                // dropdown + number" combined-field ढाँचा। फोन-field
                // focus भएको बेला पूरै capsule को outline teal glow मा
                // smooth-animate हुन्छ (`_phoneFocusNode` listener माथि)।
                AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOut,
                  decoration: BoxDecoration(
                    color: AppColors.kmGlass2Fill,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: _phoneFocusNode.hasFocus
                          ? AppColors.kmTeal
                          : AppColors.kmGlass2Border,
                      width: _phoneFocusNode.hasFocus ? 1.6 : 1.1,
                    ),
                    boxShadow: _phoneFocusNode.hasFocus
                        ? [
                            BoxShadow(
                              color: AppColors.kmTeal.withValues(alpha: 0.35),
                              blurRadius: 20,
                              spreadRadius: 1,
                            ),
                          ]
                        : null,
                  ),
                  child: Row(
                    children: [
                      InkWell(
                        borderRadius: BorderRadius.circular(999),
                        onTap: _pickCountry,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(18, 14, 12, 14),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(_country.flagEmoji,
                                  style: const TextStyle(fontSize: 20)),
                              const SizedBox(width: 7),
                              Text(
                                '+${_country.phoneCode}',
                                style: const TextStyle(
                                    color: AppColors.kmText,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600),
                              ),
                              const SizedBox(width: 3),
                              const Icon(Icons.expand_more_rounded,
                                  color: AppColors.kmMuted, size: 18),
                            ],
                          ),
                        ),
                      ),
                      Container(
                        width: 1,
                        height: 26,
                        color: Colors.white.withValues(alpha: 0.14),
                      ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          child: TextField(
                            controller: _controller,
                            focusNode: _phoneFocusNode,
                            keyboardType: TextInputType.phone,
                            style:
                                const TextStyle(color: AppColors.kmText, fontSize: 15.5),
                            decoration: InputDecoration(
                              hintText: S.phoneNumberLabel,
                              hintStyle:
                                  const TextStyle(color: AppColors.kmMuted),
                              border: InputBorder.none,
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(vertical: 16),
                            ),
                            onSubmitted: (_) => _continue(),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.only(left: 18),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                        '${_country.name}  ·  +${_country.phoneCode}',
                        style: const TextStyle(
                            color: AppColors.kmMuted, fontSize: 12)),
                  ),
                ),
                // Inline field validation — keystroke मा होइन, field बाट
                // focus हटेपछि मात्र (`_phoneFocusNode` कै existing listener
                // ले यसै गरी `setState` गर्छ, माथिको ANR-fix doc-comment
                // हेर्नुहोस्) — ताकि टाइप गर्दागर्दै (अझै अंक थोरै हुँदा) रातो
                // error नदेखियोस्, तर submit नगरिकनै/button थिच्नु अघि नै
                // प्रयोगकर्ताले अमान्य नम्बर टाइप गरेको थाहा पाओस्।
                if (!_phoneFocusNode.hasFocus &&
                    _controller.text.isNotEmpty &&
                    !_canSubmit) ...[
                  const SizedBox(height: 6),
                  Padding(
                    padding: const EdgeInsets.only(left: 18),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(S.enterValidPhone,
                          style: const TextStyle(
                              color: AppColors.kmRose,
                              fontSize: 12,
                              fontWeight: FontWeight.w600)),
                    ),
                  ),
                ],
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
