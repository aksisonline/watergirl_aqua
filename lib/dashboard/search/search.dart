import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'search_provider.dart';

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

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
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
          child: TextField(
            controller: _searchController,
            decoration: const InputDecoration(
              labelText: 'Search by name',
              border: OutlineInputBorder(),
            ),
            onChanged: (query) {
              provider.filterData(query);
            },
          ),
        ),
        isLoading
            ? const CircularProgressIndicator()
            : Expanded(
                child: ListView.builder(
                  itemCount: attendeeData.length,
                  itemBuilder: (context, index) {
                    final attendee = attendeeData[index];
                    return ListTile(
                      title: Text(attendee['attendee_name'] ?? 'Unknown Name'),
                      subtitle: Text(attendee['attendee_internal_uid'] ?? ''),
                      // ...existing code for tags, actions, etc...
                    );
                  },
                ),
              ),
      ],
    );
  }
}

