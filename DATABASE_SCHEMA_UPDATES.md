# Interim Leave Implementation - Current Status Approach

## Overview
Interim leave is a **temporary current status** of an attendee, independent of their slot attendance records. An attendee can be marked present for a slot and then go on interim leave during that same slot period.

## Correct Implementation Approach

### Separation of Concerns
- **Slot Attendance**: Records whether attendee was present/absent for specific time slots
- **Interim Leave**: Current temporary status indicating attendee is outside the venue

### Enhanced AttendeeDetails Schema
We can add interim leave as a top-level property using the existing JSON structure:

```json
// Add to attendee_properties JSON or create new current_status field
{
  "team_name": "Alpha Team",
  "building": "Main Building",
  "room": "Conference Room A",
  "current_status": {
    "interim_leave": {
      "is_on_leave": true,
      "out_time": "2025-09-17T10:15:00Z", 
      "expected_return_time": "2025-09-17T10:25:00Z",
      "actual_return_time": null,
      "initiated_by_uac": "UAC123",
      "timeout_notified": false
    }
  }
}
```

### Attendance Records Remain Unchanged
```json
// attendee_attendance stays slot-specific
[
  {
    "slot_id": "slot_001",
    "attendance_bool": true,
    "timestamp": "2025-09-17T09:30:00Z",
    "scanned_by_uac": "UAC123"
  }
]
```

## Implementation Features

### 1. Interim Leave Tracking
- Add `interim_leave: true` when user scans out for break
- Record `out_time` timestamp
- Calculate `expected_return_time` (out_time + 10 minutes)
- Track `actual_return_time` when they return
- Flag users who exceed time limit

### 2. Timer System (Flutter App)
- Show countdown timer for users on interim leave
- Push to top of attendee list with yellow highlight
- Show remaining time out of 10 minutes
- Auto-refresh every 30 seconds

### 3. Property Validation System
- Store volunteer's default property settings in SharedPreferences
- Validate against existing attendee properties before saving
- Show warning dialog if properties conflict
- Allow volunteer to override or go back to settings

### 4. Notification System
- Send notifications when users exceed 10-minute limit
- Notify attendee in-charge through dashboard
- Show flagged users in dashboard with alert badges

## API Endpoint Updates (Minimal Changes)

### New/Updated Endpoints:
```
POST /api/attendance/interim-leave/start
POST /api/attendance/interim-leave/return  
GET  /api/attendance/active-interim-leaves
GET  /api/properties/volunteer-defaults
POST /api/properties/volunteer-defaults
```

### Example API Responses:
```json
// Active interim leaves
{
  "interim_leaves": [
    {
      "attendee_id": 123,
      "attendee_name": "John Doe",
      "out_time": "2025-09-17T10:15:00Z",
      "expected_return": "2025-09-17T10:25:00Z",
      "minutes_remaining": 3,
      "status": "active"
    }
  ]
}
```

## Implementation Benefits

### Advantages of JSON Approach:
1. **No Schema Migration**: Uses existing flexible structure
2. **Backward Compatible**: Existing data remains unchanged  
3. **Easy to Extend**: Can add new fields without DB changes
4. **Simpler Development**: No complex joins or foreign keys
5. **Flexible Structure**: Perfect for dynamic properties

### Dashboard Updates:
1. Parse JSON to extract interim leave information
2. Show active interim leaves in overview cards
3. Display timer countdown in attendee table
4. Add filtering by interim leave status
5. Show alerts for overdue returns

### Flutter App Updates:
1. Extend attendance scanning to handle interim leave
2. Add timer widget for active interim leaves
3. Implement property settings screen
4. Add validation dialogs for property conflicts
5. Show push notifications for timeouts