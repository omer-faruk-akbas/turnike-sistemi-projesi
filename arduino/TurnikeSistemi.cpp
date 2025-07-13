#include "TurnikeSistemi.h"
#include <NTPClient.h>
#include <WiFiUDP.h>

// NTP istemcisi
extern WiFiUDP ntpUDP;
extern NTPClient timeClient;

// Yapıcı
TurnikeSystem::TurnikeSystem(int rssi_pin, int ss_pin, int servo_pin, int led_pin) {
  _rssi_pin = rssi_pin;
  _ss_pin = ss_pin;
  _servo_pin = servo_pin;
  _led_pin = led_pin;
  
  _turnike_aktif = true;
  _turnike_dik = false;
  
  _rfid = new MFRC522(ss_pin, rssi_pin);
  _turnikeServo = new Servo();
}

// Başlatma fonksiyonu
void TurnikeSystem::begin() {
  // Pin ayarları
  pinMode(_led_pin, OUTPUT);
  digitalWrite(_led_pin, LOW);
  
  // RFID başlat
  _rfid->PCD_Init();
  
  // Servo başlat
  _turnikeServo->attach(_servo_pin);
  _turnikeServo->write(90); // Güvenli pozisyon
  
  Serial.println("TurnikeSystem kütüphanesi başlatıldı");
}

// Firebase nesnesini ayarla
void TurnikeSystem::setFirebase(FirebaseData* firebaseData) {
  _fbdo = firebaseData;
}

// Kart UID'sini oku
String TurnikeSystem::readCardUID() {
  if (!_rfid->PICC_IsNewCardPresent() || !_rfid->PICC_ReadCardSerial()) {
    return "";
  }
  
  String uid = "";
  for (byte i = 0; i < _rfid->uid.size; i++) {
    uid += (_rfid->uid.uidByte[i] < 0x10 ? "0" : "");
    uid += String(_rfid->uid.uidByte[i], HEX);
  }
  uid.toUpperCase();
  _rfid->PICC_HaltA();
  _rfid->PCD_StopCrypto1();
  return uid;
}

// Kart yetki kontrolü ve isim getirme
bool TurnikeSystem::checkCardAuthorization(String kart_uid, String* isim) {
  bool yetki = false;
  *isim = "Belirsiz";
  
  if (Firebase.getJSON(*_fbdo, "/kullanicilar")) {
    FirebaseJson json = _fbdo->jsonObject();
    FirebaseJsonData userData;
    for (size_t i = 0; i < json.iteratorBegin(); i++) {
      int type;
      String key, value;
      json.iteratorGet(i, type, key, value);
      FirebaseJson kullaniciJson;
      json.get(userData, key);
      kullaniciJson.setJsonData(userData.stringValue);
      kullaniciJson.get(userData, "kart_uid");
      String db_kart_uid = userData.stringValue;
      kullaniciJson.get(userData, "devre_disi");
      bool devre_disi = userData.boolValue;
      
      if (db_kart_uid == kart_uid) {
        kullaniciJson.get(userData, "isim");
        *isim = userData.stringValue;
        
        if (!devre_disi) {
          yetki = true;
        }
        break;
      }
    }
    json.iteratorEnd();
  }
  return yetki;
}

// Son giriş-çıkış durumunu kontrol et
String TurnikeSystem::checkLastStatus(String kart_uid) {
  if (Firebase.getJSON(*_fbdo, "/sondurum")) {
    FirebaseJson json = _fbdo->jsonObject();
    FirebaseJsonData sonData;
    for (size_t i = 0; i < json.iteratorBegin(); i++) {
      int type;
      String key, value;
      json.iteratorGet(i, type, key, value);
      FirebaseJson userJson;
      json.get(sonData, key);
      userJson.setJsonData(sonData.stringValue);
      for (size_t j = 0; j < userJson.iteratorBegin(); j++) {
        int cardType;
        String cardKey, cardValue;
        userJson.iteratorGet(j, cardType, cardKey, cardValue);
        if (cardKey == kart_uid) {
          FirebaseJson logJson;
          logJson.setJsonData(cardValue);
          FirebaseJsonData durumData;
          logJson.get(durumData, "giris_cikis");
          userJson.iteratorEnd();
          json.iteratorEnd();
          return durumData.stringValue;
        }
      }
      userJson.iteratorEnd();
    }
    json.iteratorEnd();
  }
  return "CIKIS";
}

