# Flutter App Enhancement Plan - Interim Leave & Property Management

## Overview
Enhance the watergirl_aqua Flutter app to support interim leave functionality, dynamic property management, and improved user experience using the existing JSON-based database schema.

## Core Features to Implement

### 1. Enhanced Login Flow with Dynamic Properties

#### Property Settings Screen
Create a new screen after login to configure volunteer's default property settings:

```dart
// lib/auth/property_settings_screen.dart
class PropertySettingsScreen extends StatefulWidget {
  final String volunteerUac;
  final String volunteerName;
  
  const PropertySettingsScreen({
    Key? key,
    required this.volunteerUac,
    required this.volunteerName,
  }) : super(key: key);
}
```

#### Features:
- Fetch all available properties from Properties table (Team Name, Building, Room)
- Allow volunteer to set their default values for each property
- Store settings in SharedPreferences for offline access
- Show in settings menu for easy modification
- Validate before each attendance scan

### 2. Interim Leave Functionality

#### Enhanced QR Scanner with Interim Leave Options
Add interim leave button to QR scanner screen:

```dart
// Add to existing QR scanner
Widget _buildActionButtons() {
  return Row(
    children: [
      ElevatedButton.icon(
        onPressed: _handleRegularAttendance,
        icon: Icon(Icons.check_circle),
        label: Text('Mark Present'),
      ),
      SizedBox(width: 16),
      ElevatedButton.icon(
        onPressed: _handleInterimLeave,
        icon: Icon(Icons.access_time),
        label: Text('Interim Leave'),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.orange,
        ),
      ),
    ],
  );
}
```

#### Timer Widget for Active Interim Leaves
Display real-time countdown for users on interim leave:

```dart
// lib/dashboard/widgets/interim_leave_timer.dart
class InterimLeaveTimer extends StatefulWidget {
  final List<Map<String, dynamic>> activeInterimLeaves;
  final Function(String attendeeId) onReturnCallback;
}

class InterimLeaveTimerState extends State<InterimLeaveTimer> {
  Timer? _timer;
  
  @override
  void initState() {
    super.initState();
    _startTimer();
  }
  
  void _startTimer() {
    _timer = Timer.periodic(Duration(seconds: 30), (timer) {
      _checkTimeouts();
      setState(() {}); // Refresh UI
    });
  }
  
  void _checkTimeouts() {
    // Check for users who exceeded 10 minutes
    // Send notifications if needed
    // Flag users as overdue
  }
}
```

### 3. Enhanced Attendee List with Interim Leave Display

#### Priority Queue for Interim Leave Users
Modify attendee list to show interim leave users at the top:

```dart
// In AttendeeListNoUIDPage
List<Map<String, dynamic>> _sortAttendeesWithInterimLeave(List<Map<String, dynamic>> attendees) {
  final interimLeaveUsers = <Map<String, dynamic>>[];
  final regularUsers = <Map<String, dynamic>>[];
  
  for (final attendee in attendees) {
    final attendance = attendee['attendee_attendance'] as List<dynamic>?;
    final hasInterimLeave = attendance?.any((att) => 
      att['interim_leave'] == true && att['actual_return_time'] == null
    ) ?? false;
    
    if (hasInterimLeave) {
      interimLeaveUsers.add(attendee);
    } else {
      regularUsers.add(attendee);
    }
  }
  
  return [...interimLeaveUsers, ...regularUsers];
}
```

#### Visual Indicators
- Yellow highlight for users on interim leave
- Red highlight for overdue users (>10 minutes)
- Timer countdown display
- Quick return button

### 4. Property Validation System

#### Pre-Scan Validation
Before scanning any QR code, validate volunteer's current property settings:

```dart
// lib/services/property_validation_service.dart
class PropertyValidationService {
  static Future<ValidationResult> validateBeforeScan(
    String attendeeId,
    Map<String, dynamic> volunteerSettings
  ) async {
    // Fetch existing attendee properties
    final existingProperties = await _getAttendeeProperties(attendeeId);
    
    if (existingProperties.isNotEmpty) {
      // Check for conflicts
      final conflicts = _findConflicts(existingProperties, volunteerSettings);
      if (conflicts.isNotEmpty) {
        return ValidationResult.conflict(conflicts);
      }
    }
    
    return ValidationResult.success();
  }
}
```

#### Conflict Resolution Dialog
Show dialog when property conflicts are detected:

```dart
// Show conflict resolution dialog
Future<bool> _showPropertyConflictDialog(List<PropertyConflict> conflicts) async {
  return await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Property Conflict Detected'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('The attendee already has different properties set:'),
          SizedBox(height: 16),
          ...conflicts.map((conflict) => 
            _buildConflictItem(conflict)
          ).toList(),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text('Go Back to Settings'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text('Continue Anyway'),
        ),
      ],
    ),
  ) ?? false;
}
```

### 5. Settings Menu Enhancement

#### Comprehensive Settings Screen
Add a dedicated settings screen accessible from the main menu:

```dart
// lib/dashboard/settings/settings_screen.dart
class SettingsScreen extends StatefulWidget {
  @override
  _SettingsScreenState createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Settings')),
      body: ListView(
        children: [
          _buildPropertySettingsSection(),
          _buildNotificationSettingsSection(),
          _buildScanningPreferencesSection(),
          _buildDataSyncSection(),
        ],
      ),
    );
  }
}
```

