import 'package:watergirl_aqua/dimensions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'; // For platform detection
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:convert';
import '../register/attendee_profile.dart';
import '../register/property_editor.dart';

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
  String qrMode = 'attendance'; // 'attendance' or 'profile' mode

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
    
    if (!kIsWeb) {
      controller.stop();
      controller.start();
    }
    
    setState(() {
      isScanning = true;
    });
  }

  @override
  void initState() {
    super.initState();
    if (!kIsWeb) {
      controller = MobileScannerController();
    }
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
            qrMode = 'attendance'; // Switch to attendance mode when slot is active
          });
          return;
        }
      }
      
      setState(() {
        currentSlot = null;
        isSlotActive = false;
        qrMode = 'profile'; // Switch to profile mode when no active slot
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
    if (!kIsWeb) {
      controller.dispose();
    }
    super.dispose();
  }

  void toggleTorch() {
    if (!kIsWeb) {
      setState(() {
        torchOn = !torchOn;
      });
      controller.toggleTorch();
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = attendeeData?['attendee_internal_uid'];
    final screenSize = MediaQuery.of(context).size;
    final isLargeScreen = screenSize.width > 600;
    final isWebOrDesktop = kIsWeb;

    return Padding(
      padding: EdgeInsets.all(isLargeScreen ? 24.0 : 16.0),
      child: Column(
        children: [
          // Mode Toggle for large screens
          if (isLargeScreen)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text('Mode: ', style: TextStyle(fontWeight: FontWeight.bold)),
                    ToggleButtons(
                      isSelected: [qrMode == 'attendance', qrMode == 'profile'],
                      onPressed: (index) {
                        setState(() {
                          qrMode = index == 0 ? 'attendance' : 'profile';
                        });
                      },
                      children: const [
                        Padding(
                          padding: EdgeInsets.symmetric(horizontal: 16),
                          child: Text('Attendance'),
                        ),
                        Padding(
                          padding: EdgeInsets.symmetric(horizontal: 16),
                          child: Text('Profile'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          
          // Slot Information
          if (currentSlot != null && qrMode == 'attendance')
            Card(
              color: isSlotActive ? Colors.green[100] : Colors.orange[100],
              child: Padding(
                padding: EdgeInsets.all(isLargeScreen ? 12.0 : 8.0),
                child: Row(
                  children: [
                    Icon(
                      isSlotActive ? Icons.access_time : Icons.schedule,
                      color: isSlotActive ? Colors.green : Colors.orange,
                      size: isLargeScreen ? 28 : 24,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            currentSlot!['slot_name'] ?? 'Unknown Slot',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: isLargeScreen ? 18 : 16,
                            ),
                          ),
                          Text(
                            'Time: ${currentSlot!['slot_time_frame']}',
                            style: TextStyle(fontSize: isLargeScreen ? 14 : 12),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      isSlotActive ? 'ACTIVE' : 'INACTIVE',
                      style: TextStyle(
                        color: isSlotActive ? Colors.green : Colors.orange,
                        fontWeight: FontWeight.bold,
                        fontSize: isLargeScreen ? 16 : 14,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else if (qrMode == 'profile')
            Card(
              color: Colors.blue[100],
              child: Padding(
                padding: EdgeInsets.all(isLargeScreen ? 12.0 : 8.0),
                child: Row(
                  children: [
                    Icon(
                      Icons.person_search,
                      color: Colors.blue,
                      size: isLargeScreen ? 28 : 24,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Profile View Mode - Scan QR to view attendee details',
                      style: TextStyle(
                        color: Colors.blue[800],
                        fontWeight: FontWeight.w500,
                        fontSize: isLargeScreen ? 16 : 14,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            Card(
              color: Colors.grey[100],
              child: Padding(
                padding: EdgeInsets.all(isLargeScreen ? 12.0 : 8.0),
                child: Row(
                  children: [
                    Icon(
                      Icons.schedule_outlined,
                      color: Colors.grey,
                      size: isLargeScreen ? 28 : 24,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'No active slot - Profile mode enabled',
                      style: TextStyle(
                        color: Colors.grey,
                        fontSize: isLargeScreen ? 16 : 14,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          
          SizedBox(height: isLargeScreen ? 24 : 16),
          
          // QR Scanner with responsive sizing
          Container(
            height: isLargeScreen ? 400 : 300,
            width: isLargeScreen ? 400 : double.infinity,
            clipBehavior: Clip.hardEdge,
            decoration: const BoxDecoration(
              borderRadius: BorderRadius.all(Radius.circular(8.0))
            ),
            child: isWebOrDesktop 
                ? Container(
                    color: Colors.grey[300],
                    child: const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.qr_code_scanner, size: 64, color: Colors.grey),
                          SizedBox(height: 16),
                          Text(
                            'QR Scanner not available on web/desktop',
                            style: TextStyle(color: Colors.grey, fontSize: 16),
                            textAlign: TextAlign.center,
                          ),
                          SizedBox(height: 8),
                          Text(
                            'Please use mobile device for QR scanning',
                            style: TextStyle(color: Colors.grey, fontSize: 14),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  )
                : MobileScanner(
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
          
          if (!isWebOrDesktop) // Only show camera controls on mobile
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  icon: Icon(torchOn ? Icons.flash_on : Icons.flash_off),
                  iconSize: isLargeScreen ? 32 : 28,
                  onPressed: toggleTorch,
                ),
                IconButton(
                  icon: const Icon(Icons.cameraswitch),
                  iconSize: isLargeScreen ? 32 : 28,
                  onPressed: () {
                    if (!kIsWeb) controller.switchCamera();
                  },
                ),
              ],
            ),
          
          Container(
            width: deviceWidth,
            padding: EdgeInsets.all(isLargeScreen ? safePadding * 1.5 : safePadding),
            child: Text(
              'Scanned Data: $scannedData',
              style: TextStyle(fontSize: isLargeScreen ? 20 : 18),
            ),
          ),
          
          // Attendee information display
          Container(
            width: deviceWidth,
            padding: EdgeInsets.all(isLargeScreen ? safePadding * 1.5 : safePadding),
            child: attendeeData!.isNotEmpty
            ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Name: ${attendeeData!['attendee_name'] ?? 'Unknown'}',
                  style: TextStyle(fontSize: isLargeScreen ? 20 : 18),
                ), 
                SizedBox(height: isLargeScreen ? safePadding * 1.5 : safePadding),
                
                if (qrMode == 'attendance' && currentSlot != null) ...[
                  Text(
                    'Slot: ${currentSlot!['slot_name']}',
                    style: TextStyle(fontSize: isLargeScreen ? 20 : 18),
                  ), 
                  SizedBox(height: isLargeScreen ? safePadding * 1.5 : safePadding),
                  Text(
                    'Status: ${isPresent ? 'Present' : 'Absent'}',
                    style: TextStyle(
                      fontSize: isLargeScreen ? 20 : 18,
                      color: isPresent ? Colors.green : Colors.red,
                      fontWeight: FontWeight.bold,
                    ),
                  ), 
                  SizedBox(height: isLargeScreen ? safePadding * 1.5 : safePadding),
                ],
                
                // Action buttons
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    // Attendance toggle (only in attendance mode and active slot)
                    if (qrMode == 'attendance' && isSlotActive && currentSlot != null)
                      ElevatedButton(
                        onPressed: () {
                          setState(() {
                            isPresent = !isPresent;
                          });
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: isPresent ? Colors.teal : Colors.deepOrangeAccent,
                          padding: EdgeInsets.symmetric(
                            horizontal: isLargeScreen ? 24 : 16,
                            vertical: isLargeScreen ? 16 : 12,
                          ),
                        ),
                        child: Text(
                          isPresent ? 'Present' : 'Absent',
                          style: TextStyle(fontSize: isLargeScreen ? 16 : 14),
                        ),
                      ),
                    
                    // Profile button
                    ElevatedButton(
                      onPressed: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => AttendeeProfilePage(attendee: attendeeData!),
                          ),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        padding: EdgeInsets.symmetric(
                          horizontal: isLargeScreen ? 24 : 16,
                          vertical: isLargeScreen ? 16 : 12,
                        ),
                      ),
                      child: Text(
                        'View Profile',
                        style: TextStyle(fontSize: isLargeScreen ? 16 : 14),
                      ),
                    ),
                    
                    // Properties button (in profile mode)
                    if (qrMode == 'profile')
                      ElevatedButton(
                        onPressed: () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => PropertyEditorPage(attendee: attendeeData!),
                            ),
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          padding: EdgeInsets.symmetric(
                            horizontal: isLargeScreen ? 24 : 16,
                            vertical: isLargeScreen ? 16 : 12,
                          ),
                        ),
                        child: Text(
                          'Edit Properties',
                          style: TextStyle(
                            fontSize: isLargeScreen ? 16 : 14,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    
                    // Save button (only in attendance mode)
                    if (qrMode == 'attendance' && isSlotActive && currentSlot != null)
                      ElevatedButton(
                        onPressed: () {
                          updateCheckInOut(uid, isPresent);
                          setState(() {
                            scannedData = 'No data scanned yet';
                            isScanning = true;
                            attendeeData = {};
                          });
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          padding: EdgeInsets.symmetric(
                            horizontal: isLargeScreen ? 24 : 16,
                            vertical: isLargeScreen ? 16 : 12,
                          ),
                        ),
                        child: Text(
                          'Save Attendance',
                          style: TextStyle(
                            fontSize: isLargeScreen ? 16 : 14,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    
                    // Scan again button
                    ElevatedButton(
                      onPressed: () {
                        setState(() {
                          scannedData = 'No data scanned yet';
                          isScanning = true;
                          attendeeData = {};
                        });
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.grey,
                        padding: EdgeInsets.symmetric(
                          horizontal: isLargeScreen ? 24 : 16,
                          vertical: isLargeScreen ? 16 : 12,
                        ),
                      ),
                      child: Text(
                        'Scan Again',
                        style: TextStyle(
                          fontSize: isLargeScreen ? 16 : 14,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ) : Text(
              isWebOrDesktop 
                  ? 'QR scanning not available on this platform. Please use a mobile device.'
                  : 'No details available',
              style: TextStyle(
                fontSize: isLargeScreen ? 20 : 18,
                color: isWebOrDesktop ? Colors.orange : null,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}