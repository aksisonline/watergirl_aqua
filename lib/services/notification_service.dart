import 'dart:async';
import 'dart:io';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;

class NotificationService {
  static final FlutterLocalNotificationsPlugin _notificationsPlugin = 
      FlutterLocalNotificationsPlugin();
  static Timer? _interimLeaveTimer;
  static bool _isInitialized = false;

  /// Initialize the notification service
  static Future<void> initialize() async {
    if (_isInitialized) return;

    // Request notification permissions
    await _requestPermissions();

    // Initialize plugin settings
    const initializationSettingsAndroid = 
        AndroidInitializationSettings('@mipmap/ic_launcher');
    
    const initializationSettingsIOS = DarwinInitializationSettings(
      requestSoundPermission: true,
      requestBadgePermission: true,
      requestAlertPermission: true,
    );

    const initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: initializationSettingsIOS,
    );

    await _notificationsPlugin.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );

    _isInitialized = true;
  }

  /// Request notification permissions
  static Future<void> _requestPermissions() async {
    if (Platform.isAndroid) {
      await Permission.notification.request();
    } else if (Platform.isIOS) {
      await _notificationsPlugin
          .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          );
    }
  }

  /// Handle notification tap
  static void _onNotificationTapped(NotificationResponse response) {
    // Handle what happens when user taps notification
    print('Notification tapped: ${response.payload}');
  }

  /// Start monitoring interim leave timers
  static void startInterimLeaveTimer() {
    // Stop existing timer if running
    _interimLeaveTimer?.cancel();
    
    // Start new timer that checks every 30 seconds
    _interimLeaveTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      _checkInterimLeaveTimeouts();
    });
  }

  /// Stop monitoring interim leave timers
  static void stopInterimLeaveTimer() {
    _interimLeaveTimer?.cancel();
    _interimLeaveTimer = null;
  }

  /// Check for interim leave timeouts and send notifications
  static Future<void> _checkInterimLeaveTimeouts() async {
    try {
      // Get volunteer's current room and building settings
      final prefs = await SharedPreferences.getInstance();
      final currentBuilding = prefs.getString('default_building');
      final currentRoom = prefs.getString('default_room');

      if (currentBuilding == null || currentRoom == null) {
        return; // Cannot check without volunteer settings
      }

      // Fetch attendees on interim leave from the current room
      final currentRoomAttendees = await _getCurrentRoomInterimLeaveAttendees(
        currentBuilding, 
        currentRoom
      );

      final now = DateTime.now();

      for (final attendee in currentRoomAttendees) {
        final outTime = DateTime.tryParse(attendee['out_time'] ?? '');
        if (outTime == null) continue;

        final elapsed = now.difference(outTime);
        final minutes = elapsed.inMinutes;

        // Notify at 5 minutes (warning) and 10 minutes (overdue)
        if (minutes == 5) {
          await _showTimeoutWarningNotification(attendee['name'], minutes);
        } else if (minutes >= 10 && minutes % 5 == 0) {
          // Notify every 5 minutes after 10 minutes
          await _showOverdueNotification(attendee['name'], minutes);
        }
      }
    } catch (e) {
      print('Error checking interim leave timeouts: $e');
    }
  }

  /// Fetch attendees on interim leave from current room
  static Future<List<Map<String, dynamic>>> _getCurrentRoomInterimLeaveAttendees(
    String building, 
    String room
  ) async {
    try {
      final supabase = Supabase.instance.client;
      
      final response = await supabase
          .from('attendees')
          .select('attendee_id, name, properties, attendee_attendance')
          .eq('properties->building', building)
          .eq('properties->room', room);

      final interimLeaveAttendees = <Map<String, dynamic>>[];

      for (final attendee in response) {
        final attendance = attendee['attendee_attendance'] as List<dynamic>?;
        if (attendance == null) continue;

        // Find active interim leave (no actual_return_time)
        for (final att in attendance) {
          if (att['interim_leave'] == true && 
              att['actual_return_time'] == null &&
              att['expected_return_time'] != null) {
            
            interimLeaveAttendees.add({
              'attendee_id': attendee['attendee_id'],
              'name': attendee['name'],
              'out_time': att['expected_return_time'], // This should be out_time in real implementation
            });
            break; // Only one active interim leave per attendee
          }
        }
      }

      return interimLeaveAttendees;
    } catch (e) {
      print('Error fetching current room interim leave attendees: $e');
      return [];
    }
  }

  /// Show timeout warning notification (5 minutes)
  static Future<void> _showTimeoutWarningNotification(
    String attendeeName, 
    int minutes
  ) async {
    await _showLocalNotification(
      id: attendeeName.hashCode,
      title: 'Interim Leave Warning',
      body: '$attendeeName has been out for $minutes minutes',
      payload: 'timeout_warning:$attendeeName',
    );
  }

  /// Show overdue notification (10+ minutes)
  static Future<void> _showOverdueNotification(
    String attendeeName, 
    int minutes
  ) async {
    await _showLocalNotification(
      id: attendeeName.hashCode,
      title: 'Interim Leave Overdue!',
      body: '$attendeeName has been out for $minutes minutes - Please check!',
      payload: 'overdue:$attendeeName',
      isUrgent: true,
    );
  }

  /// Show local notification
  static Future<void> _showLocalNotification({
    required int id,
    required String title,
    required String body,
    String? payload,
    bool isUrgent = false,
  }) async {
    try {
      final androidDetails = AndroidNotificationDetails(
        'interim_leave_channel',
        'Interim Leave Notifications',
        channelDescription: 'Notifications for interim leave timeouts',
        importance: isUrgent ? Importance.high : Importance.defaultImportance,
        priority: isUrgent ? Priority.high : Priority.defaultPriority,
        enableVibration: true,
        playSound: true,
      );

      const iOSDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      );

      final platformDetails = NotificationDetails(
        android: androidDetails,
        iOS: iOSDetails,
      );

      await _notificationsPlugin.show(
        id,
        title,
        body,
        platformDetails,
        payload: payload,
      );
    } catch (e) {
      print('Error showing notification: $e');
    }
  }

  /// Cancel all notifications
  static Future<void> cancelAllNotifications() async {
    await _notificationsPlugin.cancelAll();
  }

  /// Cancel notification by ID
  static Future<void> cancelNotification(int id) async {
    await _notificationsPlugin.cancel(id);
  }

  /// Get remaining time for interim leave
  static Duration? getRemainingTime(DateTime outTime) {
    final now = DateTime.now();
    final maxDuration = const Duration(minutes: 10);
    final elapsed = now.difference(outTime);
    
    if (elapsed >= maxDuration) {
      return Duration.zero; // Overdue
    }
    
    return maxDuration - elapsed;
  }

  /// Format remaining time for display
  static String formatRemainingTime(Duration remaining) {
    if (remaining.isNegative || remaining == Duration.zero) {
      return 'OVERDUE';
    }
    
    final minutes = remaining.inMinutes;
    final seconds = remaining.inSeconds % 60;
    
    return '${minutes}:${seconds.toString().padLeft(2, '0')}';
  }

  /// Check if attendee is overdue
  static bool isOverdue(DateTime outTime) {
    final elapsed = DateTime.now().difference(outTime);
    return elapsed.inMinutes >= 10;
  }

  /// Check if attendee is approaching timeout (>5 minutes)
  static bool isApproachingTimeout(DateTime outTime) {
    final elapsed = DateTime.now().difference(outTime);
    return elapsed.inMinutes >= 5 && elapsed.inMinutes < 10;
  }

  /// Show notification for attendee return
  static Future<void> showReturnNotification(String attendeeName) async {
    await _showLocalNotification(
      id: 'return_${attendeeName}'.hashCode,
      title: 'Attendee Returned',
      body: '$attendeeName has returned from interim leave',
      payload: 'return:$attendeeName',
    );
  }

  /// Show a general notification
  static Future<void> showNotification({
    required String title,
    required String body,
    String? payload,
  }) async {
    await _showLocalNotification(
      id: DateTime.now().millisecondsSinceEpoch,
      title: title,
      body: body,
      payload: payload,
    );
  }

  /// Schedule a reminder notification
  static Future<void> scheduleReminderNotification({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledTime,
    String? payload,
  }) async {
    try {
      final androidDetails = AndroidNotificationDetails(
        'reminders_channel',
        'Reminder Notifications',
        channelDescription: 'Scheduled reminder notifications',
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
      );

      const iOSDetails = DarwinNotificationDetails();

      final platformDetails = NotificationDetails(
        android: androidDetails,
        iOS: iOSDetails,
      );

      await _notificationsPlugin.zonedSchedule(
        id,
        title,
        body,
        tz.TZDateTime.from(scheduledTime, tz.local),
        platformDetails,
        payload: payload,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: DateTimeComponents.time,
      );
    } catch (e) {
      print('Error scheduling notification: $e');
    }
  }
}