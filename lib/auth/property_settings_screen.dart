import 'package:flutter/material.dart';
import '../services/property_validation_service.dart';
import '../dashboard/dashboard.dart';

class PropertySettingsScreen extends StatefulWidget {
  final String volunteerUac;
  final String volunteerName;
  final bool isFirstTimeSetup;

  const PropertySettingsScreen({
    super.key,
    required this.volunteerUac,
    required this.volunteerName,
    this.isFirstTimeSetup = true,
  });

  @override
  PropertySettingsScreenState createState() => PropertySettingsScreenState();
}

class PropertySettingsScreenState extends State<PropertySettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  
  String? _selectedBuilding;
  String? _selectedRoom;
  
  List<String> _availableBuildings = [];
  List<String> _availableRooms = [];
  
  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // Load available properties from database
      final properties = await PropertyValidationService.getAvailableProperties();
      _availableBuildings = properties['buildings'] ?? [];

      // Load existing settings if not first time setup
      if (!widget.isFirstTimeSetup) {
        final existingSettings = await PropertyValidationService.getVolunteerSettings();
        _selectedBuilding = existingSettings['building'];
        _selectedRoom = existingSettings['room'];
        
        // Load rooms for existing building
        if (_selectedBuilding != null) {
          _availableRooms = await PropertyValidationService.getRoomsForBuilding(_selectedBuilding!);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading properties: ${e.toString()}')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _onBuildingChanged(String? building) async {
    if (building == null) return;

    setState(() {
      _selectedBuilding = building;
      _selectedRoom = null; // Reset room when building changes
      _availableRooms = [];
    });

    // Load rooms for selected building
    try {
      final rooms = await PropertyValidationService.getRoomsForBuilding(building);
      if (mounted) {
        setState(() {
          _availableRooms = rooms;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading rooms: ${e.toString()}')),
        );
      }
    }
  }

  Future<void> _saveSettings() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    if (_selectedBuilding == null || _selectedRoom == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please select both building and room')),
        );
      }
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      // Save to SharedPreferences
      await PropertyValidationService.saveVolunteerSettings(
        building: _selectedBuilding!,
        room: _selectedRoom!,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Settings saved successfully!')),
        );

        // Navigate to dashboard
        if (widget.isFirstTimeSetup) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => const Dashboard()),
          );
        } else {
          Navigator.pop(context, true); // Return success
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving settings: ${e.toString()}')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  Future<void> _skipSetup() async {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => const Dashboard()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isFirstTimeSetup ? 'Setup Properties' : 'Property Settings'),
        automaticallyImplyLeading: !widget.isFirstTimeSetup,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16.0),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (widget.isFirstTimeSetup) ...[
                      Text(
                        'Welcome, ${widget.volunteerName}!',
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Please configure your default building and room settings. These will be used when marking attendance.',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.grey[600],
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],
                    
                    // Building Selection
                    Text(
                      'Building',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      initialValue: _selectedBuilding,
                      decoration: InputDecoration(
                        hintText: 'Select a building',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                      ),
                      items: _availableBuildings.map((building) {
                        return DropdownMenuItem<String>(
                          value: building,
                          child: Text(building),
                        );
                      }).toList(),
                      onChanged: _onBuildingChanged,
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Please select a building';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 24),

                    // Room Selection
                    Text(
                      'Room',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      initialValue: _selectedRoom,
                      decoration: InputDecoration(
                        hintText: _selectedBuilding == null 
                            ? 'Select a building first'
                            : 'Select a room',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                      ),
                      items: _availableRooms.map((room) {
                        return DropdownMenuItem<String>(
                          value: room,
                          child: Text(room),
                        );
                      }).toList(),
                      onChanged: _selectedBuilding == null 
                          ? null 
                          : (value) {
                              setState(() {
                                _selectedRoom = value;
                              });
                            },
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Please select a room';
                        }
                        return null;
                      },
                    ),
                    
                    const SizedBox(height: 32),
                    
                    // Information Card
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.blue[50],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.blue[200]!),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.info_outline, color: Colors.blue[600]),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'These settings will be applied to all attendees you scan. You can change them later in the settings menu.',
                              style: TextStyle(
                                color: Colors.blue[800],
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    
                    const Spacer(),
                    
                    // Action Buttons
                    Row(
                      children: [
                        if (widget.isFirstTimeSetup) ...[
                          Expanded(
                            child: TextButton(
                              onPressed: _isSaving ? null : _skipSetup,
                              child: const Text('Skip'),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: _isSaving ? null : _saveSettings,
                              child: _isSaving
                                  ? const SizedBox(
                                      height: 20,
                                      width: 20,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    )
                                  : const Text('Continue'),
                            ),
                          ),
                        ] else ...[
                          Expanded(
                            child: OutlinedButton(
                              onPressed: _isSaving ? null : () => Navigator.pop(context),
                              child: const Text('Cancel'),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: _isSaving ? null : _saveSettings,
                              child: _isSaving
                                  ? const SizedBox(
                                      height: 20,
                                      width: 20,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    )
                                  : const Text('Save Settings'),
                            ),
                          ),
                        ],
                      ],
                    ),
                    
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
    );
  }
}
