import 'dart:async';
import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'offline_service.dart';

/// State management service for app data
class DataService {
  static final DataService _instance = DataService._internal();
  factory DataService() => _instance;
  DataService._internal();

  final SupabaseClient _supabase = Supabase.instance.client;
  final OfflineService _offlineService = OfflineService();
  
  // State streams
  final _attendeesStream = StreamController<List<Map<String, dynamic>>>.broadcast();
  final _propertiesStream = StreamController<List<Map<String, dynamic>>>.broadcast();
  final _slotsStream = StreamController<List<Map<String, dynamic>>>.broadcast();
  final _connectionStatusStream = StreamController<bool>.broadcast();
  final _syncStatusStream = StreamController<SyncStatus>.broadcast();
  
  // Cached data
  List<Map<String, dynamic>> _attendees = [];
  List<Map<String, dynamic>> _properties = [];
  List<Map<String, dynamic>> _slots = [];
  Map<String, dynamic>? _currentSlot;
  bool _isInitialized = false;
  
  // Getters for streams
  Stream<List<Map<String, dynamic>>> get attendeesStream => _attendeesStream.stream;
  Stream<List<Map<String, dynamic>>> get propertiesStream => _propertiesStream.stream;
  Stream<List<Map<String, dynamic>>> get slotsStream => _slotsStream.stream;
  Stream<bool> get connectionStatusStream => _connectionStatusStream.stream;
  Stream<SyncStatus> get syncStatusStream => _syncStatusStream.stream;
  
  // Getters for data
  List<Map<String, dynamic>> get attendees => List.unmodifiable(_attendees);
  List<Map<String, dynamic>> get properties => List.unmodifiable(_properties);
  List<Map<String, dynamic>> get slots => List.unmodifiable(_slots);
  Map<String, dynamic>? get currentSlot => _currentSlot;
  bool get isOnline => _offlineService.isOnline;

  /// Initialize the data service
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    await _offlineService.initialize();
    
    // Listen to connectivity changes
    _offlineService.connectivityStream.listen((isOnline) {
      _connectionStatusStream.add(isOnline);
      if (isOnline) {
        _syncAllData();
      }
    });
    
    // Listen to data updates from offline service
    _offlineService.dataUpdateStream.listen((dataType) {
      _handleDataUpdate(dataType);
    });
    
    // Load initial data (from cache if offline, from server if online)
    await _loadInitialData();
    
