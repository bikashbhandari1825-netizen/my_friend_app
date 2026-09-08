// screens/profile_screen.dart
// वास्तविक User Data + Session Photo Upload सहितको Profile स्क्रिन।
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../app_globals.dart';
import '../l10n/strings.dart';
import '../report_page.dart';
import '../saved_places_screen.dart';
import 'bookings_screen.dart';
import 'help_support_screen.dart';
import 'messages_screen.dart';
import 'my_reviews_screen.dart';
import 'payment_methods_screen.dart';
import 'saved_workers_screen.dart';

// 12. Profile Screen (वास्तविक User Data + Photo Upload सहित)
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  Uint8List? _pendingPhoto; // छानेको तर अझै Save नगरेको फोटो

  void _showPhotoOptions() {
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
                  _pickFromFile();
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
        setState(() => _pendingPhoto = bytes);
        _showConfirmDialog();
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('क्यामेरा खोल्न मिलेन: $e')),
      );
    }
  }

  Future<void> _pickFromFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        withData: true,
      );
      if (result != null && result.files.single.bytes != null) {
        setState(() => _pendingPhoto = result.files.single.bytes);
        _showConfirmDialog();
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('फाइल छान्न मिलेन: $e')),
      );
    }
  }

  void _showConfirmDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Profile Photo राख्ने?'),
        content: SizedBox(
          width: 150,
          height: 150,
          child: ClipOval(
            child: Image.memory(_pendingPhoto!, fit: BoxFit.cover),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              setState(() => _pendingPhoto = null);
              Navigator.pop(context);
            },
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            onPressed: () {
              setState(() {
                sessionProfilePhoto = _pendingPhoto;
                _pendingPhoto = null;
              });
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Profile Photo राखियो!')),
              );
            },
            child: const Text('Save', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    return Scaffold(
      appBar: AppBar(
          title: const Text('My Profile'),
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          elevation: 1,
          actions: [
            PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'report') {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (context) => const ReportOptionsPage()),
                  );
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'report',
                  child: Text('Report a Problem'),
                ),
              ],
            ),
          ]),
      body: uid == null
          ? const Center(child: Text('Login गर्नुहोस्'))
          : FutureBuilder<DocumentSnapshot>(
              future:
                  FirebaseFirestore.instance.collection('users').doc(uid).get(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                final data =
                    snapshot.data?.data() as Map<String, dynamic>? ?? {};

                final firstName = data['firstName'] ?? '';
                final lastName = data['lastName'] ?? '';
                final fullName = '$firstName $lastName'.trim();
                final email = data['email'] ??
                    FirebaseAuth.instance.currentUser?.email ??
                    '';
                final dob = data['dob'] ?? '';
                final role = data['role'] ?? '';
                final experience = data['experience'];

                String dobFormatted = '';
                if (dob.toString().isNotEmpty) {
                  try {
                    final parsed = DateTime.parse(dob);
                    dobFormatted =
                        '${parsed.day}/${parsed.month}/${parsed.year}';
                  } catch (_) {
                    dobFormatted = dob.toString();
                  }
                }

                return ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Row(
                      children: [
                        GestureDetector(
                          onTap: _showPhotoOptions,
                          child: Stack(
                            children: [
                              CircleAvatar(
                                radius: 35,
                                backgroundImage: sessionProfilePhoto != null
                                    ? MemoryImage(sessionProfilePhoto!)
                                    : null,
                                child: sessionProfilePhoto == null
                                    ? const Icon(Icons.person, size: 40)
                                    : null,
                              ),
                              Positioned(
                                right: 0,
                                bottom: 0,
                                child: Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: const BoxDecoration(
                                    color: Colors.green,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.camera_alt,
                                      size: 14, color: Colors.white),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 15),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                  fullName.isEmpty
                                      ? 'नाम राखिएको छैन'
                                      : fullName,
                                  style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold)),
                              if (email.toString().isNotEmpty)
                                Text(email,
                                    style: const TextStyle(color: Colors.grey)),
                              if (dobFormatted.isNotEmpty)
                                Text('जन्ममिति: $dobFormatted',
                                    style: const TextStyle(color: Colors.grey)),
                              if (role.toString().isNotEmpty)
                                Text(
                                    'भूमिका: ${role == 'worker' ? 'Worker' : 'Employer'}',
                                    style: const TextStyle(
                                        color: Colors.green,
                                        fontWeight: FontWeight.w600)),
                              if (experience != null &&
                                  experience.toString().isNotEmpty)
                                Text('अनुभव: $experience',
                                    style: const TextStyle(color: Colors.grey)),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    const Divider(),
                    ListTile(
                        leading: const Icon(Icons.calendar_today),
                        title: const Text('My Bookings'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (context) => const BookingsScreen()))),
                    ListTile(
                        leading: const Icon(Icons.message),
                        title: const Text('My Messages'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (context) => const MessagesScreen()))),
                    ListTile(
                        leading: const Icon(Icons.payment),
                        title: const Text('Payment Methods'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (context) =>
                                    const PaymentMethodsScreen()))),
                    ListTile(
                        leading: const Icon(Icons.star_border),
                        title: const Text('My Reviews'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (context) =>
                                    const MyReviewsScreen()))),
                    ListTile(
                        leading: const Icon(Icons.bookmark_border),
                        title: const Text('Saved Workers'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (context) =>
                                    const SavedWorkersScreen()))),
                    ListTile(
                        leading: const Icon(Icons.place_outlined),
                        title: Text(S.savedPlacesTitle),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (context) =>
                                    const SavedPlacesScreen()))),
                    ListTile(
                        leading: const Icon(Icons.help_outline),
                        title: const Text('Help & Support'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (context) =>
                                    const HelpSupportScreen()))),
                  ],
                );
              },
            ),
    );
  }
}
