import 'package:watergirl_aqua/dimensions.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:convert';
import '../register/attendee_profile.dart';

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
  Map<String, dynamic>? currentSlot;
  bool isSlotActive = false;

  Future<void> searchDatabase(String scannedData) async {
    final data = await supabase
        .from('attendee_details')
        .select()
        .eq('attendee_internal_uid', scannedData)
        .maybeSingle();

    setState(() {
      attendeeData = data;
      if (data != null) {
        // Check current attendance for the active slot
        _checkCurrentAttendance();
      }
    });
  }

  void _checkCurrentAttendance() {
    if (attendeeData == null || currentSlot == null) {
      isPresent = false;
      return;
    }

    try {
      final attendanceData = attendeeData!['attendee_attendance'];
      if (attendanceData != null) {
        final attendance = json.decode(attendanceData) as List;
        final currentSlotId = currentSlot!['slot_id'].toString();
        
        final slotAttendance = attendance.firstWhere(
          (a) => a['slot_id'].toString() == currentSlotId,
          orElse: () => null,
        );
        
        isPresent = slotAttendance?['attendance_bool'] == true;
      } else {
        isPresent = false;
      }
    } catch (e) {
      print('Error checking attendance: $e');
      isPresent = false;
    }
  }

  Future<void> updateCheckInOut(String uid, bool newValue) async {
    if (!mounted || currentSlot == null) return;

    try {
      // Get current attendance data
      final currentData = await supabase
          .from('attendee_details')
          .select('attendee_attendance')
          .eq('attendee_internal_uid', uid)
          .single();

      List<dynamic> attendance = [];
      if (currentData['attendee_attendance'] != null) {
        attendance = json.decode(currentData['attendee_attendance']);
      }

      // Update or add attendance for current slot
      final currentSlotId = currentSlot!['slot_id'].toString();
      final existingIndex = attendance.indexWhere(
        (a) => a['slot_id'].toString() == currentSlotId,
      );

      if (existingIndex >= 0) {
        attendance[existingIndex]['attendance_bool'] = newValue;
      } else {
        attendance.add({
          'slot_id': currentSlotId,
          'attendance_bool': newValue,
        });
      }

      // Update in database
      await supabase
          .from('attendee_details')
          .update({'attendee_attendance': json.encode(attendance)})
          .eq('attendee_internal_uid', uid);

      if (mounted && attendeeData != null) {
        setState(() {
          attendeeData!['attendee_attendance'] = json.encode(attendance);
        });
      }
    } catch (e) {
      print('Error updating attendance: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error updating attendance: $e')),
        );
      }
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
    _loadCurrentSlot();
  }

  Future<void> _loadCurrentSlot() async {
    try {
      final now = DateTime.now();
      final currentTime = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
      
      final slots = await supabase.from('slots').select('*');
      
      for (final slot in slots) {
        final timeFrame = slot['slot_time_frame'] as String;
        if (_isTimeInRange(currentTime, timeFrame)) {
          setState(() {
            currentSlot = slot;
            isSlotActive = true;
          });
          return;
        }
      }
      
      setState(() {
        currentSlot = null;
        isSlotActive = false;
      });
    } catch (e) {
      print('Error loading current slot: $e');
    }
  }

  bool _isTimeInRange(String currentTime, String timeFrame) {
    try {
      final parts = timeFrame.split('-');
      if (parts.length != 2) return false;
      
      final startTime = parts[0].trim();
      final endTime = parts[1].trim();
      
      final current = _timeToMinutes(currentTime);
      final start = _timeToMinutes(startTime);
      final end = _timeToMinutes(endTime);
      
      return current >= start && current <= end;
    } catch (e) {
      return false;
    }
  }

  int _timeToMinutes(String time) {
    final parts = time.split(':');
    return int.parse(parts[0]) * 60 + int.parse(parts[1]);
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
    final uid = attendeeData?['attendee_internal_uid'];

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          // Slot Information
          if (currentSlot != null)
            Card(
              color: isSlotActive ? Colors.green[100] : Colors.orange[100],
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Row(
                  children: [
                    Icon(
                      isSlotActive ? Icons.access_time : Icons.schedule,
                      color: isSlotActive ? Colors.green : Colors.orange,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            currentSlot!['slot_name'] ?? 'Unknown Slot',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          Text(
                            'Time: ${currentSlot!['slot_time_frame']}',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      isSlotActive ? 'ACTIVE' : 'INACTIVE',
                      style: TextStyle(
                        color: isSlotActive ? Colors.green : Colors.orange,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            Card(
              color: Colors.grey[100],
              child: const Padding(
                padding: EdgeInsets.all(8.0),
                child: Row(
                  children: [
                    Icon(Icons.schedule_outlined, color: Colors.grey),
                    SizedBox(width: 8),
                    Text('No active slot', style: TextStyle(color: Colors.grey)),
                  ],
                ),
              ),
            ),
          
          const SizedBox(height: 16),
          
          Container(
            height: 300,
            clipBehavior: Clip.hardEdge,
            decoration: const BoxDecoration(
              borderRadius: BorderRadius.all(Radius.circular(8.0))
            ),
            child: MobileScanner(
              controller: controller,
              fit: BoxFit.cover,
              onDetect: (capture) {
                if (isScanning) {
                  final List<Barcode> barcodes = capture.barcodes;
                  for (final barcode in barcodes) {
                    setState(() {
                      scannedData = barcode.rawValue ?? 'Unknown data';
                      isScanning = false;
                    });
                    searchDatabase(scannedData);
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
                  'Name: ${attendeeData!['attendee_name'] ?? 'Unknown'}',
                  style: const TextStyle(fontSize: 18),
                ), SizedBox(height: safePadding),
                if (currentSlot != null) ...[
                  Text(
                    'Slot: ${currentSlot!['slot_name']}',
                    style: const TextStyle(fontSize: 18),
                  ), SizedBox(height: safePadding),
                  Text(
                    'Status: ${isPresent ? 'Present' : 'Absent'}',
                    style: TextStyle(
                      fontSize: 18,
                      color: isPresent ? Colors.green : Colors.red,
                      fontWeight: FontWeight.bold,
                    ),
                  ), SizedBox(height: safePadding),
                ],
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    if (isSlotActive && currentSlot != null)
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
                      )
                    else
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.grey[200],
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'No active slot',
                          style: TextStyle(color: Colors.grey),
                        ),
                      ),
                    Row(
                      children: [
                        ElevatedButton(
                          onPressed: () async {
                            await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => AttendeeProfilePage(attendee: attendeeData!),
                              ),
                            );
                          },
                          child: const Text('Profile'),
                        ),
                        const SizedBox(width: 8),
                        if (isSlotActive && currentSlot != null)
                          ElevatedButton(
                            onPressed: () {
                              updateCheckInOut(uid, isPresent);
                              setState(() {
                                scannedData = 'No data scanned yet';
                                isScanning = true;
                                attendeeData = {};
                              });
                            },
                            child: const Text('Save'),
                          ),
                      ],
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