### 6. Notification System

#### Local Timer-Based Notifications

Handle all timing logic locally within the Flutter app:

```dart
// lib/services/notification_service.dart
class NotificationService {
  static Timer? _interimLeaveTimer;
  
  static void startInterimLeaveTimer(String currentRoom, String currentBuilding) {
    _interimLeaveTimer = Timer.periodic(Duration(seconds: 30), (timer) {
      _checkInterimLeaveTimeouts(currentRoom, currentBuilding);
    });
  }
  
  static void _checkInterimLeaveTimeouts(String currentRoom, String currentBuilding) {
    // Only check attendees from the current room and building
    final currentRoomAttendees = attendees.where((attendee) {
      final props = attendee.properties;
      return props['building'] == currentBuilding && 
             props['room'] == currentRoom &&
             props['current_status']?['interim_leave']?['is_on_leave'] == true;
    });
    
    for (final attendee in currentRoomAttendees) {
      DateTime outTime = DateTime.parse(attendee.properties['current_status']['interim_leave']['out_time']);
      Duration elapsed = DateTime.now().difference(outTime);
      
      if (elapsed.inMinutes >= 5) {
        // Only notify about attendees from the same room
        showLocalNotification(
          'Room Alert - Interim Leave Timeout',
          '${attendee.name} from your room has been out for ${elapsed.inMinutes} minutes'
        );
      }
    }
  }
  
  static Future<void> showLocalNotification(String title, String body) async {
    await flutterLocalNotificationsPlugin.show(
      0, // notification id
      title,
      body,
      NotificationDetails(/* ... */),
    );
  }
}
```

#### Timer Management
- All timer logic runs locally in the Flutter app
- No backend timer management required
- Calculate remaining time: `5 minutes - (current_time - out_time)`
- Show notifications when time expires
- Update UI with real-time countdown

## Implementation Timeline

### Week 1: Core Infrastructure
- [ ] Create PropertySettingsScreen
- [ ] Implement SharedPreferences storage for volunteer settings
- [ ] Add property validation service
- [ ] Update login flow to include property setup

### Week 2: Interim Leave Functionality
- [ ] Add interim leave buttons to QR scanner
- [ ] Implement timer widget for active interim leaves
- [ ] Update attendee list sorting and display
- [ ] Add visual indicators for interim leave status

### Week 3: Enhanced UI/UX
- [ ] Create comprehensive settings screen
- [ ] Implement conflict resolution dialogs
- [ ] Add notification system
- [ ] Enhance attendee list with quick action buttons

### Week 4: Testing & Optimization
- [ ] Test all new functionality
- [ ] Optimize performance for real-time updates
- [ ] Add error handling and edge cases
- [ ] User acceptance testing

## Technical Implementation Details

### Data Flow for Interim Leave
1. User scans attendee QR code
2. Volunteer selects "Interim Leave" option
3. App records current timestamp as `out_time`
4. Calculate `expected_return_time` (out_time + 10 minutes)
5. Update attendee_attendance JSON with interim leave data
6. Add attendee to top of list with timer display
7. Start local timer for timeout detection
8. When user returns, scan again to record `actual_return_time`

### Property Validation Flow
1. Volunteer sets default properties in settings
2. Before scanning any attendee:
   - Fetch attendee's existing properties
   - Compare with volunteer's settings
   - If conflict detected, show warning dialog
   - Allow volunteer to continue or go back to settings
3. If no conflict or volunteer chooses to continue:
   - Proceed with attendance marking
   - Add property metadata to attendance record

### Offline Support Enhancements
- Cache volunteer property settings locally
- Store interim leave data offline until sync
- Queue notifications for when connection restored
- Implement conflict resolution for offline/online data differences

## UI/UX Improvements

### Color Coding System
- **Green**: Present attendees
- **Red**: Absent attendees  
- **Yellow**: Interim leave (within time limit)
- **Orange**: Interim leave (approaching timeout)
- **Red with warning icon**: Overdue interim leave

### Quick Action Buttons
- **Return**: Quick button for interim leave users to mark their return
- **Extend**: Option to extend interim leave by additional 5 minutes
- **Flag**: Manual flag for attendees requiring attention

### Property Structure

### Volunteer Settings (Flutter App)
Volunteers only configure:
- **Building**: Which building they are working in
- **Room**: Which room within that building

### Volunteer Settings Example
```dart
// Stored in SharedPreferences
{
  "default_building": "Main Building",
  "default_room": "Conference Room A"
}
```

### Complete Attendee Properties (Dashboard)
When attendees are scanned, properties include:
- **Team Name**: Set via ploof dashboard (not in Flutter app)
- **Building**: From volunteer's Flutter app settings
- **Room**: From volunteer's Flutter app settings

### Property Example in JSON
```dart
// Complete attendee properties structure
{
  "team_name": "Alpha Team",        // Set via dashboard
  "building": "Main Building",      // From Flutter app settings
  "room": "Conference Room A",      // From Flutter app settings
  "current_status": {
    "interim_leave": {
      "is_on_leave": false
    }
  }
}
```

## Real-time Updates
- Auto-refresh attendee list every 30 seconds
- Real-time timer updates for interim leave countdown
- Push notifications for critical events
- Background sync for seamless user experience