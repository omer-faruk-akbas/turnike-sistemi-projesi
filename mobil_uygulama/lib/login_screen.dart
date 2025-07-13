import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'register_screen.dart';
import 'admin_screen.dart';
import 'user_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  String? _error;
  bool _loading = false;
  bool _turnikeOpen = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    if (email.isEmpty) {
      setState(() => _error = "E-posta adresi boş olamaz");
      return;
    }

    if (password.isEmpty) {
      setState(() => _error = "Şifre boş olamaz");
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final credential = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      setState(() => _turnikeOpen = !_turnikeOpen);

      if (credential.user != null) {
        final uid = credential.user!.uid;
        final ref = FirebaseDatabase.instance.ref("kullanicilar/$uid");
        final snapshot = await ref.get();

        if (!snapshot.exists) {
          setState(() {
            _error = "Kullanıcı bilgileri alınamadı";
            _loading = false;
          });
          return;
        }

        final data = Map<String, dynamic>.from(snapshot.value as Map);
        final bool yetkili = data["yetkili"] == true;
        final bool devreDisi = data["devre_disi"] == true;

        if (devreDisi) {
          setState(() {
            _error = "🚫 Hesabınız henüz aktif değil. Yönetici onayı bekleniyor.";
            _loading = false;
          });
          return;
        }

        if (!mounted) return;

        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
              builder: (_) => yetkili ? const AdminScreen() : const UserScreen()),
        );
      }
    } on FirebaseAuthException catch (e) {
      setState(() {
        switch (e.code) {
          case 'user-not-found':
            _error = "Bu e-posta adresiyle kayıtlı kullanıcı bulunamadı";
            break;
          case 'wrong-password':
            _error = "Yanlış şifre girdiniz";
            break;
          case 'invalid-email':
            _error = "Geçersiz e-posta adresi";
            break;
          default:
            _error = e.message ?? "Giriş yapılırken bir hata oluştu";
        }
      });
    } catch (e) {
      setState(() => _error = "Beklenmeyen bir hata oluştu");
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: SingleChildScrollView(
            child: Column(
              children: [
                const Text(
                  "Turnike Giriş Sistemi",
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    color: Color.fromRGBO(30, 50, 200, 1),
                  ),
                ),
                const SizedBox(height: 24),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 600),
                  transitionBuilder: (child, animation) =>
                      ScaleTransition(scale: animation, child: child),
                  child: Icon(
                    _turnikeOpen ? Icons.door_sliding : Icons.door_front_door,
                    key: ValueKey(_turnikeOpen),
                    size: 90,
                    color: Colors.red.shade400,
                  ),
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: _emailController,
                  decoration: _inputStyle("E-posta", Icons.email),
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _passwordController,
                  obscureText: true,
                  decoration: _inputStyle("Şifre", Icons.lock),
                  onSubmitted: (_) => _login(),
                ),
                const SizedBox(height: 24),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Text(
                      _error!,
                      style: const TextStyle(color: Colors.red),
                      textAlign: TextAlign.center,
                    ),
                  ),
                _loading
                    ? const CircularProgressIndicator()
                    : ElevatedButton(
                  onPressed: _login,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red[600],
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        vertical: 14, horizontal: 40),
                    textStyle: const TextStyle(fontSize: 16),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  child: const Text("Giriş Yap"),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const RegisterScreen()),
                    );
                  },
                  child: const Text("📋 Hesabınız yok mu? Kayıt olun"),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _inputStyle(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      filled: true,
      fillColor: Colors.white,
    );
  }
}
