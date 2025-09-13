import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class QRRegisterPage extends StatefulWidget {
  final Map<String, dynamic> attendee;

  const QRRegisterPage({super.key, required this.attendee});

  @override
  State<QRRegisterPage> createState() => _QRRegisterPageState();
}

class _QRRegisterPageState extends State<QRRegisterPage> {
  final SupabaseClient supabase = Supabase.instance.client;
  late MobileScannerController controller;
  String scannedData = 'No data scanned yet';
  bool torchOn = false;
  bool _isLoading = false;
  bool isScanning = true;

  Future<void> updateUID(String uid) async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
    });
    try {
      // Check if the UID already exists
      final existingUID = await supabase
          .from('attendee_details')
          .select()
          .eq('uid', uid)
          .maybeSingle();

      if (existingUID != null) {
        // UID already exists
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('This QR is already registered to another attendee.')),
        );
      } else {
        // Update the UID
        await supabase
            .from('attendee_details')
            .update({'uid': uid})
            .eq('email', widget.attendee['email']);

        setState(() {
          widget.attendee['uid'] = uid;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('UID created successfully.')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          isScanning = true; // Resume scanning after updating UID
        });
      }
    }
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan QR Code'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              setState(() {
                scannedData = 'No data scanned yet';
                isScanning = true; // Resume scanning
              });
            },
          ),
        ],
      ),
      resizeToAvoidBottomInset: true,
      body: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Column(
                children: [
                  SizedBox(
                    height: 300,
                    child: MobileScanner(
                      controller: controller,
                      fit: BoxFit.cover,
                      onDetect: (capture) {
                        if (isScanning) {
                          final List<Barcode> barcodes = capture.barcodes;
                          for (final barcode in barcodes) {
                            setState(() {
                              scannedData = barcode.rawValue ?? 'Unknown data';
                              isScanning = false; // Stop scanning
                            });
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
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Name: ${widget.attendee['name']}', style: const TextStyle(fontSize: 18)),
                        const SizedBox(height: 8.0),
                        Text('Email: ${widget.attendee['email']}', style: const TextStyle(fontSize: 18)),
                      ],
                    ),
                  ),
                  if (_isLoading) const CircularProgressIndicator(),
                  if (!_isLoading)
                    ElevatedButton(
                      onPressed: scannedData == 'No data scanned yet' ? null : () {
                        updateUID(scannedData);
                      },
                      child: const Text('Update UID'),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}