import 'dart:convert';
import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

/// Offline service to handle data caching and queue management
class OfflineService {
  static final OfflineService _instance = OfflineService._internal();
  factory OfflineService() => _instance;
  OfflineService._internal();

  static const String _cachePrefix = 'watergirl_cache_';
  static const String _queueKey = 'watergirl_attendance_queue';
  static const String _lastSyncKey = 'watergirl_last_sync';
  
  late SharedPreferences _prefs;
  late Database _db;
  late StreamSubscription<List<ConnectivityResult>> _connectivitySubscription;
  
  bool _isOnline = true;
  bool _isInitialized = false;
  Timer? _syncTimer;
  
  final SupabaseClient _supabase = Supabase.instance.client;
  final _connectivityStream = StreamController<bool>.broadcast();
  final _dataUpdateStream = StreamController<String>.broadcast();
  
  /// Get connectivity stream
  Stream<bool> get connectivityStream => _connectivityStream.stream;
  
  /// Get data update stream
  Stream<String> get dataUpdateStream => _dataUpdateStream.stream;
  
  /// Get current online status
  bool get isOnline => _isOnline;

  /// Initialize the offline service
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    _prefs = await SharedPreferences.getInstance();
    await _initDatabase();
    await _initConnectivity();
    
    _isInitialized = true;
    
