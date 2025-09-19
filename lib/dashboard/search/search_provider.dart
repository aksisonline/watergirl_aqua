import 'package:flutter/material.dart';
import 'dart:async';
import '../../services/data_service.dart';

class SearchProvider extends ChangeNotifier {
  final DataService _dataService = DataService();
  List<Map<String, dynamic>> _attendeeData = [];
  List<Map<String, dynamic>> _originalData = [];
  bool _isLoading = false;
  StreamSubscription<List<Map<String, dynamic>>>? _attendeesSubscription;

  List<Map<String, dynamic>> get attendeeData => _attendeeData;
  bool get isLoading => _isLoading;

  SearchProvider() {
    _initialize();
  }

  void _initialize() async {
    print('SearchProvider: Starting initialization...');
    _isLoading = true;
    notifyListeners();
    
    // Ensure DataService is initialized
    await _dataService.initialize();
    print('SearchProvider: DataService initialized');
    
    // Get initial data if available
    final initialData = _dataService.attendees;
    print('SearchProvider: Initial attendees count: ${initialData.length}');
    print('SearchProvider: Initial attendees data: ${initialData.map((a) => {'id': a['id'], 'name': a['attendee_name'], 'uid': a['attendee_internal_uid']}).toList()}');
    
    if (initialData.isNotEmpty) {
      _originalData = initialData;
      _attendeeData = List<Map<String, dynamic>>.from(initialData);
      _isLoading = false;
      notifyListeners();
    }
    
    // Listen to attendees stream from DataService
    _attendeesSubscription = _dataService.attendeesStream.listen(
      (attendees) {
        print('SearchProvider: Stream update received - count: ${attendees.length}');
        print('SearchProvider: Stream attendees data: ${attendees.map((a) => {'id': a['id'], 'name': a['attendee_name'], 'uid': a['attendee_internal_uid']}).toList()}');
        _originalData = attendees;
        _attendeeData = List<Map<String, dynamic>>.from(attendees);
        _isLoading = false;
        notifyListeners();
        print('SearchProvider: UI updated with ${_attendeeData.length} attendees');
      },
      onError: (error) {
        print('SearchProvider: Stream error: $error');
        _isLoading = false;
        notifyListeners();
      },
    );
    
    print('SearchProvider: Stream subscription setup complete');
  }

  void filterData(String query) {
    if (query.isEmpty) {
      _attendeeData = List<Map<String, dynamic>>.from(_originalData);
    } else {
      _attendeeData = _originalData.where((attendee) {
        final name = attendee['attendee_name']?.toLowerCase() ?? '';
        return name.contains(query.toLowerCase());
      }).toList();
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _attendeesSubscription?.cancel();
    super.dispose();
  }
}
