import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:watergirl_aqua/dashboard/dashboard.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  LoginPageState createState() => LoginPageState();
}

class LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _accessCodeController = TextEditingController();
  bool _isLoading = false;

  Future<void> _signIn(BuildContext context) async {
    if (_formKey.currentState!.validate()) {
      setState(() {
        _isLoading = true;
      });

      final SupabaseClient supabase = Supabase.instance.client;

      try {
        final response = await supabase
            .from('volunteer_access')
            .select('uac, name')
            .eq('uac', _accessCodeController.text.trim())
            .maybeSingle();

        setState(() {
          _isLoading = false;
        });

        if (response != null) {
          // Save session data
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('uac', _accessCodeController.text.trim());
          await prefs.setString('volunteer_name', response['name']);

          if (mounted) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => const Dashboard()),
            );
          }
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Invalid Access Code')),
            );
          }
        }
      } catch (e) {
        setState(() {
          _isLoading = false;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: ${e.toString()}')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                'Volunteer Access',
                style: TextStyle(fontSize: 36, fontWeight: FontWeight.bold),
              ), const SizedBox(height: 32),
              TextFormField(
                controller: _accessCodeController,
                decoration: InputDecoration(
                  contentPadding: const EdgeInsets.symmetric(vertical: 15, horizontal: 10),
                  label: const Text('Access Code'),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: const BorderSide(color: Colors.black, width: 1),
                  ),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter your access code';
                  }
                  return null;
                },
              ), const SizedBox(height: 24),
              _isLoading
              ? const CircularProgressIndicator()
              : ElevatedButton(
                onPressed: () => _signIn(context),
                child: const Text('Access Dashboard'),
              ),

            ],
          ),
        ),
      ),
    );
  }
}