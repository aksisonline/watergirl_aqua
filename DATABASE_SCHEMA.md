# Database Schema Documentation for WaterGirl Aqua

This document outlines the required database table structures for the WaterGirl Aqua application after implementing the UAC (Unique Access Code) system and slot-based attendance.

## Tables

### 1. volunteer_access
Replaces the old `volunteer_login` table to use unique access codes instead of email/password.

```sql
CREATE TABLE volunteer_access (
    id SERIAL PRIMARY KEY,
    uac VARCHAR(50) UNIQUE NOT NULL,
    name VARCHAR(255) NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
```

**Purpose**: Store volunteer access codes and associated names for authentication.

**Columns**:
- `id`: Primary key
- `uac`: Unique Access Code (string, 50 chars max, unique)
- `name`: Volunteer name for logging purposes
- `created_at`: Record creation timestamp
- `updated_at`: Record last update timestamp

### 2. attendee_details (Updated)
Modified to use the new structure with internal UIDs, properties, and attendance tracking.

```sql
CREATE TABLE attendee_details (
    id SERIAL PRIMARY KEY,
    attendee_internal_uid VARCHAR(255) UNIQUE,
    attendee_name VARCHAR(255) NOT NULL,
    attendee_properties JSONB,
    attendee_attendance JSONB,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
```

**Purpose**: Store attendee information with their QR-assigned UIDs, properties, and attendance records.

**Columns**:
- `id`: Primary key
- `attendee_internal_uid`: QR code value assigned to the attendee (nullable until assigned)
- `attendee_name`: Full name of the attendee
- `attendee_properties`: JSON object storing dynamic properties (e.g., `{"room": "A101", "team_name": "Alpha"}`)
- `attendee_attendance`: JSON array of attendance records (e.g., `[{"slot_id": "1", "attendance_bool": true}, {"slot_id": "2", "attendance_bool": false}]`)
- `created_at`: Record creation timestamp
- `updated_at`: Record last update timestamp

### 3. properties
Store available property types and their possible values for dynamic property management.

```sql
CREATE TABLE properties (
    id SERIAL PRIMARY KEY,
    property_name VARCHAR(255) NOT NULL,
    property_options TEXT NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
```

**Purpose**: Define available properties that can be assigned to attendees and their possible values.

**Columns**:
- `id`: Primary key
- `property_name`: Name of the property (e.g., "room", "team_name", "department")
- `property_options`: Comma-separated list of possible values (e.g., "A101,A102,B201,B202")
- `created_at`: Record creation timestamp
- `updated_at`: Record last update timestamp

**Example Data**:
```sql
INSERT INTO properties (property_name, property_options) VALUES
('room', 'A101,A102,A103,B201,B202,B203'),
('team_name', 'Alpha,Beta,Gamma,Delta'),
('department', 'Engineering,Marketing,Sales,HR');
```

### 4. slots
Define time slots for attendance tracking with time-based restrictions.

```sql
CREATE TABLE slots (
    slot_id VARCHAR(50) PRIMARY KEY,
    slot_name VARCHAR(255) NOT NULL,
    slot_time_frame VARCHAR(100) NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
```

**Purpose**: Define time slots during which attendance can be marked.

**Columns**:
- `slot_id`: Unique identifier for the slot
- `slot_name`: Human-readable name for the slot
- `slot_time_frame`: Time range in HH:MM-HH:MM format (e.g., "09:00-10:30")
- `created_at`: Record creation timestamp
- `updated_at`: Record last update timestamp

**Example Data**:
```sql
INSERT INTO slots (slot_id, slot_name, slot_time_frame) VALUES
('1', 'Morning Session', '09:00-10:30'),
('2', 'Late Morning Session', '11:00-12:30'),
('3', 'Afternoon Session', '14:00-15:30'),
('4', 'Late Afternoon Session', '16:00-17:30');
```

### 5. slot_details (Existing - for app bar title)
Keep existing table for storing app configuration.

```sql
CREATE TABLE slot_details (
    id SERIAL PRIMARY KEY,
    label VARCHAR(255) NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
```

**Purpose**: Store application configuration like the app bar title.

## Relationships and Data Flow

### Attendance Marking Process:
1. Application loads current time slot from `slots` table
2. QR scan identifies attendee via `attendee_internal_uid`
3. Attendance is marked only if current time falls within active slot's `slot_time_frame`
4. Attendance record is stored in `attendee_attendance` as JSON array

### Property Management:
1. Available properties are defined in `properties` table
2. Each attendee can have dynamic properties stored in `attendee_properties` JSON
3. Properties can be searched and filtered in the search functionality

### Authentication Flow:
1. Volunteer enters UAC (Unique Access Code)
2. System validates against `volunteer_access` table
3. Successful authentication grants access to dashboard functionality

## Migration Notes

When implementing these tables in your NextJS webapp:

1. **Drop old tables**: Remove `volunteer_login` table if no longer needed
2. **Data migration**: If migrating existing attendee data, map old fields to new structure:
   - `name` → `attendee_name`
   - `email` → (remove or store in properties)
   - `uid` → `attendee_internal_uid`
   - `entry_time` → convert to attendance record format

3. **Initial data**: Create initial records in `properties` and `slots` tables
4. **Indexes**: Consider adding indexes on frequently queried columns:
   ```sql
   CREATE INDEX idx_attendee_uid ON attendee_details(attendee_internal_uid);
   CREATE INDEX idx_volunteer_uac ON volunteer_access(uac);
   ```

## Security Considerations

1. **UAC Generation**: Ensure unique access codes are generated securely
2. **Property Validation**: Validate property values against allowed options
3. **Time Validation**: Implement server-side time validation for slot restrictions
4. **Data Integrity**: Use database constraints to maintain data consistency

## App Features Enabled

This schema supports:
- ✅ UAC-based volunteer authentication
- ✅ QR code assignment to attendees
- ✅ Dynamic property management and filtering
- ✅ Time-slot based attendance marking
- ✅ QR search for direct profile access
- ✅ Attendance history tracking
- ✅ Property-based attendee search
- ✅ Time-restricted attendance marking