import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';

class UserLogsScreen extends StatefulWidget {
  final String uid;
  final String isim;

  const UserLogsScreen({super.key, required this.uid, required this.isim});

  @override
  State<UserLogsScreen> createState() => _UserLogsScreenState();
}

class _UserLogsScreenState extends State<UserLogsScreen> {
  List<Map<String, dynamic>> _gecmis = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _getLogs();
  }

  Future<void> _getLogs() async {
    final ref = FirebaseDatabase.instance.ref("loglar");
    final snapshot = await ref.get();

    List<Map<String, dynamic>> logs = [];

    if (snapshot.exists) {
      for (var log in snapshot.children) {
        final data = Map<String, dynamic>.from(log.value as Map);
        if (data["uid"] == widget.uid) {
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
      _loading = false;
    });
  }

  String _timestampToString(int timestamp) {
    final dt = DateTime.fromMillisecondsSinceEpoch(timestamp * 1000);
    return "${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')}.${dt.year}  ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}";
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("${widget.isim} - Giriş/Çıkış Geçmişi"),
        backgroundColor: Colors.red,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _gecmis.isEmpty
          ? const Center(child: Text("Bu kullanıcıya ait geçmiş bulunamadı."))
          : ListView.builder(
        itemCount: _gecmis.length,
        itemBuilder: (context, index) {
          final e = _gecmis[index];
          return ListTile(
            leading: Icon(
              e["giris_cikis"] == "GIRIS" ? Icons.login : Icons.logout,
              color: e["giris_cikis"] == "GIRIS" ? Colors.green : Colors.red,
            ),
            title: Text("${e["giris_cikis"]} (${e["kaynak"]})"),
            subtitle: Text(_timestampToString(e["zaman"])),
          );
        },
      ),
    );
  }
}
