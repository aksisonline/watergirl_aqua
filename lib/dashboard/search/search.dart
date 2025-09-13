import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:convert';
import '../register/attendee_profile.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final SupabaseClient supabase = Supabase.instance.client;
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> attendeeData = [];
  List<Map<String, dynamic>> _originalData = [];
  List<Map<String, dynamic>> availableProperties = [];
  bool _isLoading = false;
  Map<String, dynamic>? currentSlot;
  bool isSlotActive = false;

  @override
  void initState() {
    super.initState();
    fetchAttendees();
    _loadCurrentSlot();
    _loadAvailableProperties();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> fetchAttendees() async {
    setState(() {
      _isLoading = true;
    });
    final data = await supabase
        .from('attendee_details')
        .select('*');

    if (!mounted) return;

    setState(() {
      _originalData = List<Map<String, dynamic>>.from(data);
      attendeeData = List<Map<String, dynamic>>.from(_originalData);
      _sortAttendees();
      _isLoading = false;
    });
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

  Future<void> _loadAvailableProperties() async {
    try {
      final data = await supabase.from('properties').select('*');
      setState(() {
        availableProperties = List<Map<String, dynamic>>.from(data);
      });
    } catch (e) {
      print('Error loading properties: $e');
    }
  }

  void _filterData(String query) {
    setState(() {
      attendeeData = _originalData.where((item) {
        final name = item['attendee_name']?.toLowerCase() ?? '';
        final searchQuery = query.toLowerCase();
        
        // Search by name
        if (name.contains(searchQuery)) return true;
        
        // Search by properties
        if (item['attendee_properties'] != null) {
          try {
            final properties = json.decode(item['attendee_properties']) as Map<String, dynamic>;
            return properties.values.any((value) => 
              value.toString().toLowerCase().contains(searchQuery));
          } catch (e) {
            // Ignore parsing errors
          }
        }
        
        return false;
      }).toList();
      _sortAttendees();
    });
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
      // Get current attendance data
      final currentData = await supabase
          .from('attendee_details')
          .select('attendee_attendance')
          .eq('attendee_internal_uid', attendeeId)
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
          .eq('attendee_internal_uid', attendeeId);

      if (!mounted) return;

      setState(() {
        attendeeData[index]['attendee_attendance'] = json.encode(attendance);
      });
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
    return Column(
      children: [
        // Slot Information
        if (currentSlot != null)
          Card(
            color: isSlotActive ? Colors.green[100] : Colors.orange[100],
            margin: const EdgeInsets.all(16.0),
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
          ),
        
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: TextField(
            controller: _searchController,
            decoration: const InputDecoration(
              labelText: 'Search by name or properties',
              border: OutlineInputBorder(),
            ),
            onChanged: _filterData,
          ),
        ),
        _isLoading
        ? const CircularProgressIndicator()
        : Expanded(
          child: ListView.builder(
            itemCount: attendeeData.length,
            itemBuilder: (context, index) {
              final item = attendeeData[index];
              final isPresent = _getCurrentAttendanceStatus(item);
              final attendeeId = item['attendee_internal_uid'];
              final attendeeName = item['attendee_name'] ?? 'Unknown';
              
              return ListTile(
                title: Text(attendeeName),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('ID: ${attendeeId ?? 'No ID'}'),
                    if (item['attendee_properties'] != null)
                      Text(
                        'Properties: ${_formatProperties(item['attendee_properties'])}',
                        style: const TextStyle(fontSize: 12),
                      ),
                  ],
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.person),
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => AttendeeProfilePage(attendee: item),
                          ),
                        );
                      },
                      tooltip: 'View Profile',
                    ),
                    ElevatedButton(
                      onPressed: isSlotActive ? () {
                        _showConfirmationDialog(attendeeName, attendeeId, isPresent, index);
                      } : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isPresent ? Colors.teal : Colors.deepOrangeAccent,
                      ),
                      child: Text(isPresent ? 'Present' : 'Absent'),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  String _formatProperties(String? propertiesJson) {
    if (propertiesJson == null) return 'None';
    
    try {
      final properties = json.decode(propertiesJson) as Map<String, dynamic>;
      if (properties.isEmpty) return 'None';
      
      return properties.entries
          .map((entry) => '${entry.key}: ${entry.value}')
          .join(', ');
    } catch (e) {
      return 'Invalid data';
    }
  }
}