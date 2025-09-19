import 'package:flutter/material.dart';
import 'dart:async';
import '../../services/data_service.dart';

class AttendeeListProvider extends ChangeNotifier {
  final DataService _dataService = DataService();
  List<Map<String, dynamic>> _attendees = [];
  bool _loading = false;
  String? _errorMessage;
  bool _networkError = false;
  StreamSubscription<List<Map<String, dynamic>>>? _attendeesSubscription;

  List<Map<String, dynamic>> get attendees => _attendees;
  bool get loading => _loading;
  String? get errorMessage => _errorMessage;
  bool get networkError => _networkError;

  AttendeeListProvider() {
    _initialize();
  }

  void _initialize() async {
    print('AttendeeListProvider: Starting initialization...');
    _loading = true;
    notifyListeners();
    
    // Ensure DataService is initialized
    await _dataService.initialize();
    print('AttendeeListProvider: DataService initialized');
    
    // Get initial data if available
    _attendees = _dataService.attendees;
    print('AttendeeListProvider: Initial attendees count: ${_attendees.length}');
    print('AttendeeListProvider: Initial attendees data: ${_attendees.map((a) => {'id': a['id'], 'name': a['attendee_name'], 'uid': a['attendee_internal_uid']}).toList()}');
    
    if (_attendees.isNotEmpty) {
      _loading = false;
      notifyListeners();
    }
    
    // Listen to attendees stream from DataService
    _attendeesSubscription = _dataService.attendeesStream.listen(
      (attendees) {
        print('AttendeeListProvider: Stream update received - count: ${attendees.length}');
        print('AttendeeListProvider: Stream attendees data: ${attendees.map((a) => {'id': a['id'], 'name': a['attendee_name'], 'uid': a['attendee_internal_uid']}).toList()}');
        _attendees = attendees;
        _loading = false;
        _errorMessage = null;
        _networkError = false;
        notifyListeners();
        print('AttendeeListProvider: UI updated with ${_attendees.length} attendees');
      },
      onError: (error) {
        print('AttendeeListProvider: Stream error: $error');
        _errorMessage = 'Failed to load attendees: $error';
        _networkError = true;
        _loading = false;
        notifyListeners();
      },
    );
    
    print('AttendeeListProvider: Stream subscription setup complete');
  }

  void setAttendees(List<Map<String, dynamic>> newList) {
    _attendees = newList;
    notifyListeners();
  }

  Future<void> refreshData() async {
    if (_loading) return; // Prevent multiple simultaneous refresh calls
    
    _loading = true;
    _errorMessage = null;
    notifyListeners();
    
    try {
      // Trigger data refresh from DataService
      await _dataService.refreshData();
      _networkError = false;
    } catch (e) {
      _errorMessage = 'Failed to refresh attendees: $e';
      _networkError = true;
    }
    
    _loading = false;
    notifyListeners();
  }

  void _showError(BuildContext context, String message) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: Colors.red),
      );
    });
  }

  @override
  void dispose() {
    _attendeesSubscription?.cancel();
    super.dispose();
  }
}
