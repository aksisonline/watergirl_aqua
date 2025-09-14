# Sample Data Setup Guide

This guide provides sample SQL statements to set up test data for the WaterGirl Aqua application with the new UAC system and slot-based attendance.

## 1. Create Sample Volunteer Access Codes

```sql
INSERT INTO volunteer_access (uac, name) VALUES
('VOL001', 'John Smith'),
('VOL002', 'Sarah Johnson'),
('VOL003', 'Mike Davis'),
('ADMIN01', 'Administrator'),
('TEMP123', 'Temporary Volunteer');
```

## 2. Create Sample Properties

```sql
INSERT INTO properties (property_name, property_options) VALUES
('room', 'A101,A102,A103,B201,B202,B203,C301,C302'),
('team_name', 'Alpha,Beta,Gamma,Delta,Echo,Foxtrot'),
('department', 'Engineering,Marketing,Sales,HR,Finance,Operations'),
('role', 'Lead,Member,Observer,Coordinator'),
('shift', 'Morning,Afternoon,Evening,Night');
```

## 3. Create Sample Time Slots

```sql
INSERT INTO slots (slot_id, slot_name, slot_time_frame) VALUES
('1', 'Morning Briefing', '09:00-09:30'),
('2', 'Session 1', '09:30-11:00'),
('3', 'Break Session', '11:15-11:30'),
('4', 'Session 2', '11:30-13:00'),
('5', 'Lunch Break', '13:00-14:00'),
('6', 'Session 3', '14:00-15:30'),
('7', 'Session 4', '15:45-17:15'),
('8', 'Evening Wrap-up', '17:15-17:45');
```

## 4. Create Sample Attendees

```sql
INSERT INTO attendee_details (attendee_name, attendee_properties) VALUES
('Alice Johnson', '{"room": "A101", "team_name": "Alpha", "department": "Engineering", "role": "Lead"}'),
('Bob Wilson', '{"room": "A102", "team_name": "Beta", "department": "Marketing", "role": "Member"}'),
('Carol Brown', '{"room": "B201", "team_name": "Gamma", "department": "Sales", "role": "Coordinator"}'),
('David Lee', '{"room": "B202", "team_name": "Delta", "department": "HR", "role": "Observer"}'),
('Emma Davis', '{"room": "C301", "team_name": "Echo", "department": "Finance", "role": "Lead"}'),
('Frank Miller', '{"room": "C302", "team_name": "Foxtrot", "department": "Operations", "role": "Member"}'),
('Grace Taylor', '{"room": "A103", "team_name": "Alpha", "department": "Engineering", "role": "Member"}'),
('Henry Clark', '{"room": "A101", "team_name": "Beta", "department": "Marketing", "role": "Member"}'),
('Ivy Rodriguez', '{"room": "B203", "team_name": "Gamma", "department": "Sales", "role": "Lead"}'),
('Jack Thompson', '{"room": "C301", "team_name": "Delta", "department": "HR", "role": "Member"}');
```

## 5. Create Sample QR Assignments

After creating attendees, you can simulate QR code assignments:

```sql
-- Assign QR codes to some attendees
UPDATE attendee_details SET attendee_internal_uid = 'QR001' WHERE attendee_name = 'Alice Johnson';
UPDATE attendee_details SET attendee_internal_uid = 'QR002' WHERE attendee_name = 'Bob Wilson';
UPDATE attendee_details SET attendee_internal_uid = 'QR003' WHERE attendee_name = 'Carol Brown';
UPDATE attendee_details SET attendee_internal_uid = 'QR004' WHERE attendee_name = 'David Lee';
UPDATE attendee_details SET attendee_internal_uid = 'QR005' WHERE attendee_name = 'Emma Davis';
```

## 6. Create Sample Attendance Records

```sql
-- Add sample attendance records for some attendees
UPDATE attendee_details 
SET attendee_attendance = '[
    {"slot_id": "1", "attendance_bool": true},
    {"slot_id": "2", "attendance_bool": true},
    {"slot_id": "4", "attendance_bool": false},
    {"slot_id": "6", "attendance_bool": true}
]'
WHERE attendee_name = 'Alice Johnson';

UPDATE attendee_details 
SET attendee_attendance = '[
    {"slot_id": "1", "attendance_bool": false},
    {"slot_id": "2", "attendance_bool": true},
    {"slot_id": "4", "attendance_bool": true}
]'
WHERE attendee_name = 'Bob Wilson';

UPDATE attendee_details 
SET attendee_attendance = '[
    {"slot_id": "1", "attendance_bool": true},
    {"slot_id": "2", "attendance_bool": true},
    {"slot_id": "4", "attendance_bool": true},
    {"slot_id": "6", "attendance_bool": true},
    {"slot_id": "7", "attendance_bool": false}
]'
WHERE attendee_name = 'Carol Brown';
```

## 7. Set App Title (slot_details table)

```sql
INSERT INTO slot_details (label) VALUES ('WaterGirl Aqua - Event Management');
```

## 8. Testing Scenarios

### Test UAC Login:
- Use any of the UAC codes: `VOL001`, `VOL002`, `VOL003`, `ADMIN01`, `TEMP123`

### Test QR Registration:
- Use attendees without `attendee_internal_uid` (Emma Davis onward)
- Scan any QR code value (simulate with text like `QR006`, `QR007`, etc.)

### Test QR Search:
- Use existing QR codes: `QR001`, `QR002`, `QR003`, `QR004`, `QR005`

### Test Property Search:
- Search for: "Alpha", "Engineering", "A101", "Lead", etc.

### Test Time-based Attendance:
- Modify slot time frames to current time for testing:
```sql
UPDATE slots SET slot_time_frame = '10:00-23:59' WHERE slot_id = '2';
```

## 9. Database Indexes for Performance

```sql
-- Add indexes for better performance
CREATE INDEX idx_attendee_uid ON attendee_details(attendee_internal_uid);
CREATE INDEX idx_volunteer_uac ON volunteer_access(uac);
CREATE INDEX idx_attendee_name ON attendee_details(attendee_name);
CREATE INDEX idx_slot_id ON slots(slot_id);
```

## 10. Quick Verification Queries

```sql
-- Verify setup
SELECT 'Volunteers' as table_name, COUNT(*) as count FROM volunteer_access
UNION ALL
SELECT 'Properties', COUNT(*) FROM properties
UNION ALL
SELECT 'Slots', COUNT(*) FROM slots
UNION ALL
SELECT 'Attendees', COUNT(*) FROM attendee_details
UNION ALL
SELECT 'Attendees with QR', COUNT(*) FROM attendee_details WHERE attendee_internal_uid IS NOT NULL;

-- Check property distribution
SELECT 
    json_extract_path_text(attendee_properties, 'team_name') as team,
    COUNT(*) as count
FROM attendee_details 
WHERE attendee_properties IS NOT NULL
GROUP BY json_extract_path_text(attendee_properties, 'team_name');
```

## Notes for Testing

1. **Time-based Testing**: Adjust slot time frames to current time for testing attendance marking
2. **QR Simulation**: Use any string value to simulate QR codes during testing
3. **Property Filtering**: Test search with property values like "Alpha", "Engineering", etc.
4. **UAC Testing**: All provided UAC codes should grant access to the dashboard
5. **Real-time Slot**: Only one slot should be active at any given time based on current time

This sample data provides a comprehensive testing environment for all the implemented features.