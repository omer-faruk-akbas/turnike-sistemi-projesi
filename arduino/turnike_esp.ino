#include <TurnikeSistemi.h>

#include <ESP8266WiFi.h>
#include <FirebaseESP8266.h>
#include <SPI.h>
#include <NTPClient.h>
#include <WiFiUDP.h>
#include <EEPROM.h>


// WiFi Ayarları
#define WIFI_SSID "wifi"
#define WIFI_PASSWORD "şifre"

// Firebase Ayarları
#define FIREBASE_HOST "..."
#define FIREBASE_AUTH "..."

// Donanım Pin Tanımlamaları
#define RST_PIN D3
#define SS_PIN  D4
#define SERVO_PIN D2
#define BUTON_PIN D1    // Sıfırlama butonu (interrupt destekli)
#define LED_PIN D0      // Durum LED'i

// Zamanlayıcı için
os_timer_t ledZamanlayici;
bool zamanlayici_aktif = false;

FirebaseData fbdo;
FirebaseAuth auth;
FirebaseConfig config;
WiFiUDP ntpUDP;
NTPClient timeClient(ntpUDP, "pool.ntp.org", 0, 60000);

// TurnikeSystem nesnesi oluştur
TurnikeSystem turnikeSystem(RST_PIN, SS_PIN, SERVO_PIN, LED_PIN);

// Değişkenler
bool turnike_aktif = true;
bool turnike_dik = false;
bool led_durum = false;
unsigned long son_firebase_kontrol = 0;

// Buton için değişkenler
volatile bool sifirlama_gerekli = false;
volatile unsigned long son_buton_zamani = 0;

// LED zamanlayıcı geri çağırma fonksiyonu
void ICACHE_RAM_ATTR ledYakSondur(void *pArg) {
  led_durum = !led_durum;
  digitalWrite(LED_PIN, led_durum);
}

// Kesme fonksiyonu (buton için) - Donanımsal reset
void ICACHE_RAM_ATTR butonKesmesi() {
  unsigned long simdiki_zaman = millis();
  
  // Debounce (sıçrama önleme) kontrolü - 50ms
  if (simdiki_zaman - son_buton_zamani > 50) {
    sifirlama_gerekli = true;
    son_buton_zamani = simdiki_zaman;
  }
}

// Zamanlayıcıyı başlat
void zamanlayici_baslat() {
  if (!zamanlayici_aktif) {
    os_timer_setfn(&ledZamanlayici, ledYakSondur, NULL);
    os_timer_arm(&ledZamanlayici, 500, true); // 500ms aralıklarla, tekrarlı
    zamanlayici_aktif = true;
  }
}

// Zamanlayıcıyı durdur
void zamanlayici_durdur() {
  if (zamanlayici_aktif) {
    os_timer_disarm(&ledZamanlayici);
    zamanlayici_aktif = false;
  }
}

// Sistemi sıfırlama fonksiyonu
void sistemi_sifirla() {
  digitalWrite(LED_PIN, LOW);
  turnikeSystem.sendLCDMessage("Sistem", "Yeniden Baslatiliyor");
  Serial.println("Sistem sıfırlanıyor...");
  
  // WiFi ve tüm bağlantıları yeniden başlat
  WiFi.disconnect();
  delay(1000);
  
  // WiFi ve diğer servisleri yeniden bağla
  wifi_baglan();
  
  turnikeSystem.sendLCDMessage("Sistem Hazir", "Kart Bekliyor");
}

void wifi_baglan() {
  turnikeSystem.sendLCDMessage("WiFi Baglaniyor", "Lutfen Bekleyin");
  
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
  
  // Bağlanma sırasında LED'i yakıp söndür
  while (WiFi.status() != WL_CONNECTED) {
    digitalWrite(LED_PIN, HIGH);
    delay(250);
    digitalWrite(LED_PIN, LOW);
    delay(250);
    Serial.print(".");
  }
  
  // Bağlantı başarılı olduğunda LED'i 3 kez hızlıca yakıp söndür
  for (int i = 0; i < 3; i++) {
    digitalWrite(LED_PIN, HIGH);
    delay(100);
    digitalWrite(LED_PIN, LOW);
    delay(100);
  }

  turnikeSystem.sendLCDMessage("WiFi Baglandi", WiFi.localIP().toString());
  Serial.println("WiFi bağlandı: " + WiFi.localIP().toString());
  delay(1000);

  timeClient.begin();
  timeClient.update();

  config.database_url = FIREBASE_HOST;
  config.signer.tokens.legacy_token = FIREBASE_AUTH;
  Firebase.begin(&config, &auth);

  // TurnikeSystem'e Firebase nesnesini tanıt
  turnikeSystem.setFirebase(&fbdo);

  Firebase.getBool(fbdo, "/kontrol/turnike_aktif");
  turnike_aktif = fbdo.boolData();

  Firebase.getBool(fbdo, "/kontrol/turnike_dik_kalsin");
  turnike_dik = fbdo.boolData();
}

