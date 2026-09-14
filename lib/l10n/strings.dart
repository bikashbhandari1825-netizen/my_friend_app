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
  static String get send => _t('send');
  static String get delete => _t('delete');
  static String get logout => _t('logout');
  static String get errorWord => _t('error');

  // ── Bottom navigation ────────────────────────────────────
  static String get navHome => _t('nav_home');
  static String get navRequests => _t('nav_requests');
  static String get navMessages => _t('nav_messages');
  static String get navProfile => _t('nav_profile');
  static String get navWatchlist => _t('nav_watchlist');
  static String get navJobFeed => _t('nav_job_feed');
  static String get navBookings => _t('nav_bookings');

  // ── Active job bar (pinned above bottom nav) ────────────
  static String get activeJobBarCancelTitle => _t('active_job_bar_cancel_title');
  static String get activeJobBarCancelBody => _t('active_job_bar_cancel_body');
  static String get keepJob => _t('keep_job');

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
  static String get settingsPrefsSection => _t('settings_prefs_section');
  static String get settingsAboutSection => _t('settings_about_section');
  static String get settingsAccountSection => _t('settings_account_section');

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
  static String get selectVehicleType => _t('select_vehicle_type');
  static String get bikeWord => _t('bike_word');
  static String get carWord => _t('car_word');
  static String get bikeRideHint => _t('bike_ride_hint');
  static String get carRideHint => _t('car_ride_hint');
  static String get selectVehicleTypeError => _t('select_vehicle_type_error');
  static String get drivingLicenseLabel => _t('driving_license_label');
  static String get vehicleRegistrationLabel =>
      _t('vehicle_registration_label');
  static String get vehicleDocsRequiredHint =>
      _t('vehicle_docs_required_hint');
  static String get uploadDriverDocsError => _t('upload_driver_docs_error');
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
  static String get applicationSubmittedBody =>
      _t('application_submitted_body');
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

  // ── Worker profile detail (watchlist → tap a worker) ─────
  static String get locationRowLabel => _t('location_row_label');
  static String get documentAvailable => _t('document_available');
  static String get callToBook => _t('call_to_book');
  static String requestServiceFrom(String name) => isNepali
      ? '$name लाई सेवा अनुरोध'
      : 'Request service from $name';
  static String get describeYourTask => _t('describe_your_task');
  static String get serviceRequestSentTitle =>
      _t('service_request_sent_title');
  static String get serviceRequestSentBody => _t('service_request_sent_body');
  static String get contactLockedCaption => _t('contact_locked_caption');
  static String get openChatLabel => _t('open_chat_label');
  static String get chatLockedCompleted => _t('chat_locked_completed');

  // ── Nearby / bidding ─────────────────────────────────────
  static String get nearbyTitle => _t('nearby_title');
  static String get findNearby => _t('find_nearby');
  static String get filterAll => _t('filter_all');
  static String get offerYourPrice => _t('offer_your_price');
  static String get askingPrice => _t('asking_price');
  static String get yourOffer => _t('your_offer');
  static String get sendOffer => _t('send_offer');
  static String get viewDetails => _t('view_details');
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
      ? (isNepali
          ? '${(km * 1000).round()} मि टाढा'
          : '${(km * 1000).round()} m away')
      : (isNepali
          ? '${km.toStringAsFixed(1)} किमी टाढा'
          : '${km.toStringAsFixed(1)} km away');
  static String fromPrice(String price) =>
      isNepali ? '$price देखि' : 'from $price';

  // ── Map booking (Pathao/InDrive-style) ───────────────────
  static String requestService(String s) =>
      isNepali ? '$s अनुरोध गर्नुहोस्' : 'Request $s';
  static String get sendRequest => _t('send_request');
  static String get findingProviders => _t('finding_providers');
  static String get waitingAccept => _t('waiting_accept');
  static String get providerOnTheWay => _t('provider_on_the_way');
  static String get noProviderAccepted => _t('no_provider_accepted');
  static String get cancelRequest => _t('cancel_request');
  static String get requestCancelled => _t('request_cancelled');
  static String get accept => _t('accept_word');
  static String get decline => _t('decline_word');
  static String get newJobNearby => _t('new_job_nearby');
  static String get jobRequests => _t('job_requests');
  static String get onlineForJobs => _t('online_for_jobs');
  static String get callWord => _t('call_word');
  static String get messageWord => _t('message_word');
  static String get trackOnMap => _t('track_on_map');
  static String get providersNearby => _t('providers_nearby');
  static String get requestSent => _t('request_sent');
  static String get jobAccepted => _t('job_accepted');
  static String get estimatedFare => _t('estimated_fare');
  static String get yourOfferPrice => _t('your_offer_price');
  static String get suggestedFare => _t('suggested_fare');
  static String get offerPrice => _t('offer_price_word');
  static String get dragForMore => _t('drag_for_more');
  static String get notAuthorizedForJobCategory =>
      _t('not_authorized_for_job_category');

  // ── Worker approval / role ───────────────────────────────
  static String get applicationSafeHelper => _t('application_safe_helper');
  static String get workerRoleWord => _t('worker_role_word');
  static String get employerRoleWord => _t('employer_role_word');

  // ── Live counter-offer alert (worker side) ───────────────
  static String get statusCounterOffer => _t('status_counter_offer');
  static String get customerCounteredTitle => _t('customer_countered_title');
  static String get customerCounteredBody => _t('customer_countered_body');
  static String get previousPriceLabel => _t('previous_price_label');
  static String get theirOfferLabel => _t('their_offer_label');
  static String get declineOrCounter => _t('decline_or_counter');
  static String get counterBack => _t('counter_back');
  static String get workerCounteredTitle => _t('worker_countered_title');
  static String get workerCounteredBody => _t('worker_countered_body');
  static String get acceptCounterOffer => _t('accept_counter_offer');
  static String get bookingConfirmed => _t('booking_confirmed');
  static String get sendNewPrice => _t('send_new_price');
  static String get declineJob => _t('decline_job');
  static String get yourPriceRs => _t('your_price_rs');
  static String get newPriceSentToCustomer => _t('new_price_sent_to_customer');
  static String get counterSentToWorker => _t('counter_sent_to_worker');
  static String get waitingWorkerCounterReply =>
      _t('waiting_worker_counter_reply');
  static String get fileTooLarge => _t('file_too_large');
  static String get fileTypeNotAllowed => _t('file_type_not_allowed');
  static String get fileEmptyOrCorrupt => _t('file_empty_or_corrupt');
  static String get fileContentMismatch => _t('file_content_mismatch');

  // ── Document upload / resync ─────────────────────────────
  static String get docsUploadPendingNote => _t('docs_upload_pending_note');
  static String get docsNotUploadedTitle => _t('docs_not_uploaded_title');
  static String get docsNotUploadedBody => _t('docs_not_uploaded_body');
  static String get reuploadDocuments => _t('reupload_documents');
  static String get docsResyncTitle => _t('docs_resync_title');
  static String get docsSyncedOk => _t('docs_synced_ok');
  static String get docsSyncFailedStorage => _t('docs_sync_failed_storage');
  static String get docsSyncFailedNetwork => _t('docs_sync_failed_network');
  static String get selectIdDoc => _t('select_id_doc');
  static String get selectSelfie => _t('select_selfie');
  static String get uploadNow => _t('upload_now');

  // ── Worker dashboard: radar filters / earnings / schedule / badge ──
  static String get filterDistance => _t('filter_distance');
  static String get allTrades => _t('all_trades');
  static String get myTrade => _t('my_trade');
  static String kmRadius(int n) => isNepali ? '$n किमी' : '$n km';
  static String get enableLocationForDistance =>
      _t('enable_location_for_distance');

  static String get earningsTitle => _t('earnings_title');
  static String get walletBalance => _t('wallet_balance');
  static String get grossEarnings => _t('gross_earnings');
  static String get commissionDeducted => _t('commission_deducted');
  static String get thisWeek => _t('this_week');
  static String get thisMonth => _t('this_month');
  static String get allTime => _t('all_time');
  static String get jobsCompletedLabel => _t('jobs_completed_label');
  static String get markComplete => _t('mark_complete');
  static String get jobMarkedComplete => _t('job_marked_complete');
  static String get collectPayment => _t('collect_payment');
  static String get amountDue => _t('amount_due');
  static String get paymentMethodLabel => _t('payment_method_label');
  static String get cashWord => _t('cash_word');
  static String get digitalWord => _t('digital_word');
  static String get confirmPaymentReceived => _t('confirm_payment_received');
  static String get completeJobTitle => _t('complete_job_title');
  static String get confirmCompleteJob => _t('confirm_complete_job');
  static String rateWorkerTitle(String name) =>
      isNepali ? '$name लाई रेटिङ दिनुहोस्' : 'Rate $name\'s service';
  static String get addCommentOptional => _t('add_comment_optional');
  static String get waitingEmployerComplete =>
      _t('waiting_employer_complete');
  static String get last7Days => _t('last_7_days');
  static String get noEarningsYet => _t('no_earnings_yet');
  static String get perJobBreakdown => _t('per_job_breakdown');
  static String commissionPctLabel(int pct) =>
      isNepali ? 'कमिसन ($pct%)' : 'Commission ($pct%)';

  static String get scheduleTitle => _t('schedule_title');
  static String get noScheduledJobs => _t('no_scheduled_jobs');
  static String get noJobsThisDay => _t('no_jobs_this_day');
  static String get upcomingJobs => _t('upcoming_jobs');

  static String get topWorker => _t('top_worker');
  static String get noRatingsYet => _t('no_ratings_yet');
  static String ratingCount(int n) => isNepali ? '$n समीक्षा' : '$n reviews';
  static String get myEarnings => _t('my_earnings');
  static String get mySchedule => _t('my_schedule');

  // ── Worker profile hub: portfolio / KYC / notifications ──
  static String get workPortfolio => _t('work_portfolio');
  static String get portfolioEmpty => _t('portfolio_empty');
  static String get portfolioEmptyOther => _t('portfolio_empty_other');
  static String get addWorkPhoto => _t('add_work_photo');
  static String get photoAdded => _t('photo_added');
  static String get removePhoto => _t('remove_photo');
  static String get fromCamera => _t('from_camera');
  static String get fromGallery => _t('from_gallery');
  static String get documentsKyc => _t('documents_kyc');
  static String get kycVerified => _t('kyc_verified');
  static String get kycUnderReview => _t('kyc_under_review');
  static String get kycRejected => _t('kyc_rejected');
  static String get kycNotSubmitted => _t('kyc_not_submitted');
  static String get resubmit => _t('resubmit');
  static String get notificationsLabel => _t('notifications_label');
  static String get notificationsOn => _t('notifications_on');
  static String get notificationsOff => _t('notifications_off');
  static String get workerAccount => _t('worker_account');

  // ── KYC rework: citizenship + selfie-with-ID + certificates ──
  static String get stepIdentity => _t('step_identity');
  static String get stepCertificates => _t('step_certificates');
  static String get citizenshipTitle => _t('citizenship_title');
  static String get citizenshipHint => _t('citizenship_hint');
  static String get citizenshipFront => _t('citizenship_front');
  static String get citizenshipBack => _t('citizenship_back');
  static String get uploadBothCitizenship => _t('upload_both_citizenship');
  static String get selfieWithIdTitle => _t('selfie_with_id_title');
  static String get selfieWithIdHint => _t('selfie_with_id_hint');
  static String get certsTitle => _t('certs_title');
  static String get certsHint => _t('certs_hint');
  static String get addCertificate => _t('add_certificate');
  static String get certsOptional => _t('certs_optional');
  static String get citizenshipFrontShort => _t('citizenship_front_short');
  static String get citizenshipBackShort => _t('citizenship_back_short');
  static String get certificatesLabel => _t('certificates_label');
  static String get takePhoto => _t('take_photo');
  static String get chooseFile => _t('choose_file');

  // ── Admin: user management ──────────────────────────────
  static String get deleteUser => _t('delete_user');
  static String get deleteUserTitle => _t('delete_user_title');
  static String get deleteUserBody => _t('delete_user_body');
  static String get userDeleted => _t('user_deleted');

  // ── Admin: generic delete (requests / reports / support) ──
  static String get deleteConfirmTitle => _t('delete_confirm_title');
  static String get deletedWord => _t('deleted_word');
  static String deleteConfirmBody(String what) => isNepali
      ? 'के तपाईं यो $what मेटाउन निश्चित हुनुहुन्छ? यो फिर्ता ल्याउन मिल्दैन।'
      : 'Are you sure you want to delete this $what? This cannot be undone.';
  static String get jobRequestWord => _t('job_request_word');
  static String get reportWord => _t('report_word');
  static String get supportTicketWord => _t('support_ticket_word');
  static String get pendingWorkerWord => _t('pending_worker_word');
  static String get userWord => _t('user_word');
  static String get searchByEmailOrPhone => _t('search_by_email_or_phone');

  // ── Admin: bulk select & delete ──────────────────────────
  static String get selectAll => _t('select_all');
  static String get deleteSelected => _t('delete_selected');
  static String nSelected(int n) => isNepali ? '$n छानियो' : '$n selected';
  static String deletedNItems(int n) => isNepali ? '$n मेटाइयो' : '$n deleted';
  static String failedNItems(int n) => isNepali ? '$n असफल' : '$n failed';
  static String bulkDeleteBody(int n, String what) => isNepali
      ? '$n वटा $what मेटाउने हो? यो फिर्ता ल्याउन मिल्दैन।'
      : 'Delete $n ${what}s? This cannot be undone.';

  static String get availableForJobs => _t('available_for_jobs');
  static String get youAreOnline => _t('you_are_online');
  static String get youAreOffline => _t('you_are_offline');

  // ── Post a job / job feed (Phase 1+2) ────────────────────
  static String get postJobTitle => _t('post_job_title');
  static String get jobDescription => _t('job_description');
  static String get jobDescriptionHint => _t('job_description_hint');
  static String get preferredDateLabel => _t('preferred_date_label');
  static String get timeSlotLabel => _t('time_slot_label');
  static String get slotMorning => _t('slot_morning');
  static String get slotAfternoon => _t('slot_afternoon');
  static String get slotEvening => _t('slot_evening');
  static String get slotAnytime => _t('slot_anytime');
  static String get jobAddressLabel => _t('job_address_label');
  static String get postJob => _t('post_job');
  static String get openJobsNearby => _t('open_jobs_nearby');
  static String get noOpenJobs => _t('no_open_jobs');
  static String get customerBudget => _t('customer_budget');
  static String get viewJobLocation => _t('view_job_location');
  static String get jobLocationTitle => _t('job_location_title');
  static String get jobDetailsTitle => _t('job_details_title');
  static String get describeJobFirst => _t('describe_job_first');
  static String get serviceAddressNote => _t('service_address_note');
  static String get pickDateFirst => _t('pick_date_first');
  static String get jobConfirmTitle => _t('job_confirm_title');
  static String get jobTitleLabel => _t('job_title_label');
  static String get jobTitleHint => _t('job_title_hint');
  static String get confirmBroadcast => _t('confirm_broadcast');
  static String get pinnedLocation => _t('pinned_location');
  static String get noWorkersOnlineNote => _t('no_workers_online_note');
  static String get newJobNotifTitle => _t('new_job_notif_title');
  static String get newCounterOfferNotifTitle =>
      _t('new_counter_offer_notif_title');
  static String newCounterOfferNotifBody(num price) => S.isNepali
      ? 'नयाँ मूल्य प्रस्ताव: Rs. $price'
      : 'New counter-offer: Rs. $price';
  static String get offerAcceptedNotifTitle =>
      _t('offer_accepted_notif_title');
  static String offerAcceptedNotifBody(String employerName, num amount) =>
      S.isNepali
          ? '$employerName ले Rs. $amount मा तपाईंको प्रस्ताव स्वीकार गर्नुभयो'
          : '$employerName accepted your offer for Rs. $amount';
  static String get staleOfferError => _t('stale_offer_error');
  static String get openInGoogleMaps => _t('open_in_google_maps');
  static String get routeFallbackWarning => _t('route_fallback_warning');
  static String get noPhoneOnFile => _t('no_phone_on_file');
  static String get activeJobTitle => _t('active_job_title');

  // ── Canonical job status labels ────────────────────────
  static String get statusSearching => _t('status_searching');
  static String get statusNew => _t('status_new');
  static String get statusCounter => _t('status_counter');
  static String get statusAccepted => _t('status_accepted');
  static String get statusInProgress => _t('status_in_progress');
  static String get statusCompleted => _t('status_completed');
  static String get statusCancelled => _t('status_cancelled');
  static String get startWork => _t('start_work');
  static String get workStarted => _t('work_started');
  static String get welcomeBack => _t('welcome_back');
  static String get loginToExisting => _t('login_to_existing');
  static String get continueWithPhone => _t('continue_with_phone');
  static String get continueWithEmail => _t('continue_with_email');
  static String get useEmailInstead => _t('use_email_instead');
  static String get usePhoneInstead => _t('use_phone_instead');
  static String get emailAuthTitle => _t('email_auth_title');
  static String get emailAuthSub => _t('email_auth_sub');
  static String get haveAccountLogin => _t('have_account_login');
  static String get noAccountSignup => _t('no_account_signup');
  static String get emailPasswordDisabled => _t('email_password_disabled');
  static String get loginNoMatchHint => _t('login_no_match_hint');
  static String get emailTakenSwitchLogin => _t('email_taken_switch_login');
  static String get wrongPasswordHint => _t('wrong_password_hint');
  static String get passwordAccountExistsHint =>
      _t('password_account_exists_hint');
  static String get googleSignInConfigError =>
      _t('google_sign_in_config_error');
  static String get googleSignInGenericError =>
      _t('google_sign_in_generic_error');
  static String get tooManyAttemptsHint => _t('too_many_attempts_hint');
  static String get forgotPassword => _t('forgot_password');
  static String get resetEmailEnterFirst => _t('reset_email_enter_first');
  static String get resetEmailSent => _t('reset_email_sent');
  static String get loginToYourAccount => _t('login_to_your_account');
  static String get createNewAccount => _t('create_new_account');
  static String get loginModeNote => _t('login_mode_note');
  static String get signupModeNote => _t('signup_mode_note');
  static String get passwordTooShort => _t('password_too_short');
  static String get enterValidEmail => _t('enter_valid_email');
  static String get approvedCelebrateTitle => _t('approved_celebrate_title');
  static String get approvedCelebrateBody => _t('approved_celebrate_body');
  static String get openingDashboard => _t('opening_dashboard');
  static String get noConversationsYet => _t('no_conversations_yet');
  static String get startTheConversation => _t('start_the_conversation');
  static String get typeMessage => _t('type_message');
  static String get youPrefix => _t('you_prefix');
  static String get activeRecently => _t('active_recently');
  static String get onlineNow => _t('online_now');
  static String get deleteChat => _t('delete_chat');
  static String get voiceMessage => _t('voice_message');
  static String get photo => _t('photo');

  // ── Home ↔ Workplace route ─────────────────────────────
  static String get homeToWorkRoute => _t('home_to_work_route');
  static String get viewRoute => _t('view_route');
  static String get routeTitle => _t('route_title');
  static String get estTravelTime => _t('est_travel_time');
  static String get distanceWord => _t('distance_word');
  static String get approxRoute => _t('approx_route');
  static String get roadRoute => _t('road_route');
  static String get homeLabelShort => _t('home_label_short');
  static String get workplaceLabelShort => _t('workplace_label_short');
  static String minutesShort(int n) => isNepali ? '$n मिनेट' : '$n min';

  // ── Job route (after accepting a job) ──────────────────
  static String get jobRouteTitle => _t('job_route_title');
  static String get jobSiteWord => _t('job_site_word');
  static String get yourLocationWord => _t('your_location_word');
  static String get customerWord => _t('customer_word');
  static String get findingRoute => _t('finding_route');
  static String get locationNeededForRoute => _t('location_needed_for_route');
  static String get waitingForWorkerLocation =>
      _t('waiting_for_worker_location');
  static String get locationServiceOff => _t('location_service_off');
  static String get routeUnavailable => _t('route_unavailable');
  static String get locationFetchFailed => _t('location_fetch_failed');
  static String get retryWord => _t('retry_word');
  static String get arrivedAtLocation => _t('arrived_at_location');
  static String get startWorkNow => _t('start_work_now');

  // ── In-chat calls ──────────────────────────────────────
  static String get voiceCall => _t('voice_call');
  static String get videoCall => _t('video_call');
  static String get joinCall => _t('join_call');
  static String get openingCall => _t('opening_call');
  static String get incomingCallBody => _t('incoming_call_body');
  static String get callLinkFailed => _t('call_link_failed');
  static String get callEnded => _t('call_ended');
  static String get callingWord => _t('calling_word');
  static String get callConnecting => _t('call_connecting');
  static String get incomingCallTitle => _t('incoming_call_title');
  static String get cameraMicNeeded => _t('camera_mic_needed');
  static String get seenWord => _t('seen_word');
  static String etaAway(int min) =>
      isNepali ? 'करिब $min मिनेट टाढा' : 'about $min min away';

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
    'nav_bookings': {'en': 'Bookings', 'ne': 'बुकिङ'},
    'active_job_bar_cancel_title': {
      'en': 'Cancel this job?',
      'ne': 'यो काम रद्द गर्ने?'
    },
    'active_job_bar_cancel_body': {
      'en': 'This will cancel the job for both sides.',
      'ne': 'यसले दुवैतर्फको काम रद्द गर्नेछ।'
    },
    'keep_job': {'en': 'Keep job', 'ne': 'काम राख्ने'},
    'ok': {'en': 'OK', 'ne': 'ठीक छ'},
    'save': {'en': 'Save', 'ne': 'सुरक्षित गर्नुहोस्'},
    'send': {'en': 'Send', 'ne': 'पठाउनुहोस्'},
    'delete': {'en': 'Delete', 'ne': 'मेटाउनुहोस्'},
    'logout': {'en': 'Logout', 'ne': 'लगआउट'},
    'error': {'en': 'Error', 'ne': 'त्रुटि'},
    'nav_home': {'en': 'Home', 'ne': 'गृह'},
    'nav_requests': {'en': 'Requests', 'ne': 'अनुरोध'},
    'nav_messages': {'en': 'Messages', 'ne': 'सन्देश'},
    'nav_profile': {'en': 'Profile', 'ne': 'प्रोफाइल'},
    'nav_watchlist': {'en': 'Watchlist', 'ne': 'सूची'},
    'nav_job_feed': {'en': 'Job feed', 'ne': 'कामको सूची'},
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
    'menu_request_history': {'en': 'Request history', 'ne': 'अनुरोध इतिहास'},
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
    'settings_prefs_section': {'en': 'Preferences', 'ne': 'प्राथमिकता'},
    'settings_about_section': {'en': 'About', 'ne': 'बारेमा'},
    'settings_account_section': {'en': 'Account', 'ne': 'खाता'},
    'employer_reg_title': {
      'en': 'Employer profile',
      'ne': 'रोजगारदाता प्रोफाइल'
    },
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
    'use_my_location': {
      'en': 'Use my current location',
      'ne': 'मेरो स्थान प्रयोग गर्नुहोस्'
    },
    'location_captured': {'en': 'Location captured', 'ne': 'स्थान लिइयो'},
    'location_denied_short': {
      'en': 'Permission denied — you can add it later',
      'ne': 'अनुमति अस्वीकृत — पछि थप्न सकिन्छ'
    },
    'getting_location': {'en': 'Getting location…', 'ne': 'स्थान लिँदै…'},
    'service_category': {'en': 'Service category', 'ne': 'सेवा श्रेणी'},
    'select_vehicle_type': {
      'en': 'Select vehicle type',
      'ne': 'सवारी प्रकार छान्नुहोस्',
    },
    'bike_word': {'en': 'Bike', 'ne': 'बाइक'},
    'car_word': {'en': 'Car', 'ne': 'कार'},
    'bike_ride_hint': {'en': 'Two-wheeler ride', 'ne': 'दुई पांग्रे सवारी'},
    'car_ride_hint': {'en': 'Car / taxi ride', 'ne': 'कार / ट्याक्सी सवारी'},
    'select_vehicle_type_error': {
      'en': 'Please select Bike or Car',
      'ne': 'कृपया बाइक वा कार छान्नुहोस्',
    },
    'driving_license_label': {
      'en': 'Driving License',
      'ne': 'सवारी चालक अनुमतिपत्र',
    },
    'vehicle_registration_label': {
      'en': 'Vehicle Registration (Blue Book)',
      'ne': 'सवारी दर्ता (ब्लु बुक)',
    },
    'vehicle_docs_required_hint': {
      'en': 'Required for Bike/Car drivers before you can go online',
      'ne': 'Bike/Car चालकका लागि अनलाइन हुनुअघि अनिवार्य',
    },
    'upload_driver_docs_error': {
      'en': 'Please upload your driving license and vehicle registration',
      'ne':
          'कृपया आफ्नो सवारी चालक अनुमतिपत्र र सवारी दर्ता अपलोड गर्नुहोस्',
    },
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
    'add_document': {
      'en': 'Add document / photo',
      'ne': 'कागजात / फोटो थप्नुहोस्'
    },
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
    'application_submitted': {
      'en': 'Application submitted!',
      'ne': 'आवेदन पठाइयो!'
    },
    'application_submitted_body': {
      'en':
          'Your registration has been sent to the admin. You will get access once approved.',
      'ne': 'तपाईंको दर्ता Admin लाई पठाइयो। स्वीकृत भएपछि access पाउनुहुनेछ।'
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
      'en':
          'Take a clear live photo of your face. This is checked against your document.',
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
    'reject_reason_title': {'en': 'Reject — reason', 'ne': 'अस्वीकृत — कारण'},
    'reject_reason_hint': {
      'en': 'e.g. Document is blurry / does not match name',
      'ne': 'जस्तै: कागजात धमिलो छ / नाम मिलेन'
    },
    'reason_label': {'en': 'Reason', 'ne': 'कारण'},
    'selfie_photo': {'en': 'Selfie', 'ne': 'सेल्फी'},
    'saved_places_title': {'en': 'Saved places', 'ne': 'सुरक्षित स्थानहरू'},
    'save_as_home': {'en': 'Save as Home', 'ne': 'घर सेभ गर्नुहोस्'},
    'save_as_work': {'en': 'Save as Work', 'ne': 'कार्यस्थल सेभ गर्नुहोस्'},
    'add_another_place': {
      'en': 'Add another place',
      'ne': 'अर्को स्थान थप्नुहोस्'
    },
    'not_set_yet': {'en': 'Not set yet', 'ne': 'अझै सेट गरिएको छैन'},
    'pick_on_map': {'en': 'Pick on map', 'ne': 'नक्सामा छान्नुहोस्'},
    'confirm_location': {
      'en': 'Confirm location',
      'ne': 'स्थान पुष्टि गर्नुहोस्'
    },
    'fetching_address': {'en': 'Fetching address…', 'ne': 'ठेगाना ल्याउँदै…'},
    'place_label': {
      'en': 'Label (e.g. Home, Mom\'s house)',
      'ne': 'नाम (जस्तै: घर, आमाको घर)'
    },
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
    'location_row_label': {'en': 'Location', 'ne': 'स्थान'},
    'document_available': {'en': 'Available', 'ne': 'उपलब्ध'},
    'call_to_book': {'en': 'Call to book directly', 'ne': 'सिधै बुक गर्न कल गर्नुहोस्'},
    'describe_your_task': {
      'en': 'Describe your problem / task',
      'ne': 'आफ्नो समस्या/काम बताउनुहोस्'
    },
    'service_request_sent_title': {
      'en': 'Request sent!',
      'ne': 'अनुरोध पठाइयो!'
    },
    'service_request_sent_body': {
      'en':
          'Your service request has been sent successfully. The worker will accept it soon!',
      'ne': 'तपाईंको सेवा अनुरोध सफलतापूर्वक पठाइयो। कामदारले चाँडै स्वीकार गर्नेछन्!'
    },
    'contact_locked_caption': {
      'en': 'Call & Message unlock once your request is accepted',
      'ne': 'तपाईंको अनुरोध स्वीकार भएपछि मात्र कल र म्यासेज उपलब्ध हुन्छ'
    },
    'open_chat_label': {
      'en': 'Tap to chat',
      'ne': 'कुराकानी गर्न ट्याप गर्नुहोस्'
    },
    'chat_locked_completed': {
      'en':
          'This job is completed. Chat & calls are closed — see History for your records.',
      'ne':
          'यो काम सकिएको छ। च्याट र कल बन्द छन् — तपाईंको रेकर्ड History मा हेर्नुहोस्।'
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
    'view_details': {'en': 'View details', 'ne': 'विवरण हेर्नुहोस्'},
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
    'location_needed_title': {'en': 'Location needed', 'ne': 'Location चाहियो'},
    'location_needed_body': {
      'en':
          'Allow location access to see workers near you and how far they are.',
      'ne': 'नजिकका कामदार र तिनको दूरी हेर्न location अनुमति दिनुहोस्।'
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
    'send_request': {'en': 'Send request', 'ne': 'अनुरोध पठाउनुहोस्'},
    'finding_providers': {
      'en': 'Finding nearby providers…',
      'ne': 'नजिकका प्रदायक खोज्दै…'
    },
    'waiting_accept': {
      'en': 'Waiting for a provider to accept your request',
      'ne': 'प्रदायकले तपाईंको अनुरोध स्वीकार गर्ने पर्खाइमा'
    },
    'provider_on_the_way': {
      'en': 'Provider is on the way',
      'ne': 'प्रदायक बाटोमा हुनुहुन्छ'
    },
    'no_provider_accepted': {
      'en': 'No provider accepted your request yet',
      'ne': 'कुनै प्रदायकले अझै तपाईंको अनुरोध स्वीकार गरेनन्'
    },
    'cancel_request': {'en': 'Cancel request', 'ne': 'अनुरोध रद्द गर्नुहोस्'},
    'request_cancelled': {'en': 'Request cancelled', 'ne': 'अनुरोध रद्द भयो'},
    'accept_word': {'en': 'Accept', 'ne': 'स्वीकार गर्नुहोस्'},
    'decline_word': {'en': 'Decline', 'ne': 'अस्वीकार गर्नुहोस्'},
    'new_job_nearby': {'en': 'New job nearby', 'ne': 'नजिकै नयाँ काम'},
    'job_requests': {'en': 'Job requests', 'ne': 'कामका अनुरोध'},
    'online_for_jobs': {
      'en': 'You are online — nearby job requests will appear here',
      'ne': 'तपाईं अनलाइन हुनुहुन्छ — नजिकका कामका अनुरोध यहाँ देखिनेछन्'
    },
    'call_word': {'en': 'Call', 'ne': 'कल गर्नुहोस्'},
    'message_word': {'en': 'Message', 'ne': 'सन्देश'},
    'track_on_map': {'en': 'Track on map', 'ne': 'नक्सामा ट्र्याक गर्नुहोस्'},
    'providers_nearby': {'en': 'providers nearby', 'ne': 'प्रदायक नजिक'},
    'request_sent': {
      'en': 'Request sent to nearby providers',
      'ne': 'नजिकका प्रदायकलाई अनुरोध पठाइयो'
    },
    'job_accepted': {'en': 'Job accepted', 'ne': 'काम स्वीकार गरियो'},
    'estimated_fare': {'en': 'Estimated fare', 'ne': 'अनुमानित भाडा'},
    'your_offer_price': {
      'en': 'Your offer price',
      'ne': 'तपाईंको प्रस्तावित मूल्य'
    },
    'suggested_fare': {'en': 'Suggested', 'ne': 'सुझाव मूल्य'},
    'offer_price_word': {'en': 'Offer price', 'ne': 'मूल्य प्रस्ताव'},
    'drag_for_more': {
      'en': 'Drag up for more',
      'ne': 'थप हेर्न माथि तान्नुहोस्'
    },
    'not_authorized_for_job_category': {
      'en': 'You are not authorized to accept this job category.',
      'ne': 'तपाईं यो कामको श्रेणी स्वीकार गर्न अधिकृत हुनुहुन्न।'
    },
    'file_too_large': {
      'en': 'File is too large — maximum 5 MB',
      'ne': 'फाइल धेरै ठूलो छ — बढीमा ५ MB'
    },
    'file_type_not_allowed': {
      'en': 'Only JPG, PNG, WebP or PDF files are allowed',
      'ne': 'JPG, PNG, WebP वा PDF फाइल मात्र स्वीकार्य छ'
    },
    'file_empty_or_corrupt': {
      'en': 'This file looks empty or unreadable',
      'ne': 'यो फाइल खाली वा पढ्न नमिल्ने देखिन्छ'
    },
    'file_content_mismatch': {
      'en':
          "The file's contents don't match its type — pick a genuine photo or PDF",
      'ne': 'फाइलको सामग्री यसको प्रकारसँग मिलेन — साँचो फोटो वा PDF छान्नुहोस्'
    },
    'docs_upload_pending_note': {
      'en':
          "Your details are saved, but your document and selfie didn't reach the server (weak network, or storage not ready). Open this screen again and use “Re-upload documents” — your application is safe.",
      'ne':
          'तपाईंको विवरण सुरक्षित छ, तर कागजात र सेल्फी सर्भरसम्म पुगेन (नेटवर्क कमजोर वा storage तयार नभएको)। यो पेज फेरि खोलेर “कागजात फेरि अपलोड गर्नुहोस्” प्रयोग गर्नुहोस् — तपाईंको आवेदन सुरक्षित छ।'
    },
    'docs_not_uploaded_title': {
      'en': 'Documents not uploaded yet',
      'ne': 'कागजात अझै अपलोड भएको छैन'
    },
    'docs_not_uploaded_body': {
      'en':
          "Your registration is saved, but your ID document and selfie haven't reached the server. Re-upload them so the admin can verify you.",
      'ne':
          'तपाईंको दर्ता सुरक्षित छ, तर परिचयपत्र र सेल्फी सर्भरसम्म पुगेको छैन। Admin ले प्रमाणित गर्न सक्ने गरी फेरि अपलोड गर्नुहोस्।'
    },
    'reupload_documents': {
      'en': 'Re-upload documents',
      'ne': 'कागजात फेरि अपलोड गर्नुहोस्'
    },
    'docs_resync_title': {
      'en': 'Upload your documents',
      'ne': 'कागजात अपलोड गर्नुहोस्'
    },
    'docs_synced_ok': {
      'en': 'Documents uploaded — the admin can now verify you.',
      'ne': 'कागजात अपलोड भयो — अब Admin ले प्रमाणित गर्न सक्नुहुन्छ।'
    },
    'docs_sync_failed_storage': {
      'en':
          "Still can't upload — the file storage service isn't ready. Please try again later.",
      'ne':
          'अझै अपलोड हुन सकेन — फाइल storage सेवा तयार छैन। कृपया केही बेरमा फेरि प्रयास गर्नुहोस्।'
    },
    'docs_sync_failed_network': {
      'en': 'Upload failed — check your internet connection and try again.',
      'ne': 'अपलोड असफल भयो — इन्टरनेट जाँचेर फेरि प्रयास गर्नुहोस्।'
    },
    'select_id_doc': {
      'en': 'ID document (citizenship / licence)',
      'ne': 'परिचयपत्र (नागरिकता / लाइसेन्स)'
    },
    'select_selfie': {'en': 'Live selfie', 'ne': 'लाइभ सेल्फी'},
    'upload_now': {'en': 'Upload now', 'ne': 'अहिले अपलोड गर्नुहोस्'},
    'filter_distance': {'en': 'Distance', 'ne': 'दूरी'},
    'all_trades': {'en': 'All trades', 'ne': 'सबै सीप'},
    'my_trade': {'en': 'My trade', 'ne': 'मेरो सीप'},
    'enable_location_for_distance': {
      'en': 'Turn on location to filter jobs by distance',
      'ne': 'दूरी अनुसार छान्न location अन गर्नुहोस्'
    },
    'earnings_title': {'en': 'Earnings & wallet', 'ne': 'आम्दानी र वालेट'},
    'wallet_balance': {'en': 'Wallet balance', 'ne': 'वालेट ब्यालेन्स'},
    'gross_earnings': {'en': 'Gross earnings', 'ne': 'कुल आम्दानी'},
    'commission_deducted': {'en': 'Commission deducted', 'ne': 'कमिसन कटौती'},
    'this_week': {'en': 'This week', 'ne': 'यो हप्ता'},
    'this_month': {'en': 'This month', 'ne': 'यो महिना'},
    'all_time': {'en': 'All time', 'ne': 'जम्मा'},
    'jobs_completed_label': {'en': 'jobs completed', 'ne': 'काम पूरा'},
    'mark_complete': {'en': 'Mark as complete', 'ne': 'पूरा भयो भन्नुहोस्'},
    'collect_payment': {'en': 'Collect payment', 'ne': 'भुक्तानी लिनुहोस्'},
    'amount_due': {'en': 'Amount due', 'ne': 'तिर्नुपर्ने रकम'},
    'payment_method_label': {
      'en': 'Payment method',
      'ne': 'भुक्तानी विधि',
    },
    'cash_word': {'en': 'Cash', 'ne': 'नगद'},
    'digital_word': {'en': 'Digital / wallet', 'ne': 'डिजिटल / वालेट'},
    'confirm_payment_received': {
      'en': 'Payment received — mark complete',
      'ne': 'भुक्तानी प्राप्त भयो — काम सकियो',
    },
    'job_marked_complete': {
      'en': 'Job marked complete',
      'ne': 'काम पूरा भएको चिन्ह लगाइयो'
    },
    'complete_job_title': {
      'en': 'Complete Job & Pay',
      'ne': 'काम सम्पन्न र भुक्तानी',
    },
    'confirm_complete_job': {
      'en': 'Confirm & Complete',
      'ne': 'पुष्टि गर्नुहोस् र सम्पन्न गर्नुहोस्',
    },
    'add_comment_optional': {
      'en': 'Add a comment (optional)',
      'ne': 'टिप्पणी थप्नुहोस् (वैकल्पिक)',
    },
    'waiting_employer_complete': {
      'en': 'Waiting for the employer to confirm job completion',
      'ne': 'रोजगारदाताले काम सम्पन्न भएको पुष्टि गर्ने पर्खाइमा',
    },
    'last_7_days': {'en': 'Last 7 days', 'ne': 'पछिल्ला ७ दिन'},
    'no_earnings_yet': {
      'en': 'No completed jobs yet — your earnings will show here',
      'ne': 'अझै कुनै पूरा भएको काम छैन — आम्दानी यहाँ देखिनेछ'
    },
    'per_job_breakdown': {
      'en': 'Per-job breakdown',
      'ne': 'काम अनुसारको हिसाब'
    },
    'schedule_title': {'en': 'Job schedule', 'ne': 'कामको तालिका'},
    'no_scheduled_jobs': {
      'en': 'No scheduled jobs',
      'ne': 'तालिकामा कुनै काम छैन'
    },
    'no_jobs_this_day': {
      'en': 'No jobs on this day',
      'ne': 'यो दिन कुनै काम छैन'
    },
    'upcoming_jobs': {'en': 'Upcoming jobs', 'ne': 'आउँदा कामहरू'},
    'top_worker': {'en': 'Top Worker', 'ne': 'उत्कृष्ट कामदार'},
    'no_ratings_yet': {'en': 'No ratings yet', 'ne': 'अझै रेटिङ छैन'},
    'my_earnings': {'en': 'My earnings', 'ne': 'मेरो आम्दानी'},
    'my_schedule': {'en': 'My schedule', 'ne': 'मेरो तालिका'},
    'work_portfolio': {'en': 'Work portfolio', 'ne': 'कामको पोर्टफोलियो'},
    'portfolio_empty': {
      'en':
          'Add photos of jobs you have done — customers trust workers who show their work.',
      'ne':
          'आफूले गरेका कामका तस्बिर थप्नुहोस् — काम देखाउने कामदारलाई ग्राहकले बढी विश्वास गर्छन्।'
    },
    'portfolio_empty_other': {
      'en': 'No work photos yet',
      'ne': 'अझै कामका तस्बिर छैनन्'
    },
    'add_work_photo': {'en': 'Add work photo', 'ne': 'कामको तस्बिर थप्नुहोस्'},
    'photo_added': {'en': 'Photo added', 'ne': 'तस्बिर थपियो'},
    'remove_photo': {'en': 'Remove this photo?', 'ne': 'यो तस्बिर हटाउने?'},
    'from_camera': {'en': 'Take a photo', 'ne': 'फोटो खिच्नुहोस्'},
    'from_gallery': {'en': 'Choose from files', 'ne': 'फाइलबाट छान्नुहोस्'},
    'documents_kyc': {
      'en': 'Documents & verification',
      'ne': 'कागजात र प्रमाणीकरण'
    },
    'kyc_verified': {'en': 'Verified', 'ne': 'प्रमाणित'},
    'kyc_under_review': {'en': 'Under review', 'ne': 'समीक्षामा'},
    'kyc_rejected': {'en': 'Rejected', 'ne': 'अस्वीकृत'},
    'kyc_not_submitted': {'en': 'Not submitted', 'ne': 'पेश गरिएको छैन'},
    'resubmit': {'en': 'Re-submit', 'ne': 'फेरि पेश गर्नुहोस्'},
    'notifications_label': {'en': 'Notifications', 'ne': 'सूचनाहरू'},
    'notifications_on': {'en': 'On', 'ne': 'चालु'},
    'notifications_off': {'en': 'Off', 'ne': 'बन्द'},
    'worker_account': {'en': 'Worker account', 'ne': 'कामदार खाता'},
    'step_identity': {'en': 'Identity', 'ne': 'परिचय'},
    'step_certificates': {'en': 'Certificates', 'ne': 'प्रमाणपत्र'},
    'citizenship_title': {
      'en': 'Citizenship verification',
      'ne': 'नागरिकता प्रमाणीकरण'
    },
    'citizenship_hint': {
      'en':
          'Upload clear photos of BOTH sides of your citizenship certificate. Details must be readable.',
      'ne':
          'आफ्नो नागरिकता प्रमाणपत्रको दुवै पाटोको स्पष्ट फोटो अपलोड गर्नुहोस्। विवरण पढ्न मिल्ने हुनुपर्छ।'
    },
    'citizenship_front': {
      'en': 'Citizenship — front photo',
      'ne': 'नागरिकता — अगाडिको फोटो'
    },
    'citizenship_back': {
      'en': 'Citizenship — back photo',
      'ne': 'नागरिकता — पछाडिको फोटो'
    },
    'upload_both_citizenship': {
      'en': 'Upload both the front and back of your citizenship',
      'ne': 'नागरिकताको अगाडि र पछाडि दुवै अपलोड गर्नुहोस्'
    },
    'selfie_with_id_title': {
      'en': 'Face verification',
      'ne': 'अनुहार प्रमाणीकरण'
    },
    'selfie_with_id_hint': {
      'en':
          'Take a live photo of your face while holding your citizenship card beside it. This confirms the ID is really yours.',
      'ne':
          'आफ्नो नागरिकता कार्ड अनुहारको छेउमा समातेर लाइभ फोटो खिच्नुहोस्। यसले परिचयपत्र साँच्चै तपाईंकै हो भनी पुष्टि गर्छ।'
    },
    'certs_title': {
      'en': 'Work experience & certificates',
      'ne': 'कामको अनुभव र प्रमाणपत्र'
    },
    'certs_hint': {
      'en':
          'Optional — add experience letters, training certificates, or photos of past work (paint jobs, pipe fittings, furniture…). Workers who show proof get more jobs.',
      'ne':
          'ऐच्छिक — अनुभव पत्र, तालिम प्रमाणपत्र, वा गरेका कामका फोटो (रङरोगन, पाइप फिटिङ, फर्निचर…) थप्नुहोस्। प्रमाण देखाउने कामदारले बढी काम पाउँछन्।'
    },
    'add_certificate': {
      'en': 'Add certificate / work photo',
      'ne': 'प्रमाणपत्र / कामको फोटो थप्नुहोस्'
    },
    'certs_optional': {
      'en': 'You can skip this and add certificates later from your profile.',
      'ne': 'यो छोड्न सकिन्छ — पछि प्रोफाइलबाट प्रमाणपत्र थप्न मिल्छ।'
    },
    'citizenship_front_short': {
      'en': 'Citizenship front',
      'ne': 'नागरिकता अगाडि'
    },
    'citizenship_back_short': {
      'en': 'Citizenship back',
      'ne': 'नागरिकता पछाडि'
    },
    'certificates_label': {'en': 'Certificates', 'ne': 'प्रमाणपत्रहरू'},
    'take_photo': {'en': 'Take a photo', 'ne': 'फोटो खिच्नुहोस्'},
    'choose_file': {'en': 'Choose from files', 'ne': 'फाइलबाट छान्नुहोस्'},
    'delete_user': {'en': 'Delete', 'ne': 'मेटाउनुहोस्'},
    'delete_user_title': {'en': 'Delete this user?', 'ne': 'यो युजर मेटाउने?'},
    'delete_user_body': {
      'en':
          'This permanently removes their profile, worker listing, pending application and notifications. It cannot be undone.',
      'ne':
          'यसले उनको प्रोफाइल, कामदार सूची, पेन्डिङ आवेदन र सूचनाहरू स्थायी रूपमा मेटाउँछ। फिर्ता गर्न मिल्दैन।'
    },
    'user_deleted': {'en': 'User deleted', 'ne': 'युजर मेटाइयो'},
    'delete_confirm_title': {'en': 'Delete this?', 'ne': 'यो मेटाउने हो?'},
    'deleted_word': {'en': 'Deleted', 'ne': 'मेटाइयो'},
    'job_request_word': {'en': 'job request', 'ne': 'काम अनुरोध'},
    'report_word': {'en': 'report', 'ne': 'रिपोर्ट'},
    'support_ticket_word': {'en': 'support ticket', 'ne': 'सपोर्ट टिकट'},
    'pending_worker_word': {'en': 'pending worker', 'ne': 'बाँकी कामदार'},
    'search_by_email_or_phone': {
      'en': 'Search by email or phone…',
      'ne': 'इमेल वा फोनले खोज्नुहोस्…'
    },
    'user_word': {'en': 'user', 'ne': 'युजर'},
    'select_all': {'en': 'Select all', 'ne': 'सबै छान्नुहोस्'},
    'delete_selected': {'en': 'Delete selected', 'ne': 'सबै मेटाउनुहोस्'},
    'available_for_jobs': {'en': 'Available', 'ne': 'उपलब्ध'},
    'you_are_online': {
      'en': "You're online — employers can find you on the map",
      'ne': 'तपाईं अनलाइन हुनुहुन्छ — रोजगारदाताले नक्सामा भेट्न सक्छन्'
    },
    'you_are_offline': {
      'en': "You're offline — you won't appear in employer searches",
      'ne': 'तपाईं अफलाइन हुनुहुन्छ — रोजगारदाताको खोजमा देखिनुहुन्न'
    },
    'post_job_title': {'en': 'Post a job', 'ne': 'काम राख्नुहोस्'},
    'job_description': {
      'en': 'What needs to be done?',
      'ne': 'के काम गर्नुपर्ने छ?'
    },
    'job_description_hint': {
      'en': 'e.g. Paint 2 rooms — walls only, paint provided',
      'ne': 'जस्तै: २ कोठा रङ लगाउने — भित्ता मात्र, रङ हामीले दिन्छौं'
    },
    'preferred_date_label': {'en': 'Preferred date', 'ne': 'रोजेको मिति'},
    'time_slot_label': {'en': 'Time slot', 'ne': 'समय'},
    'slot_morning': {'en': 'Morning', 'ne': 'बिहान'},
    'slot_afternoon': {'en': 'Afternoon', 'ne': 'दिउँसो'},
    'slot_evening': {'en': 'Evening', 'ne': 'साँझ'},
    'slot_anytime': {'en': 'Anytime', 'ne': 'जुनसुकै बेला'},
    'job_address_label': {
      'en': 'Work location / address',
      'ne': 'कामको ठाउँ / ठेगाना'
    },
    'post_job': {'en': 'Post job', 'ne': 'काम पोस्ट गर्नुहोस्'},
    'open_jobs_nearby': {
      'en': 'Open jobs near you',
      'ne': 'तपाईं नजिकका खुला कामहरू'
    },
    'no_open_jobs': {
      'en': 'No open jobs right now — check back soon',
      'ne': 'अहिले कुनै खुला काम छैन — केही बेरमा फेरि हेर्नुहोस्'
    },
    'customer_budget': {'en': "Customer's budget", 'ne': 'ग्राहकको बजेट'},
    'view_job_location': {'en': 'View location', 'ne': 'स्थान हेर्नुहोस्'},
    'job_location_title': {'en': 'Job location', 'ne': 'कामको स्थान'},
    'job_details_title': {'en': 'Job details', 'ne': 'कामको विवरण'},
    'describe_job_first': {
      'en': 'Please describe the job',
      'ne': 'कृपया काम के हो बताउनुहोस्'
    },
    'service_address_note': {
      'en': 'This is where the work will be done',
      'ne': 'यहीँ काम गरिनेछ'
    },
    'pick_date_first': {'en': 'Pick a date', 'ne': 'मिति छान्नुहोस्'},
    'job_confirm_title': {
      'en': 'Confirm job details',
      'ne': 'कामको विवरण पुष्टि गर्नुहोस्'
    },
    'job_title_label': {'en': 'Job title', 'ne': 'कामको शीर्षक'},
    'job_title_hint': {
      'en': 'e.g. Kitchen pipe leak',
      'ne': 'जस्तै: भान्साको पाइप चुहिएको'
    },
    'confirm_broadcast': {
      'en': 'Confirm & broadcast to nearby workers',
      'ne': 'पुष्टि गरी नजिकका कामदारलाई पठाउनुहोस्'
    },
    'pinned_location': {
      'en': 'Pinned location',
      'ne': 'नक्सामा पिन गरिएको स्थान'
    },
    'no_workers_online_note': {
      'en':
          "No workers online right now — they'll get your request as soon as they come online.",
      'ne':
          'अहिले कुनै कामदार अनलाइन छैनन् — अनलाइन हुनेबित्तिकै तपाईंको अनुरोध पुग्नेछ।'
    },
    'new_job_notif_title': {'en': 'New job nearby', 'ne': 'नजिकै नयाँ काम'},
    'new_counter_offer_notif_title': {
      'en': 'New counter-offer received',
      'ne': 'नयाँ मूल्य प्रस्ताव आयो'
    },
    'offer_accepted_notif_title': {
      'en': 'Your offer was accepted',
      'ne': 'तपाईंको प्रस्ताव स्वीकृत भयो'
    },
    'stale_offer_error': {
      'en':
          'This offer is no longer available — the worker sent a new price.',
      'ne': 'यो प्रस्ताव अब उपलब्ध छैन — कामदारले नयाँ मूल्य पठाइसक्नुभयो।'
    },
    'open_in_google_maps': {
      'en': 'Open in Google Maps',
      'ne': 'Google Maps मा खोल्नुहोस्'
    },
    'route_fallback_warning': {
      'en': 'Showing approximate straight-line route — road route unavailable',
      'ne': 'अनुमानित सीधा बाटो देखाइँदैछ — सडक मार्ग भेटिएन'
    },
    'no_phone_on_file': {
      'en': 'No phone number on file',
      'ne': 'फोन नम्बर उपलब्ध छैन'
    },
    'active_job_title': {'en': 'Active job', 'ne': 'सक्रिय काम'},
    'status_searching': {'en': 'Searching', 'ne': 'खोज्दै'},
    'status_new': {'en': 'New request', 'ne': 'नयाँ अनुरोध'},
    'status_counter': {'en': 'Counter-offer', 'ne': 'नयाँ मूल्य'},
    'status_counter_offer': {
      'en': 'Counter offer',
      'ne': 'नयाँ मूल्य प्रस्ताव'
    },
    'application_safe_helper': {
      'en': 'Your application is safe and submitted successfully',
      'ne': 'तपाईंको आवेदन सुरक्षित छ र सफलतापूर्वक पेश भयो'
    },
    'worker_role_word': {'en': 'Worker', 'ne': 'कामदार'},
    'employer_role_word': {'en': 'Employer', 'ne': 'रोजगारदाता'},
    'customer_countered_title': {
      'en': 'Customer sent a counter-offer',
      'ne': 'ग्राहकले नयाँ मूल्य प्रस्ताव पठाउनुभयो'
    },
    'customer_countered_body': {
      'en':
          'They changed the price you asked for. Respond now to lock the job.',
      'ne':
          'तपाईंले मागेको मूल्य उहाँले बदल्नुभयो। काम पक्का गर्न अहिले नै जवाफ दिनुहोस्।'
    },
    'previous_price_label': {'en': 'Previous', 'ne': 'अघिल्लो'},
    'their_offer_label': {'en': 'Their offer', 'ne': 'उहाँको प्रस्ताव'},
    'decline_or_counter': {
      'en': 'Decline / Counter back',
      'ne': 'अस्वीकार / पुनः मोलमोलाइ'
    },
    'counter_back': {'en': 'Counter back', 'ne': 'पुनः प्रस्ताव'},
    'worker_countered_title': {
      'en': 'Worker sent a counter-offer',
      'ne': 'कामदारले नयाँ मूल्य प्रस्ताव पठाउनुभयो'
    },
    'worker_countered_body': {
      'en':
          'They turned down your offer and proposed a new price. Respond to confirm the booking.',
      'ne':
          'उहाँले तपाईंको प्रस्ताव अस्वीकार गरी नयाँ मूल्य राख्नुभयो। बुकिङ पक्का गर्न जवाफ दिनुहोस्।'
    },
    'accept_counter_offer': {
      'en': 'Accept counter offer',
      'ne': 'नयाँ मूल्य स्वीकार्नुहोस्'
    },
    'booking_confirmed': {'en': 'Booking confirmed!', 'ne': 'बुकिङ पक्का भयो!'},
    'send_new_price': {'en': 'Send new price', 'ne': 'नयाँ मूल्य पठाउनुहोस्'},
    'decline_job': {'en': 'Decline job', 'ne': 'काम अस्वीकार गर्नुहोस्'},
    'your_price_rs': {'en': 'Your price (Rs.)', 'ne': 'तपाईंको मूल्य (Rs.)'},
    'new_price_sent_to_customer': {
      'en': 'New price sent to the customer',
      'ne': 'नयाँ मूल्य ग्राहकलाई पठाइयो'
    },
    'counter_sent_to_worker': {
      'en': 'Counter-offer sent to the worker',
      'ne': 'नयाँ मूल्य प्रस्ताव कामदारलाई पठाइयो'
    },
    'waiting_worker_counter_reply': {
      'en': 'Waiting for the worker to respond to your counter-offer…',
      'ne': 'तपाईंको नयाँ मूल्यमा कामदारको जवाफ पर्खँदै…'
    },
    'status_accepted': {'en': 'Accepted', 'ne': 'स्वीकृत'},
    'status_in_progress': {'en': 'In progress', 'ne': 'काम भइरहेको'},
    'status_completed': {'en': 'Completed', 'ne': 'पूरा भयो'},
    'status_cancelled': {'en': 'Cancelled', 'ne': 'रद्द भयो'},
    'start_work': {'en': 'Start work', 'ne': 'काम सुरु गर्नुहोस्'},
    'work_started': {'en': 'Work started', 'ne': 'काम सुरु भयो'},
    'welcome_back': {'en': 'Welcome back', 'ne': 'फिर्ता स्वागत छ'},
    'login_to_existing': {
      'en': "Enter the code — you'll be signed into your existing account.",
      'ne': 'code हाल्नुहोस् — तपाईं आफ्नै पुरानो खातामा लगइन हुनुहुनेछ।'
    },
    'continue_with_phone': {
      'en': 'Continue with phone number',
      'ne': 'फोन नम्बरबाट अगाडि बढ्नुहोस्'
    },
    'continue_with_email': {
      'en': 'Continue with email',
      'ne': 'इमेलबाट अगाडि बढ्नुहोस्'
    },
    'use_email_instead': {
      'en': 'Use email instead',
      'ne': 'बरु इमेल प्रयोग गर्नुहोस्'
    },
    'use_phone_instead': {
      'en': 'Use phone number instead',
      'ne': 'बरु फोन नम्बर प्रयोग गर्नुहोस्'
    },
    'email_auth_title': {'en': 'Email sign in', 'ne': 'इमेल लगइन'},
    'email_auth_sub': {
      'en': 'Log in, or create a new account with your email and a password.',
      'ne': 'लगइन गर्नुहोस्, वा इमेल र पासवर्डले नयाँ खाता बनाउनुहोस्।'
    },
    'have_account_login': {
      'en': 'Already have an account? Log in',
      'ne': 'पहिले नै खाता छ? लगइन गर्नुहोस्'
    },
    'no_account_signup': {
      'en': "New here? Create an account",
      'ne': 'नयाँ हो? खाता बनाउनुहोस्'
    },
    'email_password_disabled': {
      'en':
          'Email/password sign-in is not enabled. In Firebase Console → Authentication → Sign-in method, enable Email/Password.',
      'ne':
          'इमेल/पासवर्ड लगइन on छैन। Firebase Console → Authentication → Sign-in method मा Email/Password enable गर्नुहोस्।'
    },
    'login_no_match_hint': {
      'en':
          "We couldn't sign you in with that email and password. Check the password, or if you registered with Google use \"Continue with Google\" below. Brand new? Switch to Sign up.",
      'ne':
          'त्यो इमेल र पासवर्डले लगइन हुन सकेन। पासवर्ड जाँच्नुहोस्, वा Google बाट दर्ता गर्नुभएको भए तल "Google बाट जारी राख्नुहोस्" थिच्नुहोस्। बिल्कुलै नयाँ हो? Sign up मा जानुहोस्।'
    },
    'wrong_password_hint': {
      'en': 'Incorrect password for this email. Try again.',
      'ne': 'यो इमेलको पासवर्ड मिलेन। फेरि प्रयास गर्नुहोस्।'
    },
    'password_account_exists_hint': {
      'en':
          'This email is already registered with a password. Please log in with your email and password instead.',
      'ne':
          'यो इमेल पासवर्डबाट पहिले नै दर्ता छ। कृपया इमेल र पासवर्डले लगइन गर्नुहोस्।'
    },
    'google_sign_in_config_error': {
      'en':
          'Google Sign-In failed. Please check your network or SHA-1 configuration.',
      'ne':
          'Google Sign-In असफल भयो। कृपया आफ्नो इन्टरनेट वा SHA-1 configuration जाँच्नुहोस्।'
    },
    'google_sign_in_generic_error': {
      'en': 'Google Sign-In failed. Please try again.',
      'ne': 'Google Sign-In असफल भयो। कृपया फेरि प्रयास गर्नुहोस्।'
    },
    'too_many_attempts_hint': {
      'en': 'Too many attempts. Please wait a moment before trying again.',
      'ne': 'धेरै पटक प्रयास भयो। कृपया केही बेर पर्खेर फेरि प्रयास गर्नुहोस्।'
    },
    'email_taken_switch_login': {
      'en': 'This email is already registered. Enter your password and log in.',
      'ne': 'यो इमेल पहिले नै दर्ता छ। पासवर्ड हालेर लगइन गर्नुहोस्।'
    },
    'forgot_password': {'en': 'Forgot password?', 'ne': 'पासवर्ड बिर्सनुभयो?'},
    'reset_email_enter_first': {
      'en': 'Enter your email above first, then tap "Forgot password?".',
      'ne': 'पहिले माथि आफ्नो इमेल हाल्नुहोस्, अनि "पासवर्ड बिर्सनुभयो?" थिच्नुहोस्।'
    },
    'reset_email_sent': {
      'en':
          'Password reset link sent — check your email. If this account was created with Google, opening the link will also let you set a password for it.',
      'ne':
          'पासवर्ड रिसेट लिङ्क पठाइयो — इमेल जाँच्नुहोस्। यो खाता Google बाट बनेको भए पनि, लिङ्क खोलेर यसको लागि पासवर्ड सेट गर्न सकिन्छ।'
    },
    'login_to_your_account': {
      'en': 'Log in to your account',
      'ne': 'आफ्नो खातामा लगइन गर्नुहोस्'
    },
    'create_new_account': {
      'en': 'Create a new account',
      'ne': 'नयाँ खाता बनाउनुहोस्'
    },
    'login_mode_note': {
      'en': 'Verifying an existing account — nothing new is created.',
      'ne': 'पुरानै खाता जाँच्दै — नयाँ केही बन्दैन।'
    },
    'signup_mode_note': {
      'en': 'Creating a brand-new account with this email.',
      'ne': 'यो इमेलले बिल्कुलै नयाँ खाता बन्दै।'
    },
    'password_too_short': {
      'en': 'Password must be at least 6 characters',
      'ne': 'पासवर्ड कम्तीमा ६ अक्षरको हुनुपर्छ'
    },
    'enter_valid_email': {
      'en': 'Enter a valid email address',
      'ne': 'सही इमेल ठेगाना लेख्नुहोस्'
    },
    'approved_celebrate_title': {
      'en': "You're approved!",
      'ne': 'तपाईं स्वीकृत हुनुभयो!'
    },
    'approved_celebrate_body': {
      'en': 'Your KaamMitra worker account is now active — jobs are unlocked.',
      'ne': 'तपाईंको KaamMitra कामदार खाता अब सक्रिय छ — कामहरू खुल्यो।'
    },
    'opening_dashboard': {
      'en': 'Opening your dashboard…',
      'ne': 'तपाईंको ड्यासबोर्ड खुल्दै…'
    },
    'no_conversations_yet': {
      'en': 'No conversations yet',
      'ne': 'अहिलेसम्म कुनै कुराकानी छैन'
    },
    'start_the_conversation': {
      'en': 'Send a message to start the conversation',
      'ne': 'कुराकानी सुरु गर्न सन्देश पठाउनुहोस्'
    },
    'type_message': {'en': 'Type a message…', 'ne': 'सन्देश लेख्नुहोस्…'},
    'you_prefix': {'en': 'You: ', 'ne': 'तपाईं: '},
    'active_recently': {'en': 'Active recently', 'ne': 'भर्खरै सक्रिय'},
    'online_now': {'en': 'Online', 'ne': 'अनलाइन'},
    'delete_chat': {'en': 'Delete conversation?', 'ne': 'कुराकानी मेटाउने?'},
    'voice_message': {'en': 'Voice message', 'ne': 'भ्वाइस सन्देश'},
    'photo': {'en': 'Photo', 'ne': 'फोटो'},
    'home_to_work_route': {
      'en': 'Home → Workplace route',
      'ne': 'घर → कार्यस्थल मार्ग'
    },
    'view_route': {'en': 'View route', 'ne': 'मार्ग हेर्नुहोस्'},
    'route_title': {'en': 'Home ↔ Workplace', 'ne': 'घर ↔ कार्यस्थल'},
    'est_travel_time': {'en': 'Est. travel time', 'ne': 'अनुमानित यात्रा समय'},
    'distance_word': {'en': 'Distance', 'ne': 'दूरी'},
    'approx_route': {
      'en': 'Approximate straight-line route',
      'ne': 'अनुमानित सीधा रेखा मार्ग'
    },
    'road_route': {'en': 'Driving route', 'ne': 'सडक मार्ग'},
    'route_unavailable': {
      'en': 'Route unavailable right now',
      'ne': 'अहिले मार्ग भेटिएन'
    },
    'home_label_short': {'en': 'Home', 'ne': 'घर'},
    'workplace_label_short': {'en': 'Workplace', 'ne': 'कार्यस्थल'},
    'job_route_title': {'en': 'Heading to job', 'ne': 'काममा जाँदै'},
    'job_site_word': {'en': 'Job site', 'ne': 'काम स्थल'},
    'your_location_word': {'en': 'You', 'ne': 'तपाईं'},
    'customer_word': {'en': 'Customer', 'ne': 'ग्राहक'},
    'finding_route': {
      'en': 'Finding the best route…',
      'ne': 'उत्तम बाटो खोज्दै…'
    },
    'location_needed_for_route': {
      'en': 'Turn on location to see the route to the job.',
      'ne': 'काम सम्मको बाटो हेर्न स्थान अन गर्नुहोस्।'
    },
    'waiting_for_worker_location': {
      'en': 'Waiting for worker location…',
      'ne': 'कामदारको स्थान पर्खिँदै…'
    },
    'location_service_off': {
      'en': "Location is off. Turn it on and tap retry.",
      'ne': 'स्थान (Location) निष्क्रिय छ। अन गरेर पुनः प्रयास थिच्नुहोस्।'
    },
    'location_fetch_failed': {
      'en': "Couldn't get your location. Tap retry.",
      'ne': 'तपाईंको स्थान भेटिएन। पुनः प्रयास थिच्नुहोस्।'
    },
    'retry_word': {'en': 'Retry', 'ne': 'पुनः प्रयास'},
    'arrived_at_location': {
      'en': 'You have arrived at the job location',
      'ne': 'तपाईं काम स्थलमा पुग्नुभयो'
    },
    'start_work_now': {'en': 'Start work now', 'ne': 'अहिले काम सुरु गर्नुहोस्'},
    'voice_call': {'en': 'Voice call', 'ne': 'भ्वाइस कल'},
    'video_call': {'en': 'Video call', 'ne': 'भिडियो कल'},
    'join_call': {'en': 'Join', 'ne': 'सामेल हुनुहोस्'},
    'opening_call': {'en': 'Opening call…', 'ne': 'कल खुल्दै…'},
    'incoming_call_body': {
      'en': 'Incoming call — tap to join',
      'ne': 'आउँदो कल — सामेल हुन थिच्नुहोस्'
    },
    'call_link_failed': {
      'en': "Couldn't open the call. Please try again.",
      'ne': 'कल खोल्न सकिएन। फेरि प्रयास गर्नुहोस्।'
    },
    'call_ended': {'en': 'Call ended', 'ne': 'कल समाप्त भयो'},
    'calling_word': {'en': 'Calling…', 'ne': 'कल गर्दै…'},
    'call_connecting': {'en': 'Connecting…', 'ne': 'जोडिँदै…'},
    'incoming_call_title': {'en': 'Incoming call', 'ne': 'आउँदो कल'},
    'camera_mic_needed': {
      'en': 'Allow camera & microphone access to make calls.',
      'ne': 'कल गर्न क्यामेरा र माइक्रोफोन अनुमति दिनुहोस्।'
    },
    'seen_word': {'en': 'Seen', 'ne': 'हेरियो'},
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
    'wrong_number': {
      'en': 'Wrong number? Go back',
      'ne': 'गलत नम्बर? फर्कनुहोस्'
    },
    'enter_valid_phone': {
      'en': 'Enter a valid phone number',
      'ne': 'सही फोन नम्बर लेख्नुहोस्'
    },
    'enter_otp': {
      'en': 'Enter the 6-digit code',
      'ne': '6-अंकको code लेख्नुहोस्'
    },
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
    'Bike': 'बाइक',
    'Car': 'कार',
  };
}
