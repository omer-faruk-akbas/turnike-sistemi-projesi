import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';

class AdminControlScreen extends StatefulWidget {
  const AdminControlScreen({super.key});

  @override
  State<AdminControlScreen> createState() => _AdminControlScreenState();
}

class _AdminControlScreenState extends State<AdminControlScreen> {
  final _ref = FirebaseDatabase.instance.ref("kontrol");

  bool _turnikeAktif = true;
  bool _turnikeDik = false;
  String _sonKomut = "BEKLE";

  @override
  void initState() {
    super.initState();
    _ref.onValue.listen((event) {
      final data = event.snapshot.value as Map?;
      if (data != null) {
        setState(() {
          _turnikeAktif = data["turnike_aktif"] ?? true;
          _turnikeDik = data["turnike_dik_kalsin"] ?? false;
          _sonKomut = data["son_komut"] ?? "BEKLE";
        });
      }
    });
  }

  Future<void> _guncelleKomut(String komut) async {
    await _ref.update({
      "son_komut": komut,
      "ac_istegi": komut == "AC",
    });

    if (komut == "AC" && !_turnikeDik) {
      Future.delayed(const Duration(seconds: 4), () async {
        await _ref.update({
          "son_komut": "KAPAT",
          "ac_istegi": false,
        });
        if (mounted) {
          setState(() {
            _sonKomut = "KAPAT";
          });
        }
      });
    }
  }


  Future<void> _setDikKalsin(bool val) async {
    await _ref.update({
      "turnike_dik_kalsin": val,
      "son_komut": val ? "AC" : "KAPAT",
      "ac_istegi": val ? true : false,
    });
    setState(() {
      _turnikeDik = val;
      _sonKomut = val ? "AC" : "KAPAT";
    });
  }

  Future<void> _setAktif(bool val) async {
    await _ref.update({"turnike_aktif": val});
    setState(() => _turnikeAktif = val);
  }

  Widget _buildTurnikeIcon() {
    if (!_turnikeAktif) {
      return const Icon(Icons.power_off, size: 100, color: Colors.grey);
    }
    if (_turnikeDik || _sonKomut == "AC") {
      return const Icon(Icons.keyboard_arrow_up, size: 100, color: Colors.green);
    }
    if (_sonKomut == "KAPAT") {
      return const Icon(Icons.keyboard_arrow_down, size: 100, color: Colors.red);
    }
    return const Icon(Icons.hourglass_empty, size: 100, color: Colors.orange);
  }

  String _durumMetni() {
    if (!_turnikeAktif) return "Devre Dışı";
    if (_turnikeDik) return "Dik Kaldı (Sürekli Açık)";
    if (_sonKomut == "AC") return "Açıldı";
    if (_sonKomut == "KAPAT") return "Kapalı";
    return "Bekleniyor";
  }

  Future<void> _manuelKapat() async {
    await _ref.update({
      "son_komut": "KAPAT",
      "ac_istegi": false,
      "turnike_dik_kalsin": false,
    });
    setState(() {
      _turnikeDik = false;
      _sonKomut = "KAPAT";
    });
  }

  @override
  Widget build(BuildContext context) {
    final bool kilitli = !_turnikeAktif;

    return Scaffold(
      appBar: AppBar(
        title: const Text("🛡️ Turnike Kontrol Paneli"),
        backgroundColor: Colors.red[700],
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.grey[100],
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 4))
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _buildTurnikeIcon(),
              const SizedBox(height: 24),
              SwitchListTile(
                title: const Text("🔌 Turnike Aktif", style: TextStyle(fontWeight: FontWeight.w600)),
                value: _turnikeAktif,
                onChanged: _setAktif,
              ),
              const Divider(),
              SwitchListTile(
                title: const Text("📍 Turnike Dik Kalsın (Sürekli Açık)", style: TextStyle(fontWeight: FontWeight.w600)),
                value: _turnikeDik,
                onChanged: _turnikeAktif ? _setDikKalsin : null,
              ),
              const Divider(),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: kilitli || _turnikeDik ? null : () => _guncelleKomut("AC"),
                      icon: const Icon(Icons.lock_open),
                      label: const Text("Turnikeyi Aç"),
                      style: ElevatedButton.styleFrom(
                        foregroundColor: Colors.white,
                        backgroundColor: Colors.green[600],
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),
              Text(
                "Durum: ${_durumMetni()}",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: Colors.grey[800]),
              )
            ],
          ),
        ),
      ),
    );
  }
}
