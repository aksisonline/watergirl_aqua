import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth/login_signup.dart';
import 'dashboard/dashboard.dart';
import 'services/offline_service.dart';
import 'services/data_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: ".env");

  await Supabase.initialize(
    // GO TO important_creds.txt FOR YOUR_SUPABASE_URL AND ANON_KEY
    url: dotenv.env['SUPABASE_URL'] ?? '',
    anonKey: dotenv.env['SUPABASE_ANON_KEY'] ?? '',
  );

  // Initialize offline service for preload optimizations
  try {
    await OfflineService().initialize();
    await DataService().initialize();
  } catch (e) {
    print('Error initializing offline services: $e');
    // Continue with app launch even if offline services fail
  }

  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  MyAppState createState() => MyAppState();
}

class MyAppState extends State<MyApp> with WidgetsBindingObserver {

  Future<bool> _checkLoginStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final uac = prefs.getString('uac');

    if (uac != null) {
      // Verify that the UAC still exists in the database
      final SupabaseClient supabase = Supabase.instance.client;
      final response = await supabase
          .from('volunteer_access')
          .select()
          .eq('uac', uac)
          .maybeSingle();

      return response != null;
    }
    return false;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshSession();
    }
  }

  Future<void> _refreshSession() async {
    final session = Supabase.instance.client.auth.currentSession;

    if (session == null && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (ModalRoute.of(context)?.isCurrent == true) {
          Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
        }
      });
    } else {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    // const pastelPink = Color(0xFFF8BBD0);
    // const babyPink = Color(0xFFFFC1CC);
    // const white = Colors.white;
    // const black = Colors.black;
    //
    // ThemeData theme = ThemeData.light(
    //   useMaterial3: true,
    // ).copyWith(
    //   colorScheme: ColorScheme.fromSwatch().copyWith(
    //     primary: babyPink,
    //     secondary: pastelPink,
    //     onPrimary: babyPink,
    //     inversePrimary: babyPink,
    //     background: babyPink,
    //     onBackground: babyPink,
    //     inverseSurface: babyPink,
    //     onInverseSurface: babyPink,
    //     onSecondary: babyPink,
    //     onSurface: babyPink,
    //     onTertiary: babyPink,
    //     onTertiaryContainer: babyPink,
    //     tertiaryContainer: babyPink,
    //     tertiary: babyPink,
    //     brightness: Brightness.light,
    //     error: Colors.red,
    //     errorContainer: Colors.red,
    //     onError: babyPink,
    //     onErrorContainer: Colors.red,
    //     onPrimaryContainer: babyPink,
    //     onSecondaryContainer: pastelPink,
    //     onSurfaceVariant: babyPink,
    //     primaryContainer: babyPink,
    //     secondaryContainer: babyPink,
    //     surface: babyPink,
    //     surfaceVariant: babyPink,
    //     outlineVariant: babyPink,
    //     outline: babyPink,
    //     scrim: babyPink,
    //     shadow: babyPink,
    //     surfaceTint: babyPink,
    //   ),
    //   elevatedButtonTheme: ElevatedButtonThemeData(
    //     style: ButtonStyle(
    //       foregroundColor: MaterialStateProperty.all(Colors.black),
    //     ),
    //   ),
    // );
    //
    // ThemeData darkTheme = ThemeData.dark(
    //   useMaterial3: true,
    // ).copyWith(
    //   colorScheme: ColorScheme.fromSwatch().copyWith(
    //     primary: black,
    //     secondary: babyPink,
    //     onPrimary: babyPink,
    //     inversePrimary: babyPink,
    //     background: black,
    //     onBackground: babyPink,
    //     inverseSurface: black,
    //     onInverseSurface: babyPink,
    //     onSecondary: babyPink,
    //     onSurface: black,
    //     onTertiary: babyPink,
    //     onTertiaryContainer: black,
    //     tertiaryContainer: black,
    //     tertiary: babyPink,
    //     brightness: Brightness.dark,
    //     error: Colors.red,
    //     errorContainer: Colors.red,
    //     onError: babyPink,
    //     onErrorContainer: Colors.red,
    //     onPrimaryContainer: black,
    //     onSecondaryContainer: babyPink,
    //     onSurfaceVariant: black,
    //     primaryContainer: black,
    //     secondaryContainer: black,
    //     surface: black,
    //     surfaceVariant: black,
    //     outlineVariant: black,
    //     outline: black,
    //     scrim: black,
    //     shadow: black,
    //     surfaceTint: black,
    //   ),
    //   textTheme: const TextTheme(
    //     bodyMedium: TextStyle(color: black),
    //
    //   ),
    //   listTileTheme: const ListTileThemeData(
    //     textColor: black,
    //   ),
    //   inputDecorationTheme: const InputDecorationTheme(
    //
    //     labelStyle: TextStyle(color: black),
    //     floatingLabelStyle: TextStyle(color: black),
    //
    //   ),
    //   scaffoldBackgroundColor: babyPink,
    //   elevatedButtonTheme: ElevatedButtonThemeData(
    //     style: ButtonStyle(
    //       foregroundColor: MaterialStateProperty.all(Colors.white),
    //     ),
    //   ),
    // );

    return FutureBuilder<bool>(
      future: _checkLoginStatus(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(
            child: Image.asset(
              'assets/logo/4x/Asset_2xxxhdpi.png', // Update this path to your launcher icon path
              width: 200, // Adjust the size as needed
              // height: 200,
            ),
          );
        } else {
          return MaterialApp(
            themeMode: ThemeMode.system,
            theme: ThemeData.light(
              useMaterial3: true,
            ).copyWith(
              elevatedButtonTheme: ElevatedButtonThemeData(
                style: ButtonStyle(
                  foregroundColor: MaterialStateProperty.all(Colors.black),
                ),
              ),
            ),
            darkTheme: ThemeData.dark(
              useMaterial3: true,
            ).copyWith(
              elevatedButtonTheme: ElevatedButtonThemeData(
                style: ButtonStyle(
                  foregroundColor: MaterialStateProperty.all(Colors.white),
                ),
              ),
            ),

            debugShowCheckedModeBanner: false,
            initialRoute: snapshot.hasData && snapshot.data == true ? '/homepage' : '/',
            routes: {
              '/': (context) => const LoginPage(),
              '/homepage': (context) => const Dashboard(),
            },
          );
        }
      },
    );
  }
}