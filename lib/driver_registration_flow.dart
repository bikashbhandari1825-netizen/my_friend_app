// driver_registration_flow.dart
// इनड्राइभ-शैलीको ड्राइभर दर्ता: छुट्टै ७-चरण wizard (progress bar सहित)।
//   चरण १: शहर पुष्टि
//   चरण २: व्यक्तिगत जानकारी (प्रोफाइल फोटो, नाम, थर, जन्ममिति)
//   चरण ३: सवारी साधनको प्रकार (बाइक/कार)
//   चरण ४: चालक अनुमतिपत्र विवरण (फोटो, नम्बर, म्याद सकिने मिति)
//   चरण ५: सवारी कागजात + नम्बर प्लेट
//   चरण ६: परिचय प्रमाणीकरण (नागरिकता + लाइभ सेल्फी)
//   चरण ७: अन्तिम समीक्षा, सर्त स्वीकृति, पेश
// Submit हुँदा `worker_registration_page.dart` कै उस्तै Firestore/Storage
// schema (users/providers/pendingWorkers) प्रयोग गर्छ — admin dashboard र
// verification pipeline सँग पूर्ण compatible रहोस् भनेर।
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:country_picker/country_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'auth/dev_login.dart';
import 'auth/phone_format.dart';
import 'l10n/strings.dart';
import 'screens/nearby_common.dart' show serviceImageFor;
import 'services/document_service.dart';
import 'services/upload_validation.dart';
import 'theme/app_theme.dart';
import 'widgets/app_ui.dart' show SecondaryButton;
import 'widgets/country_phone_field.dart';
import 'widgets/glass_ui.dart';

class DriverRegistrationFlow extends StatefulWidget {
  const DriverRegistrationFlow({super.key});

  @override
  State<DriverRegistrationFlow> createState() =>
      _DriverRegistrationFlowState();
}

class _DriverRegistrationFlowState extends State<DriverRegistrationFlow> {
  static const _totalSteps = 7;
  int _step = 0;

  static const _districts = [
    'Kathmandu',
    'Lalitpur',
    'Bhaktapur',
    'Jhapa',
    'Morang',
    'Sunsari',
    'Kaski',
    'Chitwan',
    'Rupandehi',
    'Banke',
  ];
  String _district = 'Kathmandu';

  final _firstName = TextEditingController();
  final _lastName = TextEditingController();
  final _phone = TextEditingController();
  Country _phoneCountry =
      CountryService().findByCode('NP') ?? CountryService().getAll().first;
  final _email = TextEditingController();
  DateTime? _dob;
  Uint8List? _profilePicBytes;
  String? _profilePicName;

  String? _vehicleType; // 'Bike' | 'Car'

  final _licenseNumber = TextEditingController();
  String? _licenseCategory; // 'A' (bike) | 'B' (car)
  DateTime? _licenseIssueDate;
  DateTime? _licenseExpiryDate;
  Uint8List? _licenseBytes;
  String? _licenseName;

  final _vehicleMake = TextEditingController();
  final _vehicleModel = TextEditingController();
  final _vehicleColor = TextEditingController();
  final _vehiclePlate = TextEditingController();
  String _vehicleYear = '2020';
  static final List<String> _vehicleYears = List.generate(
      DateTime.now().year - 1989, (i) => (DateTime.now().year - i).toString());
  Uint8List? _vehicleRegBytes;
  String? _vehicleRegName;
  Uint8List? _insuranceBytes;
  String? _insuranceName;

  Uint8List? _citFrontBytes;
  String? _citFrontName;
  Uint8List? _citBackBytes;
  String? _citBackName;
  Uint8List? _selfieBytes;

  bool _agreedTerms = false;

  double? _lat;
  double? _lng;
  bool _saving = false;
  bool _wasRejected = false;
  String _rejectReason = '';
  String? _error;

  @override
  void initState() {
    super.initState();
    _checkRejected();
  }

