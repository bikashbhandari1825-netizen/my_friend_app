// l10n/strings.dart
//
// एपभरिको सबै देखिने text यहीँबाट आउँछ। `localeNotifier` (app_globals.dart) ले
// अहिलेको भाषा भन्छ; Settings मा touch गर्दा त्यो बदलिन्छ र पूरै app rebuild हुन्छ।
//
// नयाँ string थप्ने तरिका:
//   1. तल `_values` map मा `'my_key': {'en': 'English', 'ne': 'नेपाली'}` थप्नुहोस्।
//   2. माथि एउटा getter बनाउनुहोस्:  `static String get myKey => _t('my_key');`
//   3. screen मा `Text('...')` लाई `Text(S.myKey)` ले बदल्नुहोस्।
import '../app_globals.dart';

class S {
  S._();

  /// अहिलेको भाषा नेपाली हो कि?
  static bool get isNepali => localeNotifier.value.languageCode == 'ne';

  /// key बाट अहिलेको भाषाको string। नभेटिए en, त्यो पनि नभेटिए key फिर्ता।
  static String _t(String key) {
    final lang = localeNotifier.value.languageCode;
    final entry = _values[key];
    if (entry == null) return key;
    return entry[lang] ?? entry['en'] ?? key;
  }

  /// Firestore बाट English मा आउने service name लाई देखाउने भाषामा।
  static String serviceName(String englishName) {
    if (!isNepali) return englishName;
    return _serviceNe[englishName] ?? englishName;
  }

  // ── Common ───────────────────────────────────────────────
  static String get cancel => _t('cancel');
  static String get ok => _t('ok');
  static String get save => _t('save');
  static String get delete => _t('delete');
  static String get logout => _t('logout');
  static String get errorWord => _t('error');

  // ── Bottom navigation ────────────────────────────────────
  static String get navHome => _t('nav_home');
  static String get navRequests => _t('nav_requests');
  static String get navMessages => _t('nav_messages');
  static String get navProfile => _t('nav_profile');
  static String get navWatchlist => _t('nav_watchlist');

  // ── Home ─────────────────────────────────────────────────
  static String get greeting => _t('greeting');
  static String get homeQuestion => _t('home_question');
  static String get searchHint => _t('search_hint');
  static String get servicesTitle => _t('services_title');
  static String get seeAll => _t('see_all');
  static String get heroTitle => _t('hero_title');
  static String get heroSubtitle => _t('hero_subtitle');
  static String get locationLabel => _t('location_label');
  static String noServiceMatch(String query) => isNepali
      ? '"$query" सँग मिल्दो सेवा भेटिएन'
      : 'No service matches "$query"';

  // ── Home (inDrive-style) ─────────────────────────────────
  static String get whereAndPrice => _t('where_and_price');
  static String get regionAvailable => _t('region_available');
  static String get regionUnavailable => _t('region_unavailable');
  static String get locationOffTitle => _t('location_off_title');
  static String get locationOffBody => _t('location_off_body');
  static String get notNow => _t('not_now');
  static String get openSettings => _t('open_settings');
  static String get menuCity => _t('menu_city');
  static String get menuRequestHistory => _t('menu_request_history');
  static String get menuProviders => _t('menu_providers');
  static String get menuNotifications => _t('menu_notifications');
  static String get menuSupport => _t('menu_support');
  static String get providerMode => _t('provider_mode');
  static String get becomeProvider => _t('become_provider');

  // ── Drawer ───────────────────────────────────────────────
  static String get myBookings => _t('my_bookings');
  static String get messages => _t('messages');
  static String get savedWorkers => _t('saved_workers');
  static String get myReviews => _t('my_reviews');
  static String get paymentMethods => _t('payment_methods');
  static String get helpSupport => _t('help_support');
  static String get aboutApp => _t('about_app');
  static String get settings => _t('settings');

  // ── Settings ─────────────────────────────────────────────
  static String get appearance => _t('appearance');
  static String get themeLight => _t('theme_light');
  static String get themeDark => _t('theme_dark');
  static String get themeSystem => _t('theme_system');
  static String get language => _t('language');
  static String get legalDocuments => _t('legal_documents');
  static String get logOut => _t('log_out');
  static String get deleteAccount => _t('delete_account');
  static String get logoutConfirmTitle => _t('logout_confirm_title');
  static String get deleteAccountBody => _t('delete_account_body');

