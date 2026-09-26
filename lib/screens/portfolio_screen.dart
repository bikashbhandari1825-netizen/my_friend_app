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
import '../widgets/glass_ui.dart';

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
      backgroundColor: AppColors.kmSurface,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt_rounded,
                  color: AppColors.kmOrange),
              title: Text(S.fromCamera,
                  style: const TextStyle(color: AppColors.kmText)),
              onTap: () => Navigator.pop(context, 'camera'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_rounded,
                  color: AppColors.kmOrange),
              title: Text(S.fromGallery,
                  style: const TextStyle(color: AppColors.kmText)),
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
    final ok = await showKmDialog<bool>(
      context: context,
      title: S.removePhoto,
      icon: Icons.delete_outline_rounded,
      iconBg: const LinearGradient(
          colors: [AppColors.kmRose, AppColors.kmPinkDeep]),
      actions: [
        KmDialogAction(
          label: S.cancel,
          onPressed: () => Navigator.pop(context, false),
        ),
        KmDialogAction(
          label: S.delete,
          destructive: true,
          filled: true,
          onPressed: () => Navigator.pop(context, true),
        ),
      ],
    );
    if (ok != true) return;

    final db = FirebaseFirestore.instance;
    for (final c in ['providers', 'users', 'registeredWorkers']) {
      // `url` छ्यानल्ट पछिको दुबै सम्भावित स्रोतबाट हटाउने — पोर्टफोलियोमा
      // `_addPhoto()` ले थपेको वा registration बेलाको certificate, दुवै।
      await db.collection(c).doc(_uid).set(
        {
          'portfolioUrls': FieldValue.arrayRemove([url]),
          'certificateUrls': FieldValue.arrayRemove([url]),
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
    return AuroraBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                child: KmScreenHeader(title: S.workPortfolio),
              ),
              Expanded(
                child: _uid.isEmpty
              ? const Center(
                  child: Text('Login गर्नुहोस्',
                      style: TextStyle(color: AppColors.kmMuted)))
              : StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                  stream: FirebaseFirestore.instance
                      .collection('providers')
                      .doc(_uid)
                      .snapshots(),
                  builder: (context, snap) {
                    final doc = snap.data?.data() ?? const {};
                    // Registration बेला upload भएका "certificate/work photo"
                    // हरू पनि यहीं देखियोस् भनेर — पहिले यी `certificateUrls`
                    // मा मात्र बस्थे, `_addPhoto()` ले लेख्ने छुट्टै
                    // `portfolioUrls` मा कहिल्यै नआउने भएकोले गर्दा हरेक
                    // नयाँ worker को portfolio सधैं "खाली" देखिन्थ्यो।
                    final urls = <String>{
                      ...((doc['portfolioUrls'] as List?) ?? const [])
                          .cast<String>(),
                      ...((doc['certificateUrls'] as List?) ?? const [])
                          .cast<String>(),
                    }.toList();

                    if (urls.isEmpty && !_editable) {
                      return Center(
                        child: Text(S.portfolioEmptyOther,
                            style: const TextStyle(color: AppColors.kmMuted)),
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
                                color: Colors.white.withValues(alpha: 0.06),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                    color: AppColors.kmOrange.withValues(alpha: 0.4)),
                              ),
                              child: _busy
                                  ? const Center(
                                      child: CircularProgressIndicator(
                                          color: AppColors.kmOrange,
                                          strokeWidth: 2.4))
                                  : Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        const Icon(Icons.add_a_photo_rounded,
                                            color: AppColors.kmOrange, size: 26),
                                        const SizedBox(height: 6),
                                        Text(S.addWorkPhoto,
                                            textAlign: TextAlign.center,
                                            style: const TextStyle(
                                                color: AppColors.kmText,
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
                                key: ValueKey(url),
                                fit: BoxFit.cover,
                                gaplessPlayback: true,
                                errorBuilder: (_, __, ___) => Container(
                                  color: Colors.white.withValues(alpha: 0.08),
                                  child: const Icon(Icons.broken_image_rounded,
                                      color: AppColors.kmMuted),
                                ),
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
