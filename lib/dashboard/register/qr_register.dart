import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'property_editor.dart';

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

    if (widget.attendee['id'] == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error: Attendee ID is missing. Cannot assign QR.')),
        );
        setState(() {
          _isLoading = false;
          isScanning = true;
        });
      }
      return;
    }

    setState(() {
      _isLoading = true;
    });
    try {
      // Check if the UID already exists
      final existingUID = await supabase
          .from('attendee_details')
          .select()
          .eq('attendee_internal_uid', uid)
          .neq('id', widget.attendee['id']) // Ensure it's not the current user's existing QR
          .maybeSingle();

      if (existingUID != null) {
        // UID already exists and belongs to another attendee
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('This QR is already registered to another attendee.')),
        );
      } else {
        // Update the UID for the current attendee
        await supabase
            .from('attendee_details')
            .update({'attendee_internal_uid': uid})
            .eq('id', widget.attendee['id']); // Use primary key 'id' to identify the record

        setState(() {
          widget.attendee['attendee_internal_uid'] = uid;
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('QR assigned successfully.')),
        );

        // Show option to fill properties and then navigate back
        _showPropertyDialogAndPop();
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          isScanning = true; // Resume scanning after updating UID or if dialog is cancelled
        });
      }
    }
  }

  void _showPropertyDialogAndPop() {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog( // Use dialogContext for dialog's own pop
        title: const Text('Fill Properties'),
        content: const Text('Would you like to fill in the attendee properties now?'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(dialogContext).pop(); // Close dialog
              Navigator.of(context).pop(); // Close QRRegisterPage
            },
            child: const Text('Skip'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(dialogContext).pop(); // Close dialog
              _navigateToPropertyEditorAndPop();
            },
            child: const Text('Fill Now'),
          ),
        ],
      ),
    );
  }

  void _navigateToPropertyEditorAndPop() async {
    // Navigate to PropertyEditorPage
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PropertyEditorPage(attendee: widget.attendee),
      ),
    );
    
    // After PropertyEditorPage is closed (by saving or navigating back),
    // pop the QRRegisterPage, if it's still mounted.
    if (mounted) {
      Navigator.of(context).pop();
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
                        Text('Name: ${widget.attendee['attendee_name'] ?? 'Unknown'}', style: const TextStyle(fontSize: 18)),
                        const SizedBox(height: 8.0),
                        Text('ID: ${widget.attendee['attendee_internal_uid'] ?? 'No ID'}', style: const TextStyle(fontSize: 18)),
                      ],
                    ),
                  ),
                  if (_isLoading) const CircularProgressIndicator(),
                  if (!_isLoading)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        ElevatedButton(
                          onPressed: scannedData == 'No data scanned yet' ? null : () {
                            updateUID(scannedData);
                          },
                          child: const Text('Assign QR'),
                        ),
                        ElevatedButton(
                          onPressed: () {
                            // Navigate to property editor but don't pop this page yet,
                            // as QR is not yet assigned.
                             Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => PropertyEditorPage(attendee: widget.attendee),
                              ),
                            );
                          },
                          child: const Text('Edit Properties'),
                        ),
                      ],
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