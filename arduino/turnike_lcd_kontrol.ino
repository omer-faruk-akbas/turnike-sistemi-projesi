#include <LiquidCrystal.h>

// LCD bağlantıları
LiquidCrystal lcd(7, 6, 5, 4, 3, 2);  // RS, E, D4, D5, D6, D7

void setup() {
  // LCD'yi başlat
  lcd.begin(16, 2);
  
  // Seri haberleşmeyi başlat
  Serial.begin(9600);  // ESP8266'dan veri alacağız
  
  // Başlangıç mesajı
  lcd.print("LCD Hazir!");
  lcd.setCursor(0, 1);
  lcd.print("Sistem Bekleniyor");
}

void loop() {
  // ESP8266'dan gelen verileri kontrol et
  if (Serial.available()) {
    String veri = Serial.readStringUntil('\n');
    
    // LCD: ile başlayan mesajları işle
    if (veri.startsWith("LCD:")) {
      String mesaj = veri.substring(4);  // "LCD:" önekini kaldır
      
      // Satırları ayır (| işareti ile ayrılmış)
      int ayrac = mesaj.indexOf('|');
      
      if (ayrac != -1) {
        // İki satırlı mesaj
        String satir1 = mesaj.substring(0, ayrac);
        String satir2 = mesaj.substring(ayrac + 1);
        
        // LCD'yi temizle ve mesajı yazdır
        lcd.clear();
        lcd.setCursor(0, 0);
        lcd.print(satir1);
        lcd.setCursor(0, 1);
        lcd.print(satir2);
      } else {
        // Tek satırlı mesaj
        lcd.clear();
        lcd.setCursor(0, 0);
        lcd.print(mesaj);
      }
    }
  }
}