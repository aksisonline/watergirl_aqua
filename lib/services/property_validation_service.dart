import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PropertyConflict {
  final String propertyName;
  final String existingValue;
  final String newValue;

  PropertyConflict({
    required this.propertyName,
    required this.existingValue,
    required this.newValue,
  });
}

class ValidationResult {
  final bool isValid;
  final List<PropertyConflict> conflicts;
  final String? message;

  ValidationResult.success() : isValid = true, conflicts = [], message = null;
  
  ValidationResult.conflict(this.conflicts) 
      : isValid = false, 
        message = 'Property conflicts detected';
  
  ValidationResult.error(this.message) 
      : isValid = false, 
        conflicts = [];
}

class PropertyValidationService {
  static const String _buildingKey = 'default_building';
  static const String _roomKey = 'default_room';

  /// Get volunteer's default property settings from SharedPreferences
  static Future<Map<String, String?>> getVolunteerSettings() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'building': prefs.getString(_buildingKey),
      'room': prefs.getString(_roomKey),
    };
  }

  /// Save volunteer's default property settings to SharedPreferences
  static Future<void> saveVolunteerSettings({
    required String building,
    required String room,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_buildingKey, building);
    await prefs.setString(_roomKey, room);
  }

  /// Check if volunteer has configured their default property settings
  static Future<bool> hasConfiguredSettings() async {
    final settings = await getVolunteerSettings();
    return settings['building'] != null && 
           settings['room'] != null && 
           settings['building']!.isNotEmpty && 
           settings['room']!.isNotEmpty;
  }

  /// Validate before scanning any QR code
  static Future<ValidationResult> validateBeforeScan(String attendeeId) async {
    try {
      // Get volunteer's current settings
      final volunteerSettings = await getVolunteerSettings();
      
      if (volunteerSettings['building'] == null || volunteerSettings['room'] == null) {
        return ValidationResult.error(
          'Please configure your default building and room settings first.'
        );
      }

      // Fetch existing attendee properties from database
      final existingProperties = await _getAttendeeProperties(attendeeId);
      
      if (existingProperties.isNotEmpty) {
        // Check for conflicts
        final conflicts = _findConflicts(existingProperties, volunteerSettings);
        if (conflicts.isNotEmpty) {
          return ValidationResult.conflict(conflicts);
        }
      }
      
      return ValidationResult.success();
    } catch (e) {
      return ValidationResult.error('Error validating properties: ${e.toString()}');
    }
  }

  /// Fetch attendee's existing properties from the database
  static Future<Map<String, dynamic>> _getAttendeeProperties(String attendeeId) async {
    try {
      final supabase = Supabase.instance.client;
      
      // Query the attendees table for existing properties
      final response = await supabase
          .from('attendees')
          .select('properties')
          .eq('attendee_id', attendeeId)
          .maybeSingle();

      if (response != null && response['properties'] != null) {
        return Map<String, dynamic>.from(response['properties']);
      }
      
      return {};
    } catch (e) {
      print('Error fetching attendee properties: $e');
      return {};
    }
  }

  /// Find conflicts between existing properties and volunteer settings
  static List<PropertyConflict> _findConflicts(
    Map<String, dynamic> existingProperties,
    Map<String, String?> volunteerSettings,
  ) {
    final conflicts = <PropertyConflict>[];

    // Check building conflict
    if (existingProperties['building'] != null && 
        existingProperties['building'] != volunteerSettings['building']) {
      conflicts.add(PropertyConflict(
        propertyName: 'Building',
        existingValue: existingProperties['building'].toString(),
        newValue: volunteerSettings['building'] ?? '',
      ));
    }

    // Check room conflict
    if (existingProperties['room'] != null && 
        existingProperties['room'] != volunteerSettings['room']) {
      conflicts.add(PropertyConflict(
        propertyName: 'Room',
        existingValue: existingProperties['room'].toString(),
        newValue: volunteerSettings['room'] ?? '',
      ));
    }

    return conflicts;
  }

  /// Get all available properties for configuration
  static Future<Map<String, List<String>>> getAvailableProperties() async {
    try {
      final supabase = Supabase.instance.client;
      
      // Fetch distinct buildings and rooms from properties table
      final response = await supabase
          .from('properties')
          .select('team_name, building, room');

      if (response == null) return {'buildings': [], 'rooms': []};

      final buildings = <String>{};
      final rooms = <String>{};

      for (final property in response) {
        if (property['building'] != null) {
          buildings.add(property['building'].toString());
        }
        if (property['room'] != null) {
          rooms.add(property['room'].toString());
        }
      }

      return {
        'buildings': buildings.toList()..sort(),
        'rooms': rooms.toList()..sort(),
      };
    } catch (e) {
      print('Error fetching available properties: $e');
      return {'buildings': [], 'rooms': []};
    }
  }

  /// Get rooms for a specific building
  static Future<List<String>> getRoomsForBuilding(String building) async {
    try {
      final supabase = Supabase.instance.client;
      
      final response = await supabase
          .from('properties')
          .select('room')
          .eq('building', building);

      if (response == null) return [];

      final rooms = <String>{};
      for (final property in response) {
        if (property['room'] != null) {
          rooms.add(property['room'].toString());
        }
      }

      return rooms.toList()..sort();
    } catch (e) {
      print('Error fetching rooms for building: $e');
      return [];
    }
  }

  /// Update attendee properties with volunteer's settings
  static Future<bool> updateAttendeeProperties(
    String attendeeId,
    Map<String, String?> volunteerSettings,
  ) async {
    try {
      final supabase = Supabase.instance.client;
      
      // Get existing properties
      final existingProperties = await _getAttendeeProperties(attendeeId);
      
      // Merge with new settings
      final updatedProperties = Map<String, dynamic>.from(existingProperties);
      updatedProperties['building'] = volunteerSettings['building'];
      updatedProperties['room'] = volunteerSettings['room'];
      
      // Update the database
      await supabase
          .from('attendees')
          .update({'properties': updatedProperties})
          .eq('attendee_id', attendeeId);

      return true;
    } catch (e) {
      print('Error updating attendee properties: $e');
      return false;
    }
  }
}