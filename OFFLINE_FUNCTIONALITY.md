# Offline Functionality and Preload Optimizations

## Overview

The application now includes comprehensive offline functionality and preload optimizations to ensure seamless user experience even when internet connectivity is poor or unavailable.

## Key Features

### 🔌 Connectivity Monitoring
- Real-time connectivity status detection using `connectivity_plus`
- Automatic mode switching between online and offline states
- Visual indicators showing connection status throughout the app

### 💾 Local Data Caching
- **SQLite Database**: Local caching of all critical data using `sqflite`
- **Attendee Data**: Complete attendee information cached locally
- **Properties**: All property definitions cached for filtering
- **Slots**: Time slot information cached for attendance logic
- **Automatic Sync**: Data automatically synced when connection is restored

### 📋 Offline Queue System
- **Attendance Changes**: All attendance modifications queued locally when offline
- **Background Sync**: Queued changes automatically synced in background
- **Sequential Processing**: Changes processed in chronological order
- **Error Handling**: Failed sync attempts retried automatically
- **User Feedback**: Clear indication of queued vs. synced changes

### ⚡ State Management
- **Component-Level Updates**: Only affected components refresh, not entire pages
- **Optimistic Updates**: UI updates immediately, syncs in background
- **Stream-Based Architecture**: Real-time data updates across the app
- **Memory Efficient**: Smart caching prevents unnecessary API calls

## Implementation Details

### Services Architecture

#### OfflineService (`lib/services/offline_service.dart`)
Handles all offline functionality:
- SQLite database management
- Connectivity monitoring
- Queue management for attendance changes
- Background sync operations
- Cache management

#### DataService (`lib/services/data_service.dart`)
Manages application state and data:
- Stream-based data distribution
- Optimistic updates
- Search and filtering
- State synchronization

### Database Schema

#### Local Cache Tables
```sql
-- Attendee cache
CREATE TABLE attendees (
  id TEXT PRIMARY KEY,
  data TEXT NOT NULL,
  last_updated INTEGER NOT NULL
);

-- Properties cache
CREATE TABLE properties (
  id TEXT PRIMARY KEY,
  data TEXT NOT NULL,
  last_updated INTEGER NOT NULL
);

-- Slots cache
CREATE TABLE slots (
  id TEXT PRIMARY KEY,
  data TEXT NOT NULL,
  last_updated INTEGER NOT NULL
);

-- Attendance queue
CREATE TABLE attendance_queue (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  attendee_id TEXT NOT NULL,
  slot_id TEXT NOT NULL,
  attendance_bool INTEGER NOT NULL,
  timestamp INTEGER NOT NULL,
  synced INTEGER DEFAULT 0
);
```

## User Experience

### Online Mode
- Full functionality with real-time sync
- Immediate server updates
- Background caching for offline use

### Offline Mode
- Complete functionality using cached data
- Attendance changes queued locally
- Visual indicators showing offline status
- Queued changes count displayed

### Connection Restoration
- Automatic background sync of queued changes
- Progress indicators during sync
- Error handling with retry logic
- Seamless transition back to online mode

## Visual Indicators

### Connection Status Cards
- **Green**: Online and synced
- **Orange**: Online but syncing
- **Red**: Offline mode
- **Queue Counter**: Shows pending changes

### Features
- Appears automatically when offline or syncing
- Shows connection status
- Displays queued changes count
- Provides manual sync option when available

## Performance Optimizations

### Preloading Strategy
1. **App Launch**: Load all critical data immediately
2. **Background Updates**: Refresh data every 30 seconds when online
3. **Smart Caching**: Only update changed data
4. **Memory Management**: Efficient data structures prevent memory leaks

### Network Optimization
- **Minimal API Calls**: Use cached data when possible
- **Batch Operations**: Group multiple changes for efficient sync
- **Retry Logic**: Exponential backoff for failed requests
- **Background Processing**: Sync doesn't block user interface

## Implementation Best Practices

### State Management
```dart
// Listen to data streams for reactive updates
_dataService.attendeesStream.listen((attendees) {
  if (mounted) {
    setState(() {
      _originalData = attendees;
      _filterData(_searchController.text);
    });
  }
});
```

### Optimistic Updates
```dart
// Update UI immediately, sync in background
await _dataService.updateAttendance(
  attendeeId: attendeeId,
  slotId: slotId,
  isPresent: newValue,
);
```

### Connection Handling
```dart
// Monitor connectivity and adapt behavior
_dataService.connectionStatusStream.listen((isOnline) {
  if (mounted) {
    setState(() {
      _isOnline = isOnline;
    });
  }
});
```

## Error Handling

### Network Failures
- Graceful fallback to cached data
- Queue changes for later sync
- User notification of offline mode

### Sync Failures
- Automatic retry with exponential backoff
- Error logging for debugging
- User notification of sync issues

### Data Integrity
- Transaction-based database operations
- Rollback on sync failures
- Conflict resolution for concurrent changes

## Testing Scenarios

### Network Conditions
1. **Stable Connection**: Normal operation with real-time sync
2. **Intermittent Connection**: Seamless switching between modes
3. **No Connection**: Full offline functionality
4. **Slow Connection**: Background sync without blocking UI

### Data Scenarios
1. **Large Datasets**: Efficient handling of thousands of attendees
2. **Frequent Changes**: Multiple attendance updates in sequence
3. **Concurrent Users**: Proper conflict resolution
4. **Data Corruption**: Recovery and error handling

## Configuration

### Sync Intervals
- **Background Sync**: Every 30 seconds when online
- **Force Sync**: Manual trigger available
- **Retry Interval**: Exponential backoff (5s, 10s, 20s, etc.)

### Cache Limits
- **SQLite Size**: Unlimited (managed by OS)
- **Memory Cache**: Efficient data structures
- **Cleanup**: Automatic removal of old cache entries

## Migration Guide

### Existing Code Updates
1. Replace direct Supabase calls with DataService methods
2. Listen to data streams instead of manual refreshes
3. Use optimistic updates for better UX
4. Add connection status indicators

### New Dependencies
```yaml
dependencies:
  connectivity_plus: ^6.2.0
  sqflite: ^2.3.0
```

This implementation ensures that the application works seamlessly in all network conditions while providing excellent user experience through optimistic updates and intelligent caching strategies.