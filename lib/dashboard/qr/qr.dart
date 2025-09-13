import 'package:watergirl_aqua/dimensions.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class QRScannerPage extends StatefulWidget {
  const QRScannerPage({super.key});

  @override
  State<QRScannerPage> createState() => QRScannerPageState();

  QRScannerPageState? getState(BuildContext context) {
    return context.findAncestorStateOfType<QRScannerPageState>();
  }
}

class QRScannerPageState extends State<QRScannerPage> {
  final SupabaseClient supabase = Supabase.instance.client;

  Map<String, dynamic>? attendeeData = {};
  late MobileScannerController controller;
  String scannedData = 'No data scanned yet';
  bool torchOn = false; // Track torch state manually
  bool isPresent = false; // Add isPresent as a state variable
  bool isScanning = true; // Add isScanning flag

  Future<void> searchDatabase(String scannedData) async {
    final data = await supabase
        .from('attendee_details')
        .select()
        .eq('uid', scannedData)
        .maybeSingle();

    setState(() {
      attendeeData = data;
      isPresent = attendeeData!['entry_time'] != null; // Update isPresent based on fetched data
    });
  }

  Future<void> updateCheckInOut(String uid, bool newValue) async {
    if (!mounted) return; // Check if the widget is still mounted

    final currentTime = newValue ? DateTime.now().toIso8601String() : null;
    await supabase
    .from('attendee_details')
    .update({'entry_time': currentTime})
    .eq('uid', uid);

    if (mounted && attendeeData != null) {
      setState(() {
        attendeeData!['entry_time'] = currentTime;
      });
    }
  }

  void refreshCamera() {
    setState(() {
      isScanning = false;
      attendeeData = {};
      scannedData = 'No data scanned yet';
    });
    controller.stop();
    controller.start();
    setState(() {
      isScanning = true;
    });
  }

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

  @override
  Widget build(BuildContext context) {
    final uid = attendeeData!['uid'];

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          Container(
            height: 300,
            clipBehavior: Clip.hardEdge,
            decoration: const BoxDecoration(
              borderRadius: BorderRadius.all(Radius.circular(8.0))
            ),
            child: MobileScanner(
              controller: controller,
              fit: BoxFit.cover, // Ensures the camera preview fills the container
              onDetect: (capture) {
                if (isScanning) {
                  final List<Barcode> barcodes = capture.barcodes;
                  for (final barcode in barcodes) {
                    setState(() {
                      scannedData = barcode.rawValue ?? 'Unknown data';
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
          Container(
            width: deviceWidth,
            padding: EdgeInsets.all(safePadding),
            child: Text(
              'Scanned Data: $scannedData',
              style: const TextStyle(fontSize: 18),
            ),
          ),
          Container(
            width: deviceWidth,
            padding: EdgeInsets.all(safePadding),
            child: attendeeData!.isNotEmpty
            ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Name: ${attendeeData!['name']}',
                  style: const TextStyle(fontSize: 18),
                ), SizedBox(height: safePadding),
                Text(
                  'Email: ${attendeeData!['email']}',
                  style: const TextStyle(fontSize: 18),
                ), SizedBox(height: safePadding),
                Text(
                  'Current Status: ${attendeeData!['entry_time'] != null ? 'Present' : 'Absent'}',
                  style: const TextStyle(fontSize: 18),
                ), SizedBox(height: safePadding),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    ElevatedButton(
                      onPressed: () {
                        setState(() {
                          isPresent = !isPresent;
                        });
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isPresent ? Colors.teal : Colors.deepOrangeAccent,
                      ),
                      child: Text(isPresent ? 'Present' : 'Absent'),
                    ),
                    ElevatedButton(
                      onPressed: () {
                        updateCheckInOut(uid, isPresent);
                        setState(() {
                          scannedData = 'No data scanned yet';
                          isScanning = true; // Resume scanning
                          attendeeData = {};
                        });
                      },
                      child: const Text('Confirm'),
                    ),
                  ],
                ),
              ],
            ) : const Text(
              'No details available',
              style: TextStyle(fontSize: 18),
            ),
          ),
        ],
      ),
    );
  }
}