  // ── Registration ─────────────────────────────────────────
  static String get employerRegTitle => _t('employer_reg_title');
  static String get workerRegTitle => _t('worker_reg_title');
  static String get regWorkerNote => _t('reg_worker_note');
  static String get firstName => _t('first_name');
  static String get lastName => _t('last_name');
  static String get phone => _t('phone');
  static String get dob => _t('dob');
  static String get pickDate => _t('pick_date');
  static String get locationSection => _t('location_section');
  static String get useMyLocation => _t('use_my_location');
  static String get locationCaptured => _t('location_captured');
  static String get locationDeniedShort => _t('location_denied_short');
  static String get gettingLocation => _t('getting_location');
  static String get serviceCategory => _t('service_category');
  static String get experienceLabel => _t('experience_label');
  static String get yearsWord => _t('years_word');
  static String get monthsWord => _t('months_word');
  static String get startingPrice => _t('starting_price');
  static String get district => _t('district');
  static String get areaLandmark => _t('area_landmark');
  static String get experienceCertificate => _t('experience_certificate');
  static String get addDocument => _t('add_document');
  static String get next => _t('next');
  static String get submitForApproval => _t('submit_for_approval');
  static String get enterName => _t('enter_name');
  static String get enterPhone => _t('enter_phone');
  static String get enterArea => _t('enter_area');
  static String get uploadDocFirst => _t('upload_doc_first');
  static String get applicationSubmitted => _t('application_submitted');
  static String get applicationSubmittedBody => _t('application_submitted_body');
  static String get docRejectedBanner => _t('doc_rejected_banner');
  static String get viewDocument => _t('view_document');
  static String get uploading => _t('uploading');
  static String get approve => _t('approve');
  static String get reject => _t('reject');
  static String get back => _t('back_word');
  static String get stepDetails => _t('step_details');
  static String get stepDocument => _t('step_document');
  static String get stepSelfie => _t('step_selfie');
  static String get selfieVerification => _t('selfie_verification');
  static String get selfieHint => _t('selfie_hint');
  static String get takeSelfie => _t('take_selfie');
  static String get retake => _t('retake');
  static String get selfieRequired => _t('selfie_required');
  static String get vehicleDetails => _t('vehicle_details');
  static String get vehicleHint => _t('vehicle_hint');
  static String get rejectReasonTitle => _t('reject_reason_title');
  static String get rejectReasonHint => _t('reject_reason_hint');
  static String get reasonLabel => _t('reason_label');
  static String get selfiePhoto => _t('selfie_photo');

  // ── Saved places ─────────────────────────────────────────
  static String get savedPlacesTitle => _t('saved_places_title');
  static String get saveAsHome => _t('save_as_home');
  static String get saveAsWork => _t('save_as_work');
  static String get addAnotherPlace => _t('add_another_place');
  static String get notSetYet => _t('not_set_yet');
  static String get pickOnMap => _t('pick_on_map');
  static String get confirmLocation => _t('confirm_location');
  static String get fetchingAddress => _t('fetching_address');
  static String get placeLabel => _t('place_label');
  static String get moveMapHint => _t('move_map_hint');
  static String get placeSaved => _t('place_saved');

  // ── Reviews ──────────────────────────────────────────────
  static String get reviewsTitle => _t('reviews_title');
  static String get basedOnReviews => _t('based_on_reviews');
  static String get sortBy => _t('sort_by');
  static String get sortRecent => _t('sort_recent');
  static String get sortHighest => _t('sort_highest');
  static String get sortLowest => _t('sort_lowest');
  static String get noReviewsYet => _t('no_reviews_yet');

  // ── Payments ─────────────────────────────────────────────
  static String get paymentsTitle => _t('payments_title');
  static String get paymentsSub => _t('payments_sub');
  static String get payQr => _t('pay_qr');
  static String get payQrSub => _t('pay_qr_sub');
  static String get payEsewa => _t('pay_esewa');
  static String get payKhalti => _t('pay_khalti');
  static String get walletIdLabel => _t('wallet_id_label');
  static String get scanToPay => _t('scan_to_pay');
  static String get openWallet => _t('open_wallet');

  // ── Help / Support / Legal ───────────────────────────────
  static String get serviceStandard => _t('service_standard');
  static String get serviceStandardSub => _t('service_standard_sub');
  static String get workerNoResponse => _t('worker_no_response');
  static String get workerNoResponseSub => _t('worker_no_response_sub');
  static String get faq => _t('faq');
  static String get contactSupport => _t('contact_support');
  static String get contactSupportUnset => _t('contact_support_unset');
  static String get callSupport => _t('call_support');
  static String get privacyPolicy => _t('privacy_policy');
  static String get dataSecurity => _t('data_security');
  static String get dataSecureLine => _t('data_secure_line');
  static String get supportNumberLabel => _t('support_number_label');
  static String get editSupportNumber => _t('edit_support_number');
  static String get saved => _t('saved');

