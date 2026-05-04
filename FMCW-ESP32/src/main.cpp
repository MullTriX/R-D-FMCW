// =====================================================================
// ESP32 - odbiornik licznika osób z radaru FMCW (MATLAB v30)
// ---------------------------------------------------------------------
// Protokół (linie zakończone '\n'):
//   "R"        -> reset stanu
//   "C:<n>"    -> aktualny licznik osób w pomieszczeniu (np. "C:3")
//   "P:1"/"P:0"-> opcjonalna obecność (zbocze count 0<->n>0)
//   "H"        -> heartbeat (informacyjny, nie wpływa na LED)
//
// LED:
//   peopleInRoom > 0  -> LED ON
//   peopleInRoom == 0 -> LED OFF
//   (osobna zmienna decyduje o stanie diody, niezależnie od łącza)
// =====================================================================
#include <Arduino.h>

static const int LED_PIN = 2;

// Osobna zmienna - liczba osób aktualnie w pomieszczeniu
static int peopleInRoom = 0;

static String lineBuf;

static void applyLed() {
  digitalWrite(LED_PIN, (peopleInRoom > 0) ? HIGH : LOW);
}

static void handleLine(const String& line) {
  if (line.length() == 0) return;

  if (line == "R") {
    peopleInRoom = 0;
    Serial.println("ACK:R");
  } else if (line == "H") {
    // tylko heartbeat - nic nie robimy ze stanem LED
  } else if (line.startsWith("C:")) {
    int n = line.substring(2).toInt();
    if (n < 0) n = 0;
    peopleInRoom = n;
    Serial.print("ACK:C="); Serial.println(peopleInRoom);
  } else if (line.startsWith("P:")) {
    // backward-compat: P:1 -> przynajmniej 1 osoba; P:0 -> 0
    if (line.charAt(2) == '0') peopleInRoom = 0;
    else if (peopleInRoom == 0) peopleInRoom = 1;
    Serial.print("ACK:P, peopleInRoom="); Serial.println(peopleInRoom);
  }
  applyLed();
}

void setup() {
  Serial.begin(115200);
  pinMode(LED_PIN, OUTPUT);
  digitalWrite(LED_PIN, LOW); // start: nikt w pomieszczeniu
  lineBuf.reserve(64);
  Serial.println("BOOT:ESP32-Radar-Counter");
}

void loop() {
  while (Serial.available() > 0) {
    char ch = (char)Serial.read();
    if (ch == '\n' || ch == '\r') {
      if (lineBuf.length() > 0) {
        handleLine(lineBuf);
        lineBuf = "";
      }
    } else if (lineBuf.length() < 60) {
      lineBuf += ch;
    }
  }
  applyLed(); // odświeżamy w każdej iteracji - LED zależy tylko od peopleInRoom
}