import 'package:watergirl_aqua/dimensions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'; // For platform detection
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:convert';
import 'dart:io' show Platform;
import '../register/attendee_profile.dart';
import '../register/property_editor.dart';
import '../../services/data_service.dart';

// Conditional import for Windows camera
import 'package:camera/camera.dart' as camera_package;

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
  final DataService _dataService = DataService();

  Map<String, dynamic>? attendeeData = {};
  late MobileScannerController controller;
  String scannedData = 'No data scanned yet';
  bool torchOn = false; // Track torch state manually
  bool isPresent = false; // Add isPresent as a state variable
  bool isScanning = true; // Add isScanning flag
  Map<String, dynamic>? currentSlot;
  bool isSlotActive = false;
  String qrMode = 'attendance'; // 'attendance' or 'profile' mode
  bool _isOnline = true;
  int _queuedChanges = 0;
  
  // QR scanning buffer variables
  DateTime? _lastScanTime;
  static const Duration _scanBuffer = Duration(seconds: 3);
  
  // Windows camera variables
  List<camera_package.CameraDescription> _cameras = [];
  camera_package.CameraController? _windowsCameraController;
  int _selectedCameraIndex = 0;
  bool _isWindowsPlatform = false;

  Future<void> searchDatabase(String scannedData) async {
    // Check scan buffer - prevent rapid successive scans
    final now = DateTime.now();
    if (_lastScanTime != null && now.difference(_lastScanTime!) < _scanBuffer) {
      print('Scan too soon, ignoring...');
      return;
    }
    _lastScanTime = now;
    
    // Search in cached data first
    final cachedAttendees = _dataService.attendees;
    final data = cachedAttendees.firstWhere(
      (a) => a['attendee_internal_uid'] == scannedData,
      orElse: () => {},
    );

    if (data.isNotEmpty) {
      setState(() {
        attendeeData = data;
        if (data.isNotEmpty) {
          // Check current attendance for the active slot
          _checkCurrentAttendance();
        }
      });
    } else if (_isOnline) {
      // Try server search if online and not in cache
      try {
        final serverData = await supabase
            .from('attendee_details')
            .select()
            .eq('attendee_internal_uid', scannedData)
            .maybeSingle();

        setState(() {
          attendeeData = serverData;
          if (serverData != null) {
            // Check current attendance for the active slot
            _checkCurrentAttendance();
          }
        });
      } catch (e) {
        print('Error searching server: $e');
        setState(() {
          attendeeData = {};
        });
      }
    } else {
      setState(() {
        attendeeData = {};
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Attendee not found in offline cache')),
        );
      }
    }
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
      // Use DataService for optimistic updates and offline queueing
      await _dataService.updateAttendance(
        attendeeId: uid,
        slotId: currentSlot!['slot_id'].toString(),
        isPresent: newValue,
      );
      
      // Update queued changes count
      _updateQueuedChangesCount();
      
      // Update local state
      if (mounted && attendeeData != null) {
        setState(() {
          isPresent = newValue;
        });
      }
      
      // Show feedback based on connection status
      final message = _isOnline 
          ? 'Attendance updated successfully'
          : 'Attendance queued for sync when online';
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: _isOnline ? Colors.green : Colors.orange,
          ),
        );
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
      _lastScanTime = null; // Reset scan buffer
    });
    
    if (_isWindowsPlatform && _windowsCameraController != null) {
      // Restart Windows camera
      _initWindowsCameraController(_selectedCameraIndex);
    } else if (!kIsWeb) {
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
    _isWindowsPlatform = !kIsWeb && Platform.isWindows;
    
    if (!kIsWeb && !_isWindowsPlatform) {
      controller = MobileScannerController();
    }
    
    _initializeDataService();
    
    if (_isWindowsPlatform) {
      _initializeWindowsCamera();
    }
  }
  
  Future<void> _initializeWindowsCamera() async {
    try {
      _cameras = await camera_package.availableCameras();
      if (_cameras.isNotEmpty) {
        await _initWindowsCameraController(_selectedCameraIndex);
      }
    } catch (e) {
      print('Error initializing Windows camera: $e');
    }
  }
  
  Future<void> _initWindowsCameraController(int cameraIndex) async {
    if (_cameras.isEmpty) return;
    
    _windowsCameraController?.dispose();
    
    _windowsCameraController = camera_package.CameraController(
      _cameras[cameraIndex],
      camera_package.ResolutionPreset.high,
    );
    
    try {
      await _windowsCameraController!.initialize();
      if (mounted) {
        setState(() {
          _selectedCameraIndex = cameraIndex;
        });
      }
    } catch (e) {
      print('Error initializing Windows camera controller: $e');
    }
  }

  Future<void> _initializeDataService() async {
    try {
      await _dataService.initialize();
      
      // Listen to connection status
      _dataService.connectionStatusStream.listen((isOnline) {
        if (mounted) {
          setState(() {
            _isOnline = isOnline;
          });
          _updateQueuedChangesCount();
        }
      });
      
      // Listen to slots changes
      _dataService.slotsStream.listen((slots) {
        if (mounted) {
          _updateCurrentSlotFromSlots(slots);
        }
      });
      
      // Initialize current slot
      _updateCurrentSlotFromSlots(_dataService.slots);
      _updateQueuedChangesCount();
      
    } catch (e) {
      print('Error initializing data service: $e');
    }
  }

  void _updateCurrentSlotFromSlots(List<Map<String, dynamic>> slots) {
    final now = DateTime.now();
    final currentTime = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    
    Map<String, dynamic>? newCurrentSlot;
    bool newIsSlotActive = false;
    
    for (final slot in slots) {
      final timeFrame = slot['slot_time_frame'] as String;
      if (_isTimeInRange(currentTime, timeFrame)) {
        newCurrentSlot = slot;
        newIsSlotActive = true;
        break;
      }
    }
    
    setState(() {
      currentSlot = newCurrentSlot;
      isSlotActive = newIsSlotActive;
      qrMode = newIsSlotActive ? 'attendance' : 'profile';
    });
  }

  Future<void> _updateQueuedChangesCount() async {
    final count = await _dataService.getQueuedChangesCount();
    if (mounted) {
      setState(() {
        _queuedChanges = count;
      });
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

  Widget _buildCameraWidget(bool isWebOrDesktop) {
    if (isWebOrDesktop && !_isWindowsPlatform) {
      return Container(
        color: Colors.grey[300],
        child: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.qr_code_scanner, size: 64, color: Colors.grey),
              SizedBox(height: 16),
              Text(
                'QR Scanner not available on web',
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
      );
    } else if (_isWindowsPlatform) {
      if (_windowsCameraController?.value.isInitialized ?? false) {
        return camera_package.CameraPreview(_windowsCameraController!);
      } else {
        return Container(
          color: Colors.grey[300],
          child: const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text(
                  'Initializing Windows Camera...',
                  style: TextStyle(color: Colors.grey, fontSize: 16),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        );
      }
    } else {
      return MobileScanner(
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
      );
    }
  }

  @override
  void dispose() {
    if (!kIsWeb && !_isWindowsPlatform) {
      controller.dispose();
    }
    _windowsCameraController?.dispose();
    super.dispose();
  }

  void toggleTorch() {
    if (_isWindowsPlatform && _windowsCameraController != null) {
      // Windows camera torch handling
      setState(() {
        torchOn = !torchOn;
      });
      _windowsCameraController!.setFlashMode(
        torchOn ? camera_package.FlashMode.torch : camera_package.FlashMode.off
      );
    } else if (!kIsWeb) {
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
          // Connection Status and Sync Info
          if (!_isOnline || _queuedChanges > 0)
            Card(
              color: _isOnline ? Colors.orange[100] : Colors.red[100],
              margin: EdgeInsets.only(bottom: isLargeScreen ? 16.0 : 8.0),
              child: Padding(
                padding: EdgeInsets.all(isLargeScreen ? 12.0 : 8.0),
                child: Row(
                  children: [
                    Icon(
                      _isOnline ? Icons.sync : Icons.cloud_off,
                      color: _isOnline ? Colors.orange : Colors.red,
                      size: isLargeScreen ? 24 : 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _isOnline ? 'Syncing...' : 'Offline',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: isLargeScreen ? 14 : 12,
                            ),
                          ),
                          if (_queuedChanges > 0)
                            Text(
                              '$_queuedChanges changes queued',
                              style: TextStyle(fontSize: isLargeScreen ? 10 : 8),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
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

          // Windows Camera Selector
          if (_isWindowsPlatform && _cameras.isNotEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text('Camera: ', style: TextStyle(fontWeight: FontWeight.bold)),
                    DropdownButton<int>(
                      value: _selectedCameraIndex,
                      items: _cameras.asMap().entries.map((entry) {
                        final index = entry.key;
                        final camera = entry.value;
                        return DropdownMenuItem<int>(
                          value: index,
                          child: Text('${camera.name} (${camera.lensDirection.name})'),
                        );
                      }).toList(),
                      onChanged: (newIndex) async {
                        if (newIndex != null && newIndex != _selectedCameraIndex) {
                          await _initWindowsCameraController(newIndex);
                        }
                      },
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
            child: _buildCameraWidget(isWebOrDesktop),
          ),
          
          if (!isWebOrDesktop && !_isWindowsPlatform) // Only show mobile camera controls
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
          
          // Windows camera controls
          if (_isWindowsPlatform)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  icon: Icon(torchOn ? Icons.flash_on : Icons.flash_off),
                  iconSize: isLargeScreen ? 32 : 28,
                  onPressed: toggleTorch,
                  tooltip: 'Toggle Flash',
                ),
                const SizedBox(width: 16),
                IconButton(
                  icon: const Icon(Icons.refresh),
                  iconSize: isLargeScreen ? 32 : 28,
                  onPressed: refreshCamera,
                  tooltip: 'Refresh Camera',
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
                            _lastScanTime = null; // Reset scan buffer
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
                          _lastScanTime = null; // Reset scan buffer
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