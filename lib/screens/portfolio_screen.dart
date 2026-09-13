// screens/portfolio_screen.dart
// कामदारको "कामको पोर्टफोलियो" — अगाडि गरेका कामका तस्बिरहरूको ग्यालरी।
// आफ्नो प्रोफाइलमा थप्न/हटाउन मिल्छ; ग्राहकले हेर्दा view-only।
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../l10n/strings.dart';
import '../services/document_service.dart';
import '../services/upload_validation.dart';
import '../theme/app_theme.dart';

class PortfolioScreen extends StatefulWidget {
  /// null भए current user (edit गर्न मिल्ने); दिइए त्यो कामदारको (view-only)।
  final String? workerUid;
  const PortfolioScreen({super.key, this.workerUid});

  @override
  State<PortfolioScreen> createState() => _PortfolioScreenState();
}

class _PortfolioScreenState extends State<PortfolioScreen> {
  bool _busy = false;

  String get _uid =>
      widget.workerUid ?? FirebaseAuth.instance.currentUser?.uid ?? '';
  bool get _editable =>
      widget.workerUid == null ||
      widget.workerUid == FirebaseAuth.instance.currentUser?.uid;

  Future<void> _addPhoto() async {
    final src = await showModalBottomSheet<String>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt_rounded,
                  color: AppColors.igViolet),
              title: Text(S.fromCamera),
              onTap: () => Navigator.pop(context, 'camera'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_rounded,
                  color: AppColors.igViolet),
              title: Text(S.fromGallery),
              onTap: () => Navigator.pop(context, 'files'),
            ),
          ],
        ),
      ),
    );
    if (src == null) return;

    Uint8List? bytes;
    String name = 'photo.jpg';
    try {
      if (src == 'camera') {
        final XFile? p = await ImagePicker()
            .pickImage(source: ImageSource.camera, imageQuality: 75);
        if (p == null) return;
        bytes = await p.readAsBytes();
        name = p.name;
      } else {
        final file = await FilePicker.pickFile(
          type: FileType.custom,
          allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp'],
        );
        if (file == null) return;
        bytes = await file.readAsBytes();
        name = file.name;
      }
    } catch (e) {
      _snack('${S.errorWord}: $e');
      return;
    }

    final err = UploadValidation.validate(bytes, name);
    if (err != null) {
      _snack(UploadValidation.messageFor(err));
      return;
    }

    setState(() => _busy = true);
    try {
      final url = await DocumentService.uploadPortfolioPhoto(
        uid: _uid,
        bytes: bytes,
        originalName: name,
      ).timeout(const Duration(seconds: 30));

      final db = FirebaseFirestore.instance;
      for (final c in ['providers', 'users', 'registeredWorkers']) {
        await db.collection(c).doc(_uid).set(
          {
            'portfolioUrls': FieldValue.arrayUnion([url])
          },
          SetOptions(merge: true),
        );
      }
      _snack(S.photoAdded);
    } catch (e) {
      _snack(DocumentService.describeUploadError(e) == 'storage-not-setup'
          ? S.docsSyncFailedStorage
          : '${S.errorWord}: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _removePhoto(String url) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(S.removePhoto),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(S.cancel)),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(context, true),
            child: Text(S.delete, style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (ok != true) return;

    final db = FirebaseFirestore.instance;
    for (final c in ['providers', 'users', 'registeredWorkers']) {
      await db.collection(c).doc(_uid).set(
        {
          'portfolioUrls': FieldValue.arrayRemove([url])
        },
        SetOptions(merge: true),
      );
    }
    try {
      await FirebaseStorage.instance.refFromURL(url).delete();
    } catch (_) {}
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  void _openFull(String url) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
              backgroundColor: Colors.black, foregroundColor: Colors.white),
          body: Center(
            child: InteractiveViewer(
              child: Image.network(url, fit: BoxFit.contain),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(S.workPortfolio),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        flexibleSpace: const DecoratedBox(
          decoration: BoxDecoration(gradient: AppColors.buttonGradient),
        ),
      ),
      body: Container(
        decoration: const BoxDecoration(gradient: AppColors.igGradient),
        child: SafeArea(
          child: _uid.isEmpty
              ? const Center(
                  child: Text('Login गर्नुहोस्',
                      style: TextStyle(color: Colors.white)))
              : StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                  stream: FirebaseFirestore.instance
                      .collection('providers')
                      .doc(_uid)
                      .snapshots(),
                  builder: (context, snap) {
                    final urls =
                        ((snap.data?.data()?['portfolioUrls'] as List?) ??
                                const [])
                            .cast<String>();

                    if (urls.isEmpty && !_editable) {
                      return Center(
                        child: Text(S.portfolioEmptyOther,
                            style: const TextStyle(color: Colors.white70)),
                      );
                    }

                    return GridView.count(
                      crossAxisCount: 3,
                      padding: const EdgeInsets.all(12),
                      mainAxisSpacing: 8,
                      crossAxisSpacing: 8,
                      children: [
                        if (_editable)
                          GestureDetector(
                            onTap: _busy ? null : _addPhoto,
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.16),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                    color: Colors.white.withValues(alpha: 0.4)),
                              ),
                              child: _busy
                                  ? const Center(
                                      child: CircularProgressIndicator(
                                          color: Colors.white,
                                          strokeWidth: 2.4))
                                  : Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        const Icon(Icons.add_a_photo_rounded,
                                            color: Colors.white, size: 26),
                                        const SizedBox(height: 6),
                                        Text(S.addWorkPhoto,
                                            textAlign: TextAlign.center,
                                            style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 10.5)),
                                      ],
                                    ),
                            ),
                          ),
                        for (final url in urls)
                          GestureDetector(
                            onTap: () => _openFull(url),
                            onLongPress:
                                _editable ? () => _removePhoto(url) : null,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Image.network(
                                url,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => Container(
                                  color: Colors.white24,
                                  child: const Icon(Icons.broken_image_rounded,
                                      color: Colors.white54),
                                ),
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                ),
        ),
      ),
    );
  }
}
