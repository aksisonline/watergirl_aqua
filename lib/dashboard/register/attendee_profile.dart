import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:convert';
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

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // Load properties
      if (widget.attendee['attendee_properties'] != null) {
        properties = json.decode(widget.attendee['attendee_properties']);
      }

      // Load attendance history
      if (widget.attendee['attendee_attendance'] != null) {
        final attendanceData = json.decode(widget.attendee['attendee_attendance']);
        if (attendanceData is List) {
          attendanceHistory = List<Map<String, dynamic>>.from(attendanceData);
        }
      }

      // Load slots data for displaying slot names
      final slotsData = await supabase.from('slots').select('*');
      slots = List<Map<String, dynamic>>.from(slotsData);

    } catch (e) {
      print('Error loading data: $e');
    }

    setState(() {
      _isLoading = false;
    });
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
                              
                              return ListTile(
                                leading: Icon(
                                  isPresent ? Icons.check_circle : Icons.cancel,
                                  color: isPresent ? Colors.green : Colors.red,
                                ),
                                title: Text(slotName),
                                subtitle: Text('Slot ID: $slotId'),
                                trailing: Text(
                                  isPresent ? 'Present' : 'Absent',
                                  style: TextStyle(
                                    color: isPresent ? Colors.green : Colors.red,
                                    fontWeight: FontWeight.bold,
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