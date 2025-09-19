import 'package:Ploof/dimensions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:async';
import '../register/attendee_profile.dart';
import '../register/property_editor.dart';
import '../../services/data_service.dart';
import 'package:flutter/widgets.dart';
import '../../services/camera_service.dart';
import '../../services/property_validation_service.dart';
import '../../services/notification_service.dart';

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
  // Helper to check if attendee is on interim leave for the current or last slot
  bool _isAttendeeOnInterimLeave() {
    final attendanceData = attendeeData['attendee_attendance'];
    List attendance = [];
    if (attendanceData != null) {
      if (attendanceData is String) {
        final decoded = json.decode(attendanceData);
        if (decoded is List) {
          attendance = decoded;
        } else if (decoded is Map && decoded.isEmpty) {
          attendance = [];
        }
      } else if (attendanceData is List) {
        attendance = attendanceData;
      } else if (attendanceData is Map && attendanceData.isEmpty) {
        attendance = [];
      }
    }
    // Find the most recent slot record (active or not)
    Map? slotAttendance;
    if (currentSlot != null) {
      slotAttendance = attendance.firstWhere(
        (a) => a['slot_id'].toString() == currentSlot!['slot_id'].toString(),
        orElse: () => null,
      );
    }
    // If not found, check the last attendance record
    slotAttendance ??= attendance.isNotEmpty ? attendance.last : null;
    if (slotAttendance != null) {
      final interimLeave = slotAttendance['interim_leave'];
      if (interimLeave == true) {
        return true;
      }
      // Handle nested interim_leave object (e.g., { is_on_leave: true })
      if (interimLeave is Map && interimLeave['is_on_leave'] == true) {
        return true;
      }
    }
    return false;
  }
  final SupabaseClient supabase = Supabase.instance.client;
  final DataService _dataService = DataService();
  final CameraService _cameraService = CameraService();

  Map<String, dynamic> attendeeData = {};
  MobileScannerController? controller;
  String scannedData = 'No data scanned yet';
  bool torchOn = false;
  bool isPresent = false;
  bool isScanning = true;
  Map<String, dynamic>? currentSlot;
  bool isSlotActive = false;
  String qrMode = 'attendance';
  bool _isOnline = true;
  int _queuedChanges = 0;
  List<Map<String, dynamic>> _allSlots = [];

  // QR scanning buffer variables
  DateTime? _lastScanTime;
  static const Duration _scanBufferError = Duration(seconds: 3);
  static const Duration _scanBufferNormal = Duration(seconds: 1);
  int _scanCooldownSeconds = 0;
  Timer? _cooldownTimer;
  String? _lastScannedQR;

  // Interim leave functionality
  bool _showInterimLeaveOptions = false;
  String _currentScannedUid = '';

  Future<void> searchDatabase(String scannedData) async {
    if (_lastScannedQR == scannedData) {
      print('Same QR scanned, ignoring duplicate...');
      _resetForNextScan();
      return;
    }

    final scanBuffer = _scanBufferNormal;

    final now = DateTime.now();
    if (_lastScanTime != null && now.difference(_lastScanTime!) < scanBuffer) {
      print('Scan too soon, ignoring...');
      return;
    }
    _lastScanTime = now;
    _lastScannedQR = scannedData;

    _startScanCooldown(scanBuffer);

    // Validate property settings before proceeding
    final validationResult = await PropertyValidationService.validateBeforeScan(scannedData);
    if (!validationResult.isValid) {
      if (validationResult.conflicts.isNotEmpty) {
        _showPropertyConflictDialog(scannedData, validationResult.conflicts);
        return;
      } else if (validationResult.message != null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(validationResult.message!)),
          );
        }
        _resetForNextScan();
        return;
      }
    }

    final cachedAttendees = _dataService.attendees;
    final data = cachedAttendees.firstWhere(
      (a) => a['attendee_internal_uid'] == scannedData,
      orElse: () => {},
    );

    if (data.isNotEmpty) {
      setState(() {
        attendeeData = data;
        _currentScannedUid = scannedData;
        _checkCurrentAttendance();

        // Determine interim leave status
        final onInterimLeave = _isAttendeeOnInterimLeave();

        // Show interim leave options only if:
        // - Slot is inactive and attendee is on interim leave or not present
        // - Slot is active and attendee is on interim leave (to allow unflagging)
        if (currentSlot != null) {
          if (!isSlotActive) {
            _showInterimLeaveOptions = onInterimLeave || !isPresent;
          } else {
            _showInterimLeaveOptions = onInterimLeave;
          }
        } else {
          _showInterimLeaveOptions = false;
        }

        print('QR: Attendance marking conditions check:');
        print('  - isSlotActive: $isSlotActive');
        print('  - qrMode: $qrMode');
        print('  - currentSlot: ${currentSlot != null ? currentSlot!['slot_name'] : 'null'}');
        print('  - _showInterimLeaveOptions: $_showInterimLeaveOptions');

        // Only auto-mark if not showing interim leave options
        if (isSlotActive && qrMode == 'attendance' && currentSlot != null && !_showInterimLeaveOptions) {
          print('QR: All conditions met, calling _autoMarkAttendance()');
          _autoMarkAttendance();
        } else {
          print('QR: Conditions not met for auto-marking attendance. Reasons:');
          if (!isSlotActive) print('  - isSlotActive is false');
          if (qrMode != 'attendance') print('  - qrMode is not "attendance" (actual: $qrMode)');
          if (currentSlot == null) print('  - currentSlot is null');
          if (_showInterimLeaveOptions) print('  - _showInterimLeaveOptions is true');
        }
      });
    } else if (_isOnline) {
      try {
        final serverData = await supabase
            .from('attendee_details')
            .select()
            .eq('attendee_internal_uid', scannedData)
            .maybeSingle();

        setState(() {
          attendeeData = serverData ?? {};
          _currentScannedUid = scannedData;
          _showInterimLeaveOptions = qrMode == 'attendance' && currentSlot != null && serverData != null;
          
          if (serverData != null) {
            _checkCurrentAttendance();

            // Only auto-mark if not showing interim leave options
            if (isSlotActive && qrMode == 'attendance' && currentSlot != null && !_showInterimLeaveOptions) {
              _autoMarkAttendance();
            }
          }
        });
      } catch (e) {
        print('Error searching server: $e');
        _startScanCooldown(_scanBufferError);
        setState(() {
          attendeeData = {};
          _showInterimLeaveOptions = false;
        });
      }
    } else {
      setState(() {
        attendeeData = {};
        _showInterimLeaveOptions = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Attendee not found in offline cache')),
        );
      }
    }
  }

  void _startScanCooldown(Duration buffer) {
    _cooldownTimer?.cancel();
    setState(() {
      _scanCooldownSeconds = buffer.inSeconds;
    });

    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        _scanCooldownSeconds--;
        if (_scanCooldownSeconds <= 0) {
          timer.cancel();
          _scanCooldownSeconds = 0;
          if (mounted) {
            _resetForNextScan();
          }
        }
      });
    });
  }

  Future<void> _autoMarkAttendance() async {
    if (attendeeData.isEmpty || currentSlot == null) {
      print('QR: _autoMarkAttendance early return - attendeeData.isEmpty: ${attendeeData.isEmpty}, currentSlot: ${currentSlot == null ? 'null' : 'exists'}');
      return;
    }

    final uid = attendeeData['attendee_internal_uid'];
    if (uid == null) {
      print('QR: _autoMarkAttendance early return - uid is null');
      return;
    }

    print('QR: _autoMarkAttendance starting for UID: $uid, Slot: ${currentSlot!['slot_name']}');

    try {
      // Mark attendance and clear interim leave if present
      final result = await _dataService.updateAttendance(
        attendeeId: uid,
        slotId: currentSlot!['slot_id'].toString(),
        isPresent: true,
      );
      // TODO: Ensure backend/data_service clears interim leave flag when marking present

      print('QR: _autoMarkAttendance - updateAttendance call completed successfully, conflict: ${result.wasConflict}');

      _updateQueuedChangesCount();

      if (mounted) {
        setState(() {
          isPresent = true;
        });
      }

      final message = _isOnline
          ? 'Attendance marked as Present'
          : 'Attendance queued for sync when online';

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      }

      Future.delayed(const Duration(milliseconds: 1500), () {
        if (mounted) {
          _resetForNextScan();
        }
      });

    } catch (e) {
      print('Error auto-marking attendance: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error marking attendance: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _resetForNextScan() {
    _cooldownTimer?.cancel();
    setState(() {
      isScanning = true;
      _showInterimLeaveOptions = false;
      _currentScannedUid = '';
    });
  }

  // Property conflict resolution dialog
  void _showPropertyConflictDialog(String attendeeId, List<PropertyConflict> conflicts) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Property Conflict Detected'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('The attendee already has different properties set:'),
            const SizedBox(height: 16),
            ...conflicts.map((conflict) => 
              _buildConflictItem(conflict)
            ).toList(),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              _resetForNextScan();
            },
            child: const Text('Go Back to Settings'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(context).pop();
              // Continue with overriding the properties
              await _continueWithPropertyOverride(attendeeId);
            },
            child: const Text('Continue Anyway'),
          ),
        ],
      ),
    );
  }

  Widget _buildConflictItem(PropertyConflict conflict) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text(
            '${conflict.propertyName}: ',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          Text('${conflict.existingValue} → ${conflict.newValue}'),
        ],
      ),
    );
  }

  Future<void> _continueWithPropertyOverride(String attendeeId) async {
    try {
      final volunteerSettings = await PropertyValidationService.getVolunteerSettings();
      await PropertyValidationService.updateAttendeeProperties(attendeeId, volunteerSettings);
      
      // Continue with normal scanning process
      await searchDatabase(attendeeId);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error updating properties: $e')),
        );
      }
      _resetForNextScan();
    }
  }

  // Handle regular attendance marking
  Future<void> _handleRegularAttendance() async {
    if (attendeeData.isEmpty || currentSlot == null) return;

    final uid = attendeeData['attendee_internal_uid'];
    if (uid == null) return;

    try {
      final result = await _dataService.updateAttendance(
        attendeeId: uid,
        slotId: currentSlot!['slot_id'].toString(),
        isPresent: true,
      );

      _updateQueuedChangesCount();

      if (mounted) {
        setState(() {
          isPresent = true;
          _showInterimLeaveOptions = false;
        });

        // Show appropriate message based on result
        Color snackBarColor = Colors.green;
        String message = _isOnline ? 'Attendance marked as Present' : 'Attendance queued for sync when online';
        
        if (result.wasConflict) {
          snackBarColor = Colors.orange;
          message = result.message;
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: snackBarColor,
            duration: const Duration(seconds: 2),
          ),
        );

        Future.delayed(const Duration(milliseconds: 1500), () {
          if (mounted) {
            _resetForNextScan();
          }
        });
      }
    } catch (e) {
      print('Error marking regular attendance: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error marking attendance: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // Handle interim leave
  Future<void> _handleInterimLeave() async {
    if (attendeeData.isEmpty || currentSlot == null) return;

    final uid = attendeeData['attendee_internal_uid'];
    if (uid == null) return;

    try {
      // Mark as present with interim leave flag
      await _dataService.updateAttendanceWithInterimLeave(
        attendeeId: uid,
        slotId: currentSlot!['slot_id'].toString(),
        isPresent: true,
        isInterimLeave: true,
      );

      _updateQueuedChangesCount();

      if (mounted) {
        setState(() {
          isPresent = true;
          _showInterimLeaveOptions = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_isOnline
                ? 'Marked as Present on Interim Leave'
                : 'Interim leave queued for sync when online'),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 2),
          ),
        );

        // Show notification about the interim leave
        await NotificationService.showNotification(
          title: 'Interim Leave Started',
          body: '${attendeeData['attendee_name']} is now on interim leave',
          payload: 'interim_start:$uid',
        );

        Future.delayed(const Duration(milliseconds: 1500), () {
          if (mounted) {
            _resetForNextScan();
          }
        });
      }
    } catch (e) {
      print('Error marking interim leave: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error marking interim leave: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _checkCurrentAttendance() {
    if (attendeeData.isEmpty || currentSlot == null) {
      isPresent = false;
      return;
    }

    try {
      final attendanceData = attendeeData['attendee_attendance'];
      List attendance = [];
      if (attendanceData != null) {
        if (attendanceData is String) {
          final decoded = json.decode(attendanceData);
          if (decoded is List) {
            attendance = decoded;
          } else if (decoded is Map && decoded.isEmpty) {
            attendance = [];
          }
        } else if (attendanceData is List) {
          attendance = attendanceData;
        } else if (attendanceData is Map && attendanceData.isEmpty) {
          attendance = [];
        }
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
      final result = await _dataService.updateAttendance(
        attendeeId: uid,
        slotId: currentSlot!['slot_id'].toString(),
        isPresent: newValue,
      );

      _updateQueuedChangesCount();

      if (mounted && attendeeData.isNotEmpty) {
        setState(() {
          isPresent = newValue;
        });
      }

      String message = _isOnline
          ? 'Attendance updated successfully'
          : 'Attendance queued for sync when online';
      
      Color snackBarColor = _isOnline ? Colors.green : Colors.orange;
      
      if (result.wasConflict) {
        message = result.message;
        snackBarColor = Colors.orange;
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: snackBarColor,
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

  void refreshCamera() async {
    setState(() {
      isScanning = false;
      attendeeData = {};
      scannedData = 'No data scanned yet';
      _lastScanTime = null;
      _scanCooldownSeconds = 0;
      _lastScannedQR = null;
    });

    _cooldownTimer?.cancel();

    if (_cameraService.isWindowsPlatform) {
      await _cameraService.stopCamera();
      await _cameraService.initializeCamera();
    } else if (controller != null) {
      controller!.stop();
      controller!.start();
    }

    setState(() {
      isScanning = true;
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _initializeServices();
      }
    });
  }

  Future<void> _initializeServices() async {
    try {
      await _cameraService.initialize();
      await _dataService.initialize();
      await NotificationService.initialize();

      // Initialize mobile scanner for non-Windows platforms
      if (!_cameraService.isWindowsPlatform) {
        controller = MobileScannerController();
      }

      _dataService.connectionStatusStream.listen((isOnline) {
        if (mounted) {
          setState(() {
            _isOnline = isOnline;
          });
          _updateQueuedChangesCount();
        }
      });

      _dataService.slotsStream.listen((slots) {
        if (mounted) {
          print('QR: Slots loaded from stream - count: ${slots.length}');
          slots.forEach((slot) {
            print('  - ${slot['slot_name']}: ${slot['slot_time_frame']}');
          });
          setState(() {
            _allSlots = slots;
          });
          _updateCurrentSlotFromSlots(slots);
        }
      });

      _updateCurrentSlotFromSlots(_dataService.slots);
      _updateQueuedChangesCount();

      if (_cameraService.isWindowsPlatform && _cameraService.cameras.isNotEmpty) {
        await _cameraService.initializeCamera();
        if (mounted) {
          setState(() {});
        }
      }

    } catch (e) {
      print('Error initializing services: $e');
    }
  }

  void _updateCurrentSlotFromSlots(List<Map<String, dynamic>> slots) {
    print('QR: _updateCurrentSlotFromSlots called with ${slots.length} slots');
    final now = DateTime.now();
    final currentTime = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    print('QR: Current time: $currentTime');

    Map<String, dynamic>? activeSlot;
    for (final slot in slots) {
      final timeFrame = slot['slot_time_frame'] as String;
      print('QR: Checking slot ${slot['slot_name']} with timeframe: $timeFrame');
      if (_isTimeInRange(currentTime, timeFrame)) {
        print('QR: Slot ${slot['slot_name']} is ACTIVE');
        activeSlot = slot;
        break;
      } else {
        print('QR: Slot ${slot['slot_name']} is INACTIVE');
      }
    }

    setState(() {
      if (activeSlot != null) {
        print('QR: Setting active slot: ${activeSlot['slot_name']}');
        isSlotActive = true;
        currentSlot = activeSlot;
        qrMode = 'attendance';
      } else {
        print('QR: No active slot found');
        isSlotActive = false;
        // Don't nullify currentSlot if it was manually selected
        if (currentSlot == null && _allSlots.isNotEmpty) {
          // Default to first slot if nothing is selected
          // currentSlot = _allSlots.first;
        }
        qrMode = currentSlot != null ? 'attendance' : 'profile';
      }
      print('QR: Final state - isSlotActive: $isSlotActive, qrMode: $qrMode');
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
      print('QR: _isTimeInRange - currentTime: "$currentTime", timeFrame: "$timeFrame"');
      
      final parts = timeFrame.split('-');
      if (parts.length != 2) {
        print('QR: Invalid timeFrame format, parts.length = ${parts.length}');
        return false;
      }

      final startTime = parts[0].trim();
      final endTime = parts[1].trim();
      print('QR: startTime: "$startTime", endTime: "$endTime"');

      final current = _timeToMinutes(currentTime);
      final start = _timeToMinutes(startTime);
      final end = _timeToMinutes(endTime);

      print('QR: current: $current minutes, start: $start minutes, end: $end minutes');
      
      final isInRange = current >= start && current <= end;
      print('QR: Time is in range: $isInRange');
      
      return isInRange;
    } catch (e) {
      print('QR: Error in _isTimeInRange: $e');
      return false;
    }
  }

  int _timeToMinutes(String time) {
    try {
      print('QR: Converting time "$time" to minutes');
      final parts = time.split(':');
      if (parts.length != 2) {
        print('QR: Invalid time format: "$time"');
        return 0;
      }
      final hours = int.parse(parts[0]);
      final minutes = int.parse(parts[1]);
      final totalMinutes = hours * 60 + minutes;
      print('QR: "$time" = $totalMinutes minutes');
      return totalMinutes;
    } catch (e) {
      print('QR: Error parsing time "$time": $e');
      return 0;
    }
  }

 Widget _buildCameraWidget(bool isWebOrDesktop) {
    if (isWebOrDesktop && !_cameraService.isWindowsPlatform) {
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
    } else if (_cameraService.isWindowsPlatform) {
      if (_cameraService.currentController?.value.isInitialized ?? false) {
        return GestureDetector(
          onTapUp: (details) {
            // Same logic as in search.dart
            final Offset tapPosition = details.localPosition;
            final RenderBox renderBox = context.findRenderObject() as RenderBox;
            // It's crucial that the RenderBox is from the CameraPreview itself
            // or a widget that has the exact same size and position as the CameraPreview.
            // If the GestureDetector wraps a parent widget that is larger than the preview,
            // the coordinates will be off.
            final Offset localOffset = renderBox.globalToLocal(tapPosition);

            final double x = localOffset.dx / renderBox.size.width;
            final double y = localOffset.dy / renderBox.size.height;

            if (x >= 0.0 && x <= 1.0 && y >= 0.0 && y <= 1.0) {
               _cameraService.setFocusPoint(Offset(x,y));
            }
          },
          child: AspectRatio(
            aspectRatio: _cameraService.currentController!.value.aspectRatio,
            child: camera_package.CameraPreview(_cameraService.currentController!),
          ),
        );
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
      // MobileScanner for other platforms
      if (controller == null) {
        return const Center(
          child: CircularProgressIndicator(),
        );
      }
      return MobileScanner(
        controller: controller!,
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
    controller?.dispose();
    controller = null;
    _cameraService.dispose();
    _cooldownTimer?.cancel();
    super.dispose();
  }

  void toggleTorch() {
    if (_cameraService.isWindowsPlatform) {
      setState(() {
        torchOn = !torchOn;
      });
      _cameraService.setFlashMode(torchOn);
    } else if (controller != null) {
      setState(() {
        torchOn = !torchOn;
      });
      controller!.toggleTorch();
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = attendeeData['attendee_internal_uid'];
    final screenSize = MediaQuery.of(context).size;
    final isLargeScreen = screenSize.width > 600;
    final isWebOrDesktop = kIsWeb;

    return SingleChildScrollView(
      child: Padding(
        padding: EdgeInsets.all(isLargeScreen ? 24.0 : 16.0),
        child: Column(
          children: [
            // // Connection Status and Sync Info
            // if (!_isOnline || _queuedChanges > 0)
            //   Card(
            //     color: _isOnline ? Colors.orange[100] : Colors.red[100],
            //     margin: EdgeInsets.only(bottom: isLargeScreen ? 16.0 : 8.0),
            //     child: Padding(
            //       padding: EdgeInsets.all(isLargeScreen ? 12.0 : 8.0),
            //       child: Row(
            //         children: [
            //           Icon(
            //             _isOnline ? Icons.sync : Icons.cloud_off,
            //             color: _isOnline ? Colors.orange : Colors.red,
            //             size: isLargeScreen ? 24 : 20,
            //           ),
            //           const SizedBox(width: 8),
            //           Expanded(
            //             child: Column(
            //               crossAxisAlignment: CrossAxisAlignment.start,
            //               children: [
            //                 Text(
            //                   _isOnline ? 'Syncing...' : 'Offline',
            //                   style: TextStyle(
            //                     fontWeight: FontWeight.bold,
            //                     fontSize: isLargeScreen ? 14 : 12,
            //                   ),
            //                 ),
            //                 if (_queuedChanges > 0)
            //                   Text(
            //                     '$_queuedChanges changes queued',
            //                     style: TextStyle(fontSize: isLargeScreen ? 10 : 8),
            //                   ),
            //               ],
            //             ),
            //           ),
            //         ],
            //       ),
            //     ),
            //   ),

            // Mode Toggle (always show, not just for large screens)
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

            // Slot Selector (when no slot is active)
            if (!isSlotActive && _allSlots.isNotEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text('Select Slot: ', style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(width: 8),
                      Flexible(
                        child: DropdownButton<Map<String, dynamic>>(
                          value: currentSlot,
                          hint: const Text("Select a slot"),
                          isExpanded: true,
                          items: _allSlots.map((slot) {
                            return DropdownMenuItem<Map<String, dynamic>>(
                              value: slot,
                              child: Text(
                                slot['slot_name'] ?? 'Unnamed Slot',
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                              ),
                            );
                          }).toList(),
                          onChanged: (newSlot) {
                            if (newSlot != null) {
                              setState(() {
                                currentSlot = newSlot;
                                qrMode = 'attendance';
                                _checkCurrentAttendance();
                              });
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            // Windows Camera Selector
            if (_cameraService.isWindowsPlatform && _cameraService.cameras.isNotEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text('Camera: ', style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(width: 8),
                      Flexible(
                        child: DropdownButton<int>(
                          value: _cameraService.selectedCameraIndex,
                          isExpanded: true,
                          items: _cameraService.cameras.asMap().entries.map((entry) {
                            final index = entry.key;
                            final camera = entry.value;
                            return DropdownMenuItem<int>(
                              value: index,
                              child: Text(
                                camera.name,
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                              ),
                            );
                          }).toList(),
                          onChanged: (newIndex) async {
                            if (newIndex != null && newIndex != _cameraService.selectedCameraIndex) {
                              await _cameraService.initializeCamera(newIndex);
                              if (mounted) {
                                setState(() {}); // Ensure UI updates after camera switch
                              }
                            }
                          },
                        ),
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
                      Expanded(
                        child: Text(
                          'Profile View Mode - Scan QR to view attendee details',
                          style: TextStyle(
                            color: Colors.blue[800],
                            fontWeight: FontWeight.w500,
                            fontSize: isLargeScreen ? 16 : 14,
                          ),
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

            // // Scan Cooldown Indicator
            // if (_scanCooldownSeconds > 0)
            //   Card(
            //     color: isSlotActive && qrMode == 'attendance' ? Colors.green[100] : Colors.amber[100],
            //     child: Padding(
            //       padding: EdgeInsets.all(isLargeScreen ? 12.0 : 8.0),
            //       child: Row(
            //         mainAxisAlignment: MainAxisAlignment.center,
            //         children: [
            //           Icon(
            //             isSlotActive && qrMode == 'attendance' ? Icons.check_circle : Icons.timer,
            //             color: isSlotActive && qrMode == 'attendance' ? Colors.green[800] : Colors.amber[800],
            //           ),
            //           const SizedBox(width: 8),
            //           Text(
            //             isSlotActive && qrMode == 'attendance'
            //                 ? 'Attendance marked! Next scan in $_scanCooldownSeconds seconds'
            //                 : 'Next scan available in $_scanCooldownSeconds seconds',
            //             style: TextStyle(
            //               color: isSlotActive && qrMode == 'attendance' ? Colors.green[800] : Colors.amber[800],
            //               fontWeight: FontWeight.w500,
            //               fontSize: isLargeScreen ? 16 : 14,
            //             ),
            //           ),
            //         ],
            //       ),
            //     ),
            //   ),

            Container(
              height: isLargeScreen ? 400 : 300,
              width: isLargeScreen ? 400 : double.infinity,
              clipBehavior: Clip.hardEdge,
              decoration: const BoxDecoration(
                borderRadius: BorderRadius.all(Radius.circular(8.0))
              ),
              child: _buildCameraWidget(isWebOrDesktop),
            ),

            // Camera controls
            if (!isWebOrDesktop)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: Icon(torchOn ? Icons.flash_on : Icons.flash_off),
                    iconSize: isLargeScreen ? 32 : 28,
                    onPressed: toggleTorch,
                  ),
                  if (_cameraService.isWindowsPlatform)
                    IconButton(
                      icon: const Icon(Icons.refresh),
                      iconSize: isLargeScreen ? 32 : 28,
                      onPressed: refreshCamera,
                      tooltip: 'Refresh Camera',
                    )
                  else
                    IconButton(
                      icon: const Icon(Icons.cameraswitch),
                      iconSize: isLargeScreen ? 32 : 28,
                      onPressed: () {
                        controller?.switchCamera();
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
              child: attendeeData.isNotEmpty
              ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Name: ${attendeeData['attendee_name'] ?? 'Unknown'}',
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
                      // Interim leave action buttons (when options are shown)
                      if (_showInterimLeaveOptions && qrMode == 'attendance' && currentSlot != null) ...[
                        ElevatedButton.icon(
                          onPressed: _handleRegularAttendance,
                          icon: const Icon(Icons.check_circle, size: 18),
                          label: const Text('Mark Present'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                            padding: EdgeInsets.symmetric(
                              horizontal: isLargeScreen ? 24 : 16,
                              vertical: isLargeScreen ? 16 : 12,
                            ),
                          ),
                        ),
                        ElevatedButton.icon(
                          onPressed: _handleInterimLeave,
                          icon: const Icon(Icons.access_time, size: 18),
                          label: const Text('Interim Leave'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.orange,
                            foregroundColor: Colors.white,
                            padding: EdgeInsets.symmetric(
                              horizontal: isLargeScreen ? 24 : 16,
                              vertical: isLargeScreen ? 16 : 12,
                            ),
                          ),
                        ),
                      ]
                      // Regular action buttons (when interim leave options are not shown)
                      else ...[
                        if (qrMode == 'attendance' && isSlotActive && currentSlot != null)
                          Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: isLargeScreen ? 24 : 16,
                              vertical: isLargeScreen ? 16 : 12,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.green[100],
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.green),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.check_circle, color: Colors.green, size: isLargeScreen ? 20 : 18),
                                const SizedBox(width: 8),
                                Text(
                                  'Auto-marked as Present',
                                  style: TextStyle(
                                    fontSize: isLargeScreen ? 16 : 14,
                                    color: Colors.green[800],
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),

                        if (qrMode == 'attendance' && !isSlotActive && currentSlot != null)
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
                      ],

                      ElevatedButton(
                        onPressed: () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => AttendeeProfilePage(attendee: attendeeData),
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

                      if (qrMode == 'profile')
                        ElevatedButton(
                          onPressed: () async {
                            await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => PropertyEditorPage(attendee: attendeeData),
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

                      // Button to toggle interim leave options
                      if (qrMode == 'attendance' && currentSlot != null && !_showInterimLeaveOptions && !isSlotActive)
                        ElevatedButton.icon(
                          onPressed: () {
                            setState(() {
                              _showInterimLeaveOptions = true;
                            });
                          },
                          icon: const Icon(Icons.schedule, size: 18),
                          label: const Text('Interim Leave'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.orange,
                            foregroundColor: Colors.white,
                            padding: EdgeInsets.symmetric(
                              horizontal: isLargeScreen ? 24 : 16,
                              vertical: isLargeScreen ? 16 : 12,
                            ),
                          ),
                        ),

                      if (qrMode == 'attendance' && !isSlotActive && currentSlot != null && !_showInterimLeaveOptions)
                        ElevatedButton(
                          onPressed: () {
                            updateCheckInOut(uid, isPresent);
                            _resetForNextScan();
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

                      ElevatedButton(
                        onPressed: () {
                          _resetForNextScan();
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
                isWebOrDesktop && !_cameraService.isWindowsPlatform
                    ? 'QR scanning not available on this platform. Please use a mobile device.'
                    : 'No details available',
                style: TextStyle(
                  fontSize: isLargeScreen ? 20 : 18,
                  color: isWebOrDesktop && !_cameraService.isWindowsPlatform ? Colors.orange : null,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
