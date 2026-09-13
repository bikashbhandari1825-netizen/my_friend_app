// screens/worker_register_screen.dart
// कामदार दर्ता फारम (Admin Approval चाहिने)।
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../app_globals.dart';
import '../theme/app_theme.dart';

// 2. Worker Registration Screen (Updated with real FilePicker functionality)
class WorkerRegisterScreen extends StatefulWidget {
  const WorkerRegisterScreen({super.key});

  @override
  State<WorkerRegisterScreen> createState() => _WorkerRegisterScreenState();
}

class _WorkerRegisterScreenState extends State<WorkerRegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _priceValueController = TextEditingController();
  final TextEditingController _specificAreaController = TextEditingController();

  String _selectedService = 'Plumber';
  final List<String> _serviceCategories = [
    'Plumber',
    'Electrician',
    'Cleaner',
    'Carpenter',
    'Painter',
    'Driver',
    'Mechanic',
    'Tutor'
  ];

  // Experience (Years & Months)
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

  // Document Upload State
  String? _uploadedFileName;

  // Location District Selection
  String _selectedDistrict = 'Kathmandu';
  final List<String> _districtsList = [
    'Kathmandu',
    'Lalitpur',
    'Bhaktapur',
    'Jhapa',
    'Morang',
    'Sunsari',
    'Kaski',
    'Chitwan',
    'Rupandehi',
    'Banke'
  ];

  // वास्तविक फाइल पिकर फंक्सन (File Picker implementation for phone & laptop)
  Future<void> _pickDocument() async {
    try {
      final file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'doc', 'docx', 'jpg', 'png'],
      );

      if (file != null) {
        setState(() {
          _uploadedFileName = file.name;
        });
        // ignore: use_build_context_synchronously
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Selected: $_uploadedFileName')),
        );
      } else {
        // User canceled the picker
        // ignore: use_build_context_synchronously
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('File selection canceled')),
        );
      }
    } catch (e) {
      // ignore: use_build_context_synchronously
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Error picking file: $e'),
            backgroundColor: Colors.red),
      );
    }
  }

  void _registerWorker() {
    if (_formKey.currentState!.validate()) {
      if (_uploadedFileName == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content:
                  Text('Please upload your Experience Certificate/Document!'),
              backgroundColor: Colors.red),
        );
        return;
      }

      String experienceStr = '$_selectedYear years';
      if (_selectedMonth != '0') {
        experienceStr += ' $_selectedMonth months';
      }

      String fullLocation =
          '${_specificAreaController.text.trim()}, $_selectedDistrict, Nepal';
      String priceStr = 'Rs. ${_priceValueController.text.trim()}';

      setState(() {
        pendingWorkers.add({
          'name': _nameController.text.trim(),
          'service': _selectedService,
          'rating': '5.0',
          'reviews': '0',
          'experience': experienceStr,
          'distance': '1.0 km away',
          'price': priceStr,
          'location': fullLocation,
          'document': _uploadedFileName!,
        });
      });

      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Application Submitted!'),
          content: const Text(
              'Your registration request has been sent to the Admin. Once approved by the admin, your profile will be live.'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                Navigator.pop(context);
              },
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Worker Registration'),
        backgroundColor: AppColors.igViolet,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                  'Register to get hired by customers (Requires Admin Approval)',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey)),
              const SizedBox(height: 20),
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                    labelText: 'Full Name', border: OutlineInputBorder()),
                validator: (value) =>
                    value!.isEmpty ? 'Please enter your name' : null,
              ),
              const SizedBox(height: 15),
              DropdownButtonFormField<String>(
                initialValue: _selectedService,
                decoration: const InputDecoration(
                    labelText: 'Select Service Category',
                    border: OutlineInputBorder()),
                items: _serviceCategories.map((String service) {
                  return DropdownMenuItem<String>(
                    value: service,
                    child: Text(service),
                  );
                }).toList(),
                onChanged: (newValue) {
                  setState(() {
                    _selectedService = newValue!;
                  });
                },
              ),
              const SizedBox(height: 20),

              // 1. Experience Section with Years and Months inside brackets
              const Text('Experience',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87)),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  children: [
                    const Text('Years & Months: ',
                        style: TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w500)),
                    const Spacer(),
                    // Years Dropdown inside bracket
                    const Text('(',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold)),
                    DropdownButton<String>(
                      value: _selectedYear,
                      underline: const SizedBox(),
                      items: _yearsList.map((String val) {
                        return DropdownMenuItem<String>(
                            value: val, child: Text('$val yrs'));
                      }).toList(),
                      onChanged: (val) => setState(() => _selectedYear = val!),
                    ),
                    const SizedBox(width: 8),
                    DropdownButton<String>(
                      value: _selectedMonth,
                      underline: const SizedBox(),
                      items: _monthsList.map((String val) {
                        return DropdownMenuItem<String>(
                            value: val, child: Text('$val mos'));
                      }).toList(),
                      onChanged: (val) => setState(() => _selectedMonth = val!),
                    ),
                    const Text(')',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // 2. Experience Certificate Document Direct Upload Section with real File Picker
              const Text('Experience Certificate Document',
                  style: TextStyle(
                      fontWeight: FontWeight.bold, color: Colors.black87)),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.insert_drive_file, color: Colors.blue),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _uploadedFileName ?? 'No document chosen',
                        style: TextStyle(
                            color: _uploadedFileName == null
                                ? Colors.grey
                                : Colors.black87),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    ElevatedButton.icon(
                      onPressed: _pickDocument,
                      icon: const Icon(Icons.upload_file,
                          size: 16, color: Colors.white),
                      label: const Text('Upload Doc',
                          style: TextStyle(color: Colors.white)),
                      style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue.shade700),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // 3. Starting Price Section with Price inside bracket
              const Text('Starting Price',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87)),
              const SizedBox(height: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  children: [
                    const Text('Amount: ',
                        style: TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w500)),
                    const Spacer(),
                    const Text('(',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold)),
                    const Text('Rs. ',
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: AppColors.igViolet)),
                    SizedBox(
                      width: 90,
                      child: TextField(
                        controller: _priceValueController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          hintText: '500',
                          border: InputBorder.none,
                          isDense: true,
                        ),
                      ),
                    ),
                    const Text(')',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // 4. Location Section with District Option and Specific Area details
              const Text('Location',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87)),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: _selectedDistrict,
                decoration: const InputDecoration(
                    labelText: 'Select District Option',
                    border: OutlineInputBorder()),
                items: _districtsList.map((String district) {
                  return DropdownMenuItem<String>(
                    value: district,
                    child: Text(district),
                  );
                }).toList(),
                onChanged: (newValue) {
                  setState(() {
                    _selectedDistrict = newValue!;
                  });
                },
              ),
              const SizedBox(height: 15),
              TextFormField(
                controller: _specificAreaController,
                decoration: const InputDecoration(
                  labelText:
                      'Specific Area / Tole / Landmark (e.g., Baneshwor, Thamel)',
                  border: OutlineInputBorder(),
                  hintText: 'Enter specific place description',
                ),
                validator: (value) => value!.isEmpty
                    ? 'Please enter specific location details'
                    : null,
              ),
              const SizedBox(height: 30),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _registerWorker,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.igViolet,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: const Text('Submit for Approval',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
