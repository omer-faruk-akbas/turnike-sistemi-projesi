import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter_nfc_kit/flutter_nfc_kit.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _kartController = TextEditingController();
  final _isimController = TextEditingController();

  String? _error;
  bool _loading = false;

  Future<void> _register() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final kartUID = _kartController.text.trim();

      final ref = FirebaseDatabase.instance.ref("kullanicilar");
      final snapshot = await ref.get();

      bool kartZatenVar = false;
      for (final child in snapshot.children) {
        final veri = child.value as Map?;
        if (veri != null && veri["kart_uid"] == kartUID) {
          kartZatenVar = true;
          break;
        }
      }

      if (kartZatenVar) {
        setState(() {
          _error = "⚠️ Bu kart zaten başka bir kullanıcı tarafından kayıt edilmiş.";
          _loading = false;
        });
        return;
      }

      final userCredential = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );

      final uid = userCredential.user!.uid;
      await FirebaseDatabase.instance.ref("kullanicilar/$uid").set({
        "isim": _isimController.text.trim(),
        "email": _emailController.text.trim(),
        "kart_uid": kartUID,
        "yetkili": false,
        "devre_disi": true,
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("✅ Kayıt başarılı! Giriş ekranına yönlendiriliyorsunuz...")),
      );
      Navigator.pop(context);
    } on FirebaseAuthException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = "Beklenmeyen hata: $e");
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _taratNFC() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        content: Text("📲 Kartı telefonun arkasına yaklaştırın..."),
      ),
    );

    try {
      final tag = await FlutterNfcKit.poll(timeout: const Duration(seconds: 10));
      _kartController.text = tag.id;
      await FlutterNfcKit.finish();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("NFC ile kart okunamadı: $e")),
      );
    } finally {
      Navigator.pop(context);
    }
  }

  Future<void> _espdenKartOku() async {
    final ref = FirebaseDatabase.instance.ref("tarama");

    await ref.child("kart_uid").set("");
    await ref.child("durum").set(true);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        content: Text("📡 Kartı ESP RFID okuyucuya yaklaştırın..."),
      ),
    );

    await Future.delayed(const Duration(seconds: 5));
    Navigator.pop(context);

    final snapshot = await ref.child("kart_uid").get();
    final uid = snapshot.value?.toString();

    if (uid != null && uid.isNotEmpty) {
      setState(() => _kartController.text = uid);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("⚠️ Kart okutulmadı")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text("Yeni Kayıt"),
        backgroundColor: Colors.red,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: SingleChildScrollView(
          child: Column(
            children: [
              const Text(
                "Yeni Kullanıcı Kaydı",
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 24),
              _inputField(_isimController, "İsim", Icons.person),
              const SizedBox(height: 12),
              _inputField(_emailController, "E-posta", Icons.email),
              const SizedBox(height: 12),
              _inputField(_passwordController, "Şifre", Icons.lock, obscure: true),
              const SizedBox(height: 12),
              _inputField(_kartController, "Kart UID", Icons.credit_card, readOnly: true),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _taratNFC,
                      icon: const Icon(Icons.nfc, color: Colors.white),
                      label: const Text("NFC ile Tara", style: TextStyle(color: Colors.white)),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _espdenKartOku,
                      icon: const Icon(Icons.sensor_door, color: Colors.white),
                      label: const Text("ESP ile Tara", style: TextStyle(color: Colors.white)),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              if (_error != null)
                Text(_error!, style: const TextStyle(color: Colors.red)),
              if (_loading)
                const CircularProgressIndicator()
              else
                ElevatedButton(
                  onPressed: _register,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 40),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    textStyle: const TextStyle(fontSize: 16),
                  ),
                  child: const Text("Kayıt Ol", style: TextStyle(color: Colors.white)),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _inputField(TextEditingController controller, String label, IconData icon,
      {bool obscure = false, bool readOnly = false}) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      readOnly: readOnly,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        filled: true,
        fillColor: Colors.white,
      ),
    );
  }
}
