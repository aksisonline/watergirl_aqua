import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'; // For platform detection
import 'package:supabase_flutter/supabase_flutter.dart';
import 'qr_register.dart';

class AttendeeListNoUIDPage extends StatefulWidget {
  const AttendeeListNoUIDPage({super.key});

  @override
  State<AttendeeListNoUIDPage> createState() => _AttendeeListNoUIDPageState();
}

class _AttendeeListNoUIDPageState extends State<AttendeeListNoUIDPage> {
  final SupabaseClient supabase = Supabase.instance.client;
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> attendees = [];
  List<Map<String, dynamic>> _originalAttendees = []; // Store the original list here
  bool _isLoading = false;

  Future<void> fetchAttendeesWithoutUID() async {
    setState(() {
      _isLoading = true;
    });
    final data = await supabase.from('attendee_details').select('attendee_internal_uid, attendee_name, attendee_properties, attendee_attendance');

    if (!mounted) return; // Check if the widget is still mounted

    setState(() {
      _originalAttendees = List<Map<String, dynamic>>.from(data); // Save original data
      attendees = List<Map<String, dynamic>>.from(_originalAttendees); // Set filtered data
      _sortAttendees();
      _isLoading = false;
    });
  }

  @override
  void initState() {
    super.initState();
    fetchAttendeesWithoutUID();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _filterAttendees(String query) {
    setState(() {
      attendees = _originalAttendees.where((attendee) {
        final name = attendee['attendee_name']?.toLowerCase() ?? '';
        final searchQuery = query.toLowerCase();
        return name.contains(searchQuery);
      }).toList();
      _sortAttendees();
    });
  }

  void _sortAttendees() {
    attendees.sort((a, b) => (a['attendee_name'] ?? '').compareTo(b['attendee_name'] ?? ''));
  }

  Future<void> _updateAttendeeUID(Map<String, dynamic> attendee) async {
    final index = attendees.indexOf(attendee);
    if (index != -1) {
      final response = await supabase.from('attendee_details').select('attendee_internal_uid').eq('attendee_internal_uid', attendees[index]['attendee_internal_uid']).single();
      setState(() {
        attendees[index]['attendee_internal_uid'] = response['attendee_internal_uid']; // Update the UID here
        _sortAttendees();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: TextField(
            controller: _searchController,
            decoration: const InputDecoration(
              labelText: 'Search by name',
              border: OutlineInputBorder(),
            ),
            onChanged: _filterAttendees,
          ),
        ),
        _isLoading
            ? const CircularProgressIndicator()
            : Expanded(
          child: ListView.builder(
            itemCount: attendees.length,
            itemBuilder: (context, index) {
              final attendee = attendees[index];
              final uidExists = attendee['attendee_internal_uid'] != null;
              return ListTile(
                title: Text(attendee['attendee_name'] ?? 'Unknown Name'),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('ID: ${attendee['attendee_internal_uid'] ?? 'No ID'}'),
                    if (attendee['attendee_properties'] != null) 
                      Text('Properties: ${attendee['attendee_properties']}'),
                  ],
                ),
                trailing: ElevatedButton(
                  onPressed: uidExists
                      ? null
                      : () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => QRRegisterPage(attendee: attendee),
                      ),
                    );
                    await _updateAttendeeUID(attendee); // Update the specific attendee
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: uidExists ? Colors.grey : Colors.blue,
                  ),
                  child: Text(uidExists ? 'QR Assigned' : 'Assign QR'),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 0),
              );
            },
          ),
        ),
      ],
    );
  }
}
