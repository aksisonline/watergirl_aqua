import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'search_provider.dart';
import '../register/attendee_profile.dart';
import 'dart:convert';

class SearchPage extends StatelessWidget {
  const SearchPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => SearchProvider(),
      child: const _SearchPageView(),
    );
  }
}

class _SearchPageView extends StatefulWidget {
  const _SearchPageView();

  @override
  State<_SearchPageView> createState() => _SearchPageViewState();
}

class _SearchPageViewState extends State<_SearchPageView> {
  final TextEditingController _searchController = TextEditingController();
  String _selectedPropertyFilter = '';
  String _selectedPropertyValue = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // Helper to parse attendee properties
  Map<String, dynamic> _getAttendeeProperties(Map<String, dynamic> attendee) {
    try {
      if (attendee['attendee_properties'] != null) {
        if (attendee['attendee_properties'] is String) {
          return json.decode(attendee['attendee_properties']);
        } else if (attendee['attendee_properties'] is Map) {
          return Map<String, dynamic>.from(attendee['attendee_properties']);
        }
      }
    } catch (e) {
      print('Error parsing properties: $e');
    }
    return {};
  }

  // Helper to check interim leave status
  bool _isOnInterimLeave(Map<String, dynamic> attendee) {
    try {
      final attendanceData = attendee['attendee_attendance'];
      if (attendanceData == null) return false;
      
      List attendance = [];
      if (attendanceData is String) {
        final decoded = json.decode(attendanceData);
        if (decoded is List) {
          attendance = decoded;
        }
      } else if (attendanceData is List) {
        attendance = attendanceData;
      }
      
      // Check the most recent attendance record for interim leave
      if (attendance.isNotEmpty) {
        final lastRecord = attendance.last;
        final interimLeave = lastRecord['interim_leave'];
        if (interimLeave == true) return true;
        if (interimLeave is Map && interimLeave['is_on_leave'] == true) return true;
      }
    } catch (e) {
      print('Error checking interim leave: $e');
    }
    return false;
  }

  // Handle property filter selection
  void _onPropertyFilterSelected(String propertyName, String propertyValue) {
    setState(() {
      _selectedPropertyFilter = propertyName;
      _selectedPropertyValue = propertyValue;
      _searchController.text = '$propertyName: $propertyValue';
    });
    final provider = Provider.of<SearchProvider>(context, listen: false);
    provider.filterByProperty(propertyName, propertyValue);
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<SearchProvider>(context);
    final attendeeData = provider.attendeeData;
    final isLoading = provider.isLoading;

    print('SearchPageView: Building with ${attendeeData.length} attendees');
    print('SearchPageView: Loading state: $isLoading');
    print('SearchPageView: Attendees being displayed: ${attendeeData.map((a) => {'id': a['id'], 'name': a['attendee_name'], 'uid': a['attendee_internal_uid']}).toList()}');

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  labelText: 'Search by name, email, or property',
                  border: const OutlineInputBorder(),
                  suffixIcon: _selectedPropertyFilter.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            setState(() {
                              _selectedPropertyFilter = '';
                              _selectedPropertyValue = '';
                              _searchController.clear();
                            });
                            provider.filterData('');
                          },
                        )
                      : null,
                ),
                onChanged: (query) {
                  if (_selectedPropertyFilter.isEmpty) {
                    provider.filterData(query);
                  }
                },
              ),
              if (_selectedPropertyFilter.isNotEmpty)
                Container(
                  margin: const EdgeInsets.only(top: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Theme.of(context).primaryColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.filter_list, 
                           size: 16, 
                           color: Theme.of(context).primaryColor),
                      const SizedBox(width: 8),
                      Text(
                        'Filtered by $_selectedPropertyFilter: $_selectedPropertyValue',
                        style: TextStyle(color: Theme.of(context).primaryColor),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        isLoading
            ? const CircularProgressIndicator()
            : Expanded(
                child: ListView.builder(
                  itemCount: attendeeData.length,
                  itemBuilder: (context, index) {
                    final attendee = attendeeData[index];
                    final properties = _getAttendeeProperties(attendee);
                    final isOnLeave = _isOnInterimLeave(attendee);
                    
                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: isOnLeave ? Colors.orange : Colors.blue,
                          child: Icon(
                            isOnLeave ? Icons.schedule : Icons.person,
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
                            if (attendee['attendee_internal_uid'] != null)
                              Text('ID: ${attendee['attendee_internal_uid']}'),
                            if (isOnLeave)
                              Container(
                                margin: const EdgeInsets.only(top: 4),
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.orange,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Text(
                                  'On Interim Leave',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            if (properties.isNotEmpty)
                              Container(
                                margin: const EdgeInsets.only(top: 8),
                                child: Wrap(
                                  spacing: 6,
                                  runSpacing: 4,
                                  children: properties.entries.take(3).map((entry) {
                                    return GestureDetector(
                                      onTap: () => _onPropertyFilterSelected(entry.key, entry.value.toString()),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: Theme.of(context).primaryColor.withOpacity(0.1),
                                          borderRadius: BorderRadius.circular(12),
                                          border: Border.all(
                                            color: Theme.of(context).primaryColor.withOpacity(0.3),
                                          ),
                                        ),
                                        child: Text(
                                          '${entry.key}: ${entry.value}',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Theme.of(context).primaryColor,
                                          ),
                                        ),
                                      ),
                                    );
                                  }).toList(),
                                ),
                              ),
                          ],
                        ),
                        trailing: Icon(
                          Icons.arrow_forward_ios,
                          size: 16,
                          color: Colors.grey[600],
                        ),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => AttendeeProfilePage(
                                attendee: attendee,
                                onPropertyTap: _onPropertyFilterSelected,
                              ),
                            ),
                          );
                        },
                      ),
                    );
                  },
                ),
              ),
      ],
    );
  }
}