  // ── Watchlist ────────────────────────────────────────────
  static String get watchlistTitle => _t('watchlist_title');
  static String get watchlistHint => _t('watchlist_hint');

  // ── Nearby / bidding ─────────────────────────────────────
  static String get nearbyTitle => _t('nearby_title');
  static String get findNearby => _t('find_nearby');
  static String get filterAll => _t('filter_all');
  static String get offerYourPrice => _t('offer_your_price');
  static String get askingPrice => _t('asking_price');
  static String get yourOffer => _t('your_offer');
  static String get sendOffer => _t('send_offer');
  static String get describeTask => _t('describe_task');
  static String get describeTaskHint => _t('describe_task_hint');
  static String get offerSentTitle => _t('offer_sent_title');
  static String get offerSentBody => _t('offer_sent_body');
  static String get enableLocation => _t('enable_location');
  static String get locationNeededTitle => _t('location_needed_title');
  static String get locationNeededBody => _t('location_needed_body');
  static String get approxLocation => _t('approx_location');
  static String get noWorkersNearby => _t('no_workers_nearby');
  static String get retry => _t('retry');
  static String distanceLabel(double km) => km < 1
      ? (isNepali ? '${(km * 1000).round()} मि टाढा' : '${(km * 1000).round()} m away')
      : (isNepali
          ? '${km.toStringAsFixed(1)} किमी टाढा'
          : '${km.toStringAsFixed(1)} km away');
  static String fromPrice(String price) =>
      isNepali ? '$price देखि' : 'from $price';

  // ── Phone auth ───────────────────────────────────────────
  static String get welcomeTo => _t('welcome_to');
  static String get welcomeTagline => _t('welcome_tagline');
  static String get confirm => _t('confirm');
  static String get createOrChangeAccount => _t('create_or_change_account');
  static String get phoneInputTitle => _t('phone_input_title');
  static String get phoneInputSub => _t('phone_input_sub');
  static String get phoneNumberLabel => _t('phone_number_label');
  static String get countryCode => _t('country_code');
  static String get continueWord => _t('continue_word');
  static String get otpTitle => _t('otp_title');
  static String otpSentTo(String phone) =>
      isNepali ? '$phone मा code पठाइयो' : 'Code sent to $phone';
  static String get otpCodeLabel => _t('otp_code_label');
  static String get verify => _t('verify');
  static String get resendCode => _t('resend_code');
  static String get wrongNumber => _t('wrong_number');
  static String get enterValidPhone => _t('enter_valid_phone');
  static String get enterOtp => _t('enter_otp');
  static String get otpFailed => _t('otp_failed');
  static String get phoneAuthNotEnabled => _t('phone_auth_not_enabled');
  static String get anonNotEnabled => _t('anon_not_enabled');

  // ── Auth ─────────────────────────────────────────────────
  static String get emailLabel => _t('email_label');
  static String get passwordLabel => _t('password_label');
  static String get loginAction => _t('login_action');
  static String get signupAction => _t('signup_action');
  static String get toSignup => _t('to_signup');
  static String get toLogin => _t('to_login');
  static String get orWord => _t('or_word');
  static String get signInWithGoogle => _t('sign_in_google');