void setup() {
  Serial.begin(9600);
  SPI.begin();
  EEPROM.begin(512);
  
  // Pin ayarları
  pinMode(BUTON_PIN, INPUT_PULLUP);
  pinMode(LED_PIN, OUTPUT);
  digitalWrite(LED_PIN, LOW);
  
  // Kesme ataması - FALLING: Yüksekten düşüğe geçişte tetiklenir
  attachInterrupt(digitalPinToInterrupt(BUTON_PIN), butonKesmesi, FALLING);
  
  // WiFi bağlantısı
  wifi_baglan();
  
  // TurnikeSystem'i başlat
  turnikeSystem.begin();
  
  // Zamanlayıcıyı başlat
  zamanlayici_baslat();
  
  // Başlangıç bilgisi
  turnikeSystem.sendLCDMessage("Sistem Hazir", "Kart Bekliyor");
}

void loop() {
  // Donanımsal kesme ile sıfırlama kontrolü
  if (sifirlama_gerekli) {
    sifirlama_gerekli = false;
    
    // Butona basıldığında direk sistemi sıfırla
    turnikeSystem.sendLCDMessage("Sistem", "Sifirlaniyor");
    Serial.println("Kesme tetiklendi. Sistem sıfırlanıyor...");
    
    // LED hızlı yanıp sönerek sıfırlama durumunu göstersin
    for (int i = 0; i < 5; i++) {
      digitalWrite(LED_PIN, HIGH);
      delay(200);
      digitalWrite(LED_PIN, LOW);
      delay(200);
    }
    
    // Sistemi tamamen sıfırla
    sistemi_sifirla();
    return;
  }

  // WiFi bağlantı kontrolü
  if (WiFi.status() != WL_CONNECTED) {
    turnikeSystem.sendLCDMessage("WiFi Baglantisi", "Kesik, Yenileniyor");
    wifi_baglan();
    return;
  }

  // Periyodik Firebase kontrolü (her 10 saniyede bir)
  unsigned long simdiki_zaman = millis();
  if (simdiki_zaman - son_firebase_kontrol > 10000) {
    // Firebase'den ayarları güncelle
    if (Firebase.getBool(fbdo, "/kontrol/turnike_dik_kalsin")) turnike_dik = fbdo.boolData();
    if (Firebase.getBool(fbdo, "/kontrol/turnike_aktif")) turnike_aktif = fbdo.boolData();
    son_firebase_kontrol = simdiki_zaman;
  }
  
  bool onceki_durum = turnike_dik;
  if (Firebase.getBool(fbdo, "/kontrol/turnike_dik_kalsin")) {
    turnike_dik = fbdo.boolData();

    // Eğer önceden "dik kalsın" açıkken şimdi kapandıysa
    if (onceki_durum && !turnike_dik) {
      // Turnike kütüphanesi aracılığıyla kapanmalı
      turnikeSystem.controlTurnike(false);
      turnikeSystem.sendLCDMessage("Turnike", "Kapatildi");
      
      // Firebase'e son komutu bildir
      Firebase.setString(fbdo, "/kontrol/son_komut", "kapat");
    }
  }

  // Firebase üzerinden uzaktan açma isteği kontrolü
  if (Firebase.getBool(fbdo, "/kontrol/ac_istegi") && fbdo.boolData()) {
    Firebase.setBool(fbdo, "/kontrol/ac_istegi", false);
    Serial.println("Uzaktan açma isteği alındı.");
    turnikeSystem.sendLCDMessage("Uzaktan Acildi", "Gecis Yapiniz");
    turnikeSystem.controlTurnike(turnike_dik);
    return;
  }

  // Kayıt için kart tarama modu kontrolü
  if (Firebase.getBool(fbdo, "/tarama/durum") && fbdo.boolData()) {
    Serial.println("Kayıt için kart bekleniyor...");
    turnikeSystem.sendLCDMessage("Kayit Icin", "Kart Okutunuz");
    
    // Kart beklerken buton kontrolü
    unsigned long kart_bekleme_baslangic = millis();
    String kart_uid = "";
    
    while ((kart_uid = turnikeSystem.readCardUID()) == "") {
      // Donanımsal kesme kontrolü
      if (sifirlama_gerekli) {
        sifirlama_gerekli = false;
        Firebase.setBool(fbdo, "/tarama/durum", false);
        turnikeSystem.sendLCDMessage("Sistem", "Sifirlaniyor");
        sistemi_sifirla();
        return;
      }
      
      delay(100);
      
      // Uzun süre kart beklemeye devam etme, 10 saniye sonra normal işleme dön
      if (millis() - kart_bekleme_baslangic > 10000) {
        Firebase.setBool(fbdo, "/tarama/durum", false);
        turnikeSystem.sendLCDMessage("Zaman Asimi", "Kart Bekleniyor");
        delay(2000);
        turnikeSystem.sendLCDMessage("Sistem Hazir", "Kart Bekliyor");
        return;
      }
    }
    
    Firebase.setString(fbdo, "/tarama/kart_uid", kart_uid);
    Firebase.setBool(fbdo, "/tarama/durum", false);
    Serial.println("UID gönderildi: " + kart_uid);
    turnikeSystem.sendLCDMessage("Kart Tanimlandi", "UID: " + kart_uid);
    delay(2000);
    turnikeSystem.sendLCDMessage("Sistem Hazir", "Kart Bekliyor");
    return;
  }

  // Kart okuma işlemi
  String kart_uid = turnikeSystem.readCardUID();
  if (kart_uid == "") {
    delay(100);
    return;
  }

  Serial.println("Kart Okundu: " + kart_uid);
  turnikeSystem.sendLCDMessage("Kart Okundu", "Kontrol Ediliyor");
  
  // Kart okunduğunda hızlı yanıp sönme başlat
  for (int i = 0; i < 5; i++) {
    digitalWrite(LED_PIN, HIGH);
    delay(100);
    digitalWrite(LED_PIN, LOW);
    delay(100);
  }

  if (!turnike_aktif) {
    Serial.println("Turnike devre dışı.");
    turnikeSystem.sendLCDMessage("Turnike Kapali", "Yetkili Arayin");
    delay(2000);
    turnikeSystem.sendLCDMessage("Sistem Hazir", "Kart Bekliyor");
    return;
  }

  bool yetki = false;
  String kullanici_isim = "";
  yetki = turnikeSystem.checkCardAuthorization(kart_uid, &kullanici_isim);
  
  if (!yetki) {
    Serial.println("Yetkisiz kart: " + kullanici_isim);
    turnikeSystem.sendLCDMessage("Yetkisiz Kart!", kullanici_isim);
    delay(2000);
    turnikeSystem.sendLCDMessage("Sistem Hazir", "Kart Bekliyor");
    return;
  }

  // Geçiş süresi kontrolü
  if (!turnikeSystem.checkPassageTime(kart_uid)) {
    turnikeSystem.sendLCDMessage("Cok Sik Gecis!", "Lutfen Bekleyin");
    delay(2000);
    turnikeSystem.sendLCDMessage("Sistem Hazir", "Kart Bekliyor");
    return;
  }

  String son = turnikeSystem.checkLastStatus(kart_uid);
  String yeni_durum = (son == "GIRIS") ? "CIKIS" : "GIRIS";

  if (yeni_durum == "GIRIS") {
    int limit = turnikeSystem.checkDailyLimit(kart_uid);
    if (limit >= 3) {
      Serial.println("Günlük giriş sınırı aşıldı!");
      turnikeSystem.sendLCDMessage("Limit Asildi!", "Gunluk 3 Giris");
      delay(2000);
      turnikeSystem.sendLCDMessage("Sistem Hazir", "Kart Bekliyor");
      return;
    }
    turnikeSystem.updateDailyLimit(kart_uid, limit + 1);
  }

  // Geçiş işlemi başarılı olduğunda özel LED efekti
  turnikeSystem.addLog(kart_uid, yeni_durum, kullanici_isim);
  turnikeSystem.sendLCDMessage(yeni_durum + " Yapildi", "Hos Geldin " + kullanici_isim);
  
  // Başarılı geçiş için LED efekti
  for (int i = 0; i < 3; i++) {
    digitalWrite(LED_PIN, HIGH);
    delay(200);
    digitalWrite(LED_PIN, LOW);
    delay(200);
  }
  
  turnikeSystem.controlTurnike(turnike_dik);
  delay(1000);
  turnikeSystem.sendLCDMessage("Sistem Hazir", "Kart Bekliyor");
}