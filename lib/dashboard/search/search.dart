import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final SupabaseClient supabase = Supabase.instance.client;
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> attendeeData = [];
  List<Map<String, dynamic>> _originalData = []; // Add this line
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    fetchAttendees();
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
        .select('name, email, entry_time');

    if (!mounted) return;

    setState(() {
      _originalData = List<Map<String, dynamic>>.from(data); // Store the full data
      attendeeData = List<Map<String, dynamic>>.from(_originalData);
      _sortAttendees();
      _isLoading = false;
    });
  }

  void _filterData(String query) {
    setState(() {
      attendeeData = _originalData.where((item) {
        final name = item['name'].toLowerCase();
        final email = item['email'].toLowerCase();
        final searchQuery = query.toLowerCase();
        return name.contains(searchQuery) || email.contains(searchQuery);
      }).toList();
      _sortAttendees();
    });
  }

  void _sortAttendees() {
    attendeeData.sort((a, b) => a['name'].compareTo(b['name']));
  }

  void _showConfirmationDialog(String name, String email, bool isPresent, int index) async {
    final newValue = !isPresent;
    final status = newValue ? 'Present' : 'Absent';
    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Confirm Change'),
          content: Text('Do you want to mark $name as $status?'),
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
      await updateCheckInOut(email, newValue, index);
    }
  }

  Future<void> updateCheckInOut(String email, bool newValue, int index) async {
    final currentTime = newValue ? DateTime.now().toIso8601String() : null;
    await supabase
        .from('attendee_details')
        .update({'entry_time': currentTime})
        .eq('email', email);

    if (!mounted) return; // Check if the widget is still mounted

    setState(() {
      attendeeData[index]['entry_time'] = currentTime;
    });
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
              final isPresent = item['entry_time'] != null;
              final email = item['email'];
              return ListTile(
                title: Text(item['name']),
                subtitle: Text(item['email']),
                trailing: ElevatedButton(
                  onPressed: () {
                    _showConfirmationDialog(item['name'], email, isPresent, index);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isPresent ? Colors.teal : Colors.deepOrangeAccent,
                  ),
                  child: Text(isPresent ? 'Present' : 'Absent'),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}