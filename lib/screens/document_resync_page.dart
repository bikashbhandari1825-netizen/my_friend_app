// screens/document_resync_page.dart
// दर्ता सबमिट भयो तर कागजात Storage मा नपुगेको बेला — यहाँबाट परिचयपत्र + सेल्फी
// फेरि उठाएर अपलोड गर्न मिल्छ (users / providers / pendingWorkers तीनवटै update)।
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../l10n/strings.dart';
import '../services/document_service.dart';
import '../services/upload_validation.dart';
import '../theme/app_theme.dart';
import '../widgets/app_ui.dart';

class DocumentResyncPage extends StatefulWidget {
  const DocumentResyncPage({super.key});

  @override
  State<DocumentResyncPage> createState() => _DocumentResyncPageState();
}

class _DocumentResyncPageState extends State<DocumentResyncPage> {
  Uint8List? _frontBytes;
  String? _frontName;
  Uint8List? _backBytes;
  String? _backName;
  Uint8List? _selfieBytes;
  bool _busy = false;
  String? _error;

  bool _accept(Uint8List? bytes, String name) {
    final err = UploadValidation.validate(bytes, name);
    if (err != null) {
      setState(() => _error = UploadValidation.messageFor(err));
      return false;
    }
    return true;
  }

  Future<({Uint8List bytes, String name})?> _pickImage() async {
    try {
      final file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp'],
      );
      if (file == null) return null;
      final bytes = await file.readAsBytes();
      if (!_accept(bytes, file.name)) return null;
      return (bytes: bytes, name: file.name);
    } catch (e) {
      setState(() => _error = '${S.errorWord}: $e');
      return null;
    }
  }

  Future<void> _pickFront() async {
    final r = await _pickImage();
    if (r == null) return;
    setState(() {
      _frontBytes = r.bytes;
      _frontName = r.name;
      _error = null;
    });
  }

  Future<void> _pickBack() async {
    final r = await _pickImage();
    if (r == null) return;
    setState(() {
      _backBytes = r.bytes;
      _backName = r.name;
      _error = null;
    });
  }

  Future<void> _takeSelfie() async {
    try {
      final XFile? p = await ImagePicker().pickImage(
        source: ImageSource.camera,
        preferredCameraDevice: CameraDevice.front,
        imageQuality: 70,
      );
      if (p == null) return;
      final bytes = await p.readAsBytes();
      if (!_accept(bytes, p.name)) return;
      setState(() {
        _selfieBytes = bytes;
        _error = null;
      });
    } catch (e) {
      setState(() => _error = '${S.errorWord}: $e');
    }
  }

  Future<void> _upload() async {
    if (_frontBytes == null || _backBytes == null || _selfieBytes == null) {
      setState(() => _error = S.docsNotUploadedBody);
      return;
    }
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    setState(() {
      _busy = true;
      _error = null;
    });

    final reason = await DocumentService.resyncDocuments(
      uid: uid,
      citFrontBytes: _frontBytes!,
      citFrontName: _frontName ?? 'front.jpg',
      citBackBytes: _backBytes!,
      citBackName: _backName ?? 'back.jpg',
      selfieBytes: _selfieBytes!,
    );

    if (!mounted) return;
    if (reason == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(S.docsSyncedOk)));
      Navigator.pop(context, true);
      return;
    }
    setState(() {
      _busy = false;
      _error = switch (reason) {
        'storage-not-setup' => S.docsSyncFailedStorage,
        'permission-denied' => S.docsSyncFailedStorage,
        'network' => S.docsSyncFailedNetwork,
        'invalid-file' => S.fileTypeNotAllowed,
        _ => '${S.errorWord}: $reason',
      };
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: gradientAppBar(S.docsResyncTitle),
      body: AppGradientBackground(
        glows: false,
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(AppRadius.lg),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(S.docsNotUploadedBody,
                      style: const TextStyle(fontSize: 13.5, height: 1.4)),
                  const SizedBox(height: 18),
                  _PickTile(
                    label: _frontName ?? S.citizenshipFront,
                    done: _frontBytes != null,
                    icon: Icons.badge_rounded,
                    onTap: _busy ? null : _pickFront,
                  ),
                  const SizedBox(height: 12),
                  _PickTile(
                    label: _backName ?? S.citizenshipBack,
                    done: _backBytes != null,
                    icon: Icons.badge_outlined,
                    onTap: _busy ? null : _pickBack,
                  ),
                  const SizedBox(height: 12),
                  _PickTile(
                    label: S.selectSelfie,
                    done: _selfieBytes != null,
                    icon: Icons.camera_front_rounded,
                    onTap: _busy ? null : _takeSelfie,
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 14),
                    Text(_error!,
                        style: const TextStyle(
                            color: AppColors.danger, fontSize: 12.5)),
                  ],
                  const SizedBox(height: 22),
                  PrimaryButton(
                    label: S.uploadNow,
                    icon: Icons.cloud_upload_rounded,
                    loading: _busy,
                    onPressed: _upload,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PickTile extends StatelessWidget {
  final String label;
  final bool done;
  final IconData icon;
  final VoidCallback? onTap;
  const _PickTile({
    required this.label,
    required this.done,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(
              color: done ? AppColors.success : Theme.of(context).dividerColor,
              width: done ? 1.6 : 1),
        ),
        child: Row(
          children: [
            Icon(done ? Icons.check_circle_rounded : icon,
                color: done ? AppColors.success : AppColors.igViolet),
            const SizedBox(width: 12),
            Expanded(
                child: Text(label,
                    style: const TextStyle(fontWeight: FontWeight.w600))),
            const Icon(Icons.chevron_right_rounded, color: Colors.black38),
          ],
        ),
      ),
    );
  }
}