  Future<void> _checkRejected() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final doc =
        await FirebaseFirestore.instance.collection('users').doc(uid).get();
    final data = doc.data() ?? {};
    final vs = (data['verificationStatus'] ?? data['workerVerificationStatus'])
        ?.toString();
    if (mounted && vs == 'rejected') {
      setState(() {
        _wasRejected = true;
        _rejectReason = (data['rejectionReason'] ?? '').toString();
      });
    }
  }

  @override
  void dispose() {
    _firstName.dispose();
    _lastName.dispose();
    _phone.dispose();
    _email.dispose();
    _licenseNumber.dispose();
    _vehicleMake.dispose();
    _vehicleModel.dispose();
    _vehicleColor.dispose();
    _vehiclePlate.dispose();
    super.dispose();
  }

  // ── file / photo pickers ────────────────────────────────────────────────

  bool _acceptFile(Uint8List? bytes, String name) {
    final err = UploadValidation.validate(bytes, name);
    if (err != null) {
      setState(() => _error = UploadValidation.messageFor(err));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(UploadValidation.messageFor(err))),
      );
      return false;
    }
    return true;
  }

  Future<({Uint8List bytes, String name})?> _pickFile(
      {bool allowPdf = true}) async {
    final src = await showKmSheet<String>(
      context: context,
      children: [
        KmSheetOption(
          icon: Icons.camera_alt_rounded,
          label: S.takePhoto,
          selected: false,
          onTap: () => Navigator.pop(context, 'camera'),
        ),
        KmSheetOption(
          icon: Icons.folder_rounded,
          label: S.chooseFile,
          selected: false,
          onTap: () => Navigator.pop(context, 'file'),
        ),
      ],
    );
    if (src == null) return null;
    try {
      if (src == 'camera') {
        final XFile? photo = await ImagePicker()
            .pickImage(source: ImageSource.camera, imageQuality: 80);
        if (photo == null) return null;
        final bytes = await photo.readAsBytes();
        if (!mounted || !_acceptFile(bytes, photo.name)) return null;
        return (bytes: bytes, name: photo.name);
      } else {
        final file = await FilePicker.pickFile(
          type: FileType.custom,
          allowedExtensions: allowPdf
              ? ['pdf', 'jpg', 'jpeg', 'png', 'webp']
              : ['jpg', 'jpeg', 'png', 'webp'],
        );
        if (file == null) return null;
        final bytes = await file.readAsBytes();
        if (!mounted || !_acceptFile(bytes, file.name)) return null;
        return (bytes: bytes, name: file.name);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('${S.errorWord}: $e')));
      }
      return null;
    }
  }

  Future<void> _pickProfilePic() async {
    final r = await _pickFile(allowPdf: false);
    if (r == null) return;
    setState(() {
      _profilePicBytes = r.bytes;
      _profilePicName = r.name;
      _error = null;
    });
  }

  Future<void> _pickLicense() async {
    final r = await _pickFile(allowPdf: true);
    if (r == null) return;
    setState(() {
      _licenseBytes = r.bytes;
      _licenseName = r.name;
      _error = null;
    });
  }

  Future<void> _pickVehicleReg() async {
    final r = await _pickFile(allowPdf: true);
    if (r == null) return;
    setState(() {
      _vehicleRegBytes = r.bytes;
      _vehicleRegName = r.name;
      _error = null;
    });
  }

  Future<void> _pickInsurance() async {
    final r = await _pickFile(allowPdf: true);
    if (r == null) return;
    setState(() {
      _insuranceBytes = r.bytes;
      _insuranceName = r.name;
      _error = null;
    });
  }

  Future<void> _pickCitFront() async {
    final r = await _pickFile(allowPdf: false);
    if (r == null) return;
    setState(() {
      _citFrontBytes = r.bytes;
      _citFrontName = r.name;
      _error = null;
    });
  }

  Future<void> _pickCitBack() async {
    final r = await _pickFile(allowPdf: false);
    if (r == null) return;
    setState(() {
      _citBackBytes = r.bytes;
      _citBackName = r.name;
      _error = null;
    });
  }

  Future<void> _takeSelfie() async {
    try {
      final XFile? photo = await ImagePicker().pickImage(
        source: ImageSource.camera,
        preferredCameraDevice: CameraDevice.front,
        imageQuality: 70,
      );
      if (photo != null) {
        final bytes = await photo.readAsBytes();
        if (!mounted || !_acceptFile(bytes, photo.name)) return;
        setState(() {
          _selfieBytes = bytes;
          _error = null;
        });
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('${S.errorWord}: $e')));
    }
  }

  Future<void> _pickDob() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(now.year - 20),
      firstDate: DateTime(1940),
      lastDate: now,
      helpText: S.dob,
    );
    if (picked != null) setState(() => _dob = picked);
  }

  Future<void> _pickLicenseIssueDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _licenseIssueDate ?? now,
      firstDate: DateTime(1990),
      lastDate: now,
      helpText: S.licenseIssueDateLabel,
    );
    if (picked != null) setState(() => _licenseIssueDate = picked);
  }

  Future<void> _pickLicenseExpiryDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _licenseExpiryDate ?? now.add(const Duration(days: 365)),
      firstDate: DateTime(1990),
      lastDate: DateTime(now.year + 30),
      helpText: S.licenseExpiryDateLabel,
    );
    if (picked != null) setState(() => _licenseExpiryDate = picked);
  }

  String _fmtDate(DateTime? d) =>
      d == null ? '' : '${d.day}/${d.month}/${d.year}';

  String get _vehicleDetailsSummary {
    final make = _vehicleMake.text.trim();
    final model = _vehicleModel.text.trim();
    final color = _vehicleColor.text.trim();
    final plate = _vehiclePlate.text.trim();
    final head = [make, model].where((s) => s.isNotEmpty).join(' ');
    final meta = [_vehicleYear, color].where((s) => s.isNotEmpty).join(', ');
    final parts = [
      if (head.isNotEmpty) head,
      if (meta.isNotEmpty) '($meta)',
      if (plate.isNotEmpty) plate,
    ];
    return parts.join(' — ');
  }

  // ── step navigation ───────────────────────────────────────────────────────

  /// Document/field-mismatch विशेष popup — सामान्य "यो फिल्ड भरिएन" जस्ता
  /// त्रुटि (तल्लो inline `_error` text) भन्दा फरक: यहाँ प्रयोगकर्ताले
  /// भरेको/छानेको डाटा आपसमा नै बाझिएको हो (जस्तै Car छान्दा Bike-only
  /// license) — त्यसैले छुट्टै स्पष्ट alert dialog देखाउने।
  Future<void> _showMismatchAlert(String message) async {
    await showKmDialog<void>(
      context: context,
      title: 'कागजात मेल खाएन',
      message: message,
      icon: Icons.error_outline_rounded,
      iconBg: const LinearGradient(
          colors: [AppColors.kmRose, AppColors.kmPinkDeep]),
      actions: [
        KmDialogAction(
          label: 'ठीक छ',
          filled: true,
          onPressed: () => Navigator.pop(context),
        ),
      ],
    );
  }

  void _next() {
    switch (_step) {
      case 1: // Personal Information
        if (_firstName.text.trim().isEmpty) {
          setState(() => _error = S.enterName);
          return;
        }
        if (_lastName.text.trim().isEmpty) {
          setState(() => _error = S.enterName);
          return;
        }
        if (!isPlausiblePhoneDigits(digitsOnly(_phone.text))) {
          setState(() => _error = S.enterPhone);
          return;
        }
        if (_dob == null) {
          setState(() => _error = S.dobRequiredError);
          return;
        }
      case 2: // Vehicle Category
        if (_vehicleType == null) {
          setState(() => _error = S.selectVehicleTypeError);
          return;
        }
      case 3: // License Details
        if (_licenseNumber.text.trim().isEmpty ||
            _licenseCategory == null ||
            _licenseIssueDate == null ||
            _licenseExpiryDate == null) {
          setState(() => _error = S.licenseDetailsRequiredError);
          return;
        }
        // STRICT MATCH — license category (dropdown मा प्रयोगकर्ताले Step 2
        // कै vehicleType पछि पनि स्वतन्त्र रूपमा बदल्न सक्छ, हेर्नुहोस्
        // `_vehicleChip`/dropdown comment) ले छानेको Bike/Car सँग नमिले
        // (जस्तै Car दर्ता गर्दा Bike-only Category 'A' license) त्यो
        // license यो registration को लागि मान्य हुँदैन।
        final expectedCategory = _vehicleType == 'Car' ? 'B' : 'A';
        if (_licenseCategory != expectedCategory) {
          _showMismatchAlert(
              'तपाईंको license category (${_licenseCategory == 'A' ? S.licenseCategoryBike : S.licenseCategoryCar}) '
              'ले छानेको सवारी प्रकार (${_vehicleType == 'Car' ? S.carWord : S.bikeWord}) सँग मेल खाएन। '
              'कृपया सही license category छान्नुहोस् वा सवारी प्रकार बदल्नुहोस्।');
          return;
        }
        // STRICT MATCH — issue date expiry date भन्दा पछाडि हुनु अमान्य
        // (मितिहरू आपसमा नमिलेको), केवल "expiry भविष्यमा छ" भन्दा बाहिरको
        // अर्को सम्भावित असंगति।
        if (!_licenseIssueDate!.isBefore(_licenseExpiryDate!)) {
          _showMismatchAlert(
              'तपाईंको license को Issue Date र Expiry Date आपसमा मेल खाएन '
              '(Issue Date, Expiry Date भन्दा पछाडि हुन मिल्दैन)। कृपया सही '
              'मिति हालेर फेरि प्रयास गर्नुहोस्।');
          return;
        }
        if (_licenseExpiryDate!.isBefore(DateTime.now())) {
          setState(() => _error = S.licenseExpiredError);
          return;
        }
        if (_licenseBytes == null) {
          setState(() => _error = S.uploadDriverDocsError);
          return;
        }
      case 4: // Vehicle Documents & Plate
        if (_vehicleMake.text.trim().isEmpty ||
            _vehicleModel.text.trim().isEmpty ||
            _vehicleColor.text.trim().isEmpty ||
            _vehiclePlate.text.trim().isEmpty) {
          setState(() => _error = S.vehicleDetailsRequiredError);
          return;
        }
        if (_vehicleRegBytes == null) {
          setState(() => _error = S.uploadDriverDocsError);
          return;
        }
        if (_insuranceBytes == null) {
          setState(() => _error = S.uploadInsuranceError);
          return;
        }
      case 5: // Identity Verification
        if (_citFrontBytes == null || _citBackBytes == null) {
          setState(() => _error = S.uploadBothCitizenship);
          return;
        }
        if (_selfieBytes == null) {
          setState(() => _error = S.selfieRequired);
          return;
        }
    }
    setState(() {
      _error = null;
      _step++;
    });
  }

  void _prev() => setState(() {
        _error = null;
        _step--;
      });

  // ── submit ────────────────────────────────────────────────────────────────

  Future<void> _submit() async {
    if (!_agreedTerms) {
      setState(() => _error = S.agreeTermsRequiredError);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final user = FirebaseAuth.instance.currentUser!;
      final uid = user.uid;

      const priceStr = '';
      final address = '$_district, Nepal';
      final name = '${_firstName.text.trim()} ${_lastName.text.trim()}'.trim();
      final phone = _phone.text.trim().isEmpty
          ? ''
          : resolveE164(_phoneCountry, _phone.text);
      final email =
          _email.text.trim().isNotEmpty ? _email.text.trim() : (user.email ?? '');
      final effectiveService = _vehicleType ?? 'Bike';

      final db = FirebaseFirestore.instance;

      final driverFields = <String, dynamic>{
        'vehicleDetails': _vehicleDetailsSummary,
        'dob': _dob?.toIso8601String(),
        'licenseNumber': _licenseNumber.text.trim(),
        'licenseCategory': _licenseCategory,
        'licenseIssueDate': _licenseIssueDate?.toIso8601String(),
        'licenseExpiryDate': _licenseExpiryDate?.toIso8601String(),
        'vehicleMake': _vehicleMake.text.trim(),
        'vehicleModel': _vehicleModel.text.trim(),
        'vehicleYear': _vehicleYear,
        'vehicleColor': _vehicleColor.text.trim(),
        'vehiclePlate': _vehiclePlate.text.trim(),
      };

      // ── चरण A: पहिले Firestore मा दर्ता लेख्ने — कागजात upload अघि ─────────
      final pendingRef = db.collection('pendingWorkers').doc();

      await Future.wait([
        db.collection('users').doc(uid).set({
          'uid': uid,
          'firstName': _firstName.text.trim(),
          'lastName': _lastName.text.trim(),
          'name': name,
          'phone': phone.isEmpty ? (user.phoneNumber ?? '') : phone,
          'email': email,
          'role': 'worker',
          'accountStatus': 'active',
          'service': effectiveService,
          'district': _district,
          'area': '',
          'location': address,
          'profileComplete': true,
          ...driverFields,
          'documentsPending': false,
          'isVerified': false,
          'verificationStatus': 'pending',
          'workerVerificationStatus': 'pending',
          'rejectionReason': FieldValue.delete(),
          'createdAt': FieldValue.serverTimestamp(),
          if (_lat != null && _lng != null) ...{
            'lat': _lat,
            'lng': _lng,
            'locationUpdatedAt': FieldValue.serverTimestamp(),
          },
        }, SetOptions(merge: true)),
        db.collection('providers').doc(uid).set({
          'uid': uid,
          'name': name,
          'phone': phone,
          'serviceType': effectiveService,
          'address': address,
          'price': priceStr,
          'verificationStatus': 'pending',
          'isVerified': false,
          'createdAt': FieldValue.serverTimestamp(),
          ...driverFields,
          if (_lat != null && _lng != null) ...{'lat': _lat, 'lng': _lng},
        }, SetOptions(merge: true)),
        pendingRef.set({
          'uid': uid,
          'firstName': _firstName.text.trim(),
          'lastName': _lastName.text.trim(),
          'email': email,
          'phone': phone,
          'service': effectiveService,
          ...driverFields,
          'price': priceStr,
          'district': _district,
          'area': '',
          'location': address,
          'certificateUrls': const <String>[],
          'documentsPending': false,
          'isVerified': false,
          'verificationStatus': 'pending',
          'status': 'pending',
          'submittedAt': FieldValue.serverTimestamp(),
          if (_lat != null && _lng != null) ...{'lat': _lat, 'lng': _lng},
        }),
        db.collection('adminNotifications').add({
          'title': 'New driver verification',
          'body':
              '$name ($effectiveService) ले Driver को रूपमा दर्ता पेश गर्नुभयो — कागजात अपलोड हुँदै।',
          'read': false,
          'createdAt': FieldValue.serverTimestamp(),
        }),
      ]);

      // ── चरण B: कागजातहरू → Storage ──────────────────────────────────────
      String citFrontUrl = '';
      String citBackUrl = '';
      String selfieUrl = '';
      String profilePicUrl = '';
      String drivingLicenseUrl = '';
      String vehicleRegUrl = '';
      String vehicleInsuranceUrl = '';
      bool uploadFailed = false;
      String? uploadErr;

      Future<String> up(Uint8List b, String n, String type) =>
          DocumentService.uploadDocument(
            uid: uid,
            bytes: b,
            originalName: n,
            type: type,
          ).timeout(const Duration(seconds: 25));

      Future<void> tryUp(
          Uint8List? bytes, String name, String type, void Function(String) set) async {
        if (bytes == null) return;
        try {
          set(await up(bytes, name, type));
        } catch (e) {
          uploadFailed = true;
          uploadErr ??= DocumentService.describeUploadError(e);
        }
      }

      await tryUp(_profilePicBytes, _profilePicName ?? 'profile.jpg',
          'profile_picture', (u) => profilePicUrl = u);
      await tryUp(_citFrontBytes, _citFrontName ?? 'front.jpg',
          'citizenship_front', (u) => citFrontUrl = u);
      await tryUp(_citBackBytes, _citBackName ?? 'back.jpg',
          'citizenship_back', (u) => citBackUrl = u);
      await tryUp(
          _selfieBytes, 'selfie.jpg', 'selfie', (u) => selfieUrl = u);
      await tryUp(_licenseBytes, _licenseName ?? 'driving_license.jpg',
          'driving_license', (u) => drivingLicenseUrl = u);
      await tryUp(
          _vehicleRegBytes,
          _vehicleRegName ?? 'vehicle_registration.jpg',
          'vehicle_registration',
          (u) => vehicleRegUrl = u);
      await tryUp(
          _insuranceBytes,
          _insuranceName ?? 'vehicle_insurance.jpg',
          'vehicle_insurance',
          (u) => vehicleInsuranceUrl = u);

      final kyc = {
        'citizenshipFrontUrl': citFrontUrl,
        'citizenshipBackUrl': citBackUrl,
        'selfieUrl': selfieUrl,
        'profilePictureUrl': profilePicUrl,
        'licenseUrl': drivingLicenseUrl.isNotEmpty ? drivingLicenseUrl : citFrontUrl,
        'documentUrl': citFrontUrl,
        'documentName': 'Citizenship',
        'drivingLicenseUrl': drivingLicenseUrl,
        'vehicleRegistrationUrl': vehicleRegUrl,
        'vehicleInsuranceUrl': vehicleInsuranceUrl,
        'vehicleType': effectiveService,
      };

      final docPatch = {
        ...kyc,
        'documentsPending': uploadFailed,
        if (uploadErr != null) 'documentsError': uploadErr,
      };
      await Future.wait([
        db.collection('users').doc(uid).set(docPatch, SetOptions(merge: true)),
        db
            .collection('providers')
            .doc(uid)
            .set(docPatch, SetOptions(merge: true)),
        pendingRef.update(docPatch),
      ]);

      if (!mounted) return;
      await showKmDialog(
        context: context,
        title: S.applicationSubmitted,
        message: uploadFailed
            ? '${S.applicationSubmittedBody}\n\n${S.docsUploadPendingNote}'
            : S.applicationSubmittedBody,
        icon: Icons.check_circle_rounded,
        iconBg: const LinearGradient(
            colors: [AppColors.kmTeal, AppColors.kmTealBlue]),
        actions: [
          KmDialogAction(
            label: S.ok,
            filled: true,
            onPressed: () => Navigator.pop(context),
          ),
        ],
      );
      if (!mounted) return;
      // root कै StreamBuilder ले verificationStatus हेरेर सही screen देखाउँछ —
      // यहाँ नयाँ MaterialApp/route push नगरी, यो पेज नै pop गरेर हटाउने।
      Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = '${S.errorWord}: $e';
      });
    }
  }

  // ── UI ────────────────────────────────────────────────────────────────────

  Future<void> _exit() async {
    await signOutClean();
    if (!mounted) return;
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  /// "Start Fresh" — rejected भएपछि यही Driver role मा नै फेरि फस्नु
  /// नपरोस् भनेर, पूरै account मेटाएर landing page बाट फेरि कुनै पनि role
  /// (Worker/Rider/Employer) छान्न दिने।
  Future<void> _startFresh() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final phone = FirebaseAuth.instance.currentUser?.phoneNumber;
    final confirm = await showKmDialog<bool>(
      context: context,
      title: 'फेरि सुरु गर्ने?',
      message:
          'यो दर्ता र account पूर्ण रूपमा मेटिनेछ। तपाईं फेरि फोन नम्बरबाट '
          'login गरेर जुनसुकै प्रकार (Worker, Rider/Driver, Employer) '
          'छान्न सक्नुहुन्छ।',
      icon: Icons.restart_alt_rounded,
      iconBg: const LinearGradient(
          colors: [AppColors.kmRose, AppColors.kmPinkDeep]),
      actions: [
        KmDialogAction(
            label: 'रद्द गर्नुहोस्', onPressed: () => Navigator.pop(context, false)),
        KmDialogAction(
          label: 'मेटाएर फेरि सुरु गर्नुहोस्',
          destructive: true,
          filled: true,
          onPressed: () => Navigator.pop(context, true),
        ),
      ],
    );
    if (confirm != true) return;
    setState(() => _saving = true);
    try {
      await deleteAccountCascade(uid, phone: phone);
      if (!mounted) return;
      Navigator.of(context).popUntil((route) => route.isFirst);
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      final msg = e.code == 'requires-recent-login'
          ? 'सुरक्षा कारणले, कृपया लगआउट गरेर फेरि लगइन गरी प्रयास गर्नुहोस्।'
          : '${S.errorWord}: ${e.message}';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('${S.errorWord}: $e')));
    }
  }

  static const _stepTitles = [
    'stepCityConfirm',
    'stepPersonalInfo',
    'stepVehicleCategory',
    'stepLicenseDetails',
    'stepVehicleDocuments',
    'stepIdentityVerification',
    'stepFinalReview',
  ];

  String _titleFor(int step) {
    switch (_stepTitles[step]) {
      case 'stepCityConfirm':
        return S.stepCityConfirm;
      case 'stepPersonalInfo':
        return S.stepPersonalInfo;
      case 'stepVehicleCategory':
        return S.stepVehicleCategory;
      case 'stepLicenseDetails':
        return S.stepLicenseDetails;
      case 'stepVehicleDocuments':
        return S.stepVehicleDocuments;
      case 'stepIdentityVerification':
        return S.stepIdentityVerification;
      default:
        return S.stepFinalReview;
    }
  }

  /// Step-progress indicator — `worker_registration_page.dart`'s `_StepBar`
  /// कै उस्तै भाषा (circle + हरियो checkmark सफल भएको step मा), तर ७ step
  /// (यहाँ धेरै) को लागि compact — per-step text label बिना, किनभने step
  /// title माथिकै Row ले पहिल्यै देखाउँछ। `i < _step` भएको step सधैं
  /// `_next()` ले validate गरिसकेकै हो (step ordering आफैंले यही ग्यारेन्टी
  /// गर्छ), त्यसैले checkmark = "यो step साँच्चै validate भई पास भयो"।
  Widget _stepDots() {
    return Row(
      children: List.generate(_totalSteps, (i) {
        final done = i < _step;
        final active = i == _step;
        return Expanded(
          child: Row(
            children: [
              Container(
                width: 22,
                height: 22,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  gradient: (done || active) ? AppColors.kmCtaGradient : null,
                  color: (done || active)
                      ? null
                      : Colors.white.withValues(alpha: 0.08),
                  shape: BoxShape.circle,
                ),
                child: done
                    ? const Icon(Icons.check_rounded,
                        size: 13, color: AppColors.kmInk)
                    : Text('${i + 1}',
                        style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                            color: active
                                ? AppColors.kmInk
                                : AppColors.kmMuted)),
              ),
              if (i < _totalSteps - 1)
                Expanded(
                  child: Container(
                    height: 2,
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    color: done
                        ? AppColors.kmOrange
                        : Colors.white.withValues(alpha: 0.14),
                  ),
                ),
            ],
          ),
        );
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return PopScope(
      canPop: _step == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _step > 0) _prev();
      },
      child: AuroraBackground(
        orbs: const [
          KmOrb(Alignment.topRight, AppColors.kmPurple),
          KmOrb(Alignment.bottomLeft, AppColors.kmOrangeDeep),
        ],
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: KmScreenHeader(
                    title: S.driverRegTitle,
                    onBack: _saving
                        ? () {}
                        : (_step > 0 ? _prev : _exit),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(S.stepOf(_step + 1, _totalSteps),
                              style: const TextStyle(
                                  color: AppColors.kmMuted,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12.5)),
                          Text(_titleFor(_step),
                              style: const TextStyle(
                                  color: AppColors.kmText,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 13.5)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      _stepDots(),
                    ],
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: GlassPanel(
                      radius: 28,
                      padding: const EdgeInsets.all(18),
                      child: IndexedStack(
                        index: _step,
                        children: [
                          _cityStep(theme),
                          _personalStep(theme),
                          _vehicleCategoryStep(theme),
                          _licenseStep(theme),
                          _vehicleDocsStep(theme),
                          _identityStep(theme),
                          _reviewStep(theme),
                        ],
                      ),
                    ),
                  ),
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
                    child: Text(_error!,
                        style: const TextStyle(
                            color: AppColors.kmRose,
                            fontWeight: FontWeight.w600)),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 6, 20, 16),
                  child: Row(
                    children: [
                      if (_step > 0) ...[
                        Expanded(
                          child: SecondaryButton(
                            label: S.back,
                            color: AppColors.kmText,
                            onPressed: _saving ? null : _prev,
                          ),
                        ),
                        const SizedBox(width: 12),
                      ],
                      Expanded(
                        child: _step < _totalSteps - 1
                            ? KmCtaButton(
                                label: S.next,
                                icon: Icons.arrow_forward_rounded,
                                onPressed: _next,
                              )
                            : KmCtaButton(
                                label: S.submitForApproval,
                                loading: _saving,
                                onPressed: _submit,
                              ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _dec(String label) => kmInputDecoration(label);

  Widget _rejectedBanner(ThemeData theme) {
    if (!_wasRejected) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.kmPink.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.kmPink.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded,
              size: 18, color: AppColors.kmRose),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _rejectReason.isEmpty
                  ? S.docRejectedBanner
                  : '${S.docRejectedBanner}\n${S.reasonLabel}: $_rejectReason',
              style: const TextStyle(
                  color: AppColors.kmRose, fontWeight: FontWeight.w600),
            ),
          ),
          TextButton(
            onPressed: _saving ? null : _startFresh,
            child: const Text('Change role',
                style: TextStyle(
                    color: AppColors.kmRose,
                    fontWeight: FontWeight.w700,
                    fontSize: 12.5)),
          ),
        ],
      ),
    );
  }

  // ── Step 0: City Confirmation ────────────────────────────────────────────
  Widget _cityStep(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _rejectedBanner(theme),
        Text(S.cityConfirmTitle,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
        const SizedBox(height: 6),
        Text(S.cityConfirmHint, style: theme.textTheme.bodySmall),
        const SizedBox(height: 18),
        DropdownButtonFormField<String>(
          initialValue: _district,
          decoration: _dec(S.district),
          items: _districts
              .map((d) => DropdownMenuItem(value: d, child: Text(d)))
              .toList(),
          onChanged: (v) => setState(() => _district = v!),
        ),
      ],
    );
  }

  // ── Step 1: Personal Information ─────────────────────────────────────────
  Widget _personalStep(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(S.profilePictureLabel,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
        const SizedBox(height: 6),
        Text(S.profilePictureHint, style: theme.textTheme.bodySmall),
        const SizedBox(height: 14),
        Center(
          child: GestureDetector(
            onTap: _pickProfilePic,
            child: Container(
              width: 110,
              height: 110,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.06),
                shape: BoxShape.circle,
                border: Border.all(
                    color: _profilePicBytes != null
                        ? AppColors.kmTeal
                        : Colors.white.withValues(alpha: 0.16),
                    width: 2),
              ),
              clipBehavior: Clip.antiAlias,
              child: _profilePicBytes != null
                  ? Image.memory(_profilePicBytes!, fit: BoxFit.cover)
                  : const Icon(Icons.add_a_photo_rounded,
                      size: 34, color: AppColors.kmMuted),
            ),
          ),
        ),
        const SizedBox(height: 20),
        TextFormField(
          controller: _firstName,
          decoration: _dec(S.firstName),
        ),
        const SizedBox(height: 14),
        TextFormField(
          controller: _lastName,
          decoration: _dec(S.surnameLabel),
        ),
        const SizedBox(height: 14),
        CountryPhoneField(
          controller: _phone,
          country: _phoneCountry,
          onCountryChanged: (c) => setState(() => _phoneCountry = c),
          decoration: _dec(S.phone),
        ),
        const SizedBox(height: 14),
        TextFormField(
          controller: _email,
          keyboardType: TextInputType.emailAddress,
          decoration: _dec(S.emailLabel),
        ),
        const SizedBox(height: 14),
        InkWell(
          onTap: _pickDob,
          child: InputDecorator(
            decoration: _dec(S.dob),
            child: Text(_dob == null ? S.selectDateHint : _fmtDate(_dob)),
          ),
        ),
      ],
    );
  }

  // ── Step 2: Vehicle Category ─────────────────────────────────────────────
  Widget _vehicleCategoryStep(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(S.stepVehicleCategory,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
        const SizedBox(height: 6),
        Text(S.vehicleCategoryHint, style: theme.textTheme.bodySmall),
        const SizedBox(height: 18),
        Row(
          children: [
            Expanded(
              child: _vehicleChip(theme, 'Bike', S.bikeWord),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _vehicleChip(theme, 'Car', S.carWord),
            ),
          ],
        ),
      ],
    );
  }

  Widget _vehicleChip(ThemeData theme, String value, String label) {
    final selected = _vehicleType == value;
    return GestureDetector(
      onTap: () => setState(() {
        _vehicleType = value;
        _licenseCategory ??= value == 'Bike' ? 'A' : 'B';
      }),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.kmOrange.withValues(alpha: 0.14)
              : Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: selected
                  ? AppColors.kmOrange
                  : Colors.white.withValues(alpha: 0.14),
              width: selected ? 2 : 1),
        ),
        child: Column(
          children: [
            SizedBox(
              height: 56,
              width: double.infinity,
              child: Image.asset(serviceImageFor(value), fit: BoxFit.contain),
            ),
            const SizedBox(height: 8),
            Text(label,
                style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: selected ? AppColors.kmOrange : AppColors.kmText)),
          ],
        ),
      ),
    );
  }

  // ── Step 3: Driver License Details ───────────────────────────────────────
  Widget _licenseStep(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(S.drivingLicenseLabel,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
        const SizedBox(height: 6),
        Text(S.vehicleDocsRequiredHint, style: theme.textTheme.bodySmall),
        const SizedBox(height: 14),
        TextFormField(
          controller: _licenseNumber,
          decoration: _dec(S.licenseNumberLabel),
        ),
        const SizedBox(height: 14),
        DropdownButtonFormField<String>(
          initialValue: _licenseCategory,
          decoration: _dec(S.licenseCategoryLabel),
          items: [
            DropdownMenuItem(value: 'A', child: Text(S.licenseCategoryBike)),
            DropdownMenuItem(value: 'B', child: Text(S.licenseCategoryCar)),
          ],
          onChanged: (v) => setState(() => _licenseCategory = v),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: InkWell(
                onTap: _pickLicenseIssueDate,
                child: InputDecorator(
                  decoration: _dec(S.licenseIssueDateLabel),
                  child: Text(_licenseIssueDate == null
                      ? S.selectDateHint
                      : _fmtDate(_licenseIssueDate)),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: InkWell(
                onTap: _pickLicenseExpiryDate,
                child: InputDecorator(
                  decoration: _dec(S.licenseExpiryDateLabel),
                  child: Text(_licenseExpiryDate == null
                      ? S.selectDateHint
                      : _fmtDate(_licenseExpiryDate)),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _uploadTile(theme,
            label: _licenseName ?? S.drivingLicenseLabel,
            bytes: _licenseBytes,
            onTap: _pickLicense),
      ],
    );
  }

  // ── Step 4: Vehicle Documents & Plate ────────────────────────────────────
  Widget _vehicleDocsStep(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(S.vehicleRegistrationLabel,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: _vehicleMake,
                decoration: _dec(S.vehicleMakeLabel),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextFormField(
                controller: _vehicleModel,
                decoration: _dec(S.vehicleModelLabel),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: _vehicleYear,
                decoration: _dec(S.vehicleYearLabel),
                items: _vehicleYears
                    .map((y) => DropdownMenuItem(value: y, child: Text(y)))
                    .toList(),
                onChanged: (v) => setState(() => _vehicleYear = v!),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextFormField(
                controller: _vehicleColor,
                decoration: _dec(S.vehicleColorLabel),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        TextFormField(
          controller: _vehiclePlate,
          decoration: _dec(S.vehiclePlateLabel),
        ),
        const SizedBox(height: 16),
        _uploadTile(theme,
            label: _vehicleRegName ?? S.vehicleRegistrationLabel,
            bytes: _vehicleRegBytes,
            onTap: _pickVehicleReg),
        const SizedBox(height: 16),
        _uploadTile(theme,
            label: _insuranceName ?? S.vehicleInsuranceLabel,
            bytes: _insuranceBytes,
            onTap: _pickInsurance),
      ],
    );
  }

  // ── Step 5: Identity Verification ────────────────────────────────────────
  Widget _identityStep(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(S.citizenshipTitle,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
        const SizedBox(height: 6),
        Text(S.citizenshipHint, style: theme.textTheme.bodySmall),
        const SizedBox(height: 16),
        _uploadTile(theme,
            label: _citFrontName ?? S.citizenshipFront,
            bytes: _citFrontBytes,
            onTap: _pickCitFront),
        const SizedBox(height: 14),
        _uploadTile(theme,
            label: _citBackName ?? S.citizenshipBack,
            bytes: _citBackBytes,
            onTap: _pickCitBack),
        const SizedBox(height: 24),
        Divider(color: Colors.white.withValues(alpha: 0.14)),
        const SizedBox(height: 16),
        Text(S.selfieWithIdTitle,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
        const SizedBox(height: 8),
        Text(S.selfieWithIdHint, style: theme.textTheme.bodySmall),
        const SizedBox(height: 16),
        Center(
          child: Container(
            width: 170,
            height: 170,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.06),
              shape: BoxShape.circle,
              border: Border.all(
                  color: _selfieBytes != null
                      ? AppColors.kmTeal
                      : Colors.white.withValues(alpha: 0.16),
                  width: 2),
            ),
            clipBehavior: Clip.antiAlias,
            child: _selfieBytes != null
                ? Image.memory(_selfieBytes!, fit: BoxFit.cover)
                : const Icon(Icons.badge_rounded,
                    size: 58, color: AppColors.kmMuted),
          ),
        ),
        const SizedBox(height: 16),
        Center(
          child: SecondaryButton(
            label: _selfieBytes == null ? S.takeSelfie : S.retake,
            icon: Icons.camera_alt_rounded,
            color: AppColors.kmOrange,
            expand: false,
            onPressed: _takeSelfie,
          ),
        ),
      ],
    );
  }

  Widget _uploadTile(ThemeData theme,
      {required String label,
      required Uint8List? bytes,
      required VoidCallback onTap}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OutlinedButton.icon(
          onPressed: onTap,
          icon: Icon(bytes == null
              ? Icons.upload_file_rounded
              : Icons.check_circle_rounded),
          label: Text(label, overflow: TextOverflow.ellipsis),
          style: OutlinedButton.styleFrom(
            foregroundColor:
                bytes == null ? AppColors.kmOrange : AppColors.kmTeal,
            side: BorderSide(
                color: bytes == null ? AppColors.kmOrange : AppColors.kmTeal),
            padding: const EdgeInsets.symmetric(vertical: 12),
          ),
        ),
        if (bytes != null) ...[
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.memory(bytes, height: 130, fit: BoxFit.cover),
          ),
        ],
      ],
    );
  }

  // ── Step 6: Final Review, Terms, Submit ──────────────────────────────────
  Widget _reviewStep(ThemeData theme) {
    Widget section(String title, List<(String, String)> rows, VoidCallback onEdit) {
      return Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(title,
                    style: const TextStyle(
                        color: AppColors.kmText,
                        fontWeight: FontWeight.w800,
                        fontSize: 14)),
                TextButton(
                  onPressed: onEdit,
                  style: TextButton.styleFrom(
                      foregroundColor: AppColors.kmOrange),
                  child: Text(S.editWord),
                ),
              ],
            ),
            for (final r in rows)
              if (r.$2.trim().isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text('${r.$1}: ${r.$2}',
                      style: const TextStyle(
                          color: AppColors.kmMuted, fontSize: 13)),
                ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(S.stepFinalReview,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
        const SizedBox(height: 14),
        section(
            S.reviewPersonalSection,
            [
              (S.firstName, _firstName.text.trim()),
              (S.surnameLabel, _lastName.text.trim()),
              (
                S.phone,
                _phone.text.trim().isEmpty
                    ? ''
                    : resolveE164(_phoneCountry, _phone.text)
              ),
              (S.dob, _fmtDate(_dob)),
              (S.district, _district),
            ],
            () => setState(() => _step = 1)),
        section(
            S.reviewVehicleSection,
            [
              (S.stepVehicleCategory,
                  _vehicleType == 'Car' ? S.carWord : S.bikeWord),
              ('', _vehicleDetailsSummary),
            ],
            () => setState(() => _step = 2)),
        section(
            S.reviewLicenseSection,
            [
              (S.licenseNumberLabel, _licenseNumber.text.trim()),
              (S.licenseExpiryDateLabel, _fmtDate(_licenseExpiryDate)),
            ],
            () => setState(() => _step = 3)),
        section(
            S.reviewDocsSection,
            [
              (S.vehicleRegistrationLabel,
                  _vehicleRegBytes != null ? '✓' : ''),
              (S.vehicleInsuranceLabel, _insuranceBytes != null ? '✓' : ''),
              (S.citizenshipTitle,
                  (_citFrontBytes != null && _citBackBytes != null)
                      ? '✓'
                      : ''),
              (S.selfieWithIdTitle, _selfieBytes != null ? '✓' : ''),
            ],
            () => setState(() => _step = 5)),
        const SizedBox(height: 6),
        InkWell(
          onTap: () => setState(() => _agreedTerms = !_agreedTerms),
          child: Row(
            children: [
              Checkbox(
                value: _agreedTerms,
                activeColor: AppColors.kmOrange,
                onChanged: (v) => setState(() => _agreedTerms = v ?? false),
              ),
              Expanded(
                child: Text(S.agreeTermsLabel,
                    style: const TextStyle(
                        color: AppColors.kmText, fontSize: 13)),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
