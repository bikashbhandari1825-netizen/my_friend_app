// screens/hotel_registration_screen.dart
//
// Hotel Registration / Onboarding — Settings > "Register Your Hotel" बाट।
// होटल-मालिकले आफ्नै property सिधै list गर्ने फारम — submit गर्नेबित्तिकै
// साँचो Firestore `hotels`/`rooms` doc सिर्जना हुन्छ, आफैंलाई owner/partner
// तोकिन्छ (`users/{uid}.partnerHotelIds`), अनि सोझै
// `HotelPartnerDashboardScreen` खुल्छ।
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../data/hotel_mock_data.dart' show addHotelToCatalog;
import '../location_util.dart' show searchPlaces;
import '../models/hotel_models.dart';
import '../screens/nearby_common.dart' show fallbackLat, fallbackLng;
import '../services/document_service.dart';
import '../services/hotel_partner_service.dart' show grantSelfHotelPartner;
import '../services/ocr_match_service.dart';
import '../services/upload_validation.dart' show UploadValidation;
import '../theme/app_theme.dart';
import '../widgets/glass_ui.dart';
import '../widgets/liveness_selfie_capture.dart';
import 'hotel_common.dart';
import 'hotel_partner_dashboard_screen.dart';
import '../widgets/futuristic_ui.dart';

class HotelRegistrationScreen extends StatefulWidget {
  const HotelRegistrationScreen({super.key});

  @override
  State<HotelRegistrationScreen> createState() =>
      _HotelRegistrationScreenState();
}

class _HotelRegistrationScreenState extends State<HotelRegistrationScreen> {
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  final _bizRegCtrl = TextEditingController();
  final _panVatCtrl = TextEditingController();
  final _officialMobileCtrl = TextEditingController();
  final _landlineCtrl = TextEditingController();
  int _starRating = 3;
  final Set<String> _amenities = {};
  // गैलेरीबाट छानेका फोटो — submit बेला Firebase Storage मा अपलोड हुने।
  final List<({Uint8List bytes, String name})> _photos = [];
  static const _maxPhotos = 8;
  // KYC — Business license/PAN-VAT प्रमाण (pdf/jpg/png), admin-मात्र पढ्ने।
  final List<({Uint8List bytes, String name})> _documents = [];
  static const _maxDocuments = 5;
  bool _submitting = false;

