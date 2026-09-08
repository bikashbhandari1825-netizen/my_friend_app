// document_verification_page.dart
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'main.dart';

class DocumentVerificationPage extends StatefulWidget {
  const DocumentVerificationPage({super.key});

  @override
  State<DocumentVerificationPage> createState() =>
      _DocumentVerificationPageState();
}

class _DocumentVerificationPageState extends State<DocumentVerificationPage> {
  String? _uploadedFileName;
  Uint8List? _uploadedFileBytes;
  final _yearController = TextEditingController();
  String _selectedService = 'Plumber';
  final List<String> _serviceCategories = [
    'Mechanic',
    'Plumber',
    'Carpenter',
    'Painter',
    'Cleaner',
    'Driver',
    'Electrician',
    'Tutor',
  ];

  String _selectedYear = '1';
  final List<String> _yearsList = [
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
  String _selectedMonth = '0';
  final List<String> _monthsList = [
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

  bool _isSaving = false;
  String? _errorText;

  // Admin लाई मात्र जाने Notification (uid नचाहिने)
  Future<void> createAdminNotification(String title, String body) async {
    await FirebaseFirestore.instance.collection('adminNotifications').add({
      'title': title,
      'body': body,
      'read': false,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  void dispose() {
    _yearController.dispose();
    super.dispose();
  }

  void _showUploadOptions() {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.camera_alt, color: Colors.green),
                title: const Text('क्यामेराबाट फोटो खिच्ने'),
                onTap: () {
                  Navigator.pop(context);
                  _pickFromCamera();
                },
              ),
              ListTile(
                leading: const Icon(Icons.folder, color: Colors.blue),
                title: const Text('फाइलबाट छान्ने'),
                onTap: () {
                  Navigator.pop(context);
                  _pickDocument();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _pickFromCamera() async {
    try {
      final picker = ImagePicker();
      final XFile? photo = await picker.pickImage(source: ImageSource.camera);
      if (photo != null) {
        final bytes = await photo.readAsBytes();
        setState(() {
          _uploadedFileName = photo.name;
          _uploadedFileBytes = bytes;
          _errorText = null;
        });
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('क्यामेरा खोल्न मिलेन: $e')),
      );
    }
  }

  Future<void> _pickDocument() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'doc', 'docx', 'jpg', 'png'],
        withData: true,
      );

      if (result != null) {
        setState(() {
          _uploadedFileName = result.files.single.name;
          _uploadedFileBytes = result.files.single.bytes;
          _errorText = null;
        });
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('फाइल छान्न मिलेन: $e')),
      );
    }
  }

  Future<void> _done() async {
    if (_uploadedFileName == null) {
      setState(() => _errorText = 'कृपया सर्टिफिकेट अपलोड गर्नुहोस्');
      return;
    }

    setState(() {
      _isSaving = true;
      _errorText = null;
    });

    try {
      final uid = FirebaseAuth.instance.currentUser!.uid;

      final userDoc =
          await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final userData = userDoc.data() ?? {};

      String experienceStr = '$_selectedYear years';
      if (_selectedMonth != '0') {
        experienceStr += ' $_selectedMonth months';
      }

      await FirebaseFirestore.instance.collection('pendingWorkers').add({
        'uid': uid,
        'firstName': userData['firstName'] ?? '',
        'lastName': userData['lastName'] ?? '',
        'email': userData['email'] ?? '',
        'dob': userData['dob'] ?? '',
        'experience': experienceStr,
        'service': _selectedService,
        'documentName': _uploadedFileName,
        'status': 'pending',
        'submittedAt': FieldValue.serverTimestamp(),
      });

      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'workerVerificationStatus': 'pending',
      }, SetOptions(merge: true));

      await createAdminNotification(
        'Document Submitted',
        'तपाईंको सर्टिफिकेट Admin लाई पठाइयो। स्वीकृतिको लागि पर्खनुहोस्।',
      );

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const KaamMitraApp()),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _errorText = 'त्रुटि: $e');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.green.shade700,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            children: [
              const SizedBox(height: 20),
              const Text(
                'Document Verification',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              const Text(
                'तपाईंको अनुभव र सर्टिफिकेट विवरण भर्नुहोस्',
                style: TextStyle(color: Colors.white70, fontSize: 14),
              ),
              const SizedBox(height: 30),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  children: [
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text('Type of Work',
                          style: TextStyle(
                              fontSize: 15, fontWeight: FontWeight.bold)),
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      initialValue: _selectedService,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                      ),
                      items: _serviceCategories
                          .map(
                              (s) => DropdownMenuItem(value: s, child: Text(s)))
                          .toList(),
                      onChanged: (v) => setState(() => _selectedService = v!),
                    ),
                    const SizedBox(height: 20),
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text('कति वर्ष काम गरेको छ?',
                          style: TextStyle(
                              fontSize: 15, fontWeight: FontWeight.bold)),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          DropdownButton<String>(
                            value: _selectedYear,
                            underline: const SizedBox(),
                            items: _yearsList
                                .map((v) => DropdownMenuItem(
                                    value: v, child: Text('$v वर्ष')))
                                .toList(),
                            onChanged: (v) =>
                                setState(() => _selectedYear = v!),
                          ),
                          DropdownButton<String>(
                            value: _selectedMonth,
                            underline: const SizedBox(),
                            items: _monthsList
                                .map((v) => DropdownMenuItem(
                                    value: v, child: Text('$v महिना')))
                                .toList(),
                            onChanged: (v) =>
                                setState(() => _selectedMonth = v!),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text('Experience Certificate',
                          style: TextStyle(
                              fontSize: 15, fontWeight: FontWeight.bold)),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _showUploadOptions,
                        icon: const Icon(Icons.add_a_photo),
                        label: Text(_uploadedFileName ?? 'Add photo'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                      ),
                    ),
                    if (_uploadedFileBytes != null &&
                        (_uploadedFileName?.toLowerCase().endsWith('.jpg') ==
                                true ||
                            _uploadedFileName?.toLowerCase().endsWith('.png') ==
                                true ||
                            _uploadedFileName
                                    ?.toLowerCase()
                                    .endsWith('.jpeg') ==
                                true)) ...[
                      const SizedBox(height: 12),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.memory(_uploadedFileBytes!,
                            height: 150, fit: BoxFit.cover),
                      ),
                    ],
                    if (_errorText != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        _errorText!,
                        style: const TextStyle(
                            color: Colors.red, fontWeight: FontWeight.w600),
                      ),
                    ],
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _isSaving ? null : _done,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green.shade700,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        child: _isSaving
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white),
                              )
                            : const Text(
                                'Done',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold),
                              ),
                      ),
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
}