  // ─────────────────────────────────────────────────────────
  static const Map<String, Map<String, String>> _values = {
    'cancel': {'en': 'Cancel', 'ne': 'रद्द गर्नुहोस्'},
    'ok': {'en': 'OK', 'ne': 'ठीक छ'},
    'save': {'en': 'Save', 'ne': 'सुरक्षित गर्नुहोस्'},
    'delete': {'en': 'Delete', 'ne': 'मेटाउनुहोस्'},
    'logout': {'en': 'Logout', 'ne': 'लगआउट'},
    'error': {'en': 'Error', 'ne': 'त्रुटि'},

    'nav_home': {'en': 'Home', 'ne': 'गृह'},
    'nav_requests': {'en': 'Requests', 'ne': 'अनुरोध'},
    'nav_messages': {'en': 'Messages', 'ne': 'सन्देश'},
    'nav_profile': {'en': 'Profile', 'ne': 'प्रोफाइल'},
    'nav_watchlist': {'en': 'Watchlist', 'ne': 'सूची'},

    'greeting': {'en': 'Hello 👋', 'ne': 'नमस्ते 👋'},
    'home_question': {
      'en': 'What service do you need?',
      'ne': 'कस्तो सेवा चाहियो?'
    },
    'search_hint': {
      'en': 'Search — Plumber, Driver, Cleaner...',
      'ne': 'खोज्नुहोस् — प्लम्बर, ड्राइभर, सफाइ...'
    },
    'services_title': {'en': 'Services', 'ne': 'सेवाहरू'},
    'see_all': {'en': 'See all', 'ne': 'सबै हेर्नुहोस्'},
    'hero_title': {
      'en': 'Find trusted local\nservices',
      'ne': 'भरपर्दो स्थानीय\nसेवाहरू खोज्नुहोस्'
    },
    'hero_subtitle': {
      'en': 'Quick · Reliable · Affordable',
      'ne': 'छिटो · भरपर्दो · सस्तो'
    },
    'location_label': {'en': 'Kathmandu, Nepal', 'ne': 'काठमाडौँ, नेपाल'},

    'where_and_price': {
      'en': 'Where & for how much?',
      'ne': 'कहाँ र कति मूल्यमा?'
    },
    'region_available': {
      'en': 'KaamMitra is available in your area',
      'ne': 'तपाईंको क्षेत्रमा KaamMitra उपलब्ध छ'
    },
    'region_unavailable': {
      'en': "KaamMitra isn't in your region yet — we're expanding soon",
      'ne': 'तपाईंको क्षेत्रमा KaamMitra अझै छैन — चाँडै विस्तार हुँदैछ'
    },
    'location_off_title': {
      'en': 'Turn on your location',
      'ne': 'आफ्नो स्थान अन गर्नुहोस्'
    },
    'location_off_body': {
      'en':
          'We use your location to show nearby providers and the distance to each one.',
      'ne':
          'नजिकका प्रदायक र प्रत्येकसम्मको दूरी देखाउन हामी तपाईंको स्थान प्रयोग गर्छौं।'
    },
    'not_now': {'en': 'Not now', 'ne': 'अहिले होइन'},
    'open_settings': {'en': 'Open settings', 'ne': 'सेटिङ खोल्नुहोस्'},
    'menu_city': {'en': 'City', 'ne': 'सहर'},
    'menu_request_history': {
      'en': 'Request history',
      'ne': 'अनुरोध इतिहास'
    },
    'menu_providers': {'en': 'Providers', 'ne': 'प्रदायकहरू'},
    'menu_notifications': {'en': 'Notifications', 'ne': 'सूचनाहरू'},
    'menu_support': {'en': 'Support', 'ne': 'सहयोग'},
    'provider_mode': {'en': 'Provider mode', 'ne': 'प्रदायक मोड'},
    'become_provider': {'en': 'Become a provider', 'ne': 'प्रदायक बन्नुहोस्'},

    'my_bookings': {'en': 'My Bookings', 'ne': 'मेरा बुकिङहरू'},
    'messages': {'en': 'Messages', 'ne': 'सन्देशहरू'},
    'saved_workers': {'en': 'Saved Workers', 'ne': 'सुरक्षित कामदार'},
    'my_reviews': {'en': 'My Reviews', 'ne': 'मेरा समीक्षा'},
    'payment_methods': {'en': 'Payment Methods', 'ne': 'भुक्तानी विधि'},
    'help_support': {'en': 'Help & Support', 'ne': 'सहायता'},
    'about_app': {'en': 'About KaamMitra', 'ne': 'KaamMitra बारे'},
    'settings': {'en': 'Settings', 'ne': 'सेटिङ'},

    'appearance': {'en': 'Appearance', 'ne': 'रूप'},
    'theme_light': {'en': 'Light', 'ne': 'उज्यालो'},
    'theme_dark': {'en': 'Dark', 'ne': 'अँध्यारो'},
    'theme_system': {'en': 'System Default', 'ne': 'सिस्टम अनुसार'},
    'language': {'en': 'Language', 'ne': 'भाषा'},
    'legal_documents': {'en': 'Legal Documents', 'ne': 'कानुनी कागजात'},
    'log_out': {'en': 'Log Out', 'ne': 'लगआउट गर्नुहोस्'},
    'delete_account': {'en': 'Delete Account', 'ne': 'खाता मेटाउनुहोस्'},
    'logout_confirm_title': {
      'en': 'Do you want to logout?',
      'ne': 'के तपाईं लगआउट गर्न चाहनुहुन्छ?'
    },
    'delete_account_body': {
      'en':
          'Are you sure? This cannot be undone. All your data will be permanently deleted.',
      'ne':
          'के तपाईं पक्का हुनुहुन्छ? यो कार्य फिर्ता गर्न मिल्दैन। तपाईंको सबै डाटा स्थायी रूपमा मेटिनेछ।'
    },

    'employer_reg_title': {'en': 'Employer profile', 'ne': 'रोजगारदाता प्रोफाइल'},
    'worker_reg_title': {'en': 'Worker registration', 'ne': 'कामदार दर्ता'},
    'reg_worker_note': {
      'en': 'Your profile goes live after admin approval.',
      'ne': 'Admin ले स्वीकृत गरेपछि तपाईंको प्रोफाइल live हुन्छ।'
    },
    'first_name': {'en': 'First name', 'ne': 'नाम'},
    'last_name': {'en': 'Last name', 'ne': 'थर'},
    'phone': {'en': 'Phone number', 'ne': 'फोन नम्बर'},
    'dob': {'en': 'Date of birth', 'ne': 'जन्म मिति'},
    'pick_date': {'en': 'Pick a date', 'ne': 'मिति छान्नुहोस्'},
    'location_section': {'en': 'Your location', 'ne': 'तपाईंको स्थान'},
    'use_my_location': {'en': 'Use my current location', 'ne': 'मेरो स्थान प्रयोग गर्नुहोस्'},
    'location_captured': {'en': 'Location captured', 'ne': 'स्थान लिइयो'},
    'location_denied_short': {
      'en': 'Permission denied — you can add it later',
      'ne': 'अनुमति अस्वीकृत — पछि थप्न सकिन्छ'
    },
    'getting_location': {'en': 'Getting location…', 'ne': 'स्थान लिँदै…'},
    'service_category': {'en': 'Service category', 'ne': 'सेवा श्रेणी'},
    'experience_label': {'en': 'Experience', 'ne': 'अनुभव'},
    'years_word': {'en': 'yrs', 'ne': 'वर्ष'},
    'months_word': {'en': 'mos', 'ne': 'महिना'},
    'starting_price': {'en': 'Starting price (Rs.)', 'ne': 'सुरु मूल्य (रु.)'},
    'district': {'en': 'District', 'ne': 'जिल्ला'},
    'area_landmark': {
      'en': 'Area / tole / landmark',
      'ne': 'क्षेत्र / टोल / ल्यान्डमार्क'
    },
    'experience_certificate': {
      'en': 'Experience certificate',
      'ne': 'अनुभव प्रमाणपत्र'
    },
    'add_document': {'en': 'Add document / photo', 'ne': 'कागजात / फोटो थप्नुहोस्'},
    'next': {'en': 'Next', 'ne': 'अगाडि'},
    'submit_for_approval': {
      'en': 'Submit for approval',
      'ne': 'स्वीकृतिका लागि पठाउनुहोस्'
    },
    'enter_name': {'en': 'Enter your name', 'ne': 'नाम लेख्नुहोस्'},
    'enter_phone': {'en': 'Enter phone number', 'ne': 'फोन नम्बर लेख्नुहोस्'},
    'enter_area': {'en': 'Enter your area', 'ne': 'क्षेत्र लेख्नुहोस्'},
    'upload_doc_first': {
      'en': 'Please upload your certificate first',
      'ne': 'पहिले प्रमाणपत्र अपलोड गर्नुहोस्'
    },
    'application_submitted': {'en': 'Application submitted!', 'ne': 'आवेदन पठाइयो!'},
    'application_submitted_body': {
      'en':
          'Your registration has been sent to the admin. You will get access once approved.',
      'ne':
          'तपाईंको दर्ता Admin लाई पठाइयो। स्वीकृत भएपछि access पाउनुहुनेछ।'
    },
    'doc_rejected_banner': {
      'en':
          'Your previous document was rejected. Please upload a valid document and submit again.',
      'ne':
          'तपाईंको अघिल्लो कागजात अस्वीकृत भयो। कृपया मान्य कागजात अपलोड गरी फेरि पठाउनुहोस्।'
    },
    'view_document': {'en': 'View document', 'ne': 'कागजात हेर्नुहोस्'},
    'uploading': {'en': 'Uploading…', 'ne': 'अपलोड हुँदै…'},
    'approve': {'en': 'Approve', 'ne': 'स्वीकृत गर्नुहोस्'},
    'reject': {'en': 'Reject', 'ne': 'अस्वीकृत गर्नुहोस्'},
    'back_word': {'en': 'Back', 'ne': 'पछाडि'},
    'step_details': {'en': 'Details', 'ne': 'विवरण'},
    'step_document': {'en': 'Document', 'ne': 'कागजात'},
    'step_selfie': {'en': 'Selfie', 'ne': 'सेल्फी'},
    'selfie_verification': {
      'en': 'Selfie verification',
      'ne': 'सेल्फी प्रमाणीकरण'
    },
    'selfie_hint': {
      'en': 'Take a clear live photo of your face. This is checked against your document.',
      'ne': 'आफ्नो अनुहारको स्पष्ट लाइभ फोटो खिच्नुहोस्। यो कागजातसँग मिलाइन्छ।'
    },
    'take_selfie': {'en': 'Take selfie', 'ne': 'सेल्फी खिच्नुहोस्'},
    'retake': {'en': 'Retake', 'ne': 'फेरि खिच्नुहोस्'},
    'selfie_required': {
      'en': 'Please take a selfie to continue',
      'ne': 'अगाडि बढ्न सेल्फी खिच्नुहोस्'
    },
    'vehicle_details': {
      'en': 'Vehicle (model & number plate)',
      'ne': 'सवारी (मोडल र नम्बर प्लेट)'
    },
    'vehicle_hint': {
      'en': 'e.g. Bajaj Pulsar — Ba 12 Pa 3456',
      'ne': 'जस्तै: Bajaj Pulsar — बा १२ प ३४५६'
    },
    'reject_reason_title': {
      'en': 'Reject — reason',
      'ne': 'अस्वीकृत — कारण'
    },
    'reject_reason_hint': {
      'en': 'e.g. Document is blurry / does not match name',
      'ne': 'जस्तै: कागजात धमिलो छ / नाम मिलेन'
    },
    'reason_label': {'en': 'Reason', 'ne': 'कारण'},
    'selfie_photo': {'en': 'Selfie', 'ne': 'सेल्फी'},

    'saved_places_title': {'en': 'Saved places', 'ne': 'सुरक्षित स्थानहरू'},
    'save_as_home': {'en': 'Save as Home', 'ne': 'घर सेभ गर्नुहोस्'},
    'save_as_work': {'en': 'Save as Work', 'ne': 'कार्यस्थल सेभ गर्नुहोस्'},
    'add_another_place': {'en': 'Add another place', 'ne': 'अर्को स्थान थप्नुहोस्'},
    'not_set_yet': {'en': 'Not set yet', 'ne': 'अझै सेट गरिएको छैन'},
    'pick_on_map': {'en': 'Pick on map', 'ne': 'नक्सामा छान्नुहोस्'},
    'confirm_location': {'en': 'Confirm location', 'ne': 'स्थान पुष्टि गर्नुहोस्'},
    'fetching_address': {'en': 'Fetching address…', 'ne': 'ठेगाना ल्याउँदै…'},
    'place_label': {'en': 'Label (e.g. Home, Mom\'s house)', 'ne': 'नाम (जस्तै: घर, आमाको घर)'},
    'move_map_hint': {
      'en': 'Move the map to place the pin',
      'ne': 'पिन राख्न नक्सा सार्नुहोस्'
    },
    'place_saved': {'en': 'Place saved', 'ne': 'स्थान सेभ भयो'},

    'reviews_title': {'en': 'My Reviews', 'ne': 'मेरो समीक्षा'},
    'based_on_reviews': {'en': 'based on', 'ne': 'आधारित'},
    'sort_by': {'en': 'Sort by', 'ne': 'क्रमबद्ध गर्नुहोस्'},
    'sort_recent': {'en': 'Most recent', 'ne': 'नयाँ पहिले'},
    'sort_highest': {'en': 'Highest rated', 'ne': 'उच्च रेटिङ'},
    'sort_lowest': {'en': 'Lowest rated', 'ne': 'न्यून रेटिङ'},
    'no_reviews_yet': {'en': 'No reviews yet', 'ne': 'अझै कुनै समीक्षा छैन'},

    'payments_title': {'en': 'Payment methods', 'ne': 'भुक्तानी विधि'},
    'payments_sub': {
      'en': 'Choose how you pay after a job is done.',
      'ne': 'काम सकिएपछि कसरी तिर्ने भन्ने छान्नुहोस्।'
    },
    'pay_qr': {'en': 'QR code — Scan & Pay', 'ne': 'QR कोड — Scan & Pay'},
    'pay_qr_sub': {
      'en': 'Show or scan a QR to transfer instantly',
      'ne': 'तुरुन्तै पठाउन QR देखाउनुहोस् वा scan गर्नुहोस्'
    },
    'pay_esewa': {'en': 'eSewa', 'ne': 'ई-सेवा'},
    'pay_khalti': {'en': 'Khalti', 'ne': 'खल्ती'},
    'wallet_id_label': {'en': 'Wallet ID / mobile', 'ne': 'Wallet ID / मोबाइल'},
    'scan_to_pay': {'en': 'Scan to pay', 'ne': 'तिर्न scan गर्नुहोस्'},
    'open_wallet': {'en': 'Open wallet', 'ne': 'Wallet खोल्नुहोस्'},

    'service_standard': {'en': 'Service Standard', 'ne': 'सर्भिस स्ट्यान्डर्ड'},
    'service_standard_sub': {
      'en': "Workers' rights & KaamMitra's commitments",
      'ne': 'कामदारको हक र KaamMitra का प्रतिबद्धता'
    },
    'worker_no_response': {
      'en': "Worker didn't respond",
      'ne': 'कामदारले जवाफ दिएन'
    },
    'worker_no_response_sub': {
      'en': 'Message the admin if a worker goes silent',
      'ne': 'कामदारले जवाफ नदिए admin लाई सन्देश पठाउनुहोस्'
    },
    'faq': {'en': 'Frequently asked questions', 'ne': 'बारम्बार सोधिने प्रश्न'},
    'contact_support': {'en': 'Contact support', 'ne': 'सम्पर्क सहयोग'},
    'contact_support_unset': {
      'en': 'Support number will be added soon.',
      'ne': 'सहयोग नम्बर चाँडै थपिनेछ।'
    },
    'call_support': {'en': 'Call support', 'ne': 'सहयोगमा कल गर्नुहोस्'},
    'privacy_policy': {'en': 'Privacy policy', 'ne': 'प्राइभेसी पोलिसी'},
    'data_security': {'en': 'Data security', 'ne': 'डाटा सेक्युरिटी'},
    'data_secure_line': {
      'en': 'Your data is secure with us.',
      'ne': 'तपाईंको डाटा हामीसँग सुरक्षित छ।'
    },
    'support_number_label': {
      'en': 'Support phone number',
      'ne': 'सहयोग फोन नम्बर'
    },
    'edit_support_number': {
      'en': 'Edit support number',
      'ne': 'सहयोग नम्बर सम्पादन गर्नुहोस्'
    },
    'saved': {'en': 'Saved', 'ne': 'सेभ भयो'},

    'watchlist_title': {'en': 'Watchlist', 'ne': 'मन पर्ने सेवा'},
    'watchlist_hint': {
      'en': 'Tap a category to browse workers',
      'ne': 'कामदार हेर्न श्रेणीमा tap गर्नुहोस्'
    },

    'nearby_title': {'en': 'Nearby workers', 'ne': 'नजिकका कामदार'},
    'find_nearby': {
      'en': 'Find nearby workers',
      'ne': 'नजिकका कामदार खोज्नुहोस्'
    },
    'filter_all': {'en': 'All', 'ne': 'सबै'},
    'offer_your_price': {
      'en': 'Offer your price',
      'ne': 'आफ्नो मूल्य offer गर्नुहोस्'
    },
    'asking_price': {'en': 'Asking price', 'ne': 'माग मूल्य'},
    'your_offer': {'en': 'Your offer', 'ne': 'तपाईंको offer'},
    'send_offer': {'en': 'Send offer', 'ne': 'Offer पठाउनुहोस्'},
    'describe_task': {'en': 'Describe the task', 'ne': 'काम बताउनुहोस्'},
    'describe_task_hint': {
      'en': 'e.g. Kitchen pipe leaking',
      'ne': 'जस्तै: भान्साको पाइप चुहिएको'
    },
    'offer_sent_title': {'en': 'Offer sent!', 'ne': 'Offer पठाइयो!'},
    'offer_sent_body': {
      'en':
          'The worker will accept your price or send a counter-offer. Track it in My Bookings.',
      'ne':
          'कामदारले तपाईंको मूल्य स्वीकार गर्नेछ वा नयाँ मूल्य पठाउनेछ। My Bookings मा हेर्नुहोस्।'
    },
    'enable_location': {'en': 'Enable location', 'ne': 'Location अन गर्नुहोस्'},
    'location_needed_title': {
      'en': 'Location needed',
      'ne': 'Location चाहियो'
    },
    'location_needed_body': {
      'en':
          'Allow location access to see workers near you and how far they are.',
      'ne':
          'नजिकका कामदार र तिनको दूरी हेर्न location अनुमति दिनुहोस्।'
    },
    'approx_location': {
      'en': 'Approximate — location off',
      'ne': 'अनुमानित — location बन्द'
    },
    'no_workers_nearby': {
      'en': 'No workers found nearby',
      'ne': 'नजिक कुनै कामदार भेटिएन'
    },
    'retry': {'en': 'Retry', 'ne': 'फेरि प्रयास'},

    'welcome_to': {'en': 'Welcome to KaamMitra', 'ne': 'KaamMitra मा स्वागत छ'},
    'welcome_tagline': {
      'en': 'Trusted local workers, your price.',
      'ne': 'भरपर्दो स्थानीय कामदार, तपाईंकै मूल्यमा।'
    },
    'confirm': {'en': 'Confirm', 'ne': 'पुष्टि गर्नुहोस्'},
    'create_or_change_account': {
      'en': 'Create account / Change account',
      'ne': 'खाता बनाउनुहोस् / खाता बदल्नुहोस्'
    },
    'phone_input_title': {
      'en': 'Enter your phone number',
      'ne': 'आफ्नो फोन नम्बर लेख्नुहोस्'
    },
    'phone_input_sub': {
      'en': "We'll send a verification code by SMS.",
      'ne': 'हामी SMS बाट verification code पठाउनेछौं।'
    },
    'phone_number_label': {'en': 'Phone number', 'ne': 'फोन नम्बर'},
    'country_code': {'en': 'Country', 'ne': 'देश'},
    'continue_word': {'en': 'Continue', 'ne': 'अगाडि बढ्नुहोस्'},
    'otp_title': {'en': 'Verify your number', 'ne': 'नम्बर verify गर्नुहोस्'},
    'otp_code_label': {'en': '6-digit code', 'ne': '6-अंकको code'},
    'verify': {'en': 'Verify', 'ne': 'Verify गर्नुहोस्'},
    'resend_code': {'en': 'Resend code', 'ne': 'फेरि code पठाउनुहोस्'},
    'wrong_number': {'en': 'Wrong number? Go back', 'ne': 'गलत नम्बर? फर्कनुहोस्'},
    'enter_valid_phone': {
      'en': 'Enter a valid phone number',
      'ne': 'सही फोन नम्बर लेख्नुहोस्'
    },
    'enter_otp': {'en': 'Enter the 6-digit code', 'ne': '6-अंकको code लेख्नुहोस्'},
    'otp_failed': {
      'en': 'Verification failed. Check the code and try again.',
      'ne': 'Verify हुन सकेन। code जाँचेर फेरि प्रयास गर्नुहोस्।'
    },
    'phone_auth_not_enabled': {
      'en':
          'Phone sign-in is not enabled for this project. In Firebase Console → Authentication → Sign-in method, enable Phone (and add a test number to verify without SMS).',
      'ne':
          'यो project मा Phone sign-in on छैन। Firebase Console → Authentication → Sign-in method मा Phone enable गर्नुहोस् (SMS बिना test गर्न test number थप्नुहोस्)।'
    },
    'anon_not_enabled': {
      'en':
          'Free test login needs Anonymous sign-in. In Firebase Console → Authentication → Sign-in method, enable Anonymous.',
      'ne':
          'नि:शुल्क test login लाई Anonymous sign-in चाहिन्छ। Firebase Console → Authentication → Sign-in method मा Anonymous enable गर्नुहोस्।'
    },

    'email_label': {'en': 'Email', 'ne': 'इमेल'},
    'password_label': {'en': 'Password', 'ne': 'पासवर्ड'},
    'login_action': {'en': 'Log in', 'ne': 'लगइन गर्नुहोस्'},
    'signup_action': {'en': 'Sign up', 'ne': 'साइन अप गर्नुहोस्'},
    'to_signup': {
      'en': "No account? Create a new one",
      'ne': 'खाता छैन? नयाँ खाता बनाउनुहोस्'
    },
    'to_login': {
      'en': 'Already have an account? Log in',
      'ne': 'पहिले नै खाता छ? लगइन गर्नुहोस्'
    },
    'or_word': {'en': 'OR', 'ne': 'वा'},
    'sign_in_google': {'en': 'Sign in with Google', 'ne': 'Google बाट लगइन'},
  };

  static const Map<String, String> _serviceNe = {
    'Mechanic': 'मेकानिक',
    'Plumber': 'प्लम्बर',
    'Carpenter': 'सिकर्मी',
    'Painter': 'रंगरोगन',
    'Cleaner': 'सफाइ',
    'Driver': 'चालक',
    'Electrician': 'बिजुली',
    'Tutor': 'ट्युटर',
  };
}
