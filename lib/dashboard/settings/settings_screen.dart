import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/property_validation_service.dart';
import '../../services/notification_service.dart';
import '../../services/data_service.dart';
import '../../auth/property_settings_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({Key? key}) : super(key: key);

  @override
  SettingsScreenState createState() => SettingsScreenState();
}

class SettingsScreenState extends State<SettingsScreen> {
  final DataService _dataService = DataService();
  
  String? _currentBuilding;
  String? _currentRoom;
  String? _volunteerName;
  String? _volunteerUac;
  bool _notificationsEnabled = true;
  bool _isLoading = true;
  int _queuedChanges = 0;
  bool _isOnline = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final settings = await PropertyValidationService.getVolunteerSettings();
      
      setState(() {
        _currentBuilding = settings['building'];
        _currentRoom = settings['room'];
        _volunteerName = prefs.getString('volunteer_name');
        _volunteerUac = prefs.getString('uac');
        _notificationsEnabled = prefs.getBool('notifications_enabled') ?? true;
      });

      // Listen to data service for connection status
      _dataService.connectionStatusStream.listen((isOnline) {
        if (mounted) {
          setState(() {
            _isOnline = isOnline;
          });
        }
      });

      _updateQueuedChangesCount();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading settings: $e')),
        );
      }
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _updateQueuedChangesCount() async {
    final count = await _dataService.getQueuedChangesCount();
    if (mounted) {
      setState(() {
        _queuedChanges = count;
      });
    }
  }

  Future<void> _editPropertySettings() async {
    if (_volunteerUac == null || _volunteerName == null) return;

    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => PropertySettingsScreen(
          volunteerUac: _volunteerUac!,
          volunteerName: _volunteerName!,
          isFirstTimeSetup: false,
        ),
      ),
    );

    if (result == true) {
      // Reload settings after successful update
      _loadSettings();
    }
  }

  Future<void> _toggleNotifications(bool enabled) async {
    setState(() {
      _notificationsEnabled = enabled;
    });

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('notifications_enabled', enabled);

    if (enabled) {
      await NotificationService.initialize();
      NotificationService.startInterimLeaveTimer();
    } else {
      NotificationService.stopInterimLeaveTimer();
      await NotificationService.cancelAllNotifications();
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(enabled 
              ? 'Notifications enabled' 
              : 'Notifications disabled'),
        ),
      );
    }
  }

  Future<void> _syncData() async {
    try {
      await _dataService.refreshData();
      _updateQueuedChangesCount();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Data synced successfully'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Sync failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _clearCache() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear Cache'),
        content: const Text(
          'This will clear all locally cached data. Any unsaved changes will be lost. Are you sure?'
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Clear'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await _dataService.clearCache();
        _updateQueuedChangesCount();
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Cache cleared successfully'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to clear cache: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Logout'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
      
      // Stop notifications
      NotificationService.stopInterimLeaveTimer();
      await NotificationService.cancelAllNotifications();
      
      if (mounted) {
        Navigator.of(context).pushNamedAndRemoveUntil(
          '/',
          (route) => false,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final isLargeScreen = screenSize.width > 600;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        elevation: 2,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: EdgeInsets.all(isLargeScreen ? 24.0 : 16.0),
              children: [
                // User Information Section
                _buildSection(
                  title: 'User Information',
                  icon: Icons.person,
                  children: [
                    _buildInfoTile(
                      title: 'Volunteer Name',
                      subtitle: _volunteerName ?? 'Not available',
                      icon: Icons.person_outline,
                    ),
                    _buildInfoTile(
                      title: 'Access Code',
                      subtitle: _volunteerUac ?? 'Not available',
                      icon: Icons.key,
                    ),
                  ],
                ),

                const SizedBox(height: 24),

                // Property Settings Section
                _buildSection(
                  title: 'Property Settings',
                  icon: Icons.location_on,
                  children: [
                    _buildInfoTile(
                      title: 'Current Building',
                      subtitle: _currentBuilding ?? 'Not configured',
                      icon: Icons.business,
                    ),
                    _buildInfoTile(
                      title: 'Current Room',
                      subtitle: _currentRoom ?? 'Not configured',
                      icon: Icons.room,
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: _editPropertySettings,
                      icon: const Icon(Icons.edit),
                      label: const Text('Edit Property Settings'),
                      style: ElevatedButton.styleFrom(
                        padding: EdgeInsets.symmetric(
                          horizontal: isLargeScreen ? 24 : 16,
                          vertical: isLargeScreen ? 16 : 12,
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 24),

                // Notification Settings Section
                _buildSection(
                  title: 'Notification Settings',
                  icon: Icons.notifications,
                  children: [
                    SwitchListTile(
                      title: const Text('Enable Notifications'),
                      subtitle: const Text('Get alerts for interim leave timeouts'),
                      value: _notificationsEnabled,
                      onChanged: _toggleNotifications,
                      secondary: const Icon(Icons.notifications_active),
                    ),
                    if (_notificationsEnabled) ...[
                      const SizedBox(height: 8),
                      Text(
                        'You will receive notifications when attendees exceed their interim leave time limits.',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ],
                ),

                const SizedBox(height: 24),

                // Data Management Section
                _buildSection(
                  title: 'Data Management',
                  icon: Icons.storage,
                  children: [
                    // Connection Status
                    ListTile(
                      leading: Icon(
                        _isOnline ? Icons.cloud_done : Icons.cloud_off,
                        color: _isOnline ? Colors.green : Colors.red,
                      ),
                      title: Text(_isOnline ? 'Online' : 'Offline'),
                      subtitle: Text(_isOnline 
                          ? 'Connected to server' 
                          : 'Working in offline mode'),
                    ),
                    
                    // Queued Changes
                    if (_queuedChanges > 0)
                      ListTile(
                        leading: const Icon(Icons.sync, color: Colors.orange),
                        title: Text('$_queuedChanges Queued Changes'),
                        subtitle: const Text('Changes waiting to sync when online'),
                      ),

                    const SizedBox(height: 16),

                    // Sync Button
                    ElevatedButton.icon(
                      onPressed: _isOnline ? _syncData : null,
                      icon: const Icon(Icons.sync),
                      label: const Text('Sync Data'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                        padding: EdgeInsets.symmetric(
                          horizontal: isLargeScreen ? 24 : 16,
                          vertical: isLargeScreen ? 16 : 12,
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Clear Cache Button
                    OutlinedButton.icon(
                      onPressed: _clearCache,
                      icon: const Icon(Icons.clear_all),
                      label: const Text('Clear Cache'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.orange,
                        padding: EdgeInsets.symmetric(
                          horizontal: isLargeScreen ? 24 : 16,
                          vertical: isLargeScreen ? 16 : 12,
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 24),

                // App Information Section
                _buildSection(
                  title: 'App Information',
                  icon: Icons.info,
                  children: [
                    _buildInfoTile(
                      title: 'App Version',
                      subtitle: '2.0.0+1',
                      icon: Icons.info_outline,
                    ),
                    _buildInfoTile(
                      title: 'App Name',
                      subtitle: 'Ploof - WaterGirl v2',
                      icon: Icons.apps,
                    ),
                  ],
                ),

                const SizedBox(height: 32),

                // Logout Button
                Container(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _logout,
                    icon: const Icon(Icons.logout),
                    label: const Text('Logout'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.symmetric(
                        horizontal: isLargeScreen ? 32 : 24,
                        vertical: isLargeScreen ? 20 : 16,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 32),
              ],
            ),
    );
  }

  Widget _buildSection({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: Theme.of(context).primaryColor),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).primaryColor,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _buildInfoTile({
    required String title,
    required String subtitle,
    required IconData icon,
  }) {
    return ListTile(
      leading: Icon(icon, color: Colors.grey[600]),
      title: Text(title),
      subtitle: Text(subtitle),
      contentPadding: EdgeInsets.zero,
    );
  }
}