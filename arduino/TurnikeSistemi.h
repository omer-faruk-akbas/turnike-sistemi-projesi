#ifndef TurnikeSystem_h
#define TurnikeSystem_h

#include <Arduino.h>
#include <SPI.h>
#include <MFRC522.h>
#include <Servo.h>
#include <FirebaseESP8266.h>
#include <EEPROM.h>

class TurnikeSystem {
  public:
    // Yapıcı
    TurnikeSystem(int rssi_pin, int ss_pin, int servo_pin, int led_pin);
    
    // Başlatma fonksiyonları
    void begin();
    void setFirebase(FirebaseData* firebaseData);
    
    // Kart işlemleri
    String readCardUID();
    bool checkCardAuthorization(String kart_uid, String* isim);
    String checkLastStatus(String kart_uid);
    bool checkPassageTime(String uid);
    
    // LCD mesaj gönderme
    void sendLCDMessage(String line1, String line2);
    
    // Turnike kontrolü
    void controlTurnike(bool keepVertical);
    
    // Log işlemleri
    void addLog(String kart_uid, String tip, String isim);
    
    // Limit kontrolü
    int checkDailyLimit(String kart_uid);
    void updateDailyLimit(String kart_uid, int yeni_deger);
    
    // Yardımcı fonksiyonlar
    String getCurrentDateStr();
    int getUIDHash(String uid);
    
  private:
    // Donanım pinleri
    int _rssi_pin;
    int _ss_pin;
    int _servo_pin;
    int _led_pin;
    
    // Donanım nesneleri
    MFRC522* _rfid;
    Servo* _turnikeServo;
    FirebaseData* _fbdo;
    
    // Durum değişkenleri
    bool _turnike_aktif;
    bool _turnike_dik;
};

#endif