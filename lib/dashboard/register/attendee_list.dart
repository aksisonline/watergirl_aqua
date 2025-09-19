import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'attendee_list_provider.dart';
import 'qr_register.dart';

class AttendeeListNoUIDPage extends StatelessWidget {
  const AttendeeListNoUIDPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AttendeeListProvider(),
      child: const _AttendeeListView(),
    );
  }
}

class _AttendeeListView extends StatefulWidget {
  const _AttendeeListView();

  @override
  State<_AttendeeListView> createState() => _AttendeeListViewState();
}

class _AttendeeListViewState extends State<_AttendeeListView> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<AttendeeListProvider>(context);
    final attendees = provider.attendees.where((attendee) {
      final name = attendee['attendee_name']?.toLowerCase() ?? '';
      return name.contains(_searchQuery.toLowerCase());
    }).toList();

    print('AttendeeListView: Building with ${provider.attendees.length} total attendees');
    print('AttendeeListView: Filtered to ${attendees.length} attendees for query: "$_searchQuery"');
    print('AttendeeListView: Attendees being displayed: ${attendees.map((a) => {'id': a['id'], 'name': a['attendee_name'], 'uid': a['attendee_internal_uid']}).toList()}');

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
            onChanged: (query) {
              setState(() {
                _searchQuery = query;
              });
            },
          ),
        ),
        provider.loading
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
                          Text('ID: ${attendee['attendee_internal_uid'] ?? 'No ID'}'),
                          if (attendee['attendee_properties'] != null)
                            Text('Properties: ${attendee['attendee_properties']}'),
                        ],
                      ),
                      trailing: ElevatedButton(
                        onPressed: uidExists
                            ? null
                            : () async {
                                final attendeeWithId = Map<String, dynamic>.from(attendee);
                                if (!attendeeWithId.containsKey('id')) {
                                  // TODO: Optionally fetch id if needed
                                }
                                await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => QRRegisterPage(attendee: attendeeWithId),
                                  ),
                                );
                                // Data will be updated automatically via stream
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

