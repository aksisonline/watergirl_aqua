import 'dart:convert';
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
      
      // Fetch building and room properties from properties table
      final response = await supabase
          .from('properties')
          .select('property_name, property_options')
          .inFilter('property_name', ['building', 'room']);

      if (response.isEmpty) return {'buildings': [], 'rooms': []};

      final buildings = <String>[];
      final rooms = <String>[];

      for (final property in response) {
        final propertyName = property['property_name'] as String;
        final propertyOptions = property['property_options'] as String;

        if (propertyName == 'building') {
          // Parse comma-separated building options
          buildings.addAll(
            propertyOptions.split(',').map((b) => b.trim()).where((b) => b.isNotEmpty)
          );
        } else if (propertyName == 'room') {
          // Parse room options - could be JSON or comma-separated
          try {
            // Try parsing as JSON first (new nested format)
            final roomsByBuilding = jsonDecode(propertyOptions) as Map<String, dynamic>;
            for (final buildingRooms in roomsByBuilding.values) {
              if (buildingRooms is List) {
                rooms.addAll((buildingRooms as List).map((r) => r.toString()));
              }
            }
          } catch (e) {
            // Fallback to comma-separated format (old format)
            rooms.addAll(
              propertyOptions.split(',').map((r) => r.trim()).where((r) => r.isNotEmpty)
            );
          }
        }
      }

      return {
        'buildings': buildings.toSet().toList()..sort(),
        'rooms': rooms.toSet().toList()..sort(),
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
          .select('property_options')
          .eq('property_name', 'room')
          .single();

      if (response == null) return [];

      final propertyOptions = response['property_options'] as String;

      try {
        // Try parsing as JSON first (new nested format)
        final roomsByBuilding = jsonDecode(propertyOptions) as Map<String, dynamic>;
        
        if (roomsByBuilding.containsKey(building)) {
          final buildingRooms = roomsByBuilding[building];
          if (buildingRooms is List) {
            return (buildingRooms as List).map((r) => r.toString()).toList()..sort();
          }
        }
        return [];
      } catch (e) {
        // Fallback: if JSON parsing fails, return empty list 
        // (old comma-separated format doesn't support building associations)
        print('Error parsing room JSON for building $building: $e');
        return [];
      }
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