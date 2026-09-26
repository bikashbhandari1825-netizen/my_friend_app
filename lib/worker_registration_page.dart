// worker_registration_page.dart
// सेवा प्रदायक (Worker/Provider) को multi-step onboarding:
//   चरण 1: व्यक्तिगत + सेवा विवरण
//   चरण 2: लाइसेन्स/नागरिकता कागजात (गैलरी/क्यामेरा)
//   चरण 3: लाइभ सेल्फी प्रमाणीकरण
// Submit हुँदा license + selfie Firebase Storage मा जान्छ, URL हरू Firestore
// (users/{uid}, providers/{uid}, pendingWorkers) मा; verificationStatus → 'pending'।
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'auth/dev_login.dart';
import 'l10n/strings.dart';
import 'services/document_service.dart';
import 'services/upload_validation.dart';
import 'theme/app_theme.dart';
import 'widgets/app_ui.dart' show SecondaryButton;
import 'widgets/glass_ui.dart';

class WorkerRegistrationPage extends StatefulWidget {
  const WorkerRegistrationPage({super.key});

  @override
  State<WorkerRegistrationPage> createState() => _WorkerRegistrationPageState();
}

class _WorkerRegistrationPageState extends State<WorkerRegistrationPage> {
  final _formKey = GlobalKey<FormState>();
  final _firstName = TextEditingController();
  final _lastName = TextEditingController();
  final _phone = TextEditingController();
  final _price = TextEditingController(text: '500');
  final _area = TextEditingController();

  // 'Driver' यो सामान्य सेवा-सूचीमा अब छैन — Role Selection Screen कै छुट्टै
  // "Driver" कार्डबाट मात्र (driverEntry=true भई) पुग्न मिल्छ।
  static const _services = [
    'Mechanic',
    'Plumber',
    'Carpenter',
    'Painter',
    'Cleaner',
    'Electrician',
    'Tutor',
  ];
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
  static const _years = [
    '0',
    '1',
    '2',
    '3',
    '4',
    '5',
    '6',
    '7',
    '8',
    '9',
    '10+'
  ];
  static const _months = [
    '0',
    '1',
    '2',
    '3',
    '4',
    '5',
    '6',
    '7',
    '8',
    '9',
    '10',
    '11'
  ];

  int _step = 0;
  String _service = 'Plumber';
  String _district = 'Kathmandu';
  String _year = '1';
  String _month = '0';

  // InDrive-Style Ride-Sharing — 'Driver' आफैं कहिल्यै साँचो registrable
  // service होइन; यहाँ छानेको Bike/Car नै Firestore मा बचत हुने वास्तविक
  // `service` मान हो (home screen कै "Driver tap → Bike/Car popup" जस्तै
  // convention)।
  String? _vehicleType; // 'Bike' | 'Car' — _service=='Driver' हुँदा मात्र चाहिने
  String get _effectiveService =>
      _service == 'Driver' ? (_vehicleType ?? 'Bike') : _service;

  // Driver-मात्र अनिवार्य: व्यक्तिगत सम्पर्क विवरण (फोन OTP login कै बेला
  // पहिल्यै प्रमाणित भइसकेको हुन्छ — यहाँ थप्नु परेन)।
  final _email = TextEditingController();
  DateTime? _dob;

  // Driver-मात्र अनिवार्य: चालक अनुमतिपत्रका structured विवरण (कागजातको
  // तस्बिर मात्र काफी थिएन — म्याद सकिएको लाइसेन्स admin ले तुरुन्तै छुट्याउन
  // सकोस् भनेर नम्बर/श्रेणी/मिति अलग-अलग फिल्डमा)।
  final _licenseNumber = TextEditingController();
  String? _licenseCategory; // 'A' (bike) | 'B' (car)
  DateTime? _licenseIssueDate;
  DateTime? _licenseExpiryDate;

