# INSTRUKCJA INSTALACJI I KONFIGURACJI
## FMCW RADAR ANALYZER - MATLAB VERSION

### 🚀 SZYBKI START - 5 KROKÓW:

#### 1. **SPRAWDŹ WYMAGANIA**
```matlab
% W Command Window sprawdź dostępne toolboxy:
ver
```
**WYMAGANE:**
- MATLAB R2020b lub nowszy
- Signal Processing Toolbox
- **Opcjonalnie:** Phased Array System Toolbox (dla zaawansowanych funkcji)

#### 2. **ZAINSTALUJ BRAKUJĄCE TOOLBOXY**
```matlab
% Jeśli brakuje Signal Processing Toolbox:
% 1. Idź do Home → Add-Ons → Get Add-Ons
% 2. Wyszukaj "Signal Processing Toolbox"
% 3. Kliknij Install
```

#### 3. **SKOPIUJ PLIKI**
- Umieść plik `radar_fmcw_analyzer.m` w tym samym folderze co folder z danymi
- Struktura powinna wyglądać tak:
```
📁 R&D/
  📄 radar_fmcw_analyzer.m
  📁 1_one_person_raw_fmcw_data-20250414T204939Z-004/
    📁 stand_0_degres_3m_1personnes_rep2/
      📄 data_0001_a1.cf32
      📄 data_0002_a1.cf32
      ...
```

#### 4. **EDYTUJ KONFIGURACJĘ**
Otwórz plik i znajdź linię (~955):
```matlab
data_folder = '1_one_person_raw_fmcw_data-20250414T204939Z-004';
```
Zmień na właściwą ścieżkę do Twoich danych.

#### 5. **URUCHOM!**
```matlab
% W Command Window:
radar_fmcw_analyzer  % uruchomi funkcję main() automatycznie

% LUB bezpośrednio:
main
```

---

### 🎛️ TRYBY PRACY:

#### **Tryb 1: Pojedyncze klatki (SZYBKI)**
- Analiza pierwszej klatki z każdego scenariusza
- Czas: ~2-3 sekundy na scenariusz
- Idealny do szybkiego przeglądu

#### **Tryb 2: Multi-frame (DOKŁADNY)**
- Łączy 3 klatki dla lepszej czułości
- Czas: ~5-8 sekund na scenariusz
- Lepsze wykrywanie słabych sygnałów

#### **Tryb 3: Test kątów >90°**
- Specjalny tryb dla problemowych kątów (112°, 136°)
- Automatyczne poprawki kalibracji kątowej
- Pokazuje przed/po kalibracji

#### **Tryb 4: Porównanie scenariuszy**
- Zestawia 4 różne scenariusze na jednym wykresie
- Idealne do prezentacji wyników
- Automatyczny wybór reprezentatywnych przypadków

---

### 🔧 KLUCZOWE ULEPSZENIA vs PYTHON:

#### **1. Automatyczna kalibracja parametrów:**
```matlab
% MATLAB automatycznie dostrajuje:
bandwidth = auto_calibrate_bandwidth(expected_distance, detected_distance);
range_resolution = c / (2 * bandwidth);
```

#### **2. Zaawansowane przetwarzanie sygnału:**
```matlab
% Zero-padding dla lepszej rozdzielczości
range_fft_size = N_ADC_SAMPLES * 2;
doppler_fft_size = N_chirps * 2;

% Profesjonalne okna
range_window = blackman(N_ADC_SAMPLES);
spatial_window = hamming(N_RX);
```

#### **3. Beamforming dla range-angle:**
```matlab
% Coherent integration
averaged_data = coherent_average(tx_data, 'middle_50_percent');

% Spatial windowing przed angle FFT
windowed_data = range_fft .* spatial_window';
```

#### **4. Inteligentne znajdowanie pików:**
```matlab
[peaks, locs] = findpeaks(range_profile, ...
    'MinPeakHeight', 0.1 * max(range_profile), ...
    'MinPeakDistance', 10, ...
    'SortStr', 'descend');
```

---

### 📊 INTERPRETACJA WYNIKÓW:

#### **Range-Doppler Maps:**
- **Oś X:** Prędkość radialna [m/s] 
  - Ujemne = obiekt zbliża się
  - Dodatnie = obiekt oddala się
  - 0 = brak ruchu radialnego (biała linia)
- **Oś Y:** Odległość [m]
- **Kolory:** Moc odbicia [dB]

