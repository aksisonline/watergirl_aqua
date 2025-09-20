import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:convert';
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
                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: uidExists ? Colors.green : Colors.grey,
                          child: Icon(
                            uidExists ? Icons.qr_code : Icons.qr_code_scanner,
                            color: Colors.white,
                          ),
                        ),
                        title: Text(
                          attendee['attendee_name'] ?? 'Unknown Name',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('ID: ${attendee['attendee_internal_uid'] ?? 'No ID'}'),
                            if (attendee['attendee_properties'] != null) ...[
                              const SizedBox(height: 4),
                              Builder(
                                builder: (context) {
                                  // Parse properties for display
                                  Map<String, dynamic> properties = {};
                                  try {
                                    if (attendee['attendee_properties'] is String) {
                                      properties = json.decode(attendee['attendee_properties']);
                                    } else if (attendee['attendee_properties'] is Map) {
                                      properties = Map<String, dynamic>.from(attendee['attendee_properties']);
                                    }
                                  } catch (e) {
                                    return const Text(
                                      'Properties: Invalid format',
                                      style: TextStyle(fontSize: 12, color: Colors.red),
                                    );
                                  }
                                  
                                  if (properties.isEmpty) {
                                    return const Text(
                                      'Properties: None set',
                                      style: TextStyle(fontSize: 12, color: Colors.grey),
                                    );
                                  }
                                  
                                  return Wrap(
                                    spacing: 4,
                                    runSpacing: 2,
                                    children: properties.entries.take(3).map((entry) {
                                      return Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: Colors.blue.withOpacity(0.1),
                                          borderRadius: BorderRadius.circular(8),
                                          border: Border.all(color: Colors.blue.withOpacity(0.3)),
                                        ),
                                        child: Text(
                                          '${entry.key}: ${entry.value}',
                                          style: const TextStyle(
                                            fontSize: 11,
                                            color: Colors.blue,
                                          ),
                                        ),
                                      );
                                    }).toList(),
                                  );
                                },
                              ),
                            ],
                        ],
                      ),
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          ElevatedButton(
                            onPressed: () async {
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
                              backgroundColor: uidExists ? Colors.orange : Colors.blue,
                              minimumSize: const Size(80, 32),
                            ),
                            child: Text(
                              uidExists ? 'Re-register' : 'Assign QR',
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                          if (uidExists)
                            Text(
                              'QR Assigned',
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.green[700],
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                        ],
                      ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                      ),
                    );
                  },
                ),
              ),
      ],
    );
  }
}

