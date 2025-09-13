import 'package:flutter/material.dart';
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
    final data = await supabase.from('attendee_details').select();

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
        final name = attendee['name'].toLowerCase();
        final email = attendee['email'].toLowerCase();
        final searchQuery = query.toLowerCase();
        return name.contains(searchQuery) || email.contains(searchQuery);
      }).toList();
      _sortAttendees();
    });
  }

  void _sortAttendees() {
    attendees.sort((a, b) => a['name'].compareTo(b['name']));
  }

  Future<void> _updateAttendeeUID(Map<String, dynamic> attendee) async {
    final index = attendees.indexOf(attendee);
    if (index != -1) {
      final response = await supabase.from('attendee_details').select('uid').eq('email', attendees[index]['email']).single();
      setState(() {
        attendees[index]['uid'] = response['uid']; // Update the UID here
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
              labelText: 'Search by name or email',
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
              final uidExists = attendee['uid'] != null;
              return ListTile(
                title: Text(attendee['name']),
                subtitle: Text(attendee['email']),
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
                  child: Text(uidExists ? 'UID Exists' : 'Create UID'),
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
