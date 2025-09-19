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
  
  // Background sync
  Timer? _backgroundSyncTimer;
  DateTime? _lastSyncTime;
  static const Duration _backgroundSyncInterval = Duration(seconds: 5);
  
  // Cache management
  static const int _maxCacheSize = 1000; // Maximum number of attendees to keep in memory
  final Set<String> _dirtyAttendeeIds = {}; // Track attendees with unsent changes
  DateTime? _lastCacheCleanup;
  
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
        _startBackgroundSync(); // Start background sync when online
      } else {
        _stopBackgroundSync(); // Stop background sync when offline
      }
    });
    
    // Listen to data updates from offline service
    _offlineService.dataUpdateStream.listen((dataType) {
      _handleDataUpdate(dataType);
    });
    
    // Load initial data (from cache if offline, from server if online)
    await _loadInitialData();
    
    // Start background sync timer if online
    if (_offlineService.isOnline) {
      _startBackgroundSync();
    }
    
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
    print('DataService: Loading data from server...');
    
    // Load attendees
    final attendeesData = await _supabase.from('attendee_details').select('*');
    final rawAttendees = List<Map<String, dynamic>>.from(attendeesData);
    print('DataService: Loaded ${rawAttendees.length} raw attendees from server');
    
    // Deduplicate by ID (primary key)
    _attendees = _deduplicateAttendees(rawAttendees);
    print('DataService: After deduplication: ${_attendees.length} unique attendees');
    print('DataService: Server attendees sample: ${_attendees.take(3).map((a) => {'id': a['id'], 'name': a['attendee_name'], 'uid': a['attendee_internal_uid']}).toList()}');
    
    // Check for duplicates
    _checkForDuplicates(_attendees, 'server');
    
    await _offlineService.cacheAttendees(_attendees);
    _attendeesStream.add(_attendees);
    print('DataService: Attendees added to stream');
    
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

  /// Check for duplicates in attendee data
  void _checkForDuplicates(List<Map<String, dynamic>> attendees, String source) {
    print('DataService: Checking for duplicates in $source data...');
    
    final ids = <dynamic, int>{};
    final names = <String, int>{};
    final uids = <String, int>{};
    
    for (final attendee in attendees) {
      final id = attendee['id'];
      final name = attendee['attendee_name'];
      final uid = attendee['attendee_internal_uid'];
      
      if (id != null) {
        ids[id] = (ids[id] ?? 0) + 1;
      }
      if (name != null) {
        names[name] = (names[name] ?? 0) + 1;
      }
      if (uid != null && uid.toString().isNotEmpty) {
        uids[uid] = (uids[uid] ?? 0) + 1;
      }
    }
    
    // Report duplicates
    final duplicateIds = ids.entries.where((e) => e.value > 1).toList();
    final duplicateNames = names.entries.where((e) => e.value > 1).toList();
    final duplicateUIDs = uids.entries.where((e) => e.value > 1).toList();
    
    if (duplicateIds.isNotEmpty) {
      print('DataService: DUPLICATE IDs found in $source: $duplicateIds');
    }
    if (duplicateNames.isNotEmpty) {
      print('DataService: DUPLICATE Names found in $source: $duplicateNames');
    }
    if (duplicateUIDs.isNotEmpty) {
      print('DataService: DUPLICATE UIDs found in $source: $duplicateUIDs');
    }
    
    if (duplicateIds.isEmpty && duplicateNames.isEmpty && duplicateUIDs.isEmpty) {
      print('DataService: No duplicates found in $source data');
    }
  }

  /// Deduplicate attendees by ID (primary key), keeping the most recent entry
  List<Map<String, dynamic>> _deduplicateAttendees(List<Map<String, dynamic>> attendees) {
    print('DataService: Deduplicating ${attendees.length} attendees...');
    
    final Map<dynamic, Map<String, dynamic>> uniqueAttendees = {};
    
    for (final attendee in attendees) {
      final id = attendee['id'];
      if (id != null) {
        // Keep this attendee (will overwrite if duplicate ID exists)
        // This means we keep the last occurrence which should be the most recent
        uniqueAttendees[id] = attendee;
      }
    }
    
    final result = uniqueAttendees.values.toList();
    final duplicatesRemoved = attendees.length - result.length;
    
    if (duplicatesRemoved > 0) {
      print('DataService: Removed $duplicatesRemoved duplicate attendees');
    }
    
    return result;
  }

  /// Load data from cache
  Future<void> _loadFromCache() async {
    print('DataService: Loading data from cache...');
    
    // Load cached attendees
    final rawAttendees = await _offlineService.getCachedAttendees();
    print('DataService: Loaded ${rawAttendees.length} raw attendees from cache');
    
    // Deduplicate by ID (primary key)
    _attendees = _deduplicateAttendees(rawAttendees);
    print('DataService: After deduplication: ${_attendees.length} unique attendees');
    print('DataService: Cache attendees sample: ${_attendees.take(3).map((a) => {'id': a['id'], 'name': a['attendee_name'], 'uid': a['attendee_internal_uid']}).toList()}');
    
    // Check for duplicates
    _checkForDuplicates(_attendees, 'cache');
    
    _attendeesStream.add(_attendees);
    print('DataService: Cache attendees added to stream');
    
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
    print('DataService: Handling data update for: $dataType');
    switch (dataType) {
      case 'attendees':
        final rawAttendees = await _offlineService.getCachedAttendees();
        _attendees = _deduplicateAttendees(rawAttendees);
        print('DataService: Updated attendees from offline service - count: ${_attendees.length} (deduped from ${rawAttendees.length})');
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
      print('DataService: _isTimeInRange - currentTime: "$currentTime", timeFrame: "$timeFrame"');
      
      final parts = timeFrame.split('-');
      if (parts.length != 2) {
        print('DataService: Invalid timeFrame format, parts.length = ${parts.length}');
        return false;
      }
      
      final startTime = parts[0].trim();
      final endTime = parts[1].trim();
      print('DataService: startTime: "$startTime", endTime: "$endTime"');
      
      final current = _timeToMinutes(currentTime);
      final start = _timeToMinutes(startTime);
      final end = _timeToMinutes(endTime);
      
      print('DataService: current: $current minutes, start: $start minutes, end: $end minutes');
      
      final isInRange = current >= start && current <= end;
      print('DataService: Time is in range: $isInRange');
      
      return isInRange;
    } catch (e) {
      print('DataService: Error in _isTimeInRange: $e');
      return false;
    }
  }

  /// Convert time to minutes
  int _timeToMinutes(String time) {
    try {
      print('DataService: Converting time "$time" to minutes');
      final parts = time.split(':');
      if (parts.length != 2) {
        print('DataService: Invalid time format: "$time"');
        return 0;
      }
      final hours = int.parse(parts[0]);
      final minutes = int.parse(parts[1]);
      final totalMinutes = hours * 60 + minutes;
      print('DataService: "$time" = $totalMinutes minutes');
      return totalMinutes;
    } catch (e) {
      print('DataService: Error parsing time "$time": $e');
      return 0;
    }
  }

  /// Sync all data from server
  Future<void> _syncAllData() async {
    if (!_offlineService.isOnline) return;
    
    _syncStatusStream.add(SyncStatus.syncing);
    
    try {
      await _loadFromServer();
      await _offlineService.forceSyncNow();
      
      // Clear cache after successful sync
      await _clearCacheAfterSync();
      
      _syncStatusStream.add(SyncStatus.synced);
    } catch (e) {
      print('Error syncing data: $e');
      _syncStatusStream.add(SyncStatus.error);
    }
  }

  /// Start background sync timer
  void _startBackgroundSync() {
    print('DataService: Starting background sync timer (${_backgroundSyncInterval.inSeconds}s interval)');
    _backgroundSyncTimer?.cancel(); // Cancel any existing timer
    
    _backgroundSyncTimer = Timer.periodic(_backgroundSyncInterval, (timer) {
      if (_offlineService.isOnline && _isInitialized) {
        _performBackgroundSync();
      }
    });
  }

  /// Stop background sync timer
  void _stopBackgroundSync() {
    print('DataService: Stopping background sync timer');
    _backgroundSyncTimer?.cancel();
    _backgroundSyncTimer = null;
  }

  /// Perform background sync to check for server changes
  Future<void> _performBackgroundSync() async {
    try {
      print('DataService: Performing background sync check...');
      
      // Get current server data to compare with local cache
      final serverAttendees = await _supabase.from('attendee_details').select('*');
      final rawServerAttendees = List<Map<String, dynamic>>.from(serverAttendees);
      
      // Deduplicate server data
      final deduplicatedServerAttendees = _deduplicateAttendees(rawServerAttendees);

      // Check if there are any differences between server and local data
      if (_hasDataChanged(deduplicatedServerAttendees, _attendees)) {
        print('DataService: Server changes detected, updating local cache...');
        
        // Update local data with server data
        _attendees = deduplicatedServerAttendees;
        await _offlineService.cacheAttendees(_attendees);
        _attendeesStream.add(_attendees);
        
        // Update sync time
        _lastSyncTime = DateTime.now();
        
        // Perform cache cleanup after successful sync
        await _clearCacheAfterSync();
        
        print('DataService: Background sync completed - local cache updated');
      } else {
        print('DataService: No server changes detected');
        
        // Still perform occasional cache cleanup even without changes
        final now = DateTime.now();
        if (_lastCacheCleanup == null || 
            now.difference(_lastCacheCleanup!).inMinutes > 30) {
          _performCacheCleanup();
        }
      }
    } catch (e) {
      print('DataService: Background sync error: $e');
      // Don't throw error for background sync failures
    }
  }

  /// Check if server data has changed compared to local data
  bool _hasDataChanged(List<Map<String, dynamic>> serverData, List<Map<String, dynamic>> localData) {
    if (serverData.length != localData.length) {
      print('DataService: Data length changed - server: ${serverData.length}, local: ${localData.length}');
      return true;
    }
    
    // Create maps for easier comparison
    final serverMap = {for (var item in serverData) item['id']: item};
    final localMap = {for (var item in localData) item['id']: item};
    
    // Check if any item has different content
    for (var id in serverMap.keys) {
      if (!localMap.containsKey(id)) {
        print('DataService: New item found on server: $id');
        return true;
      }
      
      // Compare attendance data (most likely to change)
      final serverAttendance = serverMap[id]!['attendee_attendance'];
      final localAttendance = localMap[id]!['attendee_attendance'];
      
      if (serverAttendance != localAttendance) {
        print('DataService: Attendance changed for ID $id');
        return true;
      }
      
      // Compare properties (can change via property editor)
      final serverProperties = serverMap[id]!['attendee_properties'];
      final localProperties = localMap[id]!['attendee_properties'];
      
      if (json.encode(serverProperties) != json.encode(localProperties)) {
        print('DataService: Properties changed for ID $id');
        return true;
      }
    }
    
    return false;
  }

  /// Smart cache cleanup - removes old data while preserving dirty items
  void _performCacheCleanup() {
    if (_attendees.length <= _maxCacheSize) {
      return; // No cleanup needed
    }
    
    print('DataService: Performing cache cleanup - current size: ${_attendees.length}');
    
    // Separate dirty and clean attendees
    final dirtyAttendees = <Map<String, dynamic>>[];
    final cleanAttendees = <Map<String, dynamic>>[];
    
    for (final attendee in _attendees) {
      final uid = attendee['attendee_internal_uid']?.toString() ?? '';
      if (_dirtyAttendeeIds.contains(uid)) {
        dirtyAttendees.add(attendee);
      } else {
        cleanAttendees.add(attendee);
      }
    }
    
    // Sort clean attendees by last access (if we had that data) or by ID
    // For now, just keep the first ones and remove excess
    final excessCount = _attendees.length - _maxCacheSize;
    final toRemove = cleanAttendees.take(excessCount);
    
    // Remove excess clean attendees
    for (final attendee in toRemove) {
      _attendees.remove(attendee);
    }
    
    _lastCacheCleanup = DateTime.now();
    print('DataService: Cache cleanup completed - removed $excessCount items, new size: ${_attendees.length}');
  }

  /// Clear cache after successful sync (preserving dirty items)
  Future<void> _clearCacheAfterSync() async {
    print('DataService: Clearing cache after successful sync...');
    
    // Get list of attendees with queued changes
    final queuedChangesCount = await _offlineService.getQueuedChangesCount();
    
    if (queuedChangesCount == 0) {
      // No queued changes, safe to clear cache completely
      print('DataService: No queued changes, clearing entire cache');
      await _offlineService.clearCache();
      _dirtyAttendeeIds.clear();
    } else {
      // Keep dirty items, clear others
      print('DataService: $queuedChangesCount queued changes, preserving dirty items');
      _performCacheCleanup();
    }
    
    _lastCacheCleanup = DateTime.now();
  }

  /// Mark attendee as dirty (has unsent changes)
  void _markAttendeeDirty(String attendeeId) {
    _dirtyAttendeeIds.add(attendeeId);
    print('DataService: Marked attendee $attendeeId as dirty');
  }

  /// Mark attendee as clean (changes synced)
  void _markAttendeeClean(String attendeeId) {
    _dirtyAttendeeIds.remove(attendeeId);
    print('DataService: Marked attendee $attendeeId as clean');
  }

  /// Refresh data (manual refresh)
  Future<void> refreshData() async {
    print('DataService: Manual refresh requested');
    if (_offlineService.isOnline) {
      await _syncAllData();
    } else {
      // Just reload from cache and deduplicate
      await _loadFromCache();
    }
  }

  /// Force a clean data reload (clears cache and reloads)
  Future<void> forceCleanReload() async {
    print('DataService: Force clean reload requested - clearing cache...');
    await _offlineService.clearCache();
    
    // Reset local state
    _attendees.clear();
    _properties.clear();
    _slots.clear();
    _currentSlot = null;
    
    // Reload initial data
    await _loadInitialData();
    print('DataService: Force clean reload completed');
  }

  /// Refresh a specific attendee from server to ensure local cache consistency
  Future<void> _refreshAttendeeFromServer(String attendeeId) async {
    try {
      print('DataService: Refreshing attendee $attendeeId from server...');
      
      final serverData = await _supabase
          .from('attendee_details')
          .select('*')
          .eq('attendee_internal_uid', attendeeId)
          .single();
      
      if (serverData != null) {
        // Find and update the attendee in local cache
        final attendeeIndex = _attendees.indexWhere(
          (a) => a['attendee_internal_uid'] == attendeeId,
        );
        
        if (attendeeIndex >= 0) {
          _attendees[attendeeIndex] = Map<String, dynamic>.from(serverData);
          
          // Update cache and notify listeners
          await _offlineService.cacheAttendees(_attendees);
          _attendeesStream.add(_attendees);
          
          print('DataService: Successfully refreshed attendee $attendeeId from server');
        }
      }
    } catch (e) {
      print('DataService: Error refreshing attendee from server: $e');
      // Don't throw error - this is an optimization, not critical
    }
  }

  /// Update attendance for an attendee
  Future<AttendanceUpdateResult> updateAttendance({
    required String attendeeId,
    required String slotId,
    required bool isPresent,
  }) async {
    print('DataService: updateAttendance called - attendeeId: $attendeeId, slotId: $slotId, isPresent: $isPresent');
    print('DataService: Current online status: ${_offlineService.isOnline}');
    
    if (_offlineService.isOnline) {
      try {
        print('DataService: Attempting to update attendance on server...');
        // Try to update immediately
        final result = await _updateAttendanceOnServerWithResult(attendeeId, slotId, isPresent);
        
        print('DataService: Server update successful, updating local state...');
        // Update local state immediately
        _updateLocalAttendanceState(attendeeId, slotId, isPresent);
        
        // Refresh this specific attendee from server to ensure consistency
        await _refreshAttendeeFromServer(attendeeId);
        
        return result;
        
      } catch (e) {
        print('Error updating attendance on server: $e');
        // Queue for later sync
        await _offlineService.queueAttendanceChange(
          attendeeId: attendeeId,
          slotId: slotId,
          attendanceBool: isPresent,
        );
        
        // Mark as dirty since we have unsent changes
        _markAttendeeDirty(attendeeId);
        
        // Update local state optimistically
        _updateLocalAttendanceState(attendeeId, slotId, isPresent);
        
        return AttendanceUpdateResult(
          success: true,
          wasConflict: false,
          message: 'Queued for sync when online',
        );
      }
    } else {
      // Queue for later sync when offline
      await _offlineService.queueAttendanceChange(
        attendeeId: attendeeId,
        slotId: slotId,
        attendanceBool: isPresent,
      );
      
      // Mark as dirty since we have unsent changes
      _markAttendeeDirty(attendeeId);
      
      // Update local state optimistically
      _updateLocalAttendanceState(attendeeId, slotId, isPresent);
      
      return AttendanceUpdateResult(
        success: true,
        wasConflict: false,
        message: 'Queued for sync when online',
      );
    }
  }

  /// Update attendance on server with conflict resolution
  Future<void> _updateAttendanceOnServer(String attendeeId, String slotId, bool isPresent) async {
    print('DataService: _updateAttendanceOnServer called for attendeeId: $attendeeId');
    
    final now = DateTime.now();
    final timestamp = now.toIso8601String();
    
    // Get current attendance data
    final currentData = await _supabase
        .from('attendee_details')
        .select('attendee_attendance')
        .eq('attendee_internal_uid', attendeeId)
        .single();

    print('DataService: Retrieved current attendance data: ${currentData['attendee_attendance']}');

    List<dynamic> attendance = [];
    if (currentData['attendee_attendance'] != null) {
      attendance = json.decode(currentData['attendee_attendance']);
    }

    print('DataService: Parsed attendance list - length: ${attendance.length}');

    // Find existing record for current slot
    final existingIndex = attendance.indexWhere(
      (a) => a['slot_id'].toString() == slotId,
    );

    if (existingIndex >= 0) {
      final existingRecord = attendance[existingIndex];
      
      // Check for conflict: if already marked present by another scan
      if (existingRecord['attendance_bool'] == true && isPresent == true) {
        print('DataService: Conflict detected - attendee already marked present');
        
        // Preserve original timestamp but add additional scan info
        if (existingRecord['additional_scans'] == null) {
          existingRecord['additional_scans'] = [];
        }
        
        existingRecord['additional_scans'].add({
          'timestamp': timestamp,
          'device_scan': true,
        });
        
        print('DataService: Added additional scan timestamp: $timestamp');
      } else {
        // Normal update - no conflict
        print('DataService: Updating existing attendance record at index $existingIndex');
        attendance[existingIndex]['attendance_bool'] = isPresent;
        attendance[existingIndex]['last_updated'] = timestamp;
        
        // If marking present for first time, set primary timestamp
        if (isPresent && existingRecord['primary_scan_time'] == null) {
          attendance[existingIndex]['primary_scan_time'] = timestamp;
        }
      }
    } else {
      print('DataService: Adding new attendance record for slot $slotId');
      final newRecord = {
        'slot_id': slotId,
        'attendance_bool': isPresent,
        'last_updated': timestamp,
      };
      
      // Set primary scan time if marking present
      if (isPresent) {
        newRecord['primary_scan_time'] = timestamp;
      }
      
      attendance.add(newRecord);
    }

    print('DataService: Final attendance array: ${json.encode(attendance)}');

    // Update in database
  await _supabase
    .from('attendee_details')
    .update({'attendee_attendance': attendance})
    .eq('attendee_internal_uid', attendeeId);
        
    print('DataService: Database update completed successfully');
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
        if (attendee['attendee_attendance'] is String) {
          attendance = json.decode(attendee['attendee_attendance']);
        } else if (attendee['attendee_attendance'] is List) {
          attendance = List.from(attendee['attendee_attendance']);
        }
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

      attendee['attendee_attendance'] = attendance;
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
        
        // Refresh this specific attendee from server to ensure consistency
        await _refreshAttendeeFromServer(attendeeId);
        
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
    .update({'attendee_attendance': attendance})
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

  attendee['attendee_attendance'] = attendance;
      _attendees[attendeeIndex] = attendee;
      
      // Notify listeners
      _attendeesStream.add(_attendees);
    }
  }

  /// Mark an attendee as going on interim leave
  Future<void> markInterimLeave({
    required String attendeeId,
    required String slotId,
  }) async {
    print('DataService: markInterimLeave called for attendeeId: $attendeeId, slotId: $slotId');
    
    // Call the existing updateAttendanceWithInterimLeave method
    // marking them as present but on interim leave
    await updateAttendanceWithInterimLeave(
      attendeeId: attendeeId,
      slotId: slotId,
      isPresent: true, // They are present but on interim leave
      isInterimLeave: true,
    );
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

    attendee['attendee_attendance'] = attendance;
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

  /// Update attendance on server and return result with conflict information
  Future<AttendanceUpdateResult> _updateAttendanceOnServerWithResult(String attendeeId, String slotId, bool isPresent) async {
    print('DataService: _updateAttendanceOnServerWithResult called for attendeeId: $attendeeId');
    
    final now = DateTime.now();
    final timestamp = now.toIso8601String();
    bool wasConflict = false;
    String? conflictMessage;
    
    // Get current attendance data
    final currentData = await _supabase
        .from('attendee_details')
        .select('attendee_attendance')
        .eq('attendee_internal_uid', attendeeId)
        .single();

    print('DataService: Retrieved current attendance data: ${currentData['attendee_attendance']}');

    List<dynamic> attendance = [];
    if (currentData['attendee_attendance'] != null) {
      attendance = json.decode(currentData['attendee_attendance']);
    }

    // Find existing record for current slot
    final existingIndex = attendance.indexWhere(
      (a) => a['slot_id'].toString() == slotId,
    );

    if (existingIndex >= 0) {
      final existingRecord = attendance[existingIndex];
      
      // Check for conflict: if already marked present by another scan
      if (existingRecord['attendance_bool'] == true && isPresent == true) {
        print('DataService: Conflict detected - attendee already marked present');
        wasConflict = true;
        
        final originalTime = existingRecord['primary_scan_time'] ?? existingRecord['last_updated'];
        conflictMessage = 'Already marked present at ${originalTime != null ? DateTime.parse(originalTime).toLocal().toString().substring(11, 16) : 'unknown time'}';
        
        // Preserve original timestamp but add additional scan info
        if (existingRecord['additional_scans'] == null) {
          existingRecord['additional_scans'] = [];
        }
        
        existingRecord['additional_scans'].add({
          'timestamp': timestamp,
          'device_scan': true,
        });
        
        print('DataService: Added additional scan timestamp: $timestamp');
      } else {
        // Normal update - no conflict
        print('DataService: Updating existing attendance record at index $existingIndex');
        attendance[existingIndex]['attendance_bool'] = isPresent;
        attendance[existingIndex]['last_updated'] = timestamp;
        
        // If marking present for first time, set primary timestamp
        if (isPresent && existingRecord['primary_scan_time'] == null) {
          attendance[existingIndex]['primary_scan_time'] = timestamp;
        }
      }
    } else {
      print('DataService: Adding new attendance record for slot $slotId');
      final newRecord = {
        'slot_id': slotId,
        'attendance_bool': isPresent,
        'last_updated': timestamp,
      };
      
      // Set primary scan time if marking present
      if (isPresent) {
        newRecord['primary_scan_time'] = timestamp;
      }
      
      attendance.add(newRecord);
    }

    print('DataService: Final attendance array: ${json.encode(attendance)}');

    // Update in database
    await _supabase
        .from('attendee_details')
        .update({'attendee_attendance': json.encode(attendance)})
        .eq('attendee_internal_uid', attendeeId);
        
    print('DataService: Database update completed successfully');
    
    return AttendanceUpdateResult(
      success: true,
      wasConflict: wasConflict,
      message: conflictMessage ?? 'Attendance updated successfully',
    );
  }

  /// Dispose resources
  void dispose() {
    _stopBackgroundSync(); // Stop background sync timer
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

/// Result of attendance update operation
class AttendanceUpdateResult {
  final bool success;
  final bool wasConflict;
  final String message;
  final String? originalScanTime;
  
  AttendanceUpdateResult({
    required this.success,
    required this.wasConflict,
    required this.message,
    this.originalScanTime,
  });
}