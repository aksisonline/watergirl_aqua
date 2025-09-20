import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:convert';
import 'dart:async';
import 'property_editor.dart';

class AttendeeProfilePage extends StatefulWidget {
  final Map<String, dynamic> attendee;
  final Function(String, String)? onPropertyTap;

  const AttendeeProfilePage({super.key, required this.attendee, this.onPropertyTap});

  @override
  State<AttendeeProfilePage> createState() => _AttendeeProfilePageState();
}

class _AttendeeProfilePageState extends State<AttendeeProfilePage> {
  final SupabaseClient supabase = Supabase.instance.client;
  List<Map<String, dynamic>> attendanceHistory = [];
  List<Map<String, dynamic>> slots = [];
  Map<String, dynamic> properties = {};
  bool _isLoading = false;
  Timer? _timer;
  DateTime? _interimLeaveStartTime;
  Duration _timeOnLeave = Duration.zero;
  bool _isOnInterimLeave = false;

  @override
  void initState() {
    super.initState();
    _loadData();
    _startTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_isOnInterimLeave && _interimLeaveStartTime != null) {
        setState(() {
          _timeOnLeave = DateTime.now().difference(_interimLeaveStartTime!);
        });
      }
    });
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // Load properties
      if (widget.attendee['attendee_properties'] != null) {
        if (widget.attendee['attendee_properties'] is String) {
          properties = json.decode(widget.attendee['attendee_properties']);
        } else if (widget.attendee['attendee_properties'] is Map) {
          properties = Map<String, dynamic>.from(widget.attendee['attendee_properties']);
        }
      }

      // Load attendance history
      if (widget.attendee['attendee_attendance'] != null) {
        final attendanceData = widget.attendee['attendee_attendance'];
        if (attendanceData is String) {
          final decoded = json.decode(attendanceData);
          if (decoded is List) {
            attendanceHistory = List<Map<String, dynamic>>.from(decoded);
          }
        } else if (attendanceData is List) {
          attendanceHistory = List<Map<String, dynamic>>.from(attendanceData);
        }
      }

      // Load slots data for displaying slot names
      final slotsData = await supabase.from('slots').select('*');
      slots = List<Map<String, dynamic>>.from(slotsData);

      // Check interim leave status
      _checkInterimLeaveStatus();

    } catch (e) {
      print('Error loading data: $e');
    }

    setState(() {
      _isLoading = false;
    });
  }

  void _checkInterimLeaveStatus() {
    if (attendanceHistory.isEmpty) return;
    
    // Check the most recent attendance record
    final lastRecord = attendanceHistory.last;
    final interimLeave = lastRecord['interim_leave'];
    
    if (interimLeave == true) {
      _isOnInterimLeave = true;
      _interimLeaveStartTime = DateTime.tryParse(lastRecord['timestamp'] ?? '');
    } else if (interimLeave is Map && interimLeave['is_on_leave'] == true) {
      _isOnInterimLeave = true;
      _interimLeaveStartTime = DateTime.tryParse(interimLeave['out_time'] ?? '');
    } else {
      _isOnInterimLeave = false;
      _interimLeaveStartTime = null;
    }
  }

  String _getSlotName(String slotId) {
    final slot = slots.firstWhere(
      (s) => s['slot_id'].toString() == slotId,
      orElse: () => {'slot_name': 'Unknown Slot'},
    );
    return slot['slot_name'] ?? 'Unknown Slot';
  }

  Future<void> _navigateToPropertyEditor() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PropertyEditorPage(attendee: widget.attendee),
      ),
    );
    
    if (result == true) {
      // Refresh the data after properties are updated
      _loadData();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.attendee['attendee_name'] ?? 'Attendee Profile'),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            onPressed: _navigateToPropertyEditor,
            tooltip: 'Edit Properties',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Basic Info Card
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Basic Information',
                            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 8),
                          Text('Name: ${widget.attendee['attendee_name'] ?? 'Unknown'}'),
                          Text('ID: ${widget.attendee['attendee_internal_uid'] ?? 'No ID'}'),
                        ],
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 16),

                  // Interim Leave Status Card
                  if (_isOnInterimLeave)
                    Card(
                      color: Colors.orange[100],
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.schedule, color: Colors.orange[800]),
                                const SizedBox(width: 8),
                                Text(
                                  'Currently on Interim Leave',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.orange[800],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                const Text('Time away: '),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: _timeOnLeave.inMinutes > 10 ? Colors.red : Colors.orange,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    '${_timeOnLeave.inMinutes}:${(_timeOnLeave.inSeconds % 60).toString().padLeft(2, '0')}',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            if (_timeOnLeave.inMinutes > 10)
                              Container(
                                margin: const EdgeInsets.only(top: 8),
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Colors.red[100],
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: Colors.red),
                                ),
                                child: Row(
                                  children: [
                                    Icon(Icons.warning, color: Colors.red, size: 16),
                                    const SizedBox(width: 8),
                                    const Text(
                                      'Exceeded 10-minute limit',
                                      style: TextStyle(
                                        color: Colors.red,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  
                  if (_isOnInterimLeave) const SizedBox(height: 16),
                  
                  // Properties Card
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'Properties',
                                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                              ),
                              TextButton(
                                onPressed: _navigateToPropertyEditor,
                                child: const Text('Edit'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          if (properties.isEmpty)
                            const Text('No properties set', style: TextStyle(fontStyle: FontStyle.italic))
                          else
                            ...properties.entries.map((entry) => 
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 2),
                                child: widget.onPropertyTap != null
                                    ? GestureDetector(
                                        onTap: () {
                                          widget.onPropertyTap!(entry.key, entry.value.toString());
                                          Navigator.pop(context); // Go back to search page
                                        },
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                                          decoration: BoxDecoration(
                                            color: Theme.of(context).primaryColor.withOpacity(0.1),
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Text('${entry.key}: ${entry.value}'),
                                              const SizedBox(width: 4),
                                              const Icon(Icons.filter_list, size: 16),
                                            ],
                                          ),
                                        ),
                                      )
                                    : Text('${entry.key}: ${entry.value}'),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 16),
                  
                  // Attendance History Card
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Attendance History',
                            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 8),
                          if (attendanceHistory.isEmpty)
                            const Text('No attendance records', style: TextStyle(fontStyle: FontStyle.italic))
                          else
                            ...attendanceHistory.map((attendance) {
                              final slotId = attendance['slot_id'].toString();
                              final isPresent = attendance['attendance_bool'] == true;
                              final slotName = _getSlotName(slotId);
                              final timestamp = attendance['timestamp'];
                              final interimLeave = attendance['interim_leave'];
                              final isOnInterimLeave = interimLeave == true || 
                                                     (interimLeave is Map && interimLeave['is_on_leave'] == true);
                              
                              return Card(
                                margin: const EdgeInsets.symmetric(vertical: 4),
                                child: ListTile(
                                  leading: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        isPresent ? Icons.check_circle : Icons.cancel,
                                        color: isPresent ? Colors.green : Colors.red,
                                      ),
                                      if (isOnInterimLeave)
                                        Container(
                                          margin: const EdgeInsets.only(top: 2),
                                          child: Icon(
                                            Icons.schedule,
                                            color: Colors.orange,
                                            size: 16,
                                          ),
                                        ),
                                    ],
                                  ),
                                  title: Text(slotName),
                                  subtitle: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('Slot ID: $slotId'),
                                      if (timestamp != null)
                                        Text(
                                          'Time: ${DateTime.tryParse(timestamp)?.toLocal().toString().substring(0, 19) ?? timestamp}',
                                          style: const TextStyle(fontSize: 12),
                                        ),
                                      if (isOnInterimLeave)
                                        Container(
                                          margin: const EdgeInsets.only(top: 4),
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: Colors.orange,
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          child: const Text(
                                            'Interim Leave',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                  trailing: Text(
                                    isPresent ? 'Present' : 'Absent',
                                    style: TextStyle(
                                      color: isPresent ? Colors.green : Colors.red,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              );
                            }),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}