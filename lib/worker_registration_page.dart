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
import 'widgets/app_ui.dart';

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

  static const _services = [
    'Mechanic',
    'Plumber',
    'Carpenter',
    'Painter',
    'Cleaner',
    'Driver',
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

  // Driver-मात्र अनिवार्य कागजात — सवारी चालक अनुमतिपत्र + सवारी दर्ता (ब्लु
  // बुक)। यी बिना Bike/Car चालक अनलाइन नहोस् भनेर submit नै रोकिन्छ (तल
  // `_submit()` हेर्नुहोस्)।
  Uint8List? _licenseBytes;
  String? _licenseName;
  Uint8List? _vehicleRegBytes;
  String? _vehicleRegName;

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
    final src = await showModalBottomSheet<String>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt_rounded),
              title: Text(S.takePhoto),
              onTap: () => Navigator.pop(context, 'camera'),
            ),
            ListTile(
              leading: const Icon(Icons.folder_rounded),
              title: Text(S.chooseFile),
              onTap: () => Navigator.pop(context, 'file'),
            ),
          ],
        ),
      ),
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
        (_licenseBytes == null || _vehicleRegBytes == null)) {
      setState(() => _error = S.uploadDriverDocsError);
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

      final db = FirebaseFirestore.instance;

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
          'email': user.email ?? '',
          'role': 'worker',
          'accountStatus': 'active',
          'service': _effectiveService,
          'experience': experience,
          'priceValue': _price.text.trim(),
          'district': _district,
          'area': _area.text.trim(),
          'location': address,
          'profileComplete': true,
          'vehicleDetails': FieldValue.delete(),
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
          if (_lat != null && _lng != null) ...{'lat': _lat, 'lng': _lng},
        }, SetOptions(merge: true)),

        // pendingWorkers — admin ले हेर्ने (real-time)
        pendingRef.set({
          'uid': uid,
          'firstName': _firstName.text.trim(),
          'lastName': _lastName.text.trim(),
          'email': user.email ?? '',
          'phone': phone,
          'service': _effectiveService,
          'experience': experience,
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
      // सवारी चालक अनुमतिपत्र + सवारी दर्ता (ब्लु बुक) पनि Storage मा।
      String drivingLicenseUrl = '';
      String vehicleRegUrl = '';
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
      await showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: Text(S.applicationSubmitted),
          content: Text(uploadFailed
              ? '${S.applicationSubmittedBody}\n\n${S.docsUploadPendingNote}'
              : S.applicationSubmittedBody),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context), child: Text(S.ok)),
          ],
        ),
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
      child: Scaffold(
        appBar: gradientAppBar(
          S.workerRegTitle,
          leading: _step > 0
              ? IconButton(
                  icon: const Icon(Icons.arrow_back_rounded),
                  onPressed: _saving ? null : _prev,
                )
              : IconButton(
                  icon: const Icon(Icons.logout_rounded),
                  tooltip: S.logOut,
                  onPressed: _saving ? null : _exit,
                ),
        ),
        body: AppGradientBackground(
          glows: false,
          child: SafeArea(
            child: Column(
              children: [
                _StepBar(step: _step),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surface,
                        borderRadius: BorderRadius.circular(AppRadius.lg),
                        boxShadow: const [
                          BoxShadow(
                              color: Colors.black26,
                              blurRadius: 20,
                              offset: Offset(0, 8)),
                        ],
                      ),
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
                        style: TextStyle(
                            color: theme.colorScheme.error,
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
                            onPressed: _saving ? null : _prev,
                          ),
                        ),
                        const SizedBox(width: 12),
                      ],
                      Expanded(
                        child: _step < 3
                            ? PrimaryButton(
                                label: S.next,
                                icon: Icons.arrow_forward_rounded,
                                onPressed: _next,
                              )
                            : PrimaryButton(
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

  InputDecoration _dec(String label) => InputDecoration(labelText: label);

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
                color: theme.colorScheme.error.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(Icons.error_outline_rounded,
                      size: 18, color: theme.colorScheme.error),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _rejectReason.isEmpty
                          ? S.docRejectedBanner
                          : '${S.docRejectedBanner}\n${S.reasonLabel}: $_rejectReason',
                      style: TextStyle(
                          color: theme.colorScheme.error,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          Text(S.regWorkerNote, style: theme.textTheme.bodySmall),
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
            onChanged: (v) => setState(() {
              _service = v!;
              if (_service != 'Driver') _vehicleType = null;
            }),
          ),
          // InDrive-Style Ride-Sharing — Driver छानेपछि Bike/Car मध्ये एउटा
          // अनिवार्य; यही नै Firestore मा बचत हुने वास्तविक `service` मान
          // बन्छ (माथि `_effectiveService` हेर्नुहोस्)।
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
      onTap: () => setState(() => _vehicleType = value),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.igViolet.withValues(alpha: 0.12)
              : theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(
              color: selected ? AppColors.igViolet : theme.dividerColor,
              width: selected ? 2 : 1),
        ),
        child: Column(
          children: [
            Icon(icon, color: selected ? AppColors.igViolet : null),
            const SizedBox(height: 6),
            Text(label,
                style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: selected ? AppColors.igViolet : null)),
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
                bytes == null ? AppColors.igViolet : AppColors.success,
            side: BorderSide(
                color: bytes == null ? AppColors.igViolet : AppColors.success),
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
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
        const SizedBox(height: 6),
        Text(S.citizenshipHint, style: theme.textTheme.bodySmall),
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
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
        const SizedBox(height: 8),
        Text(S.selfieWithIdHint,
            textAlign: TextAlign.center, style: theme.textTheme.bodySmall),
        const SizedBox(height: 20),
        Container(
          width: 200,
          height: 200,
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            shape: BoxShape.circle,
            border: Border.all(
                color: _selfieBytes != null
                    ? AppColors.success
                    : theme.dividerColor,
                width: 2),
          ),
          clipBehavior: Clip.antiAlias,
          child: _selfieBytes != null
              ? Image.memory(_selfieBytes!, fit: BoxFit.cover)
              : Icon(Icons.badge_rounded,
                  size: 70, color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 20),
        SecondaryButton(
          label: _selfieBytes == null ? S.takeSelfie : S.retake,
          icon: Icons.camera_alt_rounded,
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
          _uploadTile(theme,
              label: _licenseName ?? S.drivingLicenseLabel,
              bytes: _licenseBytes,
              onTap: _pickLicense),
          const SizedBox(height: 16),
          Text(S.vehicleRegistrationLabel,
              style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          _uploadTile(theme,
              label: _vehicleRegName ?? S.vehicleRegistrationLabel,
              bytes: _vehicleRegBytes,
              onTap: _pickVehicleReg),
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
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                const Icon(Icons.insert_drive_file_rounded,
                    size: 18, color: AppColors.igViolet),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(_certs[i].name,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 18),
                  onPressed: () => setState(() => _certs.removeAt(i)),
                ),
              ],
            ),
          ),
        OutlinedButton.icon(
          onPressed: _addCert,
          icon: const Icon(Icons.add_rounded),
          label: Text(S.addCertificate),
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
  const _StepBar({required this.step});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final labels = [
      S.stepDetails,
      S.stepIdentity,
      S.stepSelfie,
      S.stepCertificates,
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
                    color: (done || active)
                        ? AppColors.lime
                        : theme.colorScheme.surfaceContainerHighest,
                    shape: BoxShape.circle,
                  ),
                  child: done
                      ? const Icon(Icons.check_rounded,
                          size: 15, color: AppColors.onLime)
                      : Text('${i + 1}',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: active
                                  ? AppColors.onLime
                                  : theme.colorScheme.onSurfaceVariant)),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(labels[i],
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 11.5,
                          fontWeight:
                              active ? FontWeight.w700 : FontWeight.w500,
                          color: active
                              ? theme.colorScheme.onSurface
                              : theme.colorScheme.onSurfaceVariant)),
                ),
                if (i < labels.length - 1)
                  Container(
                    width: 10,
                    height: 2,
                    color: theme.dividerColor,
                  ),
              ],
            ),
          );
        }),
      ),
    );
  }
}
