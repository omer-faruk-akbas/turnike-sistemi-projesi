import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'UserLogsScreen.dart';
import 'admin_turnike_panel.dart';
import 'login_screen.dart';

class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  final DatabaseReference _ref = FirebaseDatabase.instance.ref("kullanicilar");
  Map<String, dynamic> _users = {};
  Map<String, dynamic> _filteredUsers = {};
  bool _loading = true;
  final TextEditingController _searchController = TextEditingController();
  String _adminName = "";

  @override
  void initState() {
    super.initState();
    _loadUsers();
    _loadAdminName();
    _searchController.addListener(_applyFilter);
  }

  Future<void> _loadAdminName() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final snapshot = await FirebaseDatabase.instance.ref("kullanicilar/$uid/isim").get();
    if (snapshot.exists) {
      setState(() {
        _adminName = snapshot.value.toString();
      });
    }
  }

  Future<void> _loadUsers() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final snapshot = await _ref.get();
    if (snapshot.exists) {
      final data = Map<String, dynamic>.from(snapshot.value as Map);
      data.remove(uid); // kendini listeleme
      setState(() {
        _users = data;
        _filteredUsers = data;
        _loading = false;
      });
    }
  }

  void _applyFilter() {
    final query = _searchController.text.toLowerCase();
    if (query.isEmpty) {
      setState(() => _filteredUsers = _users);
    } else {
      final filtered = _users.entries.where((entry) {
        final user = Map<String, dynamic>.from(entry.value);
        final ad = (user["isim"] ?? "").toLowerCase();
        final mail = (user["email"] ?? "").toLowerCase();
        final uid = (user["kart_uid"] ?? "").toLowerCase();
        return ad.contains(query) || mail.contains(query) || uid.contains(query);
      }).map((e) => MapEntry(e.key, e.value)).toMap();
      setState(() => _filteredUsers = filtered);
    }
  }

  Future<void> _toggleYetki(String uid, bool current) async {
    await _ref.child(uid).update({"yetkili": !current});
    _loadUsers();
  }

  Future<void> _toggleDurum(String uid, bool current) async {
    await _ref.child(uid).update({"devre_disi": !current});
    _loadUsers();
  }

  Future<void> _deleteUser(String uid) async {
    await _ref.child(uid).remove();
    _loadUsers();
  }

  Future<void> _logout() async {
    await FirebaseAuth.instance.signOut();
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: Text("👤 Yönetici: $_adminName"),
        backgroundColor: Colors.red[700],
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            onPressed: _logout,
            icon: const Icon(Icons.logout),
            tooltip: "Çıkış Yap",
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: "🔍 İsim, e-posta veya kart UID ara...",
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                filled: true,
                fillColor: Colors.white,
              ),
            ),
          ),
          Expanded(
            child: _filteredUsers.isEmpty
                ? const Center(child: Text("Kayıtlı kullanıcı bulunamadı."))
                : ListView.builder(
              itemCount: _filteredUsers.length,
              itemBuilder: (context, index) {
                final entry = _filteredUsers.entries.elementAt(index);
                final uid = entry.key;
                final user = Map<String, dynamic>.from(entry.value);
                final bool yetkili = user["yetkili"] == true;
                final bool devreDisi = user["devre_disi"] == true;
                final bool yeniKayit = devreDisi == true;
                final String sonGiris = user["son_giris"] != null
                    ? _timestampToString(user["son_giris"])
                    : "Yok";

                return Card(
                  elevation: 3,
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  color: yeniKayit ? Colors.yellow[100] : null,
                  child: ListTile(
                    leading: const CircleAvatar(
                      backgroundColor: Colors.red,
                      child: Icon(Icons.person, color: Colors.white),
                    ),
                    title: Text(user["isim"] ?? "İsimsiz",
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("📧 ${user["email"] ?? "-"}"),
                        Text("🆔 Kart UID: ${user["kart_uid"] ?? "-"}"),
                        Text("🛡️ Yetkili: ${yetkili ? "Evet" : "Hayır"}"),
                        Text("🔒 Durum: ${devreDisi ? "Devre Dışı" : "Aktif"}"),
                        Text("📅 Son Giriş: $sonGiris"),
                      ],
                    ),
                    isThreeLine: true,
                    trailing: PopupMenuButton<String>(
                      onSelected: (value) {
                        if (value == "yetki") {
                          _toggleYetki(uid, yetkili);
                        } else if (value == "durum") {
                          _toggleDurum(uid, devreDisi);
                        } else if (value == "sil") {
                          _deleteUser(uid);
                        } else if (value == "gecmis") {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => UserLogsScreen(
                                uid: uid,
                                isim: user["isim"] ?? "Kullanıcı",
                              ),
                            ),
                          );
                        }
                      },
                      itemBuilder: (context) => [
                        PopupMenuItem(
                          value: "yetki",
                          child: Text(yetkili ? "Yetkiyi Kaldır" : "Yetkili Yap"),
                        ),
                        PopupMenuItem(
                          value: "durum",
                          child: Text(devreDisi ? "Aktif Et" : "Devre Dışı Bırak"),
                        ),
                        const PopupMenuItem(
                          value: "sil",
                          child: Text("🗑️ Kullanıcıyı Sil"),
                        ),
                        const PopupMenuItem(
                          value: "gecmis",
                          child: Text("📜 Geçmiş Girişleri Gör"),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: ElevatedButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AdminControlScreen()),
              ),
              icon: const Icon(Icons.settings),
              label: const Text("Turnike Kontrolü"),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red[600],
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 24),
                textStyle: const TextStyle(fontSize: 16),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _timestampToString(int timestamp) {
    final dt = DateTime.fromMillisecondsSinceEpoch(timestamp * 1000);
    return "${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')}.${dt.year}  ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}";
  }
}

extension MapEntryListExtension<K, V> on Iterable<MapEntry<K, V>> {
  Map<K, V> toMap() => Map.fromEntries(this);
}
