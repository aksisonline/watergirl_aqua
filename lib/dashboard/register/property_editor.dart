import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:convert';

class PropertyEditorPage extends StatefulWidget {
  final Map<String, dynamic> attendee;

  const PropertyEditorPage({super.key, required this.attendee});

  @override
  State<PropertyEditorPage> createState() => _PropertyEditorPageState();
}

class _PropertyEditorPageState extends State<PropertyEditorPage> {
  final SupabaseClient supabase = Supabase.instance.client;
  Map<String, dynamic> properties = {};
  Map<String, List<String>> availableProperties = {};
  bool _isLoading = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadProperties();
    _loadAvailableProperties();
  }

  Future<void> _loadProperties() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // Load existing properties from attendee_properties column
      if (widget.attendee['attendee_properties'] != null) {
        properties = json.decode(widget.attendee['attendee_properties']);
      }
    } catch (e) {
      print('Error loading properties: $e');
    }

    setState(() {
      _isLoading = false;
    });
  }

  Future<void> _loadAvailableProperties() async {
    try {
      final data = await supabase.from('properties').select('property_name, property_options');
      
      for (final row in data) {
        final propertyName = row['property_name'] as String;
        final propertyOptions = row['property_options'] as String;
        availableProperties[propertyName] = propertyOptions.split(',').map((e) => e.trim()).toList();
      }
      
      setState(() {});
    } catch (e) {
      print('Error loading available properties: $e');
    }
  }

  Future<void> _saveProperties() async {
    setState(() {
      _isSaving = true;
    });

    try {
      final propertiesJson = json.encode(properties);
      
      await supabase
          .from('attendee_details')
          .update({'attendee_properties': propertiesJson})
          .eq('attendee_internal_uid', widget.attendee['attendee_internal_uid']);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Properties saved successfully')),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving properties: $e')),
        );
      }
    }

    setState(() {
      _isSaving = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Properties'),
        actions: [
          if (_isSaving)
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            TextButton(
              onPressed: _saveProperties,
              child: const Text('Save'),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Attendee: ${widget.attendee['attendee_name'] ?? 'Unknown'}',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Properties:',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView.builder(
                      itemCount: availableProperties.length,
                      itemBuilder: (context, index) {
                        final propertyName = availableProperties.keys.elementAt(index);
                        final options = availableProperties[propertyName]!;
                        final currentValue = properties[propertyName];

                        return Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  propertyName,
                                  style: const TextStyle(fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 8),
                                DropdownButtonFormField<String>(
                                  value: currentValue,
                                  hint: Text('Select $propertyName'),
                                  items: [
                                    const DropdownMenuItem<String>(
                                      value: null,
                                      child: Text('None'),
                                    ),
                                    ...options.map((option) => DropdownMenuItem<String>(
                                      value: option,
                                      child: Text(option),
                                    )),
                                  ],
                                  onChanged: (value) {
                                    setState(() {
                                      if (value == null) {
                                        properties.remove(propertyName);
                                      } else {
                                        properties[propertyName] = value;
                                      }
                                    });
                                  },
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}