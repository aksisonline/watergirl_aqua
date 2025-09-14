import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'; // For platform detection
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'dart:convert';
import '../register/attendee_profile.dart';
import '../../services/data_service.dart';
import '../../services/camera_service.dart';

// Conditional import for Windows camera
import 'package:camera/camera.dart' as camera_package;

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final SupabaseClient supabase = Supabase.instance.client;
  final TextEditingController _searchController = TextEditingController();
  final DataService _dataService = DataService();
  final CameraService _cameraService = CameraService();

  List<Map<String, dynamic>> attendeeData = [];
  List<Map<String, dynamic>> _originalData = [];
  List<Map<String, dynamic>> availableProperties = [];
  Map<String, Set<String>> propertyValues = {}; // Track unique values for each property
  List<String> searchSuggestions = [];
  bool _isLoading = false;
  Map<String, dynamic>? currentSlot;
  bool isSlotActive = false;
  MobileScannerController? _qrController;
  Map<String, String> _activeFilters = {}; // Property filters
  bool _showSuggestions = false;
  bool _isOnline = true;
  int _queuedChanges = 0;

  @override
  void initState() {
    super.initState();
    _initializeDataService();
  }

  Future<void> _initializeDataService() async {
    setState(() {
      _isLoading = true;
    });

    try {
      await _dataService.initialize();
      
      // Listen to data streams
      _dataService.attendeesStream.listen((attendees) {
        if (mounted) {
          setState(() {
            _originalData = attendees;
            _extractPropertyValues();
            _filterData(_searchController.text);
            _isLoading = false;
          });
        }
      });
      
      _dataService.connectionStatusStream.listen((isOnline) {
        if (mounted) {
          setState(() {
            _isOnline = isOnline;
          });
          _updateQueuedChangesCount();
        }
      });
      
      _dataService.propertiesStream.listen((properties) {
        if (mounted) {
          setState(() {
            availableProperties = properties;
          });
        }
      });
      
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
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
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

  @override
  void dispose() {
    _searchController.dispose();
    _qrController?.dispose();
    super.dispose();
  }

  void _extractPropertyValues() {
    propertyValues = _dataService.getPropertyValues();
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

  void _filterData(String query) {
    setState(() {
      _updateSearchSuggestions(query);
      attendeeData = _dataService.searchAttendees(query, _activeFilters);
      _sortAttendees();
    });
  }

  void _updateSearchSuggestions(String query) {
    searchSuggestions.clear();
    
    if (query.length > 1) {
      final queryLower = query.toLowerCase();
      
      // Add property-based suggestions
      propertyValues.forEach((property, values) {
        for (final value in values) {
          if (value.toLowerCase().contains(queryLower)) {
            searchSuggestions.add('$property: $value');
          }
        }
      });
      
      // Limit suggestions
      searchSuggestions = searchSuggestions.take(5).toList();
    }
    
    _showSuggestions = query.isNotEmpty && searchSuggestions.isNotEmpty;
  }

  void _applyPropertyFilter(String property, String value) {
    setState(() {
      _activeFilters[property] = value;
      _searchController.clear();
      _showSuggestions = false;
      _filterData('');
    });
  }

  void _removeFilter(String property) {
    setState(() {
      _activeFilters.remove(property);
      _filterData(_searchController.text);
    });
  }

  void _clearAllFilters() {
    setState(() {
      _activeFilters.clear();
      _searchController.clear();
      _showSuggestions = false;
      _filterData('');
    });
  }

  void _showQRScannerModal() async {
    // Initialize camera service if not already done
    if (!_cameraService.isInitialized) {
      await _cameraService.initialize();
    }

    // For Windows, we need to initialize the camera before showing the modal
    if (_cameraService.isWindowsPlatform && _cameraService.cameras.isNotEmpty) {
      await _cameraService.stopCamera(); // Stop any existing camera usage
      await _cameraService.initializeCamera(); // Initialize with saved preference
    } else if (!_cameraService.isWindowsPlatform) {
      _qrController = MobileScannerController();
    }

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _QRScannerModalContent(
        cameraService: _cameraService,
        qrController: _qrController,
        onQRDetected: (scannedData) {
          Navigator.pop(context);
          _searchByQR(scannedData);
        },
        onClose: () {
          _qrController?.dispose();
          _cameraService.stopCamera(); // Stop camera when closing
          Navigator.pop(context);
        },
      ),
    );
  }

  Future<void> _searchByQR(String uid) async {
    // Search in cached data first
    final cachedAttendees = _dataService.attendees;
    final attendee = cachedAttendees.firstWhere(
      (a) => a['attendee_internal_uid'] == uid,
      orElse: () => {},
    );

    if (attendee.isNotEmpty) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => AttendeeProfilePage(attendee: attendee),
        ),
      );
    } else if (_isOnline) {
      // Try server search if online and not in cache
      try {
        final data = await supabase
            .from('attendee_details')
            .select('*')
            .eq('attendee_internal_uid', uid)
            .maybeSingle();

        if (data != null) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => AttendeeProfilePage(attendee: data),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No attendee found with this QR code')),
          );
        }
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error searching: $e')),
        );
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Attendee not found in offline cache')),
      );
    }
  }

  void _sortAttendees() {
    attendeeData.sort((a, b) => (a['attendee_name'] ?? '').compareTo(b['attendee_name'] ?? ''));
  }

  void _showConfirmationDialog(String name, String attendeeId, bool isPresent, int index) async {
    if (!isSlotActive || currentSlot == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No active slot for attendance marking')),
      );
      return;
    }

    final newValue = !isPresent;
    final status = newValue ? 'Present' : 'Absent';
    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Confirm Change'),
          content: Text('Do you want to mark $name as $status for ${currentSlot!['slot_name']}?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Confirm'),
            ),
          ],
        );
      },
    );

    if (result == true) {
      await updateCheckInOut(attendeeId, newValue, index);
    }
  }

  Future<void> updateCheckInOut(String attendeeId, bool newValue, int index) async {
    if (currentSlot == null) return;

    try {
      // Use DataService for optimistic updates and offline queueing
      await _dataService.updateAttendance(
        attendeeId: attendeeId,
        slotId: currentSlot!['slot_id'].toString(),
        isPresent: newValue,
      );
      
      // Update queued changes count
      _updateQueuedChangesCount();
      
      if (!mounted) return;

      // Show feedback based on connection status
      final message = _isOnline 
          ? 'Attendance updated successfully'
          : 'Attendance queued for sync when online';
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: _isOnline ? Colors.green : Colors.orange,
        ),
      );
    } catch (e) {
      print('Error updating attendance: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error updating attendance: $e')),
        );
      }
    }
  }

  bool _getCurrentAttendanceStatus(Map<String, dynamic> attendee) {
    if (currentSlot == null || attendee['attendee_attendance'] == null) {
      return false;
    }

    try {
      final attendance = json.decode(attendee['attendee_attendance']) as List;
      final currentSlotId = currentSlot!['slot_id'].toString();
      
      final slotAttendance = attendance.firstWhere(
        (a) => a['slot_id'].toString() == currentSlotId,
        orElse: () => null,
      );
      
      return slotAttendance?['attendance_bool'] == true;
    } catch (e) {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final isLargeScreen = screenSize.width > 600;

    return Column(
      children: [
        // Connection Status and Sync Info
        if (!_isOnline || _queuedChanges > 0)
          Card(
            color: _isOnline ? Colors.orange[100] : Colors.red[100],
            margin: EdgeInsets.all(isLargeScreen ? 24.0 : 16.0),
            child: Padding(
              padding: EdgeInsets.all(isLargeScreen ? 16.0 : 8.0),
              child: Row(
                children: [
                  Icon(
                    _isOnline ? Icons.sync : Icons.cloud_off,
                    color: _isOnline ? Colors.orange : Colors.red,
                    size: isLargeScreen ? 28 : 24,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _isOnline ? 'Syncing data...' : 'Offline Mode',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: isLargeScreen ? 16 : 14,
                          ),
                        ),
                        if (_queuedChanges > 0)
                          Text(
                            '$_queuedChanges changes queued for sync',
                            style: TextStyle(fontSize: isLargeScreen ? 12 : 10),
                          ),
                        if (!_isOnline)
                          Text(
                            'Data cached locally, changes will sync when online',
                            style: TextStyle(fontSize: isLargeScreen ? 12 : 10),
                          ),
                      ],
                    ),
                  ),
                  if (_isOnline && _queuedChanges > 0)
                    IconButton(
                      icon: const Icon(Icons.sync),
                      onPressed: () async {
                        await _dataService.refreshData();
                        _updateQueuedChangesCount();
                      },
                      tooltip: 'Force sync now',
                    ),
                ],
              ),
            ),
          ),
        // Slot Information
        if (currentSlot != null)
          Card(
            color: isSlotActive ? Colors.green[100] : Colors.orange[100],
            margin: EdgeInsets.all(isLargeScreen ? 24.0 : 16.0),
            child: Padding(
              padding: EdgeInsets.all(isLargeScreen ? 16.0 : 8.0),
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
          ),
        
        // Search Bar with QR Button
        Padding(
          padding: EdgeInsets.symmetric(
            horizontal: isLargeScreen ? 24.0 : 16.0,
            vertical: 8.0,
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  children: [
                    TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        labelText: 'Search by name or properties',
                        border: const OutlineInputBorder(),
                        suffixIcon: _searchController.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear),
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() {
                                    _showSuggestions = false;
                                  });
                                  _filterData('');
                                },
                              )
                            : null,
                      ),
                      onChanged: (value) {
                        _filterData(value);
                      },
                      onTap: () {
                        if (_searchController.text.isNotEmpty) {
                          setState(() {
                            _showSuggestions = true;
                          });
                        }
                      },
                    ),
                    // Search Suggestions
                    if (_showSuggestions && searchSuggestions.isNotEmpty)
                      Container(
                        width: double.infinity,
                        constraints: const BoxConstraints(maxHeight: 150),
                        decoration: BoxDecoration(
                          color: Theme.of(context).cardColor,
                          border: Border.all(color: Colors.grey[300]!),
                          borderRadius: const BorderRadius.vertical(bottom: Radius.circular(8)),
                        ),
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: searchSuggestions.length,
                          itemBuilder: (context, index) {
                            final suggestion = searchSuggestions[index];
                            final parts = suggestion.split(': ');
                            if (parts.length == 2) {
                              return ListTile(
                                dense: true,
                                leading: const Icon(Icons.label),
                                title: Text(suggestion),
                                onTap: () {
                                  _applyPropertyFilter(parts[0], parts[1]);
                                },
                              );
                            }
                            return const SizedBox.shrink();
                          },
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // QR Button
              Container(
                decoration: BoxDecoration(
                  color: _cameraService.isWindowsPlatform || !kIsWeb ? Theme.of(context).primaryColor : Colors.grey[300],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: IconButton(
                  icon: Icon(
                    Icons.qr_code_scanner,
                    color: _cameraService.isWindowsPlatform || !kIsWeb ? Colors.white : Colors.grey[600],
                    size: isLargeScreen ? 28 : 24,
                  ),
                  onPressed: _cameraService.isWindowsPlatform || !kIsWeb ? _showQRScannerModal : null,
                  tooltip: _cameraService.isWindowsPlatform || !kIsWeb
                      ? 'Scan QR code'
                      : 'QR scanner not available on web',
                ),
              ),
            ],
          ),
        ),

        // Property Filter Chips
        if (propertyValues.isNotEmpty)
          Container(
            padding: EdgeInsets.symmetric(horizontal: isLargeScreen ? 24.0 : 16.0),
            height: 60,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                // Active filters
                ..._activeFilters.entries.map((filter) => Container(
                  margin: const EdgeInsets.only(right: 8),
                  child: Chip(
                    label: Text('${filter.key}: ${filter.value}'),
                    deleteIcon: const Icon(Icons.close, size: 18),
                    onDeleted: () => _removeFilter(filter.key),
                    backgroundColor: Theme.of(context).primaryColor.withAlpha(51),
                  ),
                )),
                
                // Clear all filters button
                if (_activeFilters.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(right: 16),
                    child: ActionChip(
                      label: const Text('Clear All'),
                      onPressed: _clearAllFilters,
                      backgroundColor: Colors.red.withAlpha(26),
                    ),
                  ),
                
                // Property filter buttons
                ...propertyValues.entries.map((property) {
                  if (_activeFilters.containsKey(property.key)) return const SizedBox.shrink();
                  
                  return Container(
                    margin: const EdgeInsets.only(right: 8),
                    child: ActionChip(
                      label: Text('${property.key} (${property.value.length})'),
                      onPressed: () => _showPropertyFilterDialog(property.key, property.value),
                      backgroundColor: Theme.of(context).primaryColor.withAlpha(26),
                    ),
                  );
                }),
              ],
            ),
          ),
        
        _isLoading
        ? const CircularProgressIndicator()
        : attendeeData.isEmpty
          ? Expanded(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.search_off,
                      size: 64,
                      color: Colors.grey[400],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _activeFilters.isNotEmpty || _searchController.text.isNotEmpty
                          ? 'No results found'
                          : 'No attendees available',
                      style: TextStyle(
                        fontSize: 18,
                        color: Colors.grey[600],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _activeFilters.isNotEmpty || _searchController.text.isNotEmpty
                          ? 'Try adjusting your search or filters'
                          : 'No attendee data has been loaded yet',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[500],
                      ),
                      textAlign: TextAlign.center,
                    ),
                    if (_activeFilters.isNotEmpty || _searchController.text.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: ElevatedButton(
                          onPressed: () {
                            _searchController.clear();
                            _clearAllFilters();
                          },
                          child: const Text('Clear All'),
                        ),
                      ),
                  ],
                ),
              ),
            )
          : Expanded(
              child: ListView.builder(
                itemCount: attendeeData.length,
                itemBuilder: (context, index) {
                  final item = attendeeData[index];
                  final isPresent = _getCurrentAttendanceStatus(item);
                  final attendeeId = item['attendee_internal_uid'];
                  final attendeeName = item['attendee_name'] ?? 'Unknown';
                  return Card(
                    margin: EdgeInsets.symmetric(
                      horizontal: isLargeScreen ? 24.0 : 16.0,
                      vertical: 4.0,
                    ),
                    child: ListTile(
                      title: Text(
                        attendeeName,
                        style: TextStyle(
                          fontSize: isLargeScreen ? 18 : 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('ID: ${attendeeId ?? 'No ID'}'),
                          if (item['attendee_properties'] != null)
                            Wrap(
                              children: _buildPropertyChips(item['attendee_properties'], isLargeScreen),
                            ),
                        ],
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: Icon(
                              Icons.person,
                              size: isLargeScreen ? 28 : 24,
                            ),
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => AttendeeProfilePage(
                                    attendee: item,
                                    onPropertyTap: _applyPropertyFilter,
                                  ),
                                ),
                              );
                            },
                            tooltip: 'View Profile',
                          ),
                          if (isSlotActive)
                            ElevatedButton(
                              onPressed: () {
                                _showConfirmationDialog(attendeeName, attendeeId, isPresent, index);
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: isPresent ? Colors.teal : Colors.deepOrangeAccent,
                                padding: EdgeInsets.symmetric(
                                  horizontal: isLargeScreen ? 16 : 12,
                                  vertical: isLargeScreen ? 12 : 8,
                                ),
                              ),
                              child: Text(
                                isPresent ? 'Present' : 'Absent',
                                style: TextStyle(fontSize: isLargeScreen ? 16 : 14),
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
      ],
    );
  }

  void _showPropertyFilterDialog(String property, Set<String> values) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Filter by $property'),
        content: SizedBox(
          width: double.maxFinite,
          height: 300,
          child: ListView.builder(
            itemCount: values.length,
            itemBuilder: (context, index) {
              final value = values.elementAt(index);
              return ListTile(
                title: Text(value),
                trailing: Text(
                  '${_getAttendeeCountForProperty(property, value)} attendees',
                  style: TextStyle(color: Colors.grey[600]),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _applyPropertyFilter(property, value);
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  int _getAttendeeCountForProperty(String property, String value) {
    return _originalData.where((attendee) {
      if (attendee['attendee_properties'] != null) {
        try {
          final properties = json.decode(attendee['attendee_properties']) as Map<String, dynamic>;
          return properties[property]?.toString() == value;
        } catch (e) {
          return false;
        }
      }
      return false;
    }).length;
  }

  List<Widget> _buildPropertyChips(dynamic properties, bool isLargeScreen) {
    if (properties == null) return [];

    try {
      final Map<String, dynamic> propertiesMap = properties is String
          ? json.decode(properties)
          : properties as Map<String, dynamic>;

      return propertiesMap.entries.map((entry) {
        return Padding(
          padding: const EdgeInsets.only(right: 4.0, top: 4.0),
          child: Chip(
            label: Text(
              '${entry.key}: ${entry.value}',
              style: TextStyle(fontSize: isLargeScreen ? 12 : 10),
            ),
            padding: EdgeInsets.all(isLargeScreen ? 4 : 2),
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        );
      }).toList();
    } catch (e) {
      return [Text('Error parsing properties: $e')];
    }
  }
}


class _QRScannerModalContent extends StatelessWidget {
  final CameraService cameraService;
  final MobileScannerController? qrController;
  final Function(String) onQRDetected;
  final VoidCallback onClose;

  const _QRScannerModalContent({
    required this.cameraService,
    this.qrController,
    required this.onQRDetected,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.8,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Scan QR Code',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: onClose,
                ),
              ],
            ),
          ),
          // Show current camera info for Windows (read-only)
          if (cameraService.isWindowsPlatform && cameraService.cameras.isNotEmpty)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue[200]!),
              ),
              child: Row(
                children: [
                  Icon(Icons.camera_alt, color: Colors.blue[700], size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Using: ${cameraService.cameras[cameraService.selectedCameraIndex].name}',
                      style: TextStyle(
                        color: Colors.blue[800],
                        fontWeight: FontWeight.w500,
                        fontSize: 14,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    'Set in QR Scanner',
                    style: TextStyle(
                      color: Colors.blue[600],
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: cameraService.isWindowsPlatform
                ? _buildWindowsCameraPreview()
                : MobileScanner(
                    controller: qrController!,
                    onDetect: (barcode) {
                      for (final code in barcode.barcodes) {
                        final scannedData = code.rawValue ?? '';
                        if (scannedData.isNotEmpty) {
                          onQRDetected(scannedData);
                          break;
                        }
                      }
                    },
                  ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Point your camera at a QR code to find attendee details',
              style: TextStyle(color: Colors.grey[600]),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWindowsCameraPreview() {
    if (cameraService.currentController?.value.isInitialized ?? false) {
      return Container(
        margin: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey[300]!),
          borderRadius: BorderRadius.circular(8),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: AspectRatio(
            aspectRatio: cameraService.currentController!.value.aspectRatio,
            child: camera_package.CameraPreview(cameraService.currentController!),
          ),
        ),
      );
    } else {
      return Container(
        margin: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.grey[300],
          borderRadius: BorderRadius.circular(8),
        ),
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
  }
}