    // Start periodic sync when online
    if (_isOnline) {
      _startPeriodicSync();
    }
  }

  /// Initialize SQLite database for local caching
  Future<void> _initDatabase() async {
    final databasesPath = await getDatabasesPath();
    final path = join(databasesPath, 'watergirl_cache.db');
    
    _db = await openDatabase(
      path,
      version: 2, // Increment version to trigger migration
      onCreate: (db, version) async {
        // Create tables for caching
        await db.execute('''
          CREATE TABLE attendees (
            id TEXT PRIMARY KEY,
            data TEXT NOT NULL,
            last_updated INTEGER NOT NULL
          )
        ''');
        
        await db.execute('''
          CREATE TABLE properties (
            id TEXT PRIMARY KEY,
            data TEXT NOT NULL,
            last_updated INTEGER NOT NULL
          )
        ''');
        
        await db.execute('''
          CREATE TABLE slots (
            id TEXT PRIMARY KEY,
            data TEXT NOT NULL,
            last_updated INTEGER NOT NULL
          )
        ''');
        
        await db.execute('''
          CREATE TABLE attendance_queue (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            attendee_id TEXT NOT NULL,
            slot_id TEXT NOT NULL,
            attendance_bool INTEGER NOT NULL,
            interim_leave INTEGER DEFAULT 0,
            out_time TEXT,
            expected_return_time TEXT,
            timestamp INTEGER NOT NULL,
            synced INTEGER DEFAULT 0
          )
        ''');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          // Add interim leave columns to existing attendance_queue table
          await db.execute('''
            ALTER TABLE attendance_queue ADD COLUMN interim_leave INTEGER DEFAULT 0
          ''');
          await db.execute('''
            ALTER TABLE attendance_queue ADD COLUMN out_time TEXT
          ''');
          await db.execute('''
            ALTER TABLE attendance_queue ADD COLUMN expected_return_time TEXT
          ''');
        }
      },
    );
  }

  /// Initialize connectivity monitoring
  Future<void> _initConnectivity() async {
    final connectivity = Connectivity();
    
    // Check initial connectivity
    final result = await connectivity.checkConnectivity();
    _updateConnectivityStatus(result);
    
    // Listen for connectivity changes
    _connectivitySubscription = connectivity.onConnectivityChanged.listen(
      (List<ConnectivityResult> result) {
        _updateConnectivityStatus(result);
      },
    );
  }

  /// Update connectivity status
  void _updateConnectivityStatus(List<ConnectivityResult> result) {
    final wasOnline = _isOnline;
    _isOnline = result.any((connectivity) => 
      connectivity != ConnectivityResult.none);
    
    _connectivityStream.add(_isOnline);
    
    // If we just came back online, sync queued data
    if (!wasOnline && _isOnline) {
      _syncQueuedData();
      _startPeriodicSync();
    } else if (!_isOnline) {
      _stopPeriodicSync();
    }
  }

  /// Cache attendee data locally
  Future<void> cacheAttendees(List<Map<String, dynamic>> attendees) async {
    if (!_isInitialized) await initialize();
    
    final batch = _db.batch();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    
    for (final attendee in attendees) {
      batch.insert(
        'attendees',
        {
          'id': attendee['attendee_internal_uid'],
          'data': json.encode(attendee),
          'last_updated': timestamp,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    
    await batch.commit();
    _dataUpdateStream.add('attendees');
  }

  /// Get cached attendee data
  Future<List<Map<String, dynamic>>> getCachedAttendees() async {
    if (!_isInitialized) await initialize();
    
    final results = await _db.query('attendees', orderBy: 'last_updated DESC');
    return results.map((row) => 
      json.decode(row['data'] as String) as Map<String, dynamic>
    ).toList();
  }

  /// Cache properties data
  Future<void> cacheProperties(List<Map<String, dynamic>> properties) async {
    if (!_isInitialized) await initialize();
    
    final batch = _db.batch();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    
    for (final property in properties) {
      batch.insert(
        'properties',
        {
          'id': property['property_id']?.toString() ?? property['property_name'],
          'data': json.encode(property),
          'last_updated': timestamp,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    
    await batch.commit();
    _dataUpdateStream.add('properties');
  }

  /// Get cached properties data
  Future<List<Map<String, dynamic>>> getCachedProperties() async {
    if (!_isInitialized) await initialize();
    
    final results = await _db.query('properties', orderBy: 'last_updated DESC');
    return results.map((row) => 
      json.decode(row['data'] as String) as Map<String, dynamic>
    ).toList();
  }

  /// Cache slots data
  Future<void> cacheSlots(List<Map<String, dynamic>> slots) async {
    if (!_isInitialized) await initialize();
    
    final batch = _db.batch();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    
    for (final slot in slots) {
      batch.insert(
        'slots',
        {
          'id': slot['slot_id']?.toString() ?? slot['slot_name'],
          'data': json.encode(slot),
          'last_updated': timestamp,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    
    await batch.commit();
    _dataUpdateStream.add('slots');
  }

  /// Get cached slots data
  Future<List<Map<String, dynamic>>> getCachedSlots() async {
    if (!_isInitialized) await initialize();
    
    final results = await _db.query('slots', orderBy: 'last_updated DESC');
    return results.map((row) => 
      json.decode(row['data'] as String) as Map<String, dynamic>
    ).toList();
  }

  /// Queue attendance change for later sync
  Future<void> queueAttendanceChange({
    required String attendeeId,
    required String slotId,
    required bool attendanceBool,
  }) async {
    if (!_isInitialized) await initialize();
    
    await _db.insert('attendance_queue', {
      'attendee_id': attendeeId,
      'slot_id': slotId,
      'attendance_bool': attendanceBool ? 1 : 0,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'synced': 0,
    });
    
    // Try to sync immediately if online
    if (_isOnline) {
      _syncQueuedData();
    }
  }

  /// Queue attendance change with interim leave for later sync
  Future<void> queueAttendanceChangeWithInterimLeave({
    required String attendeeId,
    required String slotId,
    required bool attendanceBool,
    required bool isInterimLeave,
  }) async {
    if (!_isInitialized) await initialize();
    
    final now = DateTime.now();
    await _db.insert('attendance_queue', {
      'attendee_id': attendeeId,
      'slot_id': slotId,
      'attendance_bool': attendanceBool ? 1 : 0,
      'interim_leave': isInterimLeave ? 1 : 0,
      'out_time': isInterimLeave ? now.toIso8601String() : null,
      'expected_return_time': isInterimLeave 
          ? now.add(const Duration(minutes: 10)).toIso8601String() 
          : null,
      'timestamp': now.millisecondsSinceEpoch,
      'synced': 0,
    });
    
    // Try to sync immediately if online
    if (_isOnline) {
      _syncQueuedData();
    }
  }

  /// Queue attendance return for later sync
  Future<void> queueAttendanceReturn({
    required String attendeeId,
    required String slotId,
  }) async {
    if (!_isInitialized) await initialize();
    
    await _db.insert('attendance_queue', {
      'attendee_id': attendeeId,
      'slot_id': slotId,
      'attendance_bool': 1, // Still present, just returned
      'interim_leave': 0, // No longer on interim leave
      'actual_return_time': DateTime.now().toIso8601String(),
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'synced': 0,
    });
    
    // Try to sync immediately if online
    if (_isOnline) {
      _syncQueuedData();
    }
  }

  /// Get queued attendance changes count
  Future<int> getQueuedChangesCount() async {
    if (!_isInitialized) await initialize();
    
    final result = await _db.rawQuery(
      'SELECT COUNT(*) as count FROM attendance_queue WHERE synced = 0'
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// Sync queued attendance data with server
  Future<void> _syncQueuedData() async {
    if (!_isOnline || !_isInitialized) {
      print('OfflineService: _syncQueuedData called but not online or not initialized. Online: $_isOnline, Initialized: $_isInitialized');
      return;
    }
    print('OfflineService: _syncQueuedData running');
    
    try {
      // Get unsynced attendance changes
      final queuedChanges = await _db.query(
        'attendance_queue',
        where: 'synced = ?',
        whereArgs: [0],
        orderBy: 'timestamp ASC',
      );
      
      print('OfflineService: Queued changes count: ${queuedChanges.length}');
      
      if (queuedChanges.isEmpty) return;
      
      // Process each queued change
      for (final change in queuedChanges) {
        try {
          print('OfflineService: Syncing queued change id: ${change['id']}');
          await _syncAttendanceChange(change);
          
          // Mark as synced
          await _db.update(
            'attendance_queue',
            {'synced': 1},
            where: 'id = ?',
            whereArgs: [change['id']],
          );
          
          print('OfflineService: Marked change id ${change['id']} as synced');
        } catch (e) {
          print('Error syncing attendance change ${change['id']}: $e');
          // Continue with next change
        }
      }
      
      // Update last sync time
      await _prefs.setInt(_lastSyncKey, DateTime.now().millisecondsSinceEpoch);
      
      print('OfflineService: Finished syncing queued changes');
      
    } catch (e) {
      print('Error during sync: $e');
    }
  }

  /// Sync individual attendance change
  Future<void> _syncAttendanceChange(Map<String, dynamic> change) async {
    print('OfflineService: _syncAttendanceChange for attendeeId: ${change['attendee_id']}, slotId: ${change['slot_id']}, attendanceBool: ${change['attendance_bool']}');
    
    final attendeeId = change['attendee_id'] as String;
    final slotId = change['slot_id'] as String;
    final attendanceBool = change['attendance_bool'] == 1;
    
    // Get current attendance data from server
    final currentData = await _supabase
        .from('attendee_details')
        .select('attendee_attendance')
        .eq('attendee_internal_uid', attendeeId)
        .single();

    print('OfflineService: Raw attendance data from DB: ${currentData['attendee_attendance']} (type: ${currentData['attendee_attendance'].runtimeType})');

    List<dynamic> attendance = [];
    if (currentData['attendee_attendance'] != null) {
      print('OfflineService: Processing attendance data...');
      if (currentData['attendee_attendance'] is String) {
        print('OfflineService: Decoding JSON string...');
        attendance = json.decode(currentData['attendee_attendance']);
      } else if (currentData['attendee_attendance'] is List) {
        print('OfflineService: Using existing List...');
        attendance = List.from(currentData['attendee_attendance']);
      }
      print('OfflineService: Final attendance: $attendance');
    }

    // Update or add attendance for the slot
    final existingIndex = attendance.indexWhere(
      (a) => a['slot_id'].toString() == slotId,
    );

    print('OfflineService: Existing index: $existingIndex');

    if (existingIndex >= 0) {
      print('OfflineService: Updating existing record at index $existingIndex');
      attendance[existingIndex]['attendance_bool'] = attendanceBool;
      print('OfflineService: Updated existing attendance record for slot ${change['slot_id']}');
    } else {
      print('OfflineService: Adding new attendance record');
      attendance.add({
        'slot_id': slotId,
        'attendance_bool': attendanceBool,
      });
      print('OfflineService: Added new attendance record for slot ${change['slot_id']}');
    }

    print('OfflineService: About to update database with attendance: ${json.encode(attendance)}');
    print('OfflineService: Attendance type: ${attendance.runtimeType}');
    print('OfflineService: Attendance content: $attendance');

    // Always encode attendance as JSON string for DB update
    try {
      final updateData = {'attendee_attendance': attendance}; // Don't double-encode, let Supabase handle it
      print('OfflineService: Updating DB with: $updateData');
      
      await _supabase
          .from('attendee_details')
          .update(updateData)
          .eq('attendee_internal_uid', attendeeId);
      
      print('OfflineService: Database update successful');
    } catch (e) {
      print('OfflineService: Database update failed: $e');
      rethrow;
    }

    print('OfflineService: Updated attendee_attendance in DB for ${change['attendee_id']}');

    // Update local cache (can keep as List)
    await _updateLocalAttendeeData(attendeeId, attendance);
  }

  /// Update local attendee data with new attendance
  Future<void> _updateLocalAttendeeData(String attendeeId, List<dynamic> attendance) async {
    final result = await _db.query(
      'attendees',
      where: 'id = ?',
      whereArgs: [attendeeId],
    );
    
    if (result.isNotEmpty) {
      final attendeeData = json.decode(result.first['data'] as String) as Map<String, dynamic>;
      attendeeData['attendee_attendance'] = json.encode(attendance);
      
      await _db.update(
        'attendees',
        {
          'data': json.encode(attendeeData),
          'last_updated': DateTime.now().millisecondsSinceEpoch,
        },
        where: 'id = ?',
        whereArgs: [attendeeId],
      );
      
      _dataUpdateStream.add('attendees');
    }
  }

  /// Start periodic sync
  void _startPeriodicSync() {
    _stopPeriodicSync(); // Stop any existing timer
    
    print('OfflineService: Starting periodic sync timer');
    
    // Sync every 30 seconds when online
    _syncTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      print('OfflineService: Periodic sync timer fired. Online: $_isOnline');
      if (_isOnline) {
        _syncQueuedData();
      }
    });
  }

  /// Stop periodic sync
  void _stopPeriodicSync() {
    _syncTimer?.cancel();
    _syncTimer = null;
  }

  /// Force sync now (for manual refresh)
  Future<void> forceSyncNow() async {
    if (_isOnline) {
      await _syncQueuedData();
    }
  }

  /// Get last sync timestamp
  Future<DateTime?> getLastSyncTime() async {
    final timestamp = _prefs.getInt(_lastSyncKey);
    return timestamp != null ? DateTime.fromMillisecondsSinceEpoch(timestamp) : null;
  }

  /// Clear all cached data
  Future<void> clearCache() async {
    if (!_isInitialized) await initialize();
    
    await _db.delete('attendees');
    await _db.delete('properties');
    await _db.delete('slots');
    
    _dataUpdateStream.add('cache_cleared');
  }

  /// Dispose resources
  void dispose() {
    _connectivitySubscription.cancel();
    _stopPeriodicSync();
    _connectivityStream.close();
    _dataUpdateStream.close();
    _db.close();
  }
}