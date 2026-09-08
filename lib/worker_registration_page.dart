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

import 'app.dart';
import 'l10n/strings.dart';
import 'services/document_service.dart';
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
  final _vehicle = TextEditingController();

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
  static const _years = ['0', '1', '2', '3', '4', '5', '6', '7', '8', '9', '10+'];
  static const _months =
      ['0', '1', '2', '3', '4', '5', '6', '7', '8', '9', '10', '11'];

  int _step = 0;
  String _service = 'Plumber';
  String _district = 'Kathmandu';
  String _year = '1';
  String _month = '0';

  String? _docName;
  Uint8List? _docBytes;
  Uint8List? _selfieBytes;
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
    _vehicle.dispose();
    super.dispose();
  }

  // ── document / selfie pickers ──────────────────────────────────────────────

  void _showDocOptions() {
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt_rounded),
              title: const Text('Camera'),
              onTap: () {
                Navigator.pop(context);
                _pickDoc(fromCamera: true);
              },
            ),
            ListTile(
              leading: const Icon(Icons.folder_rounded),
              title: const Text('Gallery / File'),
              onTap: () {
                Navigator.pop(context);
                _pickDoc(fromCamera: false);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickDoc({required bool fromCamera}) async {
    try {
      if (fromCamera) {
        final XFile? photo =
            await ImagePicker().pickImage(source: ImageSource.camera);
        if (photo != null) {
          final bytes = await photo.readAsBytes();
          setState(() {
            _docName = photo.name;
            _docBytes = bytes;
            _error = null;
          });
        }
      } else {
        final res = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'],
          withData: true,
        );
        if (res != null) {
          setState(() {
            _docName = res.files.single.name;
            _docBytes = res.files.single.bytes;
            _error = null;
          });
        }
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('${S.errorWord}: $e')));
    }
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
    } else if (_step == 1) {
      if (_docName == null) {
        setState(() => _error = S.uploadDocFirst);
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
      final vehicle = _vehicle.text.trim();

      // 1. license + selfie → Firebase Storage।
      //    Storage अझै enable नभए वा upload fail भए पनि दर्ता रोकिँदैन —
      //    URL खाली राखेर Firestore मा data save हुन्छ (admin ले नाम/फोन देख्छ)।
      String licenseUrl = '';
      String selfieUrl = '';
      bool uploadFailed = false;
      try {
        licenseUrl = await DocumentService.uploadDocument(
          uid: uid,
          bytes: _docBytes!,
          originalName: _docName!,
          type: 'license',
        ).timeout(const Duration(seconds: 25));
      } catch (_) {
        uploadFailed = true;
      }
      try {
        selfieUrl = await DocumentService.uploadDocument(
          uid: uid,
          bytes: _selfieBytes!,
          originalName: 'selfie.jpg',
          type: 'selfie',
        ).timeout(const Duration(seconds: 25));
      } catch (_) {
        uploadFailed = true;
      }

      // 2. users/{uid}
      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'uid': uid,
        'firstName': _firstName.text.trim(),
        'lastName': _lastName.text.trim(),
        'name': name,
        'phone': phone.isEmpty ? (user.phoneNumber ?? '') : phone,
        'email': user.email ?? '',
        'role': 'worker',
        'accountStatus': 'active',
        'service': _service,
        'experience': experience,
        'priceValue': _price.text.trim(),
        'district': _district,
        'area': _area.text.trim(),
        'location': address,
        'profileComplete': true,
        'licenseUrl': licenseUrl,
        'selfieUrl': selfieUrl,
        'documentUrl': licenseUrl, // पुरानो field सँग compat
        'documentName': _docName,
        'documentsPending': uploadFailed,
        if (vehicle.isNotEmpty) 'vehicleDetails': vehicle,
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
      }, SetOptions(merge: true));

      // 3. providers/{uid}
      await FirebaseFirestore.instance.collection('providers').doc(uid).set({
        'uid': uid,
        'name': name,
        'phone': phone,
        'serviceType': _service,
        'address': address,
        'experience': experience,
        'price': priceStr,
        'licenseUrl': licenseUrl,
        'selfieUrl': selfieUrl,
        if (vehicle.isNotEmpty) 'vehicleDetails': vehicle,
        'verificationStatus': 'pending',
        'isVerified': false,
        'createdAt': FieldValue.serverTimestamp(),
        if (_lat != null && _lng != null) ...{'lat': _lat, 'lng': _lng},
      }, SetOptions(merge: true));

      // 4. pendingWorkers (admin ले हेर्ने)
      await FirebaseFirestore.instance.collection('pendingWorkers').add({
        'uid': uid,
        'firstName': _firstName.text.trim(),
        'lastName': _lastName.text.trim(),
        'email': user.email ?? '',
        'phone': phone,
        'service': _service,
        'experience': experience,
        'price': priceStr,
        'district': _district,
        'area': _area.text.trim(),
        'location': address,
        if (vehicle.isNotEmpty) 'vehicleDetails': vehicle,
        'documentName': _docName,
        'documentUrl': licenseUrl,
        'licenseUrl': licenseUrl,
        'selfieUrl': selfieUrl,
        'certificateYear': _year,
        'documentsPending': uploadFailed,
        'isVerified': false,
        'verificationStatus': 'pending',
        'status': 'pending',
        'submittedAt': FieldValue.serverTimestamp(),
        if (_lat != null && _lng != null) ...{'lat': _lat, 'lng': _lng},
      });

      await FirebaseFirestore.instance.collection('adminNotifications').add({
        'title': 'New provider verification',
        'body': '$name ($_service) ले कागजात + सेल्फी पठाउनुभयो।',
        'read': false,
        'createdAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;
      await showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: Text(S.applicationSubmitted),
          content: Text(uploadFailed
              ? '${S.applicationSubmittedBody}\n\n(${S.errorWord}: ${S.uploading} — कागजात पछि सिंक हुनेछ)'
              : S.applicationSubmittedBody),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context), child: Text(S.ok)),
          ],
        ),
      );
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const KaamMitraApp()),
        (_) => false,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = '${S.errorWord}: $e';
      });
    }
  }

  // ── UI ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(S.workerRegTitle)),
      body: SafeArea(
        child: Column(
          children: [
            _StepBar(step: _step),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: IndexedStack(
                  index: _step,
                  children: [
                    _detailsStep(theme),
                    _documentStep(theme),
                    _selfieStep(theme),
                  ],
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
                    child: _step < 2
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
                .map((s) => DropdownMenuItem(
                    value: s, child: Text(S.serviceName(s))))
                .toList(),
            onChanged: (v) => setState(() => _service = v!),
          ),
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
                      .map((v) =>
                          DropdownMenuItem(value: v, child: Text(v)))
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
                      .map((v) =>
                          DropdownMenuItem(value: v, child: Text(v)))
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
          if (_service == 'Driver') ...[
            const SizedBox(height: 14),
            TextFormField(
              controller: _vehicle,
              decoration: _dec(S.vehicleDetails).copyWith(
                  hintText: S.vehicleHint),
            ),
          ],
        ],
      ),
    );
  }

  Widget _documentStep(ThemeData theme) {
    final isImg = _docName != null &&
        RegExp(r'\.(jpg|jpeg|png)$', caseSensitive: false)
            .hasMatch(_docName!);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(S.experienceCertificate,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
        const SizedBox(height: 6),
        Text(S.regWorkerNote, style: theme.textTheme.bodySmall),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: _showDocOptions,
          icon: const Icon(Icons.upload_file_rounded),
          label: Text(_docName ?? S.addDocument,
              overflow: TextOverflow.ellipsis),
        ),
        if (_docBytes != null && isImg) ...[
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.memory(_docBytes!, height: 200, fit: BoxFit.cover),
          ),
        ],
      ],
    );
  }

  Widget _selfieStep(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(S.selfieVerification,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
        const SizedBox(height: 8),
        Text(S.selfieHint,
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
                    ? AppColors.lime
                    : theme.dividerColor,
                width: 2),
          ),
          clipBehavior: Clip.antiAlias,
          child: _selfieBytes != null
              ? Image.memory(_selfieBytes!, fit: BoxFit.cover)
              : Icon(Icons.face_retouching_natural_rounded,
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
}

class _StepBar extends StatelessWidget {
  final int step;
  const _StepBar({required this.step});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final labels = [S.stepDetails, S.stepDocument, S.stepSelfie];
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
      child: Row(
        children: List.generate(3, (i) {
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
                          fontWeight: active
                              ? FontWeight.w700
                              : FontWeight.w500,
                          color: active
                              ? theme.colorScheme.onSurface
                              : theme.colorScheme.onSurfaceVariant)),
                ),
                if (i < 2)
                  Container(
                    width: 12,
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