// Günlük limit kontrolü
int TurnikeSystem::checkDailyLimit(String kart_uid) {
  String bugun = getCurrentDateStr();
  String yol = "/sayaclar/" + kart_uid + "/" + bugun;
  if (Firebase.getInt(*_fbdo, yol)) return _fbdo->intData();
  return 0;
}

// Günlük limit güncelleme
void TurnikeSystem::updateDailyLimit(String kart_uid, int yeni_deger) {
  String bugun = getCurrentDateStr();
  Firebase.setInt(*_fbdo, "/sayaclar/" + kart_uid + "/" + bugun, yeni_deger);
}

// Geçiş zamanı kontrolü
bool TurnikeSystem::checkPassageTime(String uid) {
  int addr = getUIDHash(uid);
  unsigned long son_gecis;
  EEPROM.get(addr, son_gecis);
  timeClient.update();
  unsigned long simdi = timeClient.getEpochTime();
  if ((simdi - son_gecis) < 30) {
    Serial.println("30 saniye geçmeden tekrar geçiş yapılamaz.");
    return false;
  }
  EEPROM.put(addr, simdi);
  EEPROM.commit();
  return true;
}

// Bugünün tarihini string olarak döndür
String TurnikeSystem::getCurrentDateStr() {
  timeClient.update();
  time_t rawtime = timeClient.getEpochTime();
  struct tm *timeinfo = localtime(&rawtime);
  char buffer[9];
  sprintf(buffer, "%04d%02d%02d", 1900 + timeinfo->tm_year, 1 + timeinfo->tm_mon, timeinfo->tm_mday);
  return String(buffer);
}

// UID için hash değeri oluştur
int TurnikeSystem::getUIDHash(String uid) {
  int sum = 0;
  for (int i = 0; i < uid.length(); i++) sum += uid[i];
  return (sum * 3) % 500; // Çakışmayı önlemek için basit bir hash
}

// LCD'ye mesaj gönderme fonksiyonu
void TurnikeSystem::sendLCDMessage(String line1, String line2) {
  // Arduino'daki formata uygun olarak gönder
  Serial.println("LCD:" + line1 + "|" + line2);
  
  // Debug mesajı
  Serial.println("LCD mesaj gönderildi: " + line1 + " | " + line2);
}

// Turnike kontrolü
void TurnikeSystem::controlTurnike(bool keepVertical) {
  _turnikeServo->write(0); // Turnikeyi aç
  
  if (!keepVertical) {
    sendLCDMessage("Turnike Acildi", "5sn Sonra Kapanir");
    delay(5000);
    _turnikeServo->write(90); // 5 saniye sonra kapat
    sendLCDMessage("Turnike Kapandi", "Kart Bekliyor");
    Serial.println("Turnike kapatıldı.");
  } else {
    sendLCDMessage("Turnike Acildi", "Dik Kalacak");
    Serial.println("Turnike açık bırakıldı.");
  }
}

// Log ekleme işlemi
void TurnikeSystem::addLog(String kart_uid, String tip, String isim) {
  String uid = "";
  
  if (Firebase.getJSON(*_fbdo, "/kullanicilar")) {
    FirebaseJson json = _fbdo->jsonObject();
    FirebaseJsonData userData;
    for (size_t i = 0; i < json.iteratorBegin(); i++) {
      int type;
      String key, value;
      json.iteratorGet(i, type, key, value);
      FirebaseJson kullaniciJson;
      json.get(userData, key);
      kullaniciJson.setJsonData(userData.stringValue);
      kullaniciJson.get(userData, "kart_uid");
      String db_kart_uid = userData.stringValue;
      if (db_kart_uid == kart_uid) {
        uid = key;
        break;
      }
    }
    json.iteratorEnd();
  }

  timeClient.update();
  unsigned long zaman = timeClient.getEpochTime();

  FirebaseJson logJson;
  logJson.set("uid", uid);
  logJson.set("kart_uid", kart_uid);
  logJson.set("isim", isim);
  logJson.set("giris_cikis", tip);
  logJson.set("kaynak", "KART");
  logJson.set("zaman", (int)zaman);

  Firebase.pushJSON(*_fbdo, "/loglar", logJson);
  Firebase.setJSON(*_fbdo, "/sondurum/" + uid + "/" + kart_uid, logJson);

  Serial.println(tip + " kaydedildi: " + isim);
}