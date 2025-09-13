import 'package:watergirl_aqua/dashboard/register/attendee_list.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'; // For platform detection
import 'dart:io' show Platform; // For platform detection
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:watergirl_aqua/dimensions.dart';
import '/auth/login_signup.dart';
import 'search/search.dart';
import 'package:watergirl_aqua/dashboard/qr/qr.dart';
import '../services/data_service.dart';

class Dashboard extends StatefulWidget {
  final int initialIndex;

  const Dashboard({super.key, this.initialIndex = 0});

  @override
  State<Dashboard> createState() => _DashboardState();
}

class _DashboardState extends State<Dashboard> {
  late int _selectedIndex;
  String _appBarTitle = 'Home';
  final GlobalKey<QRScannerPageState> qrScannerKey = GlobalKey<QRScannerPageState>();
  final DataService _dataService = DataService();
  late List<Widget> _widgetOptions;
  
  // Define page titles
  final List<String> _pageTitles = [
    'Register Page',
    'Search',
    'QR Scanner', // This will be dynamic
  ];

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.initialIndex;
    _updateAppBarTitle(); // Update title on init
    _widgetOptions = <Widget>[
      const AttendeeListNoUIDPage(),
      const SearchPage(),
      QRScannerPage(key: qrScannerKey), // Use the GlobalKey here
    ];
  }

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
      _updateAppBarTitle(); // Update title when tab changes
    });
  }

  void _updateAppBarTitle() {
    setState(() {
      if (_selectedIndex == 2) {
        // For QR Scanner, we'll make it dynamic based on slot status
        _updateQRScannerTitle();
      } else {
        _appBarTitle = _pageTitles[_selectedIndex];
      }
    });
  }

  void _updateQRScannerTitle() async {
    // Use DataService instead of direct Supabase calls
    final currentSlot = _dataService.currentSlot;
    
    if (currentSlot != null) {
      final now = DateTime.now();
      final currentTime = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
      final timeFrame = currentSlot['slot_time_frame'] as String;
      
      if (_isTimeInRange(currentTime, timeFrame)) {
        setState(() {
          _appBarTitle = 'Attendance - ${currentSlot['slot_name']}';
        });
        return;
      }
    }
    
    setState(() {
      _appBarTitle = 'QR Scanner - Profile View';
    });
  }

  bool _isTimeInRange(String currentTime, String timeFrame) {
    try {
      final parts = timeFrame.split('-');
      if (parts.length != 2) return false;
      
      final startTime = parts[0].trim();
      final endTime = parts[1].trim();
      
      final current = _timeToMinutes(currentTime);
      final start = _timeToMinutes(startTime);
      final end = _timeToMinutes(endTime);
      
      return current >= start && current <= end;
    } catch (e) {
      return false;
    }
  }

  int _timeToMinutes(String time) {
    final parts = time.split(':');
    return int.parse(parts[0]) * 60 + int.parse(parts[1]);
  }

  Future<void> _fetchAppBarTitle() async {
    // This method is now handled by _updateAppBarTitle
    // Keep it for backwards compatibility but make it call the new method
    _updateAppBarTitle();
  }

  void _reloadCurrentPage() async {
    if (!mounted) return; // Check if the widget is still mounted

    // Use DataService for efficient refresh instead of full page reload
    try {
      await _dataService.refreshData();
      
      // Update title for QR scanner page
      if (_selectedIndex == 2) {
        _updateAppBarTitle();
      }
      
      // Refresh QR camera if needed
      if (_selectedIndex == 2) {
        final qrPageState = qrScannerKey.currentState;
        if (qrPageState != null && qrPageState.mounted) {
          qrPageState.refreshCamera();
        }
      }
    } catch (e) {
      print('Error refreshing data: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error refreshing: $e')),
        );
      }
    }
  }

  Future<void> _signOut(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('uac');
    await prefs.remove('volunteer_name');

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => const LoginPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final supabase = Supabase.instance.client;
    
    // Get screen size for responsive design
    final screenSize = MediaQuery.of(context).size;
    final isLargeScreen = screenSize.width > 600; // Web/desktop
    final isWebOrDesktop = kIsWeb || (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS));

    return PopScope(
      canPop: false,
      child: Container(
        // decoration: const BoxDecoration(
        //   image: DecorationImage(
        //     image: AssetImage("assets/scaffold_bg/erased.jpeg"),
        //     opacity: 0.5,
        //     fit: BoxFit.cover,
        //   ),
        // ),
        child: Scaffold(
          extendBody: true,
          // backgroundColor: Colors.transparent,
          appBar: AppBar(
            // backgroundColor: Colors.black26,
            scrolledUnderElevation: 0,
            leading: const SizedBox(),
            leadingWidth: 0,
            title: Text(
              _appBarTitle,
              style: TextStyle(
                fontSize: isLargeScreen ? 24 : 20,
                fontWeight: FontWeight.w600,
              ),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.refresh),
                iconSize: isLargeScreen ? 28 : 25,
                onPressed: _reloadCurrentPage,
                tooltip: 'Refresh',
              ),
              IconButton(
                icon: const Icon(Icons.logout),
                iconSize: isLargeScreen ? 24 : 20,
                onPressed: () async {
                  await supabase.auth.signOut();
                  _signOut(context);
                },
                tooltip: 'Logout',
              ),
              if (isLargeScreen) const SizedBox(width: 16), // Extra padding for large screens
            ],
          ),
          body: LayoutBuilder(
            builder: (context, constraints) {
              return Container(
                constraints: BoxConstraints(
                  maxWidth: isWebOrDesktop ? 1200 : double.infinity, // Max width for desktop
                ),
                child: _widgetOptions.elementAt(_selectedIndex),
              );
            },
          ),
          bottomNavigationBar: Container(
            constraints: BoxConstraints(
              maxWidth: isWebOrDesktop ? 1200 : double.infinity,
            ),
            child: SizedBox(
              height: isLargeScreen ? heightBottomNavigationBar + 10 : heightBottomNavigationBar,
              child: BottomNavigationBar(
                elevation: 0,
                // backgroundColor: Colors.black26,
                selectedIconTheme: IconThemeData(size: isLargeScreen ? 35 : 30),
                unselectedIconTheme: IconThemeData(size: isLargeScreen ? 30 : 24),
                selectedLabelStyle: TextStyle(fontSize: isLargeScreen ? 14 : 12),
                unselectedLabelStyle: TextStyle(fontSize: isLargeScreen ? 12 : 10),
                currentIndex: _selectedIndex,
                onTap: _onItemTapped,
                showSelectedLabels: isLargeScreen, // Show labels on large screens
                showUnselectedLabels: isLargeScreen,
                type: BottomNavigationBarType.fixed, // Add this to show all tabs
                items: const [
                  BottomNavigationBarItem(icon: Icon(Icons.qr_code), label: 'Register'),
                  BottomNavigationBarItem(icon: Icon(Icons.search), label: 'Search'),
                  BottomNavigationBarItem(icon: Icon(Icons.document_scanner_outlined), label: 'QR Scanner'),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}