  // Owner Identity Verification (Face Liveness + OCR cross-match) — पहिले
  // यो flow मा owner-पहिचान भन्ने अवधारणा नै थिएन, केवल व्यवसाय-स्तरका
  // कागजात मात्र थिए। worker_registration_page.dart कै उस्तै ढाँचा (नाम +
  // नागरिकता अगाडि/पछाडि + live liveness selfie)।
  final _ownerNameCtrl = TextEditingController();
  DateTime? _ownerDob;
  Uint8List? _ownerCitFrontBytes;
  String? _ownerCitFrontName;
  Uint8List? _ownerCitBackBytes;
  String? _ownerCitBackName;
  Uint8List? _ownerSelfieBytes;
  bool _ocrChecking = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _addressCtrl.dispose();
    _priceCtrl.dispose();
    _bizRegCtrl.dispose();
    _panVatCtrl.dispose();
    _officialMobileCtrl.dispose();
    _landlineCtrl.dispose();
    _ownerNameCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickOwnerDob() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(now.year - 30),
      firstDate: DateTime(1940),
      lastDate: now,
      helpText: 'Owner Date of Birth',
    );
    if (picked != null) setState(() => _ownerDob = picked);
  }

  bool _acceptFile(Uint8List? bytes, String name) {
    final err = UploadValidation.validate(bytes, name);
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(UploadValidation.messageFor(err))),
      );
      return false;
    }
    return true;
  }

  /// Owner citizenship capture — camera-or-file, worker_registration_page
  /// .dart::_pickFile() कै उस्तै ढाँचा (त्यो file निजी भएकोले सिधै reuse
  /// गर्न मिल्दैन — यो screen पहिल्यै आफ्नै निजी upload helper duplicate
  /// गरिरहेकै थियो, यहाँ पनि उस्तै pattern)।
  Future<({Uint8List bytes, String name})?> _pickOwnerDocFile() async {
    final src = await showKmSheet<String>(
      context: context,
      children: [
        KmSheetOption(
          icon: Icons.camera_alt_rounded,
          label: 'Take Photo',
          selected: false,
          onTap: () => Navigator.pop(context, 'camera'),
        ),
        KmSheetOption(
          icon: Icons.folder_rounded,
          label: 'Choose File',
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
          allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp'],
        );
        if (file == null) return null;
        final bytes = await file.readAsBytes();
        if (!mounted || !_acceptFile(bytes, file.name)) return null;
        return (bytes: bytes, name: file.name);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
      return null;
    }
  }

  Future<void> _pickOwnerCitFront() async {
    final r = await _pickOwnerDocFile();
    if (r == null) return;
    setState(() {
      _ownerCitFrontBytes = r.bytes;
      _ownerCitFrontName = r.name;
    });
  }

  Future<void> _pickOwnerCitBack() async {
    final r = await _pickOwnerDocFile();
    if (r == null) return;
    setState(() {
      _ownerCitBackBytes = r.bytes;
      _ownerCitBackName = r.name;
    });
  }

  Future<void> _takeOwnerSelfie() async {
    try {
      final bytes = await captureLivenessSelfie(context);
      if (bytes != null && _acceptFile(bytes, 'owner_selfie.jpg')) {
        setState(() => _ownerSelfieBytes = bytes);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Future<void> _addPhotos() async {
    if (_photos.length >= _maxPhotos) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You can add up to $_maxPhotos photos.')),
      );
      return;
    }
    List<XFile> picked;
    try {
      picked = await ImagePicker().pickMultiImage(imageQuality: 80);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open gallery: $e')),
      );
      return;
    }
    if (picked.isEmpty) return;
    final room = _maxPhotos - _photos.length;
    for (final p in picked.take(room)) {
      final bytes = await p.readAsBytes();
      final err = UploadValidation.validate(bytes, p.name);
      if (err != null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(UploadValidation.messageFor(err))),
        );
        continue;
      }
      if (!mounted) return;
      setState(() => _photos.add((bytes: bytes, name: p.name)));
    }
  }

  void _removePhoto(int index) => setState(() => _photos.removeAt(index));

  /// गैलेरीबाट छानेका फोटो Firebase Storage मा अपलोड गरेर download URL
  /// फर्काउने — portfolio_screen.dart::_addPhoto कै उही pattern (फाइल
  /// pick-time मै validate भइसकेको, यहाँ दोहोर्‍याउनु पर्दैन)।
  Future<List<String>> _uploadPhotos(String uid, String hotelId) async {
    final urls = <String>[];
    for (var i = 0; i < _photos.length; i++) {
      final photo = _photos[i];
      final ext = UploadValidation.safeExtension(photo.name);
      final ref =
          FirebaseStorage.instance.ref('hotel_photos/$uid/$hotelId/$i.$ext');
      final sniffed = UploadValidation.sniffMime(photo.bytes);
      await ref.putData(
        photo.bytes,
        SettableMetadata(
            contentType: sniffed.isNotEmpty ? sniffed : 'image/jpeg'),
      );
      urls.add(await ref.getDownloadURL());
    }
    return urls;
  }

  /// KYC — Business license/PAN-VAT प्रमाण (camera नभई file picker मात्र,
  /// pdf पनि चाहिने भएकोले photo gallery जस्तो multi-select उपलब्ध छैन)।
  Future<void> _addDocument() async {
    if (_documents.length >= _maxDocuments) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('You can add up to $_maxDocuments documents.')),
      );
      return;
    }
    try {
      final file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png', 'webp'],
      );
      if (file == null) return;
      final bytes = await file.readAsBytes();
      final err = UploadValidation.validate(bytes, file.name);
      if (err != null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(UploadValidation.messageFor(err))),
        );
        return;
      }
      if (!mounted) return;
      setState(() => _documents.add((bytes: bytes, name: file.name)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open file picker: $e')),
      );
    }
  }

  void _removeDocument(int index) =>
      setState(() => _documents.removeAt(index));

  /// KYC प्रमाण Firebase Storage मा अपलोड — `hotel_documents/{uid}/...`
  /// (storage.rules मा यो path owner/admin-मात्र पढ्न मिल्ने गरी निजी
  /// राखिएको, hotel_photos जस्तो सार्वजनिक होइन)।
  Future<List<String>> _uploadDocuments(String uid, String hotelId) async {
    final urls = <String>[];
    for (var i = 0; i < _documents.length; i++) {
      final doc = _documents[i];
      final ext = UploadValidation.safeExtension(doc.name);
      final ref = FirebaseStorage.instance
          .ref('hotel_documents/$uid/$hotelId/$i.$ext');
      final sniffed = UploadValidation.sniffMime(doc.bytes);
      await ref.putData(
        doc.bytes,
        SettableMetadata(
            contentType:
                sniffed.isNotEmpty ? sniffed : 'application/octet-stream'),
      );
      // KYC प्रमाणको token-URL `hotels` (सबै लग इन युजरले पढ्ने) मा नराखी
      // Storage path मात्र — हेर्नुहोस् `services/kyc_url.dart`।
      urls.add(ref.fullPath);
    }
    return urls;
  }

  Future<void> _submit() async {
    final name = _nameCtrl.text.trim();
    final address = _addressCtrl.text.trim();
    final price = double.tryParse(_priceCtrl.text.trim());
    if (name.isEmpty || address.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Please enter at least a hotel name and address.')),
      );
      return;
    }
    if (price == null || price <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Please enter a valid starting room price.')),
      );
      return;
    }
    final bizReg = _bizRegCtrl.text.trim();
    final panVat = _panVatCtrl.text.trim();
    if (bizReg.isEmpty || panVat.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                'Please enter your Business Registration and PAN/VAT number.')),
      );
      return;
    }
    final officialMobile = _officialMobileCtrl.text.trim();
    final landline = _landlineCtrl.text.trim();
    if (officialMobile.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                "Please enter the hotel's official contact mobile number.")),
      );
      return;
    }
    if (_documents.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                'Please upload at least one proof document (business license or PAN/VAT certificate).')),
      );
      return;
    }
    // Owner Identity Verification — required field checks (worker/driver
    // flow कै उस्तै pattern)।
    final ownerName = _ownerNameCtrl.text.trim();
    if (ownerName.isEmpty || _ownerDob == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                "Please enter the owner's name and date of birth.")),
      );
      return;
    }
    if (_ownerCitFrontBytes == null || _ownerCitBackBytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text("Please upload the owner's citizenship (front and back).")),
      );
      return;
    }
    if (_ownerSelfieBytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please complete the owner's selfie verification.")),
      );
      return;
    }
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You must be signed in to register a hotel.')),
      );
      return;
    }
    // Strict Document Cross-Matching — टाइप गरिएको owner नाम/जन्ममिति
    // owner को नागरिकता फोटोमा छापिएको छ कि (on-device OCR)।
    setState(() => _ocrChecking = true);
    final ocr = await OcrMatchService.matchFields(
      imageBytesList: [_ownerCitFrontBytes!, _ownerCitBackBytes!],
      expectations: [
        OcrFieldExpectation(
          fieldKey: 'ownerName',
          label: 'Owner Name',
          expectedValue: ownerName,
          type: OcrFieldType.name,
        ),
        OcrFieldExpectation(
          fieldKey: 'ownerDob',
          label: 'Owner Date of Birth',
          expectedValue: _ownerDob!.toIso8601String(),
          type: OcrFieldType.dob,
        ),
      ],
    );
    if (!mounted) return;
    setState(() => _ocrChecking = false);
    final mismatch = ocr.where((r) => !r.matched).map((r) => r.label).toList();
    if (mismatch.isNotEmpty) {
      await showMismatchAlert(context,
          "${mismatch.join(' र ')} owner को नागरिकता फोटोमा भेटिएन। कृपया माथिको Owner Identity Verification खण्ड जाँच्नुहोस्।");
      return;
    }
    // Backend duplicate lock — यही PAN/VAT नम्बर अर्कै account (uid फरक)
    // ले पहिल्यै pending/approved होटलमा प्रयोग गरिसकेको भए रोक्ने। यो
    // client-side best-effort जाँच हो (Firestore rules ले डाटाबेस-व्यापी
    // uniqueness जोगाउन सक्दैन, त्यसको लागि Cloud Function/transaction
    // नै चाहिन्छ) — तर इमानदार दोहोरो दर्ताका लागि पर्याप्त।
    setState(() => _submitting = true);
    try {
      final dupCheck = await FirebaseFirestore.instance
          .collection('hotels')
          .where('panVatNumber', isEqualTo: panVat)
          .get()
          .timeout(const Duration(seconds: 15));
      final dup = dupCheck.docs.where((d) {
        final data = d.data();
        if ((data['ownerId'] ?? '') == uid) return false;
        final status = (data['status'] ?? '').toString();
        return status != HotelVerificationStatus.rejected;
      });
      if (dup.isNotEmpty) {
        if (!mounted) return;
        setState(() => _submitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text(
                  'This PAN/VAT number is already registered to another hotel account.')),
        );
        return;
      }
    } catch (_) {
      // नेटवर्क/timeout भए यो best-effort जाँच नै रोक्ने कारण नबनोस् —
      // असली uniqueness अझै firestore.rules/backend स्तरमा छैन।
    }
    try {
      // ठेगाना टाइप गरेकै भरमा lat/lng स्वतः (Google Geocoding, बाँकी app
      // भरि नै प्रयोग हुने उही Cloud Function) — छुट्टै नक्सा-छनोट UI
      // नचाहिने गरी फारम सरल राख्न। नभेटिए Kathmandu केन्द्र default।
      double lat = fallbackLat, lng = fallbackLng;
      final geocoded = await searchPlaces(address);
      if (geocoded.isNotEmpty) {
        lat = geocoded.first.lat;
        lng = geocoded.first.lng;
      }

      final db = FirebaseFirestore.instance;
      final hotelRef = db.collection('hotels').doc();
      // doc सिर्जना हुनुअघि नै Storage मा अपलोड (path मा यही
      // hotelRef.id चाहिने भएकोले)।
      final images = await _uploadPhotos(uid, hotelRef.id);
      final documentUrls = await _uploadDocuments(uid, hotelRef.id);

      // Owner Identity — `DocumentService` (worker/driver कै उही shared
      // upload helper, hotel_owner_* allowlisted types) प्रयोग गरेर, यो
      // screen को आफ्नै (hotel_photos/hotel_documents कै उस्तै) निजी
      // duplicate upload-logic नथपी।
      final ownerCitFrontUrl = await DocumentService.uploadDocument(
        uid: uid,
        bytes: _ownerCitFrontBytes!,
        originalName: _ownerCitFrontName ?? 'owner_citizenship_front.jpg',
        type: 'hotel_owner_citizenship_front',
      );
      final ownerCitBackUrl = await DocumentService.uploadDocument(
        uid: uid,
        bytes: _ownerCitBackBytes!,
        originalName: _ownerCitBackName ?? 'owner_citizenship_back.jpg',
        type: 'hotel_owner_citizenship_back',
      );
      final ownerSelfieUrl = await DocumentService.uploadDocument(
        uid: uid,
        bytes: _ownerSelfieBytes!,
        originalName: 'owner_selfie.jpg',
        type: 'hotel_owner_selfie',
      );

      final hotel = Hotel(
        id: hotelRef.id,
        name: name,
        description: _descCtrl.text.trim(),
        address: address,
        location: GeoPoint(lat, lng),
        amenities: _amenities.toList(),
        starRating: _starRating.toDouble(),
        rules: '',
        images: images,
        checkInTime: '14:00',
        checkOutTime: '11:00',
        officialMobileNumber: officialMobile,
        landlinePhone: landline,
        ownerId: uid,
        businessRegNumber: bizReg,
        panVatNumber: panVat,
        documentUrls: documentUrls,
        ownerName: ownerName,
        ownerDob: _ownerDob!.toIso8601String(),
        ownerCitizenshipFrontUrl: ownerCitFrontUrl,
        ownerCitizenshipBackUrl: ownerCitBackUrl,
        ownerSelfieUrl: ownerSelfieUrl,
        // नयाँ दर्ता सधैं pending बाटै सुरु — firestore.rules ले creation
        // मै यो जाँच्छ, मालिकले पछि आफैं बदल्न पाउँदैन (Super-Admin
        // approval अनिवार्य, hotel_verification_admin_screen.dart हेर्नुहोस्)।
        status: HotelVerificationStatus.pending,
      );
      await hotelRef.set(hotel.toMap());

      final roomRef = db.collection('rooms').doc();
      final room = HotelRoom(
        id: roomRef.id,
        hotelId: hotelRef.id,
        roomType: 'Standard',
        pricePerNight: price,
        capacity: 2,
        totalInventory: 5,
        amenities: _amenities.toList(),
        images: const [],
        status: HotelRoomStatus.available,
      );
      await roomRef.set(room.toMap());

      // आफैंलाई यो होटलको partner तोक्ने — Partner Dashboard र booking-
      // status rule दुवैले यही `users/{uid}.partnerHotelIds` हेर्छन्।
      await grantSelfHotelPartner(hotelRef.id);

      // guest-साइड search/detail ले पढ्ने उही in-memory catalog मा पनि
      // तुरुन्तै थप्ने — restart नपर्खी यही session मै देखियोस्।
      addHotelToCatalog(hotel, room);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                '$name submitted! Your registration is under verification by Admin.')),
      );
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => HotelPartnerDashboardScreen(
              hotelIds: [hotelRef.id]),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not register your hotel: $e')),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return OledBackdrop(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Column(
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 16, 20, 0),
                child: KmScreenHeader(title: 'Register Your Hotel'),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                  children: [
                    _label('Hotel name'),
                    _field(_nameCtrl, 'e.g. Mountain View Inn'),
                    const SizedBox(height: 14),
                    _label('Description'),
                    _field(_descCtrl, 'Tell guests what makes your place special',
                        maxLines: 3),
                    const SizedBox(height: 14),
                    _label('Address'),
                    _field(_addressCtrl, 'Street, city'),
                    const SizedBox(height: 14),
                    _label('Official contact mobile number'),
                    _field(_officialMobileCtrl, 'e.g. 98XXXXXXXX',
                        keyboardType: TextInputType.phone),
                    const SizedBox(height: 14),
                    _label('Landline phone (optional)'),
                    _field(_landlineCtrl, 'e.g. 01-XXXXXXX',
                        keyboardType: TextInputType.phone),
                    const SizedBox(height: 14),
                    _label('Star rating'),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: [1, 2, 3, 4, 5].map((s) {
                        final selected = _starRating == s;
                        return ChoiceChip(
                          label: Text('$s★'),
                          selected: selected,
                          onSelected: (_) => setState(() => _starRating = s),
                          selectedColor: AppColors.kmOrange,
                          labelStyle: TextStyle(
                              color: selected
                                  ? AppColors.kmInk
                                  : AppColors.kmText,
                              fontWeight: FontWeight.w700),
                          backgroundColor:
                              Colors.white.withValues(alpha: 0.06),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 14),
                    _label('Amenities'),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: kHotelAmenities.map((a) {
                        final selected = _amenities.contains(a);
                        return FilterChip(
                          avatar: Icon(hotelAmenityIcon(a),
                              size: 16,
                              color: selected
                                  ? AppColors.kmInk
                                  : AppColors.kmMuted),
                          label: Text(a),
                          selected: selected,
                          onSelected: (sel) => setState(() {
                            if (sel) {
                              _amenities.add(a);
                            } else {
                              _amenities.remove(a);
                            }
                          }),
                          selectedColor: AppColors.kmOrange,
                          labelStyle: TextStyle(
                              color: selected
                                  ? AppColors.kmInk
                                  : AppColors.kmText,
                              fontWeight: FontWeight.w700,
                              fontSize: 12),
                          backgroundColor:
                              Colors.white.withValues(alpha: 0.06),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 14),
                    _label('Starting room price / night (Rs.)'),
                    _field(_priceCtrl, 'e.g. 2500',
                        keyboardType: TextInputType.number),
                    const SizedBox(height: 14),
                    _label('Hotel photos'),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        for (var i = 0; i < _photos.length; i++)
                          _photoTile(i),
                        if (_photos.length < _maxPhotos) _addPhotoTile(),
                      ],
                    ),
                    const SizedBox(height: 14),
                    _label('Business Registration Number'),
                    _field(_bizRegCtrl, 'e.g. 123456/078/079'),
                    const SizedBox(height: 14),
                    _label('PAN / VAT Number'),
                    _field(_panVatCtrl, 'e.g. 600123456'),
                    const SizedBox(height: 14),
                    _label('Proof documents (business license, PAN/VAT certificate)'),
                    const SizedBox(height: 8),
                    for (var i = 0; i < _documents.length; i++) _documentRow(i),
                    if (_documents.length < _maxDocuments)
                      OutlinedButton.icon(
                        onPressed: _addDocument,
                        icon: const Icon(Icons.upload_file_rounded, size: 18),
                        label: const Text('Add Proof Document'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.kmOrange,
                          side: BorderSide(
                              color: AppColors.kmOrange.withValues(alpha: 0.5)),
                          minimumSize: const Size(double.infinity, 44),
                        ),
                      ),
                    const SizedBox(height: 6),
                    const Text(
                      'Your hotel will be visible to guests only after Admin verifies these documents.',
                      style: TextStyle(color: AppColors.kmMuted, fontSize: 11.5),
                    ),
                    const SizedBox(height: 24),
                    _label('Owner Identity Verification'),
                    const SizedBox(height: 4),
                    const Text(
                      "We need to verify the hotel owner's identity (name, DOB, citizenship, and a live selfie) to prevent fraudulent listings.",
                      style: TextStyle(color: AppColors.kmMuted, fontSize: 11.5),
                    ),
                    const SizedBox(height: 10),
                    _field(_ownerNameCtrl, "Owner's full name"),
                    const SizedBox(height: 10),
                    InkWell(
                      onTap: _pickOwnerDob,
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 14),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          _ownerDob == null
                              ? "Owner date of birth"
                              : '${_ownerDob!.day}/${_ownerDob!.month}/${_ownerDob!.year}',
                          style: TextStyle(
                              color: _ownerDob == null
                                  ? AppColors.kmMuted
                                  : AppColors.kmText),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: _ownerDocTile(
                            label: 'Citizenship Front',
                            bytes: _ownerCitFrontBytes,
                            onTap: _pickOwnerCitFront,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _ownerDocTile(
                            label: 'Citizenship Back',
                            bytes: _ownerCitBackBytes,
                            onTap: _pickOwnerCitBack,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    _ownerDocTile(
                      label: _ownerSelfieBytes == null
                          ? 'Take Liveness Selfie'
                          : 'Retake Selfie',
                      bytes: _ownerSelfieBytes,
                      onTap: _takeOwnerSelfie,
                    ),
                    const SizedBox(height: 24),
                    KmCtaButton(
                      label: 'Submit Registration',
                      icon: Icons.storefront_rounded,
                      loading: _submitting || _ocrChecking,
                      onPressed:
                          _submitting || _ocrChecking ? null : _submit,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6, left: 2),
        child: Text(text,
            style: const TextStyle(
                color: AppColors.kmMuted,
                fontWeight: FontWeight.w800,
                fontSize: 12,
                letterSpacing: 0.3)),
      );

  Widget _photoTile(int index) {
    final photo = _photos[index];
    return Stack(
      clipBehavior: Clip.none,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.memory(photo.bytes,
              width: 84, height: 84, fit: BoxFit.cover),
        ),
        Positioned(
          right: -6,
          top: -6,
          child: GestureDetector(
            onTap: () => _removePhoto(index),
            child: Container(
              width: 22,
              height: 22,
              decoration: const BoxDecoration(
                  color: AppColors.kmRose, shape: BoxShape.circle),
              child: const Icon(Icons.close_rounded,
                  size: 14, color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }

  Widget _addPhotoTile() {
    return GestureDetector(
      onTap: _addPhotos,
      child: Container(
        width: 84,
        height: 84,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.kmOrange.withValues(alpha: 0.4)),
        ),
        child: const Icon(Icons.add_a_photo_rounded,
            color: AppColors.kmOrange, size: 26),
      ),
    );
  }

  Widget _documentRow(int index) {
    final doc = _documents[index];
    final isPdf = doc.name.toLowerCase().endsWith('.pdf');
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(isPdf ? Icons.picture_as_pdf_rounded : Icons.image_rounded,
              color: AppColors.kmOrange, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(doc.name,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: AppColors.kmText, fontSize: 13)),
          ),
          IconButton(
            onPressed: () => _removeDocument(index),
            icon: const Icon(Icons.close_rounded,
                size: 18, color: AppColors.kmMuted),
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }

  /// Owner Identity Verification — upload/retake button + thumbnail preview,
  /// worker_registration_page.dart::_uploadTile() कै उस्तै दृश्य भाषा।
  Widget _ownerDocTile({
    required String label,
    required Uint8List? bytes,
    required VoidCallback onTap,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OutlinedButton.icon(
          onPressed: onTap,
          icon: Icon(
              bytes == null
                  ? Icons.camera_alt_rounded
                  : Icons.check_circle_rounded,
              size: 18,
              color: bytes == null ? AppColors.kmOrange : AppColors.kmTealBlue),
          label: Text(label, overflow: TextOverflow.ellipsis),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.kmText,
            side: BorderSide(
                color: (bytes == null ? AppColors.kmOrange : AppColors.kmTealBlue)
                    .withValues(alpha: 0.5)),
          ),
        ),
        if (bytes != null) ...[
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.memory(bytes, height: 90, fit: BoxFit.cover),
          ),
        ],
      ],
    );
  }

  Widget _field(TextEditingController c, String hint,
      {int maxLines = 1, TextInputType? keyboardType}) {
    return TextField(
      controller: c,
      maxLines: maxLines,
      keyboardType: keyboardType,
      style: const TextStyle(color: AppColors.kmText),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: AppColors.kmMuted),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.05),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}