    _isInitialized = true;
  }

  /// Load initial data
  Future<void> _loadInitialData() async {
    _syncStatusStream.add(SyncStatus.syncing);
    
    try {
      if (_offlineService.isOnline) {
        // Try to load from server first
        await _loadFromServer();
      } else {
        // Load from cache when offline
        await _loadFromCache();
      }
      
      _syncStatusStream.add(SyncStatus.synced);
    } catch (e) {
      print('Error loading initial data: $e');
      // Fallback to cache
      await _loadFromCache();
      _syncStatusStream.add(SyncStatus.error);
    }
  }

  /// Load data from server and cache it
  Future<void> _loadFromServer() async {
    // Load attendees
    final attendeesData = await _supabase.from('attendee_details').select('*');
    _attendees = List<Map<String, dynamic>>.from(attendeesData);
    await _offlineService.cacheAttendees(_attendees);
    _attendeesStream.add(_attendees);
    
    // Load properties
    final propertiesData = await _supabase.from('properties').select('*');
    _properties = List<Map<String, dynamic>>.from(propertiesData);
    await _offlineService.cacheProperties(_properties);
    _propertiesStream.add(_properties);
    
    // Load slots
    final slotsData = await _supabase.from('slots').select('*');
    _slots = List<Map<String, dynamic>>.from(slotsData);
    await _offlineService.cacheSlots(_slots);
    _slotsStream.add(_slots);
    
    // Determine current slot
    _updateCurrentSlot();
  }

  /// Load data from cache
  Future<void> _loadFromCache() async {
    // Load cached attendees
    _attendees = await _offlineService.getCachedAttendees();
    _attendeesStream.add(_attendees);
    
    // Load cached properties
    _properties = await _offlineService.getCachedProperties();
    _propertiesStream.add(_properties);
    
    // Load cached slots
    _slots = await _offlineService.getCachedSlots();
    _slotsStream.add(_slots);
    
    // Determine current slot
    _updateCurrentSlot();
  }

  /// Handle data updates from offline service
  Future<void> _handleDataUpdate(String dataType) async {
    switch (dataType) {
      case 'attendees':
        _attendees = await _offlineService.getCachedAttendees();
        _attendeesStream.add(_attendees);
        break;
      case 'properties':
        _properties = await _offlineService.getCachedProperties();
        _propertiesStream.add(_properties);
        break;
      case 'slots':
        _slots = await _offlineService.getCachedSlots();
        _slotsStream.add(_slots);
        _updateCurrentSlot();
        break;
    }
  }

  /// Update current slot based on time
  void _updateCurrentSlot() {
    final now = DateTime.now();
    final currentTime = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    
    _currentSlot = null;
    
    for (final slot in _slots) {
      final timeFrame = slot['slot_time_frame'] as String;
      if (_isTimeInRange(currentTime, timeFrame)) {
        _currentSlot = slot;
        break;
      }
    }
  }

  /// Check if current time is in range
  bool _isTimeInRange(String currentTime, String timeFrame) {
    try {
      final parts = timeFrame.split('-');
      if (parts.length != 2) return false;
      
      final startTime = parts[0].trim();
      final endTime = parts[1].trim();
      
      final current = _timeToMinutes(currentTime);
      final start = _timeToMinutes(startTime);
      final end = _timeToMinutes(endTime);
      
      return current >= start && current <= end;
    } catch (e) {
      return false;
    }
  }

  /// Convert time to minutes
  int _timeToMinutes(String time) {
    final parts = time.split(':');
    return int.parse(parts[0]) * 60 + int.parse(parts[1]);
  }

  /// Sync all data from server
  Future<void> _syncAllData() async {
    if (!_offlineService.isOnline) return;
    
    _syncStatusStream.add(SyncStatus.syncing);
    
    try {
      await _loadFromServer();
      await _offlineService.forceSyncNow();
      _syncStatusStream.add(SyncStatus.synced);
    } catch (e) {
      print('Error syncing data: $e');
      _syncStatusStream.add(SyncStatus.error);
    }
  }

  /// Refresh data (manual refresh)
  Future<void> refreshData() async {
    if (_offlineService.isOnline) {
      await _syncAllData();
    } else {
      // Just reload from cache and notify
      await _loadFromCache();
    }
  }

  /// Update attendance for an attendee
  Future<void> updateAttendance({
    required String attendeeId,
    required String slotId,
    required bool isPresent,
  }) async {
    if (_offlineService.isOnline) {
      try {
        // Try to update immediately
        await _updateAttendanceOnServer(attendeeId, slotId, isPresent);
        
        // Update local state immediately
        _updateLocalAttendanceState(attendeeId, slotId, isPresent);
        
      } catch (e) {
        print('Error updating attendance on server: $e');
        // Queue for later sync
        await _offlineService.queueAttendanceChange(
          attendeeId: attendeeId,
          slotId: slotId,
          attendanceBool: isPresent,
        );
        
        // Update local state optimistically
        _updateLocalAttendanceState(attendeeId, slotId, isPresent);
      }
    } else {
      // Queue for later sync when offline
      await _offlineService.queueAttendanceChange(
        attendeeId: attendeeId,
        slotId: slotId,
        attendanceBool: isPresent,
      );
      
      // Update local state optimistically
      _updateLocalAttendanceState(attendeeId, slotId, isPresent);
    }
  }

  /// Update attendance on server
  Future<void> _updateAttendanceOnServer(String attendeeId, String slotId, bool isPresent) async {
    // Get current attendance data
    final currentData = await _supabase
        .from('attendee_details')
        .select('attendee_attendance')
        .eq('attendee_internal_uid', attendeeId)
        .single();

    List<dynamic> attendance = [];
    if (currentData['attendee_attendance'] != null) {
      attendance = json.decode(currentData['attendee_attendance']);
    }

    // Update or add attendance for current slot
    final existingIndex = attendance.indexWhere(
      (a) => a['slot_id'].toString() == slotId,
    );

    if (existingIndex >= 0) {
      attendance[existingIndex]['attendance_bool'] = isPresent;
    } else {
      attendance.add({
        'slot_id': slotId,
        'attendance_bool': isPresent,
      });
    }

    // Update in database
    await _supabase
        .from('attendee_details')
        .update({'attendee_attendance': json.encode(attendance)})
        .eq('attendee_internal_uid', attendeeId);
  }

  /// Update local attendance state optimistically
  void _updateLocalAttendanceState(String attendeeId, String slotId, bool isPresent) {
    final attendeeIndex = _attendees.indexWhere(
      (a) => a['attendee_internal_uid'] == attendeeId,
    );
    
    if (attendeeIndex >= 0) {
      final attendee = Map<String, dynamic>.from(_attendees[attendeeIndex]);
      
      List<dynamic> attendance = [];
      if (attendee['attendee_attendance'] != null) {
        attendance = json.decode(attendee['attendee_attendance']);
      }

      // Update or add attendance for current slot
      final existingIndex = attendance.indexWhere(
        (a) => a['slot_id'].toString() == slotId,
      );

      if (existingIndex >= 0) {
        attendance[existingIndex]['attendance_bool'] = isPresent;
      } else {
        attendance.add({
          'slot_id': slotId,
          'attendance_bool': isPresent,
        });
      }
      
      attendee['attendee_attendance'] = json.encode(attendance);
      _attendees[attendeeIndex] = attendee;
      
      // Cache the updated data
      _offlineService.cacheAttendees(_attendees);
      
      // Notify listeners
      _attendeesStream.add(_attendees);
    }
  }

  /// Get queued changes count
  Future<int> getQueuedChangesCount() async {
    return await _offlineService.getQueuedChangesCount();
  }

  /// Get last sync time
  Future<DateTime?> getLastSyncTime() async {
    return await _offlineService.getLastSyncTime();
  }

  /// Search attendees by query
  List<Map<String, dynamic>> searchAttendees(String query, Map<String, String> filters) {
    return _attendees.where((attendee) {
      // Search by name
      final name = attendee['attendee_name']?.toLowerCase() ?? '';
      final searchQuery = query.toLowerCase();
      bool matchesName = query.isEmpty || name.contains(searchQuery);
      
      // Search by properties
      bool matchesProperties = true;
      if (query.isNotEmpty && attendee['attendee_properties'] != null) {
        try {
          final properties = json.decode(attendee['attendee_properties']) as Map<String, dynamic>;
          matchesProperties = properties.values.any((value) => 
            value.toString().toLowerCase().contains(searchQuery));
          matchesName = matchesName || matchesProperties;
        } catch (e) {
          // Ignore parsing errors
        }
      }
      
      // Apply filters
      bool matchesFilters = true;
      if (filters.isNotEmpty && attendee['attendee_properties'] != null) {
        try {
          final properties = json.decode(attendee['attendee_properties']) as Map<String, dynamic>;
          for (final filter in filters.entries) {
            if (properties[filter.key]?.toString() != filter.value) {
              matchesFilters = false;
              break;
            }
          }
        } catch (e) {
          matchesFilters = false;
        }
      }
      
      return matchesName && matchesFilters;
    }).toList();
  }

  /// Get property values for filtering
  Map<String, Set<String>> getPropertyValues() {
    final propertyValues = <String, Set<String>>{};
    
    for (final attendee in _attendees) {
      if (attendee['attendee_properties'] != null) {
        try {
          final properties = json.decode(attendee['attendee_properties']) as Map<String, dynamic>;
          properties.forEach((key, value) {
            if (!propertyValues.containsKey(key)) {
              propertyValues[key] = <String>{};
            }
            propertyValues[key]!.add(value.toString());
          });
        } catch (e) {
          // Ignore parsing errors
        }
      }
    }
    
    return propertyValues;
  }

  /// Update attendance with interim leave functionality
  Future<void> updateAttendanceWithInterimLeave({
    required String attendeeId,
    required String slotId,
    required bool isPresent,
    required bool isInterimLeave,
  }) async {
    if (_offlineService.isOnline) {
      try {
        // Try to update immediately
        await _updateAttendanceWithInterimLeaveOnServer(
          attendeeId, 
          slotId, 
          isPresent, 
          isInterimLeave
        );
        
        // Update local state immediately
        _updateLocalAttendanceStateWithInterimLeave(
          attendeeId, 
          slotId, 
          isPresent, 
          isInterimLeave
        );
        
      } catch (e) {
        print('Error updating interim leave attendance on server: $e');
        // Queue for later sync
        await _offlineService.queueAttendanceChangeWithInterimLeave(
          attendeeId: attendeeId,
          slotId: slotId,
          attendanceBool: isPresent,
          isInterimLeave: isInterimLeave,
        );
        
        // Update local state optimistically
        _updateLocalAttendanceStateWithInterimLeave(
          attendeeId, 
          slotId, 
          isPresent, 
          isInterimLeave
        );
      }
    } else {
      // Queue for later sync when offline
      await _offlineService.queueAttendanceChangeWithInterimLeave(
        attendeeId: attendeeId,
        slotId: slotId,
        attendanceBool: isPresent,
        isInterimLeave: isInterimLeave,
      );
      
      // Update local state optimistically
      _updateLocalAttendanceStateWithInterimLeave(
        attendeeId, 
        slotId, 
        isPresent, 
        isInterimLeave
      );
    }
  }

  /// Update attendance with interim leave on server
  Future<void> _updateAttendanceWithInterimLeaveOnServer(
    String attendeeId, 
    String slotId, 
    bool isPresent, 
    bool isInterimLeave
  ) async {
    // Get current attendance data
    final currentData = await _supabase
        .from('attendee_details')
        .select('attendee_attendance')
        .eq('attendee_internal_uid', attendeeId)
        .single();

    List<dynamic> attendance = [];
    if (currentData['attendee_attendance'] != null) {
      attendance = json.decode(currentData['attendee_attendance']);
    }

    // Update or add attendance for current slot with interim leave info
    final existingIndex = attendance.indexWhere(
      (a) => a['slot_id'].toString() == slotId,
    );

    final now = DateTime.now();
    final attendanceRecord = {
      'slot_id': slotId,
      'attendance_bool': isPresent,
      'interim_leave': isInterimLeave,
      'out_time': isInterimLeave ? now.toIso8601String() : null,
      'expected_return_time': isInterimLeave 
          ? now.add(const Duration(minutes: 10)).toIso8601String() 
          : null,
      'actual_return_time': null,
    };

    if (existingIndex >= 0) {
      attendance[existingIndex] = attendanceRecord;
    } else {
      attendance.add(attendanceRecord);
    }

    // Update in database
    await _supabase
        .from('attendee_details')
        .update({'attendee_attendance': json.encode(attendance)})
        .eq('attendee_internal_uid', attendeeId);
  }

  /// Update local attendance state with interim leave optimistically
  void _updateLocalAttendanceStateWithInterimLeave(
    String attendeeId, 
    String slotId, 
    bool isPresent, 
    bool isInterimLeave
  ) {
    final attendeeIndex = _attendees.indexWhere(
      (a) => a['attendee_internal_uid'] == attendeeId,
    );
    
    if (attendeeIndex >= 0) {
      final attendee = Map<String, dynamic>.from(_attendees[attendeeIndex]);
      
      List<dynamic> attendance = [];
      if (attendee['attendee_attendance'] != null) {
        if (attendee['attendee_attendance'] is String) {
          attendance = json.decode(attendee['attendee_attendance']);
        } else {
          attendance = List.from(attendee['attendee_attendance']);
        }
      }

      // Update or add attendance for current slot
      final existingIndex = attendance.indexWhere(
        (a) => a['slot_id'].toString() == slotId,
      );

      final now = DateTime.now();
      final attendanceRecord = {
        'slot_id': slotId,
        'attendance_bool': isPresent,
        'interim_leave': isInterimLeave,
        'out_time': isInterimLeave ? now.toIso8601String() : null,
        'expected_return_time': isInterimLeave 
            ? now.add(const Duration(minutes: 10)).toIso8601String() 
            : null,
        'actual_return_time': null,
      };

      if (existingIndex >= 0) {
        attendance[existingIndex] = attendanceRecord;
      } else {
        attendance.add(attendanceRecord);
      }

      attendee['attendee_attendance'] = json.encode(attendance);
      _attendees[attendeeIndex] = attendee;
      
      // Notify listeners
      _attendeesStream.add(_attendees);
    }
  }

  /// Update attendance to mark return from interim leave
  Future<void> updateAttendanceReturn({
    required String attendeeId,
    required String slotId,
  }) async {
    if (_offlineService.isOnline) {
      try {
        // Try to update immediately
        await _updateAttendanceReturnOnServer(attendeeId, slotId);
        
        // Update local state immediately
        _updateLocalAttendanceStateReturn(attendeeId, slotId);
        
      } catch (e) {
        print('Error updating return on server: $e');
        // Queue for later sync
        await _offlineService.queueAttendanceReturn(
          attendeeId: attendeeId,
          slotId: slotId,
        );
        
        // Update local state optimistically
        _updateLocalAttendanceStateReturn(attendeeId, slotId);
      }
    } else {
      // Queue for later sync when offline
      await _offlineService.queueAttendanceReturn(
        attendeeId: attendeeId,
        slotId: slotId,
      );
      
      // Update local state optimistically
      _updateLocalAttendanceStateReturn(attendeeId, slotId);
    }
  }

  /// Update attendance return on server
  Future<void> _updateAttendanceReturnOnServer(String attendeeId, String slotId) async {
    // Get current attendance data
    final currentData = await _supabase
        .from('attendee_details')
        .select('attendee_attendance')
        .eq('attendee_internal_uid', attendeeId)
        .single();

    List<dynamic> attendance = [];
    if (currentData['attendee_attendance'] != null) {
      attendance = json.decode(currentData['attendee_attendance']);
    }

    // Find and update the attendance record for the current slot
    final existingIndex = attendance.indexWhere(
      (a) => a['slot_id'].toString() == slotId,
    );

    if (existingIndex >= 0) {
      attendance[existingIndex]['actual_return_time'] = DateTime.now().toIso8601String();
      attendance[existingIndex]['interim_leave'] = false; // Mark as returned

      // Update in database
      await _supabase
          .from('attendee_details')
          .update({'attendee_attendance': json.encode(attendance)})
          .eq('attendee_internal_uid', attendeeId);
    }
  }

  /// Update local attendance state for return
  void _updateLocalAttendanceStateReturn(String attendeeId, String slotId) {
    final attendeeIndex = _attendees.indexWhere(
      (a) => a['attendee_internal_uid'] == attendeeId,
    );
    
    if (attendeeIndex >= 0) {
      final attendee = Map<String, dynamic>.from(_attendees[attendeeIndex]);
      
      List<dynamic> attendance = [];
      if (attendee['attendee_attendance'] != null) {
        if (attendee['attendee_attendance'] is String) {
          attendance = json.decode(attendee['attendee_attendance']);
        } else {
          attendance = List.from(attendee['attendee_attendance']);
        }
      }

      // Find and update the attendance record for the current slot
      final existingIndex = attendance.indexWhere(
        (a) => a['slot_id'].toString() == slotId,
      );

      if (existingIndex >= 0) {
        attendance[existingIndex]['actual_return_time'] = DateTime.now().toIso8601String();
        attendance[existingIndex]['interim_leave'] = false; // Mark as returned

        attendee['attendee_attendance'] = json.encode(attendance);
        _attendees[attendeeIndex] = attendee;
        
        // Notify listeners
        _attendeesStream.add(_attendees);
      }
    }
  }

  /// Clear all cached data
  Future<void> clearCache() async {
    await _offlineService.clearCache();
    _attendees.clear();
    _properties.clear();
    _slots.clear();
    _currentSlot = null;
    
    _attendeesStream.add(_attendees);
    _propertiesStream.add(_properties);
    _slotsStream.add(_slots);
  }

  /// Dispose resources
  void dispose() {
    _attendeesStream.close();
    _propertiesStream.close();
    _slotsStream.close();
    _connectionStatusStream.close();
    _syncStatusStream.close();
    _offlineService.dispose();
  }
}

/// Sync status enum
enum SyncStatus {
  idle,
  syncing,
  synced,
  error,
}