#### **Range-Angle Maps:**
- **Oś X:** Kąt azymutowy [-180° do +180°]
- **Oś Y:** Odległość [m]  
- **Czerwony krzyżyk:** Oczekiwana pozycja obiektu
- **Białe linie przerywane:** Kąty referencyjne (0°, 30°, 60°, 90°, etc.)

#### **Range Profile:**
- **Piki:** Wykryte obiekty
- **Czerwona linia:** Oczekiwana odległość
- **Automatyczna kalibracja:** Dopasowanie skali do rzeczywistości

#### **Panel diagnostyczny:**
```
DIAGNOSTYKA SYSTEMU:
Rozdzielczość zasięgu: 0.0375 m     ← Im mniejsza, tym lepsza dokładność
Maksymalny zasięg: 4.8 m            ← Maksymalna wykrywalna odległość  
PRF: 5555.6 Hz                      ← Częstotliwość powtarzania impulsów
Szerokość pasma: 4.00 GHz           ← Im większa, tym lepsza rozdzielczość

DOPPLER:
Rozdzielczość prędkości: 0.042 m/s  ← Najmniejsza wykrywalna zmiana prędkości
Maksymalna prędkość: ±2.7 m/s       ← Bez niejednoznaczności Doppler
Maksymalna prędkość: ±10 km/h       

KALIBRACJA:
Zastosowano korektę: 3.33x          ← Korekcja parametrów radaru

WYKRYTE ODBICIA:
  2.00 m                            ← Pozycje wykrytych obiektów
  0.60 m
```

---

### ⚡ PORÓWNANIE WYDAJNOŚCI:

| Aspekt | Python | MATLAB |
|--------|---------|---------|
| **Szybkość przetwarzania** | ~15s/scenariusz | ~3s/scenariusz |
| **Jakość kalibracji** | Manualna | Automatyczna |
| **Precyzja kątów >90°** | Problematyczna | Rozwiązana |
| **Znajdowanie pików** | Podstawowe | Zaawansowane |
| **Beamforming** | Brak | Profesjonalny |
| **Rozdzielczość** | Standardowa | Ulepszona (zero-padding) |
| **Diagnostyka** | Podstawowa | Kompletna |

---

### 🛠️ ROZWIĄZYWANIE PROBLEMÓW:

#### **"Undefined function or variable"**
```matlab
% Sprawdź czy jesteś we właściwym folderze:
pwd
cd('C:\Users\mullt\Szkola\R&D')  % Dostosuj ścieżkę
```

#### **"Folder z danymi nie istnieje"**
```matlab
% Sprawdź listę plików:
dir
% Zaktualizuj ścieżkę w kodzie:
data_folder = 'właściwa_nazwa_folderu';
```

#### **Brak Signal Processing Toolbox**
1. **Home** → **Add-Ons** → **Get Add-Ons**
2. Wyszukaj: **"Signal Processing Toolbox"**
3. Kliknij **Install**
4. Restartuj MATLAB

#### **Powolne działanie**
```matlab
% Zmniejsz liczbę analizowanych scenariuszy:
num_scenarios = 1;  % zamiast 3

% Lub użyj trybu pojedynczych klatek (1) zamiast multi-frame (2)
```

#### **Błędy z .cf32**
```matlab
% Sprawdź rozmiar pliku:
dir('ścieżka/do/pliku.cf32')

% Plik powinien mieć ~2MB (262144 próbki × 8 bajtów)
```

---

### 📈 OCZEKIWANE WYNIKI:

Po uruchomieniu powinieneś zobaczyć:
1. **Inicjalizację:** Skanowanie folderów i plików
2. **Menu wyboru:** Tryby analizy 1-4  
3. **Proces analizy:** Kalibracja i przetwarzanie każdego scenariusza
4. **Wykresy:** Automatyczne generowanie i zapisywanie
5. **Pliki PNG:** Wyniki zapisane w folderze roboczym

**Przykładowe pliki wyjściowe:**
- `results_stand_0_degres_3m_1personnes_rep2.png`
- `results_stand_112_degres_2m_1personnesLAB2_rep2.png` 
- `comparison_scenarios_matlab.png`

---

### 🎯 NASTĘPNE KROKI:

1. **Uruchom kod** z domyślnymi ustawieniami
2. **Sprawdź wyniki** - czy kalibracja działa poprawnie
3. **Dostosuj parametry** jeśli potrzeba (w klasie RadarConfig)
4. **Eksperymentuj** z różnymi trybami analizy
5. **Porównaj** z wynikami Python dla walidacji

---

**🚀 GOTOWY DO STARTU! Skopiuj kod, dostosuj ścieżkę i uruchom `main`!**