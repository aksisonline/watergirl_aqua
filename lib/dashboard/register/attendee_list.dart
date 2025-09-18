import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'; // For platform detection
import 'package:supabase_flutter/supabase_flutter.dart';
import 'qr_register.dart';
import '../../services/data_service.dart';

class AttendeeListNoUIDPage extends StatefulWidget {
  const AttendeeListNoUIDPage({super.key});

  @override
  State<AttendeeListNoUIDPage> createState() => AttendeeListNoUIDPageState();

  static AttendeeListNoUIDPageState? of(BuildContext context) {
    return context.findAncestorStateOfType<AttendeeListNoUIDPageState>();
  }
}

class AttendeeListNoUIDPageState extends State<AttendeeListNoUIDPage> {
  final SupabaseClient supabase = Supabase.instance.client;
  final TextEditingController _searchController = TextEditingController();
  final DataService _dataService = DataService();
  List<Map<String, dynamic>> attendees = [];
  List<Map<String, dynamic>> _originalAttendees = []; // Store the original list here
  bool _isLoading = false;
  bool _isOnline = true;
  int _queuedChanges = 0;

  Future<void> initializeDataService() async {
    setState(() {
      _isLoading = true;
    });

    try {
      await _dataService.initialize();
      
      // Listen to attendee data changes
      _dataService.attendeesStream.listen((attendeeData) {
        if (mounted) {
          setState(() {
            _originalAttendees = attendeeData;
            _filterAttendees(_searchController.text);
            _isLoading = false;
          });
        }
      });
      
      // Listen to connection status changes
      _dataService.connectionStatusStream.listen((isOnline) {
        if (mounted) {
          setState(() {
            _isOnline = isOnline;
          });
          _updateQueuedChangesCount();
        }
      });
      
      // Initialize data if not loaded yet
      if (_dataService.attendees.isNotEmpty) {
        setState(() {
          _originalAttendees = _dataService.attendees;
          _filterAttendees(_searchController.text);
          _isLoading = false;
        });
      }
      
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

  Future<void> _updateQueuedChangesCount() async {
    final count = await _dataService.getQueuedChangesCount();
    if (mounted) {
      setState(() {
        _queuedChanges = count;
      });
    }
  }

  Future<void> fetchAttendeesWithoutUID() async {
    // This method is now replaced by DataService streams
    // Keep for backward compatibility but delegate to refresh
    await _dataService.refreshData();
  }

  @override
  void initState() {
    super.initState();
    initializeDataService();
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
    // This method is now handled by DataService streams
    // The UI will automatically update when the stream emits new data
    // No need to manually refresh individual attendees
  }

  Future<void> refreshList() async {
    await _dataService.refreshData();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Sync status indicator
        if (!_isOnline || _queuedChanges > 0)
          Container(
            width: double.infinity,
            color: _isOnline ? Colors.orange.shade100 : Colors.red.shade100,
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
            child: Row(
              children: [
                Icon(
                  _isOnline ? Icons.sync : Icons.sync_disabled,
                  size: 16,
                  color: _isOnline ? Colors.orange : Colors.red,
                ),
                const SizedBox(width: 8),
                Text(
                  _isOnline 
                    ? (_queuedChanges > 0 ? 'Syncing $_queuedChanges changes...' : 'Online')
                    : 'Offline - $_queuedChanges changes pending',
                  style: TextStyle(
                    fontSize: 12,
                    color: _isOnline ? Colors.orange.shade800 : Colors.red.shade800,
                  ),
                ),
              ],
            ),
          ),
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
                    // Ensure attendee map contains 'id' key for QRRegisterPage
                    final attendeeWithId = Map<String, dynamic>.from(attendee);
                    if (!attendeeWithId.containsKey('id')) {
                      // Try to fetch the id if missing (should not happen, but fallback)
                      final response = await supabase
                          .from('attendee_details')
                          .select('id')
                          .eq('attendee_internal_uid', attendee['attendee_internal_uid'])
                          .maybeSingle();
                      if (response != null && response['id'] != null) {
                        attendeeWithId['id'] = response['id'];
                      }
                    }
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => QRRegisterPage(
                          attendee: attendeeWithId,
                          dataService: _dataService, // Pass DataService to QRRegisterPage
                        ),
                      ),
                    );
                    // No need to call _updateAttendeeUID anymore as DataService handles this
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

