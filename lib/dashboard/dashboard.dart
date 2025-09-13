import 'package:watergirl_aqua/dashboard/register/attendee_list.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:watergirl_aqua/dimensions.dart';
import '/auth/login_signup.dart';
import 'search/search.dart';
import 'package:watergirl_aqua/dashboard/qr/qr.dart';
import 'register/qr_search.dart';

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
  late List<Widget> _widgetOptions;

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.initialIndex;
    _fetchAppBarTitle();
    _widgetOptions = <Widget>[
      const AttendeeListNoUIDPage(),
      const SearchPage(),
      QRScannerPage(key: qrScannerKey), // Use the GlobalKey here
      const QRSearchPage(), // Add QR Search page
    ];
  }

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  Future<void> _fetchAppBarTitle() async {
    final supabase = Supabase.instance.client;
    final response = await supabase.from('slot_details').select('label');
    setState(() {
      _appBarTitle = response[0]['label'];
    });
  }

  void _reloadCurrentPage() async {
    if (!mounted) return; // Check if the widget is still mounted

    if (_selectedIndex < 3) {
      Navigator.pushReplacement(
        context,
        PageRouteBuilder(
          pageBuilder: (context, animation1, animation2) => Dashboard(initialIndex: _selectedIndex),
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
        ),
      );
    } else {
      // Handle refresh for QRPage if needed
      final qrPageState = qrScannerKey.currentState;
      if (qrPageState != null && qrPageState.mounted) {
        qrPageState.refreshCamera();
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
            title: Text(_appBarTitle),
            actions: [
              IconButton(
                icon: const Icon(Icons.refresh),
                iconSize: 25,
                onPressed: _reloadCurrentPage,
              ),
              IconButton(
                icon: const Icon(Icons.logout),
                iconSize: 20,
                onPressed: () async {
                  await supabase.auth.signOut();
                  _signOut(context);
                },
              ),
            ],
          ),
          body: _widgetOptions.elementAt(_selectedIndex),
          bottomNavigationBar: SizedBox(
            height: heightBottomNavigationBar,
            child: BottomNavigationBar(
              elevation: 0,
              // backgroundColor: Colors.black26,
              selectedIconTheme: const IconThemeData(size: 30),
              currentIndex: _selectedIndex,
              onTap: _onItemTapped,
              showSelectedLabels: false,
              showUnselectedLabels: false,
              type: BottomNavigationBarType.fixed, // Add this to show all 4 tabs
              items: const [
                BottomNavigationBarItem(icon: Icon(Icons.qr_code), label: 'QR'),
                BottomNavigationBarItem(icon: Icon(Icons.search), label: 'Search'),
                BottomNavigationBarItem(icon: Icon(Icons.document_scanner_outlined), label: 'QR Scanner'),
                BottomNavigationBarItem(icon: Icon(Icons.qr_code_scanner), label: 'QR Search'),
              ],
            ),
          ),
        ),
      ),
    );
  }
}