  // Driver-मात्र अनिवार्य: सवारीका structured विवरण।
  final _vehicleMake = TextEditingController();
  final _vehicleModel = TextEditingController();
  final _vehicleColor = TextEditingController();
  final _vehiclePlate = TextEditingController();
  String _vehicleYear = '2020';
  static final List<String> _vehicleYears = List.generate(
      DateTime.now().year - 1989, (i) => (DateTime.now().year - i).toString());

  // माथिका structured फिल्डबाट बनेको एउटै पढ्न-मिल्ने सारांश — profile/admin
  // कार्डमा पहिल्यैदेखि प्रयोग हुने `vehicleDetails` field सँग compat राख्न।
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

  // Driver-मात्र अनिवार्य कागजात — सवारी चालक अनुमतिपत्र + सवारी दर्ता (ब्लु
  // बुक)। यी बिना Bike/Car चालक अनलाइन नहोस् भनेर submit नै रोकिन्छ (तल
  // `_submit()` हेर्नुहोस्)।
  Uint8List? _licenseBytes;
  String? _licenseName;
  Uint8List? _vehicleRegBytes;
  String? _vehicleRegName;
  Uint8List? _insuranceBytes;
  String? _insuranceName;

  // Identity: नागरिकता अगाडि + पछाडि
  Uint8List? _citFrontBytes;
  String? _citFrontName;
  Uint8List? _citBackBytes;
  String? _citBackName;
  // अनुहार प्रमाणीकरण (नागरिकता समातेको लाइभ फोटो)
  Uint8List? _selfieBytes;
  // कामको अनुभव / प्रमाणपत्र (ऐच्छिक, 0..n)
  final List<({Uint8List bytes, String name})> _certs = [];

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
    _price.dispose();
    _area.dispose();
    _email.dispose();
    _licenseNumber.dispose();
    _vehicleMake.dispose();
    _vehicleModel.dispose();
    _vehicleColor.dispose();
    _vehiclePlate.dispose();
    super.dispose();
  }

  // ── document / selfie pickers ──────────────────────────────────────────────

  /// picker बाट आएको फाइल स्वीकार्ने अघि साइज/प्रकार/signature जाँच।
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

  /// क्यामेरा वा फाइलबाट एउटा document/photo उठाउने (validate सहित)।
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

  Future<void> _addCert() async {
    final r = await _pickFile(allowPdf: true);
    if (r == null) return;
    setState(() {
      _certs.add(r);
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

  // ── step navigation ───────────────────────────────────────────────────────

  void _next() {
    if (_step == 0) {
      if (!_formKey.currentState!.validate()) return;
      if (_service == 'Driver' && _vehicleType == null) {
        setState(() => _error = S.selectVehicleTypeError);
        return;
      }
      if (_service == 'Driver' &&
          (_email.text.trim().isEmpty || !_email.text.contains('@'))) {
        setState(() => _error = S.emailLabel);
        return;
      }
      if (_service == 'Driver' && _dob == null) {
        setState(() => _error = S.dobRequiredError);
        return;
      }
    } else if (_step == 1) {
      if (_citFrontBytes == null || _citBackBytes == null) {
        setState(() => _error = S.uploadBothCitizenship);
        return;
      }
    } else if (_step == 2) {
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
    if (_selfieBytes == null) {
      setState(() => _error = S.selfieRequired);
      return;
    }
    if (_service == 'Driver' && _vehicleType == null) {
      setState(() => _error = S.selectVehicleTypeError);
      return;
    }
    if (_service == 'Driver' &&
        (_email.text.trim().isEmpty || !_email.text.contains('@'))) {
      setState(() => _error = S.emailLabel);
      return;
    }
    if (_service == 'Driver' && _dob == null) {
      setState(() => _error = S.dobRequiredError);
      return;
    }
    if (_service == 'Driver' &&
        (_licenseNumber.text.trim().isEmpty ||
            _licenseCategory == null ||
            _licenseIssueDate == null ||
            _licenseExpiryDate == null)) {
      setState(() => _error = S.licenseDetailsRequiredError);
      return;
    }
    if (_service == 'Driver' &&
        _licenseExpiryDate!.isBefore(DateTime.now())) {
      setState(() => _error = S.licenseExpiredError);
      return;
    }
    if (_service == 'Driver' &&
        (_vehicleMake.text.trim().isEmpty ||
            _vehicleModel.text.trim().isEmpty ||
            _vehicleColor.text.trim().isEmpty ||
            _vehiclePlate.text.trim().isEmpty)) {
      setState(() => _error = S.vehicleDetailsRequiredError);
      return;
    }
    if (_service == 'Driver' &&
        (_licenseBytes == null || _vehicleRegBytes == null)) {
      setState(() => _error = S.uploadDriverDocsError);
      return;
    }
    if (_service == 'Driver' && _insuranceBytes == null) {
      setState(() => _error = S.uploadInsuranceError);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final user = FirebaseAuth.instance.currentUser!;
      final uid = user.uid;

      final experience = _month == '0'
          ? '$_year ${S.yearsWord}'
          : '$_year ${S.yearsWord} $_month ${S.monthsWord}';
      final priceStr = 'Rs. ${_price.text.trim()}';
      final address = '${_area.text.trim()}, $_district, Nepal';
      final name = '${_firstName.text.trim()} ${_lastName.text.trim()}'.trim();
      final phone = _phone.text.trim();
      final email = _service == 'Driver' && _email.text.trim().isNotEmpty
          ? _email.text.trim()
          : (user.email ?? '');

      final db = FirebaseFirestore.instance;

      // Driver-मात्र structured compliance विवरण — तीनवटै doc मा उस्तै दोहोरिन्छ
      // भन्दा एकैचोटि बनाएर spread गर्दा सजिलो/छोटो हुन्छ। Driver बाहेक अरू
      // service मा फेरि switch भए (जस्तै rejected भएर फेरि पेश गर्दा) पुरानो
      // driver-मात्रका field हरू users doc मा नै बसिरहन नदिन delete गरिन्छ।
      const driverOnlyKeys = [
        'vehicleDetails',
        'dob',
        'licenseNumber',
        'licenseCategory',
        'licenseIssueDate',
        'licenseExpiryDate',
        'vehicleMake',
        'vehicleModel',
        'vehicleYear',
        'vehicleColor',
        'vehiclePlate',
      ];
      final driverFields = _service != 'Driver'
          ? {for (final k in driverOnlyKeys) k: FieldValue.delete()}
          : <String, dynamic>{
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
      // `pendingWorkers` सधैँ नयाँ (non-merge) doc हो — FieldValue.delete()
      // त्यहाँ अवैध हुन्छ (मेटाउन केही छँदै छैन), त्यसैले Driver नभएमा यहाँ
      // key नै नथपिने (माथिको merge-doc हरूमा भने delete सही तरिका हो)।
      final driverFieldsNew =
          _service == 'Driver' ? driverFields : const <String, dynamic>{};

      // ── चरण A: पहिले Firestore मा दर्ता लेख्ने — कागजात upload अघि ─────────
      //   यसले admin को "बाँकी स्वीकृति" list (real-time snapshots() stream) मा
      //   कामदार तुरुन्तै देखियोस्, storage upload (हरेक फाइल २५s सम्म) पर्खनु
      //   नपरोस्। कागजातका URL पछि चरण C मा भरिन्छन्।
      final pendingRef = db.collection('pendingWorkers').doc();

      await Future.wait([
        // users/{uid} — कामदारको आफ्नै gate पनि तुरुन्तै अगाडि बढोस्
        db.collection('users').doc(uid).set({
          'uid': uid,
          'firstName': _firstName.text.trim(),
          'lastName': _lastName.text.trim(),
          'name': name,
          'phone': phone.isEmpty ? (user.phoneNumber ?? '') : phone,
          'email': email,
          'role': 'worker',
          'accountStatus': 'active',
          'service': _effectiveService,
          'experience': experience,
          'priceValue': _price.text.trim(),
          'district': _district,
          'area': _area.text.trim(),
          'location': address,
          'profileComplete': true,
          ...driverFields,
          // आशावादी: upload अझै बाँकी छ तर fail भएको छैन। चरण C ले fail भए
          // मात्र यसलाई true बनाउँछ — त्यसैले बीचमा "कागजात अपलोड भएन" warning
          // नदेखियोस्।
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

        // providers/{uid}
        db.collection('providers').doc(uid).set({
          'uid': uid,
          'name': name,
          'phone': phone,
          'serviceType': _effectiveService,
          'address': address,
          'experience': experience,
          'price': priceStr,
          'verificationStatus': 'pending',
          'isVerified': false,
          'createdAt': FieldValue.serverTimestamp(),
          ...driverFields,
          if (_lat != null && _lng != null) ...{'lat': _lat, 'lng': _lng},
        }, SetOptions(merge: true)),

        // pendingWorkers — admin ले हेर्ने (real-time)
        pendingRef.set({
          'uid': uid,
          'firstName': _firstName.text.trim(),
          'lastName': _lastName.text.trim(),
          'email': email,
          'phone': phone,
          'service': _effectiveService,
          'experience': experience,
          ...driverFieldsNew,
          'price': priceStr,
          'district': _district,
          'area': _area.text.trim(),
          'location': address,
          'certificateYear': _year,
          'certificateUrls': const <String>[],
          'documentsPending': false,
          'isVerified': false,
          'verificationStatus': 'pending',
          'status': 'pending',
          'submittedAt': FieldValue.serverTimestamp(),
          if (_lat != null && _lng != null) ...{'lat': _lat, 'lng': _lng},
        }),

        db.collection('adminNotifications').add({
          'title': 'New provider verification',
          'body':
              '$name ($_effectiveService) ले दर्ता पेश गर्नुभयो — कागजात अपलोड हुँदै।',
          'read': false,
          'createdAt': FieldValue.serverTimestamp(),
        }),
      ]);

      // ── चरण B: नागरिकता (अगाडि/पछाडि) + अनुहार + प्रमाणपत्रहरू → Storage ──
      //   Storage enable नभए वा fail भए पनि दर्ता रोकिँदैन — URL खाली रहन्छ।
      String citFrontUrl = '';
      String citBackUrl = '';
      String selfieUrl = '';
      final List<String> certUrls = [];
      bool uploadFailed = false;
      String? uploadErr;

      Future<String> up(Uint8List b, String n, String type) =>
          DocumentService.uploadDocument(
            uid: uid,
            bytes: b,
            originalName: n,
            type: type,
          ).timeout(const Duration(seconds: 25));

      try {
        citFrontUrl = await up(
            _citFrontBytes!, _citFrontName ?? 'front.jpg', 'citizenship_front');
      } catch (e) {
        uploadFailed = true;
        uploadErr ??= DocumentService.describeUploadError(e);
      }
      try {
        citBackUrl = await up(
            _citBackBytes!, _citBackName ?? 'back.jpg', 'citizenship_back');
      } catch (e) {
        uploadFailed = true;
        uploadErr ??= DocumentService.describeUploadError(e);
      }
      try {
        selfieUrl = await up(_selfieBytes!, 'selfie.jpg', 'selfie');
      } catch (e) {
        uploadFailed = true;
        uploadErr ??= DocumentService.describeUploadError(e);
      }
      for (var i = 0; i < _certs.length; i++) {
        try {
          certUrls.add(await up(
              _certs[i].bytes, _certs[i].name, 'certificate_${i + 1}'));
        } catch (e) {
          uploadFailed = true;
          uploadErr ??= DocumentService.describeUploadError(e);
        }
      }

      // Driver Verification & Registration — Bike/Car चालकका लागि मात्र,
      // सवारी चालक अनुमतिपत्र + सवारी दर्ता (ब्लु बुक) + बिमा पनि Storage मा।
      String drivingLicenseUrl = '';
      String vehicleRegUrl = '';
      String vehicleInsuranceUrl = '';
      if (_service == 'Driver') {
        try {
          drivingLicenseUrl = await up(_licenseBytes!,
              _licenseName ?? 'driving_license.jpg', 'driving_license');
        } catch (e) {
          uploadFailed = true;
          uploadErr ??= DocumentService.describeUploadError(e);
        }
        try {
          vehicleRegUrl = await up(_vehicleRegBytes!,
              _vehicleRegName ?? 'vehicle_registration.jpg',
              'vehicle_registration');
        } catch (e) {
          uploadFailed = true;
          uploadErr ??= DocumentService.describeUploadError(e);
        }
        try {
          vehicleInsuranceUrl = await up(_insuranceBytes!,
              _insuranceName ?? 'vehicle_insurance.jpg', 'vehicle_insurance');
        } catch (e) {
          uploadFailed = true;
          uploadErr ??= DocumentService.describeUploadError(e);
        }
      }

      // पुरानो field हरूसँग compat — admin dashboard ले documentUrl/licenseUrl
      // पढ्छ। Driver का लागि `licenseUrl` लाई साँच्चै सवारी चालक अनुमतिपत्रले
      // नै override गर्छ (नत्र त्यो सधैँ नागरिकता-अगाडिको alias मात्र हुन्थ्यो)।
      final kyc = {
        'citizenshipFrontUrl': citFrontUrl,
        'citizenshipBackUrl': citBackUrl,
        'selfieUrl': selfieUrl,
        'certificateUrls': certUrls,
        'licenseUrl': _service == 'Driver' ? drivingLicenseUrl : citFrontUrl,
        'documentUrl': citFrontUrl,
        'documentName': 'Citizenship',
        if (_service == 'Driver') ...{
          'drivingLicenseUrl': drivingLicenseUrl,
          'vehicleRegistrationUrl': vehicleRegUrl,
          'vehicleInsuranceUrl': vehicleInsuranceUrl,
          'vehicleType': _effectiveService,
        },
      };

      // ── चरण C: upload सकिएपछि तीनवटै doc मा URL + documentsPending भर्ने ──
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
        icon: Icons.task_alt_rounded,
        actions: [
          KmDialogAction(
              label: S.ok,
              filled: true,
              onPressed: () => Navigator.pop(context)),
        ],
      );
      if (!mounted) return;
      // नयाँ KaamMitraApp() नबनाउने — root कै authStateChanges()/users-doc
      // StreamBuilder ले नै verificationStatus अपडेट भएपछि सही screen देखाउँछ
      // (त्यही एउटै Navigator भित्र)। दोस्रोपटक फेरि नयाँ MaterialApp push
      // गर्दा (उही rootNavigatorKey दुइटा ठाउँमा) element-lifecycle assertion
      // (red/black screen crash) आउँथ्यो — यो पेज pop गरेर हटाउनु मात्र पर्छ।
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return PopScope(
      // step > 0 मा system-back ले अघिल्लो step मा फर्काउँछ; step 0 मा normal।
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
                    title: S.workerRegTitle,
                    onBack: _saving
                        ? () {}
                        : (_step > 0 ? _prev : _exit),
                  ),
                ),
                _StepBar(step: _step, service: _service),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: GlassPanel(
                      radius: 28,
                      padding: const EdgeInsets.all(18),
                      child: IndexedStack(
                        index: _step,
                        children: [
                          _detailsStep(theme),
                          _citizenshipStep(theme),
                          _selfieStep(theme),
                          _certsStep(theme),
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
                        child: _step < 3
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

  Widget _detailsStep(ThemeData theme) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_wasRejected)
            Container(
              margin: const EdgeInsets.only(bottom: 14),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.kmPink.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: AppColors.kmPink.withValues(alpha: 0.4)),
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
                          color: AppColors.kmRose,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          Text(S.regWorkerNote,
              style: const TextStyle(color: AppColors.kmMuted, fontSize: 12.5)),
          const SizedBox(height: 16),
          TextFormField(
            controller: _firstName,
            decoration: _dec(S.firstName),
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? S.enterName : null,
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _lastName,
            decoration: _dec(S.lastName),
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? S.enterName : null,
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            decoration: _dec(S.phone),
            validator: (v) =>
                (v == null || v.trim().length < 7) ? S.enterPhone : null,
          ),
          const SizedBox(height: 14),
          DropdownButtonFormField<String>(
            initialValue: _service,
            decoration: _dec(S.serviceCategory),
            items: _services
                .map((s) =>
                    DropdownMenuItem(value: s, child: Text(S.serviceName(s))))
                .toList(),
            onChanged: (v) => setState(() => _service = v!),
          ),
          // यो 'Driver' शाखा अब कहिल्यै पुग्दैन (Driver अब छुट्टै
          // DriverRegistrationFlow मार्फत जान्छ, र 'Driver' _services
          // dropdown मा छैन) — तर _effectiveService/driverFields जस्ता
          // साझा helper ले अझै यो जाँच्ने भएकोले सुरक्षित रूपमा राखिएको।
          if (_service == 'Driver') ...[
            const SizedBox(height: 14),
            Text(S.selectVehicleType,
                style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _vehicleChip(theme, 'Bike', Icons.two_wheeler_rounded,
                      S.bikeWord),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _vehicleChip(
                      theme, 'Car', Icons.local_taxi_rounded, S.carWord),
                ),
              ],
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
          const SizedBox(height: 18),
          Text(S.experienceLabel,
              style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _year,
                  decoration: _dec(S.yearsWord),
                  items: _years
                      .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                      .toList(),
                  onChanged: (v) => setState(() => _year = v!),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _month,
                  decoration: _dec(S.monthsWord),
                  items: _months
                      .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                      .toList(),
                  onChanged: (v) => setState(() => _month = v!),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _price,
            keyboardType: TextInputType.number,
            decoration: _dec(S.startingPrice),
          ),
          const SizedBox(height: 14),
          DropdownButtonFormField<String>(
            initialValue: _district,
            decoration: _dec(S.district),
            items: _districts
                .map((d) => DropdownMenuItem(value: d, child: Text(d)))
                .toList(),
            onChanged: (v) => setState(() => _district = v!),
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _area,
            decoration: _dec(S.areaLandmark),
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? S.enterArea : null,
          ),
        ],
      ),
    );
  }

  Widget _vehicleChip(
      ThemeData theme, String value, IconData icon, String label) {
    final selected = _vehicleType == value;
    return GestureDetector(
      onTap: () => setState(() {
        _vehicleType = value;
        _licenseCategory ??= value == 'Bike' ? 'A' : 'B';
      }),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
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
            Icon(icon, color: selected ? AppColors.kmOrange : AppColors.kmMuted),
            const SizedBox(height: 6),
            Text(label,
                style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: selected ? AppColors.kmOrange : AppColors.kmText)),
          ],
        ),
      ),
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
            child: Image.memory(bytes, height: 150, fit: BoxFit.cover),
          ),
        ],
      ],
    );
  }

  Widget _citizenshipStep(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(S.citizenshipTitle,
            style: const TextStyle(
                color: AppColors.kmText,
                fontWeight: FontWeight.w800,
                fontSize: 16)),
        const SizedBox(height: 6),
        Text(S.citizenshipHint,
            style: const TextStyle(color: AppColors.kmMuted, fontSize: 12.5)),
        const SizedBox(height: 18),
        _uploadTile(theme,
            label: _citFrontName ?? S.citizenshipFront,
            bytes: _citFrontBytes,
            onTap: _pickCitFront),
        const SizedBox(height: 16),
        _uploadTile(theme,
            label: _citBackName ?? S.citizenshipBack,
            bytes: _citBackBytes,
            onTap: _pickCitBack),
      ],
    );
  }

  Widget _selfieStep(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(S.selfieWithIdTitle,
            style: const TextStyle(
                color: AppColors.kmText,
                fontWeight: FontWeight.w800,
                fontSize: 16)),
        const SizedBox(height: 8),
        Text(S.selfieWithIdHint,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.kmMuted, fontSize: 12.5)),
        const SizedBox(height: 20),
        Container(
          width: 200,
          height: 200,
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
                  size: 70, color: AppColors.kmMuted),
        ),
        const SizedBox(height: 20),
        SecondaryButton(
          label: _selfieBytes == null ? S.takeSelfie : S.retake,
          icon: Icons.camera_alt_rounded,
          color: AppColors.kmOrange,
          expand: false,
          onPressed: _takeSelfie,
        ),
      ],
    );
  }

  Widget _certsStep(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Driver Verification & Registration — Bike/Car चालकका लागि मात्र,
        // सवारी चालक अनुमतिपत्र + सवारी दर्ता (ब्लु बुक) अनिवार्य। यी बिना
        // submit नै हुँदैन (तल `_submit()` हेर्नुहोस्) — verification pending
        // हुँदा नै admin ले हेर्न पाओस् भनेर।
        if (_service == 'Driver') ...[
          Text(S.drivingLicenseLabel,
              style:
                  const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
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
          const SizedBox(height: 24),
          Text(S.vehicleRegistrationLabel,
              style:
                  const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
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
          const SizedBox(height: 24),
          Divider(color: theme.dividerColor),
          const SizedBox(height: 16),
        ],
        Text(S.certsTitle,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
        const SizedBox(height: 6),
        Text(S.certsHint, style: theme.textTheme.bodySmall),
        const SizedBox(height: 16),
        for (var i = 0; i < _certs.length; i++)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(Icons.insert_drive_file_rounded,
                    size: 18, color: AppColors.kmOrange),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(_certs[i].name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: AppColors.kmText)),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded,
                      size: 18, color: AppColors.kmMuted),
                  onPressed: () => setState(() => _certs.removeAt(i)),
                ),
              ],
            ),
          ),
        OutlinedButton.icon(
          onPressed: _addCert,
          icon: const Icon(Icons.add_rounded),
          label: Text(S.addCertificate),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.kmOrange,
            side: const BorderSide(color: AppColors.kmOrange),
          ),
        ),
        const SizedBox(height: 10),
        Text(S.certsOptional,
            style: TextStyle(
                fontSize: 11.5, color: theme.colorScheme.onSurfaceVariant)),
      ],
    );
  }
}

class _StepBar extends StatelessWidget {
  final int step;
  final String service;
  const _StepBar({required this.step, required this.service});

  @override
  Widget build(BuildContext context) {
    final labels = [
      S.stepDetails,
      S.stepIdentity,
      S.stepSelfie,
      service == 'Driver' ? S.stepVehicleDocs : S.stepCertificates,
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
      child: Row(
        children: List.generate(labels.length, (i) {
          final done = i < step;
          final active = i == step;
          return Expanded(
            child: Row(
              children: [
                Container(
                  width: 26,
                  height: 26,
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
                          size: 15, color: AppColors.kmInk)
                      : Text('${i + 1}',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: active
                                  ? AppColors.kmInk
                                  : AppColors.kmMuted)),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(labels[i],
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 11.5,
                          fontWeight:
                              active ? FontWeight.w700 : FontWeight.w500,
                          color:
                              active ? AppColors.kmText : AppColors.kmMuted)),
                ),
                if (i < labels.length - 1)
                  Container(
                    width: 10,
                    height: 2,
                    color: Colors.white.withValues(alpha: 0.14),
                  ),
              ],
            ),
          );
        }),
      ),
    );
  }
}
