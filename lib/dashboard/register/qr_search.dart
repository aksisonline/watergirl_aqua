import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:convert';
import 'property_editor.dart';
import 'attendee_profile.dart';

class QRSearchPage extends StatefulWidget {
  const QRSearchPage({super.key});

  @override
  State<QRSearchPage> createState() => _QRSearchPageState();
}

class _QRSearchPageState extends State<QRSearchPage> {
  final SupabaseClient supabase = Supabase.instance.client;
  late MobileScannerController controller;
  String scannedData = 'No data scanned yet';
  bool torchOn = false;
  bool _isLoading = false;
  bool isScanning = true;
  Map<String, dynamic>? attendeeData;

  @override
  void initState() {
    super.initState();
    controller = MobileScannerController();
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  void toggleTorch() {
    setState(() {
      torchOn = !torchOn;
    });
    controller.toggleTorch();
  }

  Future<void> searchDatabase(String uid) async {
    setState(() {
      _isLoading = true;
    });

    try {
      final data = await supabase
          .from('attendee_details')
          .select('*')
          .eq('attendee_internal_uid', uid)
          .maybeSingle();

      setState(() {
        attendeeData = data;
        _isLoading = false;
      });

      if (data != null) {
        // Navigate to profile page
        _navigateToProfile();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No attendee found with this QR code')),
        );
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error searching: $e')),
      );
    }
  }

  void _navigateToProfile() async {
    if (attendeeData != null) {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => AttendeeProfilePage(attendee: attendeeData!),
        ),
      );
      
      // Reset the scanner after returning from profile
      setState(() {
        scannedData = 'No data scanned yet';
        attendeeData = null;
        isScanning = true;
      });
    }
  }

  void refreshCamera() {
    setState(() {
      isScanning = false;
      attendeeData = null;
      scannedData = 'No data scanned yet';
    });
    controller.stop();
    controller.start();
    setState(() {
      isScanning = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('QR Search'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: refreshCamera,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            flex: 3,
            child: MobileScanner(
              controller: controller,
              onDetect: (barcode) {
                if (isScanning) {
                  for (final code in barcode.barcodes) {
                    setState(() {
                      scannedData = code.rawValue ?? 'Unknown data';
                      isScanning = false; // Stop scanning
                    });
                    searchDatabase(scannedData); // Search the database
                  }
                }
              },
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                icon: Icon(torchOn ? Icons.flash_on : Icons.flash_off),
                onPressed: toggleTorch,
              ),
              IconButton(
                icon: const Icon(Icons.cameraswitch),
                onPressed: () => controller.switchCamera(),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              'Scanned Data: $scannedData',
              style: const TextStyle(fontSize: 18),
            ),
          ),
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: CircularProgressIndicator(),
            ),
          if (attendeeData != null && !_isLoading)
            Expanded(
              flex: 1,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Found: ${attendeeData!['attendee_name'] ?? 'Unknown'}',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    ElevatedButton(
                      onPressed: _navigateToProfile,
                      child: const Text('View Profile'),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}