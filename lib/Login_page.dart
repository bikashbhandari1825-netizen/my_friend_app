// Login_page.dart
// ignore_for_file: file_names

import 'package:firebase_auth/firebase_auth.dart' show FirebaseAuth;
import 'package:flutter/material.dart';

import 'theme/app_theme.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  // पासवर्ड देखाउने वा लुकाउने अवस्था नियन्त्रण गर्ने भेरिएबल
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    var padding = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: TextField(
        controller: _emailController,
        decoration: const InputDecoration(
          labelText: 'इमेल लेख्नुहोस्',
          border: InputBorder.none,
        ),
      ),
    );
    return Scaffold(
      backgroundColor: AppColors.igViolet,
      appBar: AppBar(title: const Text('KaamMitra - Login')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Container(
          width: double.infinity,
          height: double.infinity,
          padding: const EdgeInsets.all(16.0),
          decoration: const BoxDecoration(
            gradient: AppColors.instaGradient,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Card(
                color: const Color(0xFFF3E8FB), // हल्का violet कलर
                elevation: 3,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                child: padding,
              ),
              const SizedBox(height: 16),

              // पासवर्ड लेख्ने बक्स र आँखाको आइकन भएको ठाउँ (हरियो ब्याकग्राउन्डसहित)
              Card(
                color: const Color(0xFFF3E8FB), // हल्का violet कलर
                elevation: 3,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  child: TextField(
                    controller: _passwordController,
                    obscureText:
                        _obscurePassword, // यहाँबाट पासवर्ड लुक्छ वा देखिन्छ
                    decoration: InputDecoration(
                      labelText: 'पासवर्ड लेख्नुहोस्',
                      border: InputBorder.none,
                      // यहाँ पासवर्ड बक्सको छेउमा आँखाको आइकन राखिएको छ
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility_off
                              : Icons.visibility,
                        ),
                        onPressed: () {
                          // आइकन थिच्दा यो स्टेट बद्लिन्छ
                          setState(() {
                            _obscurePassword = !_obscurePassword;
                          });
                        },
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // लगइन बटन
              ElevatedButton(
                onPressed: () async {
                  try {
                    await FirebaseAuth.instance.signInWithEmailAndPassword(
                      email: _emailController.text.trim(),
                      password: _passwordController.text.trim(),
                    );

                    // लगइन सफल भएपछि मुख्य पेजमा पठाउने
                    if (!mounted) return;
                    // ignore: use_build_context_synchronously
                    Navigator.pop(context);
                  } catch (e) {
                    debugPrint("लगइन गर्न मिलेन: $e");
                  }
                },
                child: const Text('लगइन गर्नुहोस्'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
