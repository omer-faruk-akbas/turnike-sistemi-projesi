import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'login_screen.dart';

class UserScreen extends StatefulWidget {
  const UserScreen({super.key});

  @override
  State<UserScreen> createState() => _UserScreenState();
}

class _UserScreenState extends State<UserScreen> {
  final uid = FirebaseAuth.instance.currentUser!.uid;
  final _isimController = TextEditingController();
  final _emailController = TextEditingController();
  final _kartController = TextEditingController();
  bool _loading = true;
  List<Map<String, dynamic>> _gecmis = [];
  String? _sonDurum;

  DatabaseReference? _sonDurumRef;
  Stream<DatabaseEvent>? _sonDurumStream;

  @override
  void initState() {
    super.initState();
    _getUserData();
    _getGecmis();
  }

  @override
  void dispose() {
    _sonDurumRef?.onValue.drain();
    super.dispose();
  }

  Future<void> _getUserData() async {
    final ref = FirebaseDatabase.instance.ref("kullanicilar/$uid");
    final snapshot = await ref.get();
    if (snapshot.exists) {
      final data = Map<String, dynamic>.from(snapshot.value as Map);
      final kartUid = data["kart_uid"] ?? "";

      setState(() {
        _isimController.text = data["isim"] ?? "";
        _emailController.text = data["email"] ?? "";
        _kartController.text = kartUid;
        _loading = false;
      });

      _listenToSondurum(kartUid);
    }
  }

  void _listenToSondurum(String kartUid) {
    _sonDurumRef = FirebaseDatabase.instance.ref("sondurum/$uid/$kartUid");
    _sonDurumRef!.onValue.listen((event) {
      if (event.snapshot.exists) {
        final data = Map<String, dynamic>.from(event.snapshot.value as Map);
        final durum = data["giris_cikis"];
        setState(() {
          _sonDurum = durum == "GIRIS"
              ? "🟢 ŞU ANDA: İÇERİDE"
              : "🔴 ŞU ANDA: DIŞARIDA";


          _getGecmis();
        }
        );
      } else {
        setState(() {
          _sonDurum = "❔ ŞU ANDA: BİLGİ YOK";
        });
      }
    });
  }

  Future<void> _getGecmis() async {
    final ref = FirebaseDatabase.instance.ref("loglar");
    final snapshot = await ref.get();

    List<Map<String, dynamic>> logs = [];

    if (snapshot.exists) {
      for (var log in snapshot.children) {
        final data = Map<String, dynamic>.from(log.value as Map);
        if (data["kart_uid"] == _kartController.text.trim()) {
          logs.add({
            "zaman": data["zaman"],
            "giris_cikis": data["giris_cikis"],
            "kaynak": data["kaynak"],
          });
        }
      }

      logs.sort((a, b) => (b["zaman"] as int).compareTo(a["zaman"] as int));
    }

    setState(() {
      _gecmis = logs;
    });
  }

  Future<void> _turnikeAc() async {
    final kontrolRef = FirebaseDatabase.instance.ref("kontrol/turnike_aktif");
    final kontrolSnap = await kontrolRef.get();

    // 🔒 Turnike devre dışıysa işlem yapılmasın
    if (!kontrolSnap.exists || kontrolSnap.value != true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("⛔ Turnike şu anda devre dışı.")),
      );
      return;
    }


    final kartUid = _kartController.text.trim();
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final tarih = DateTime.now();
    final tarihKey = "${tarih.year}${tarih.month.toString().padLeft(2, '0')}${tarih.day.toString().padLeft(2, '0')}";

    final sayacRef = FirebaseDatabase.instance.ref("sayaclar/$kartUid/$tarihKey");
    final sayacSnap = await sayacRef.get();
    int sayac = sayacSnap.exists ? sayacSnap.value as int : 0;

    final sonRef = FirebaseDatabase.instance.ref("sondurum/$uid/$kartUid");
    final sonSnap = await sonRef.get();

    String girisCikis = "GIRIS";
    if (sonSnap.exists) {
      final veri = Map<String, dynamic>.from(sonSnap.value as Map);
      if (veri["giris_cikis"] == "GIRIS") {
        girisCikis = "CIKIS";
      }
    }

    if (girisCikis == "GIRIS" && sayac >= 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("🚫 Günlük giriş hakkınız doldu.")),
      );
      return;
    }

    if (girisCikis == "GIRIS") {
      await sayacRef.set(sayac + 1);
    }

    await FirebaseDatabase.instance.ref("kontrol").update({
      "ac_istegi": true,
      "son_komut": "AC",
    });

    final log = {
      "uid": uid,
      "isim": _isimController.text.trim(),
      "kart_uid": kartUid,
      "giris_cikis": girisCikis,
      "kaynak": "UYGULAMA",
      "zaman": now,
    };

    await FirebaseDatabase.instance.ref("loglar").push().set(log);
    await FirebaseDatabase.instance.ref("sondurum/$uid/$kartUid").set(log);

    _getGecmis();

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("🚪 Turnike açıldı, durum güncellendi.")),
    );

    await FirebaseDatabase.instance.ref("kullanicilar/$uid").update({
      "son_giris": now,
    });
  }


  Future<void> _updateUserData() async {
    final ref = FirebaseDatabase.instance.ref("kullanicilar/$uid");
    await ref.update({
      "isim": _isimController.text.trim(),
      "email": _emailController.text.trim(),
      "kart_uid": _kartController.text.trim(),
    });
    _listenToSondurum(_kartController.text.trim());
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("✅ Bilgiler güncellendi")),
    );
  }

  void _logout() async {
    await FirebaseAuth.instance.signOut();
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
  }

  String _timestampToString(int timestamp) {
    final dt = DateTime.fromMillisecondsSinceEpoch(timestamp * 1000);
    return "${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')}.${dt.year}  ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}";
  }

  InputDecoration _inputStyle(String label) {
    return InputDecoration(
      labelText: label,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      filled: true,
      fillColor: Colors.white,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: Text("Hoşgeldiniz, ${_isimController.text}"),
        backgroundColor: Colors.red,
        foregroundColor: Colors.white,
        actions: [
          IconButton(onPressed: _logout, icon: const Icon(Icons.logout)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.account_circle, size: 100, color: Colors.blueGrey),
            const SizedBox(height: 16),
            TextField(controller: _isimController, decoration: _inputStyle("Adınız")),
            const SizedBox(height: 12),
            TextField(controller: _emailController, decoration: _inputStyle("E-posta")),
            const SizedBox(height: 12),
            TextField(controller: _kartController, decoration: _inputStyle("Kart UID")),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _updateUserData,
                    icon: const Icon(Icons.save),
                    label: const Text("Bilgileri Güncelle"),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _turnikeAc,
                    icon: const Icon(Icons.lock_open),
                    label: const Text("Turnikeyi Aç"),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_sonDurum != null)
              Text(
                _sonDurum!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
            const SizedBox(height: 32),
            const Text(
              "📜 Giriş / Çıkış Geçmişi",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            const Divider(thickness: 1),
            ..._gecmis.map((e) {
              return ListTile(
                leading: Icon(
                  e["giris_cikis"] == "GIRIS" ? Icons.login : Icons.logout,
                  color: e["giris_cikis"] == "GIRIS" ? Colors.green : Colors.red,
                ),
                title: Text("${e["giris_cikis"]} (${e["kaynak"]})"),
                subtitle: Text(_timestampToString(e["zaman"])),
              );
            }).toList(),
          ],
        ),
      ),
    );
  }
}
