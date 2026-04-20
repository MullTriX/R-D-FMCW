import numpy as np
import matplotlib.pyplot as plt
import os
import glob
from pathlib import Path

# --- 1. KONFIGURACJA RADARU IWR1443 ---
# Te wartości muszą pasować do Twojej konfiguracji w mmWave Studio!
N_RX = 4            # IWR1443 ma 4 odbiorniki
N_TX = 3            # Zakładamy użycie wszystkich 3 nadajników (MIMO)
N_ADC_SAMPLES = 256 # Typowa wartość (sprawdź w swojej konfiguracji)
N_LOOPS = 85        # Dostosowane na podstawie rzeczywistych danych (256 chirpów / 3 TX = ~85)

# Całkowita liczba chirpów w pliku (ramce) przy TDM MIMO
# Na podstawie analizy rzeczywistych plików: 256 chirpów
TOTAL_CHIRPS = 256  # Rzeczywista wartość z plików 

# Parametry fizyczne anteny (dla range-angle)
LAMBDA = 0.0039     # Długość fali dla 77 GHz (w metrach)
ANTENNA_SPACING = LAMBDA / 2  # Typowy odstęp między antenami

# Parametry kalibracji - WYMAGAJĄ DOSTOSOWANIA do rzeczywistej konfiguracji radaru
# Te wartości zależą od parametrów chirp w mmWave Studio!
BANDWIDTH = 4e9     # Szerokość pasma [Hz] - typowo 2-4 GHz dla IWR1443
RANGE_RESOLUTION = 3e8 / (2 * BANDWIDTH)  # c/(2*BW) w metrach
MAX_RANGE = RANGE_RESOLUTION * (N_ADC_SAMPLES // 2)  # Maksymalny zasięg

# Parametry dla obliczania prędkości Doppler
CHIRP_TIME = 60e-6  # Czas jednego chirpa [s] - typowo 20-100μs (dostosuj do konfiguracji!)
FRAME_PERIOD = N_TX * N_LOOPS * CHIRP_TIME  # Okres ramki
PRF = 1 / (N_TX * CHIRP_TIME)  # Pulse Repetition Frequency dla jednego TX

print(f"KALIBRACJA: Rozdzielczość zasięgu = {RANGE_RESOLUTION:.3f}m, Maksymalny zasięg = {MAX_RANGE:.1f}m")
print(f"DOPPLER: PRF = {PRF:.1f} Hz, Okres ramki = {FRAME_PERIOD*1000:.1f}ms")

# Folder z danymi
DATA_FOLDER = '1_one_person_raw_fmcw_data-20250414T204939Z-004'

def load_radar_data(filepath):
    """Wczytuje i organizuje dane z pliku .cf32"""
    try:
        data = np.fromfile(filepath, dtype=np.complex64)
    except FileNotFoundError:
        print(f"Nie znaleziono pliku: {filepath}")
        return None

    # Sprawdzenie rozmiaru
    expected_size = N_RX * TOTAL_CHIRPS * N_ADC_SAMPLES
    if data.size != expected_size:
        print(f"UWAGA: Plik {os.path.basename(filepath)}")
        print(f"Rozmiar: {data.size}, oczekiwany: {expected_size}")
        # Próba dopasowania
        if data.size % (N_RX * N_ADC_SAMPLES) == 0:
            actual_chirps = data.size // (N_RX * N_ADC_SAMPLES)
            print(f"Dostosowuję do {actual_chirps} chirpów")
            data = data.reshape(actual_chirps, N_RX, N_ADC_SAMPLES)
        else:
            return None
    else:
        # Reshape zgodnie z oczekiwaną organizacją
        data = data.reshape(TOTAL_CHIRPS, N_RX, N_ADC_SAMPLES)
    
    return data

def generate_range_doppler_map(radar_cube, tx_idx=0, rx_idx=0):
    """Generuje mapę Range-Doppler dla wybranej kombinacji TX/RX"""
    # Demultipleksacja TDM MIMO - wybieramy chirpy z jednego nadajnika
    tx_data = radar_cube[tx_idx::N_TX, :, :]
    
    # Wybieramy konkretną antenę odbiorczą
    adc_data = tx_data[:, rx_idx, :]
    
    # Usuwanie DC offset (średniej) z każdego chirpa
    adc_data = adc_data - np.mean(adc_data, axis=1, keepdims=True)
    
    # Okna (lepsze parametry)
    range_win = np.blackman(N_ADC_SAMPLES)  # Blackman daje lepsze tłumienie
    doppler_win = np.blackman(len(adc_data))
    
    # Range FFT z oknem
    range_fft = np.fft.fft(adc_data * range_win, axis=1)
    range_fft = range_fft[:, :N_ADC_SAMPLES//2]
    
    # Usuwanie pierwszych kilku bin'ów (DC i bardzo bliskie odbicia)
    range_fft[:, :3] = 0
    
    # Doppler FFT
    doppler_input = range_fft.T * doppler_win
    doppler_fft = np.fft.fft(doppler_input, axis=1)
    doppler_fft = np.fft.fftshift(doppler_fft, axes=1)
    
    # Lepsze skalowanie logarytmiczne
    magnitude = np.abs(doppler_fft)
    
    # Normalizacja do maksymalnej wartości
    magnitude = magnitude / np.max(magnitude)
    
    # Logarytm z lepszym floor
    result = 20 * np.log10(magnitude + 1e-6)
    
    return result

def generate_range_angle_map(radar_cube, tx_idx=0, range_bin=None):
    """Generuje mapę Range-Angle dla wybranego nadajnika"""
    # Demultipleksacja TDM MIMO
    tx_data = radar_cube[tx_idx::N_TX, :, :]
    
    # Usuwanie DC offset dla każdej anteny
    for rx in range(N_RX):
        tx_data[:, rx, :] = tx_data[:, rx, :] - np.mean(tx_data[:, rx, :], axis=1, keepdims=True)
    
    # Uśrednianie po chirpach (dla stabilności)
    if len(tx_data) > 10:
        # Używamy tylko środkowe chirpy
        start_idx = len(tx_data) // 4
        end_idx = 3 * len(tx_data) // 4
        averaged_data = np.mean(tx_data[start_idx:end_idx], axis=0)
    else:
        averaged_data = np.mean(tx_data, axis=0)
    
    # Range FFT dla wszystkich anten odbiorczych
    range_win = np.blackman(N_ADC_SAMPLES)
    range_fft = np.fft.fft(averaged_data * range_win, axis=1)
    range_fft = range_fft[:, :N_ADC_SAMPLES//2]
    
    # Usuwanie pierwszych kilku bin'ów (bardzo bliska odległość)
    range_fft[:, :5] = 0
    
    # Angle FFT (po antenach) dla każdego range bin
    # Padding dla lepszej rozdzielczości kątowej
    angle_fft_size = 64  # Zwiększamy rozmiar FFT dla lepszej rozdzielczości
    angle_fft = np.fft.fft(range_fft.T, n=angle_fft_size, axis=1)
    angle_fft = np.fft.fftshift(angle_fft, axes=1)
    
    # Lepsze skalowanie
    magnitude = np.abs(angle_fft)
    
    # Skalowanie logarytmiczne z lepszą normalizacją
    # Używamy percentyli zamiast maksimum dla lepszej dynamiki
    magnitude_norm = magnitude / np.percentile(magnitude, 99)
    result = 20 * np.log10(magnitude_norm + 1e-6)
    
    return result, angle_fft_size

def calculate_angle_axis(angle_fft_size):
    """Oblicza rzeczywistą skalę kątową w stopniach - ulepszona dla kątów > 90°"""
    
    # Dla radarów FMCW, kąty są zazwyczaj mapowane liniowo w zakresie -180° do +180°
    # zamiast używania arcsin (który ogranicza do -90°/+90°)
    
    # Prosta liniowa mapa kątowa - lepiej działa dla pełnego zakresu
    angles_deg = np.linspace(-180, 180, angle_fft_size)
    
    # Alternatywnie, można użyć mapowania opartego na fizyce anteny
    # ale dla praktycznych zastosowań, liniowe mapowanie jest bardziej stabilne
    
    return angles_deg

def calculate_range_axis():
    """Oblicza rzeczywistą skalę zasięgu w metrach"""
    range_bins = np.arange(N_ADC_SAMPLES // 2)
    ranges_m = range_bins * RANGE_RESOLUTION
    return ranges_m

def calculate_doppler_axis(n_doppler_bins):
    """Oblicza rzeczywistą skalę prędkości Doppler w m/s"""
    # Doppler bins są wycentrowane wokół 0 (brak ruchu)
    # Indeks 0 = maksymalna prędkość ujemna (zbliżanie się)
    # Indeks N/2 = brak ruchu (0 m/s) 
    # Indeks N = maksymalna prędkość dodatnia (oddalanie się)
    
    # Rozdzielczość prędkości
    velocity_resolution = (LAMBDA * PRF) / (2 * n_doppler_bins)
    
    # Maksymalna prędkość (niejednoznaczna)
    max_velocity = velocity_resolution * n_doppler_bins / 2
    
    # Skala prędkości: od -max_velocity do +max_velocity
    doppler_bins = np.arange(n_doppler_bins)
    velocities_ms = (doppler_bins - n_doppler_bins//2) * velocity_resolution
    
    return velocities_ms, max_velocity, velocity_resolution

def calibrate_angle_scale(radar_cube, expected_angle, expected_distance, scenario_name):
    """Kalibruje skalę kątową na podstawie oczekiwanego kąta"""
    
    # Generuj range-angle mapę
    ra_map, angle_fft_size = generate_range_angle_map(radar_cube, tx_idx=0)
    angle_axis = calculate_angle_axis(angle_fft_size)
    
    # Znajdź najsilniejsze odbicie w okolicy oczekiwanej odległości
    if expected_distance:
        # Przekształć odległość na indeks w mapie
        range_idx_expected = int((expected_distance / MAX_RANGE) * ra_map.shape[0])
        range_idx_expected = max(0, min(range_idx_expected, ra_map.shape[0]-1))
        
        # Sprawdź wokół oczekiwanej odległości (+/- 20%)
        range_start = max(0, int(range_idx_expected * 0.8))
        range_end = min(ra_map.shape[0], int(range_idx_expected * 1.2))
        
        # Znajdź najsilniejszy punkt w tym obszarze
        roi = ra_map[range_start:range_end, :]
        max_pos = np.unravel_index(np.argmax(roi), roi.shape)
        
        # Przelicz z powrotem na kąt
        angle_idx = max_pos[1]
        detected_angle = angle_axis[angle_idx]
        detected_range = (range_start + max_pos[0]) * MAX_RANGE / ra_map.shape[0]
        
        print(f"\n🔍 ANALIZA KĄTA dla {scenario_name}:")
        print(f"   Oczekiwany kąt: {expected_angle}°")
        print(f"   Oczekiwana odległość: {expected_distance}m")
        print(f"   Wykryty kąt: {detected_angle:.1f}°")
        print(f"   Wykryta odległość: {detected_range:.1f}m")
        
        # Jeśli różnica kątowa jest większa niż 20°, zaproponuj korektę
        angle_error = abs(detected_angle - expected_angle)
        if angle_error > 20:
            # Oblicz offset kątowy
            angle_offset = expected_angle - detected_angle
            corrected_angles = angle_axis + angle_offset
            
            print(f"   ⚠️  SUGEROWANA KOREKCJA KĄTA:")
            print(f"   Błąd kątowy: {angle_error:.1f}°")
            print(f"   Offset korekcyjny: {angle_offset:.1f}°")
            
            return corrected_angles, angle_offset
    
    return angle_axis, 0
    """Oblicza rzeczywistą skalę zasięgu w metrach"""
    range_bins = np.arange(N_ADC_SAMPLES // 2)
    ranges_m = range_bins * RANGE_RESOLUTION
    return ranges_m

def calibrate_range_scale(radar_cube, expected_distance, scenario_name):
    """Kalibruje skalę zasięgu na podstawie oczekiwanej odległości"""
    global RANGE_RESOLUTION, MAX_RANGE
    
    # Analizuj profil zasięgu
    range_profile, detected_ranges, peak_powers, range_axis = analyze_range_profile(radar_cube, expected_distance)
    
    if detected_ranges:
        # Znajdź najsilniejsze odbicie
        strongest_peak_idx = np.argmax(peak_powers)
        detected_distance = detected_ranges[strongest_peak_idx]
        
        print(f"\n🔍 ANALIZA ZASIĘGU dla {scenario_name}:")
        print(f"   Oczekiwana odległość: {expected_distance}m")
        print(f"   Wykryte odległości: {[f'{d:.2f}m' for d in detected_ranges]}")
        print(f"   Najsilniejsze odbicie: {detected_distance:.2f}m")
        
        # Jeśli różnica jest znaczna, zaproponuj korektę
        if expected_distance and abs(detected_distance - expected_distance) > 0.5:
            correction_factor = expected_distance / detected_distance
            suggested_resolution = RANGE_RESOLUTION * correction_factor
            suggested_max_range = suggested_resolution * (N_ADC_SAMPLES // 2)
            
            print(f"   ⚠️  SUGEROWANA KOREKCJA:")
            print(f"   Aktualna rozdzielczość: {RANGE_RESOLUTION:.4f}m")
            print(f"   Sugerowana rozdzielczość: {suggested_resolution:.4f}m")
            print(f"   Nowy maksymalny zasięg: {suggested_max_range:.1f}m")
            
            return suggested_resolution, suggested_max_range, range_profile
    
    return RANGE_RESOLUTION, MAX_RANGE, range_profile

def analyze_range_profile(radar_cube, expected_distance=None):
    """Analizuje profil zasięgu aby znaleźć faktyczne odbicia"""
    # Weź pierwszy TX i uśrednij po wszystkich RX i chirpach
    tx_data = radar_cube[0::N_TX, :, :]
    
    # Usunięcie DC
    for rx in range(N_RX):
        tx_data[:, rx, :] = tx_data[:, rx, :] - np.mean(tx_data[:, rx, :], axis=1, keepdims=True)
    
    # Uśrednij po chirpach i antenach
    averaged_data = np.mean(tx_data, axis=(0, 1))
    
    # Range FFT
    range_win = np.blackman(N_ADC_SAMPLES)
    range_fft = np.fft.fft(averaged_data * range_win)
    range_profile = np.abs(range_fft[:N_ADC_SAMPLES//2])
    
    # Znajdź piki
    # Usuń pierwsze 5 bin'ów (bardzo blisko)
    range_profile[:5] = 0
    
    # Znajdź najsilniejsze odbicia
    peak_indices = []
    for i in range(10, len(range_profile)-10):
        if (range_profile[i] > range_profile[i-5:i].max() and 
            range_profile[i] > range_profile[i+1:i+6].max() and
            range_profile[i] > 0.1 * range_profile.max()):
            peak_indices.append(i)
    
    # Oblicz odległości dla pików
    range_axis = calculate_range_axis()
    detected_ranges = [range_axis[i] for i in peak_indices]
    peak_powers = [range_profile[i] for i in peak_indices]
    
    return range_profile, detected_ranges, peak_powers, range_axis

def find_radar_files(base_folder, pattern="*.cf32"):
    """Znajduje wszystkie pliki radar z danego folderu"""
    folder_path = Path(base_folder)
    files = []
    
    for subfolder in folder_path.iterdir():
        if subfolder.is_dir():
            cf32_files = list(subfolder.glob(pattern))
            if cf32_files:
                files.extend(cf32_files)
    
    return sorted(files)

def analyze_scenario(folder_name, file_list, multi_frame=False):
    """Analizuje scenariusz z jednego folderu"""
    print(f"\n=== Analizuję scenariusz: {folder_name} ===")
    
    # Wyciągnij parametry ze nazwy folderu
    params = parse_folder_name(folder_name)
    print(f"Parametry: {params}")
    
    if multi_frame and len(file_list) > 1:
        # Tryb multi-frame: łączymy kilka klatek
        print(f"Przetwarzam {min(3, len(file_list))} klatek razem")
        all_data = []
        for file_path in file_list[:3]:  # Ograniczamy do pierwszych 3 plików
            data = load_radar_data(file_path)
            if data is not None:
                all_data.append(data)
        
        if all_data:
            # Łączymy dane z różnych klatek
            combined_data = np.concatenate(all_data, axis=0)
            process_single_scenario(folder_name, combined_data, "Multi-frame", params)
    else:
        # Tryb single-frame: analizujemy pierwszą klatkę
        print("Przetwarzam pojedynczą klatkę")
        first_file = file_list[0]
        data = load_radar_data(first_file)
        if data is not None:
            process_single_scenario(folder_name, data, os.path.basename(first_file), params)

def parse_folder_name(folder_name):
    """Wyciąga parametry z nazwy folderu"""
    parts = folder_name.split('_')
    params = {}
    
    for i, part in enumerate(parts):
        if 'degres' in part and i > 0:
            # Kąt to część przed "degres"
            angle_part = parts[i-1]
            params['angle'] = f"{angle_part}°"
        elif 'm' in part and any(c.isdigit() for c in part):
            # Odległość
            params['distance'] = part
        elif 'rep' in part:
            # Powtórzenie
            params['repetition'] = part
        elif 'LAB' in part:
            # Oznaczenie laboratorium
            params['lab'] = part
    
    return params

def process_single_scenario(scenario_name, radar_cube, file_info, params):
    """Przetwarza pojedynczy scenariusz i generuje mapy"""
    global RANGE_RESOLUTION, MAX_RANGE
    
    # Wyciągnij oczekiwaną odległość i kąt z nazwy
    expected_distance = None
    expected_angle = None
    
    if 'distance' in params:
        distance_str = params['distance'].replace('m', '')
        try:
            expected_distance = float(distance_str)
        except:
            pass
    
    if 'angle' in params:
        angle_str = params['angle'].replace('°', '')
        try:
            expected_angle = float(angle_str)
        except:
            pass
    
    # KALIBRACJA ZASIĘGU: Sprawdź rzeczywiste odbicia
    corrected_resolution, corrected_max_range, range_profile = calibrate_range_scale(
        radar_cube, expected_distance, scenario_name)
    
    # Zastosuj korekcję zasięgu jeśli jest znacząca
    if abs(corrected_resolution - RANGE_RESOLUTION) > 0.001:
        print(f"   ✅ STOSUJE KOREKTĘ ZASIĘGU dla tego scenariusza")
        RANGE_RESOLUTION = corrected_resolution
        MAX_RANGE = corrected_max_range

    # KALIBRACJA KĄTA: Sprawdź rzeczywiste kąty
    angle_axis_corrected, angle_offset = calibrate_angle_scale(
        radar_cube, expected_angle, expected_distance, scenario_name)
    
    if abs(angle_offset) > 5:
        print(f"   ✅ STOSUJE KOREKTĘ KĄTA: {angle_offset:.1f}°")
    
    # Przygotuj wykres z dodatkowym panelem dla profilu zasięgu  
    fig = plt.figure(figsize=(18, 14))
    
    # Layout: 3 wiersze, 3 kolumny
    gs = fig.add_gridspec(3, 3, height_ratios=[1, 1, 0.7], hspace=0.3, wspace=0.3)
    
    # Tytuł z parametrami
    param_str = ", ".join([f"{k}: {v}" for k, v in params.items()])
    fig.suptitle(f'{scenario_name}\n{file_info}\n{param_str}', fontsize=12)
    
    # Oblicz skale osi
    range_axis = calculate_range_axis()
    
    # SUBPLOT 1: Range-Doppler TX1/RX1
    ax1 = fig.add_subplot(gs[0, 0])
    rd_map = generate_range_doppler_map(radar_cube, tx_idx=0, rx_idx=0)
    vmin_rd = np.percentile(rd_map, 5)
    vmax_rd = np.percentile(rd_map, 95)
    
    # Oblicz rzeczywiste skale
    velocity_axis, max_velocity, vel_resolution = calculate_doppler_axis(rd_map.shape[1])
    
    im1 = ax1.imshow(rd_map, aspect='auto', origin='lower', cmap='viridis', 
                     vmin=vmin_rd, vmax=vmax_rd,
                     extent=[velocity_axis[0], velocity_axis[-1], 0, MAX_RANGE])
    ax1.set_title(f'Range-Doppler (TX1/RX1)\nMax vel: ±{max_velocity:.1f} m/s (±{max_velocity*3.6:.1f} km/h)')
    ax1.set_ylabel('Odległość [m]')
    ax1.set_xlabel('Prędkość radialna [m/s]')
    ax1.axvline(x=0, color='white', alpha=0.5, linestyle='-', linewidth=1)  # Linia 0 m/s
    plt.colorbar(im1, ax=ax1, label='Power (dB)')
    
    # SUBPLOT 2: Range-Doppler TX1/RX4
    ax2 = fig.add_subplot(gs[0, 1])
    rd_map2 = generate_range_doppler_map(radar_cube, tx_idx=0, rx_idx=3)
    vmin_rd2 = np.percentile(rd_map2, 5)
    vmax_rd2 = np.percentile(rd_map2, 95)
    
    velocity_axis2, max_velocity2, _ = calculate_doppler_axis(rd_map2.shape[1])
    
    im2 = ax2.imshow(rd_map2, aspect='auto', origin='lower', cmap='viridis', 
                     vmin=vmin_rd2, vmax=vmax_rd2,
                     extent=[velocity_axis2[0], velocity_axis2[-1], 0, MAX_RANGE])
    ax2.set_title(f'Range-Doppler (TX1/RX4)\nRozdzielczość: {vel_resolution:.3f} m/s')
    ax2.set_ylabel('Odległość [m]')
    ax2.set_xlabel('Prędkość radialna [m/s]')
    ax2.axvline(x=0, color='white', alpha=0.5, linestyle='-', linewidth=1)  # Linia 0 m/s
    plt.colorbar(im2, ax=ax2, label='Power (dB)')
    
    # SUBPLOT 3: Range Profile
    ax3 = fig.add_subplot(gs[0, 2])
    ax3.plot(range_axis, range_profile[:len(range_axis)], 'b-', linewidth=2)
    ax3.set_title('Profil zasięgu (Range Profile)')
    ax3.set_xlabel('Odległość [m]')
    ax3.set_ylabel('Moc odbicia')
    ax3.grid(True, alpha=0.3)
    
    # Oznacz oczekiwaną odległość
    if expected_distance and expected_distance < MAX_RANGE:
        ax3.axvline(x=expected_distance, color='red', linestyle='--', 
                   label=f'Oczekiwane: {expected_distance}m')
        ax3.legend()
    
    # SUBPLOT 4: Range-Angle TX1 z poprawioną skalą kątową
    ax4 = fig.add_subplot(gs[1, 0])
    ra_map, angle_fft_size = generate_range_angle_map(radar_cube, tx_idx=0)
    
    # Użyj skorygowanej skali kątowej
    if len(angle_axis_corrected) != angle_fft_size:
        print(f"OSTRZEŻENIE: Rozmiar angle_axis ({len(angle_axis_corrected)}) != angle_fft_size ({angle_fft_size})")
        angle_axis_corrected = np.linspace(-180, 180, angle_fft_size)
    
    vmin_ra = np.percentile(ra_map, 10)
    vmax_ra = np.percentile(ra_map, 90)
    
    im4 = ax4.imshow(ra_map, aspect='auto', origin='lower', cmap='viridis', 
                     vmin=vmin_ra, vmax=vmax_ra,
                     extent=[angle_axis_corrected[0], angle_axis_corrected[-1], 0, MAX_RANGE])
    ax4.set_title('Range-Angle (TX1) - Skalibrowany')
    ax4.set_ylabel('Odległość [m]')
    ax4.set_xlabel('Kąt azymutowy [°]')
    ax4.grid(True, alpha=0.3)
    
    # Oznacz oczekiwaną pozycję
    if expected_distance and expected_angle:
        ax4.scatter([expected_angle], [expected_distance], 
                   c='red', s=100, marker='x', linewidth=3,
                   label=f'Oczekiwane: ({expected_angle}°, {expected_distance}m)')
        ax4.legend()
    
    # Linie pomocnicze dla kątów (dostosowane do nowego zakresu)
    key_angles = [0, 30, 60, 90, 120, 150, 180]
    for angle in key_angles:
        if angle_axis_corrected[0] <= angle <= angle_axis_corrected[-1]:
            ax4.axvline(x=angle, color='white', alpha=0.3, linestyle='--', linewidth=0.5)
    
    plt.colorbar(im4, ax=ax4, label='Power (dB)')
    
    # SUBPLOT 5: Range-Angle TX3
    ax5 = fig.add_subplot(gs[1, 1])
    ra_map2, _ = generate_range_angle_map(radar_cube, tx_idx=2)
    vmin_ra2 = np.percentile(ra_map2, 10)
    vmax_ra2 = np.percentile(ra_map2, 90)
    
    im5 = ax5.imshow(ra_map2, aspect='auto', origin='lower', cmap='viridis', 
                     vmin=vmin_ra2, vmax=vmax_ra2,
                     extent=[angle_axis_corrected[0], angle_axis_corrected[-1], 0, MAX_RANGE])
    ax5.set_title('Range-Angle (TX3) - Porównanie MIMO')
    ax5.set_ylabel('Odległość [m]')
    ax5.set_xlabel('Kąt azymutowy [°]')
    ax5.grid(True, alpha=0.3)
    
    # Linie pomocnicze
    for angle in key_angles:
        if angle_axis_corrected[0] <= angle <= angle_axis_corrected[-1]:
            ax5.axvline(x=angle, color='white', alpha=0.3, linestyle='--', linewidth=0.5)
    
    plt.colorbar(im5, ax=ax5, label='Power (dB)')
    
    # SUBPLOT 6: Podsumowanie/diagnostyka
    ax6 = fig.add_subplot(gs[1, 2])
    ax6.axis('off')
    
    # Tekst diagnostyczny
    diag_text = f"DIAGNOSTYKA:\n\n"
    diag_text += f"Rozdzielczość: {RANGE_RESOLUTION:.4f}m\n"
    diag_text += f"Maks. zasięg: {MAX_RANGE:.1f}m\n"
    if abs(angle_offset) > 1:
        diag_text += f"Korekcja kąta: {angle_offset:.1f}°\n"
    diag_text += f"\nDOPPLER:\n"
    diag_text += f"Vel. rozdzielczość: {vel_resolution:.3f} m/s\n"
    diag_text += f"Maks. prędkość: ±{max_velocity:.1f} m/s\n"
    diag_text += f"Maks. prędkość: ±{max_velocity*3.6:.0f} km/h\n"
    diag_text += f"PRF: {PRF:.1f} Hz\n"
    diag_text += f"\n"
    
    if expected_distance and expected_angle:
        diag_text += f"Oczekiwane:\n"
        diag_text += f"  Kąt: {expected_angle}°\n"
        diag_text += f"  Odległość: {expected_distance}m\n\n"
    
    # Znajdź najsilniejsze odbicia w range-angle
    peak_ranges = []
    peak_angles = []
    for r_idx in range(0, ra_map.shape[0], ra_map.shape[0]//10):  # Sample every 10%
        for a_idx in range(0, ra_map.shape[1], ra_map.shape[1]//20):  # Sample every 5%
            if ra_map[r_idx, a_idx] > vmin_ra + 0.8 * (vmax_ra - vmin_ra):
                range_val = r_idx * MAX_RANGE / ra_map.shape[0]
                angle_val = angle_axis_corrected[a_idx]
                peak_ranges.append(range_val)
                peak_angles.append(angle_val)
    
    if peak_ranges:
        diag_text += f"Silne odbicia:\n"
        for i, (pr, pa) in enumerate(zip(peak_ranges[:4], peak_angles[:4])):
            diag_text += f"  ({pa:.0f}°, {pr:.1f}m)\n"
    
    ax6.text(0.1, 0.9, diag_text, transform=ax6.transAxes, fontsize=10,
             verticalalignment='top', fontfamily='monospace',
             bbox=dict(boxstyle="round,pad=0.5", facecolor="lightblue", alpha=0.8))
    
    # Tekst wyjaśniający na dole
    fig.text(0.02, 0.02, 
             'DOPPLER BINS → PRĘDKOŚĆ: Oś X na wykresach Range-Doppler pokazuje teraz rzeczywiste prędkości. ' +
             'Wartości ujemne = obiekt się zbliża, dodatnie = obiekt się oddala. ' +
             '0 m/s = brak ruchu radialnego (biała linia). Czerwony krzyżyk = oczekiwana pozycja.',
             fontsize=9, ha='left', va='bottom',
             bbox=dict(boxstyle="round,pad=0.3", facecolor="lightgreen", alpha=0.8))
    
    # Zapisz wykres
    save_path = f"results_{scenario_name}_{file_info.replace('.cf32', '')}.png"
    plt.savefig(save_path, dpi=150, bbox_inches='tight')
    print(f"Zapisano wykres: {save_path}")
    
    plt.show()

def main():
    """Główna funkcja analizująca dane"""
    print("=== ANALIZA DANYCH RADAR FMCW IWR1443 ===")
    
    # Znajdź wszystkie pliki
    all_files = find_radar_files(DATA_FOLDER)
    if not all_files:
        print("Nie znaleziono plików .cf32!")
        return
    
    print(f"Znaleziono {len(all_files)} plików .cf32")
    
    # Grupowanie plików według folderów (scenariuszy)
    scenarios = {}
    for file_path in all_files:
        folder_name = file_path.parent.name
        if folder_name not in scenarios:
            scenarios[folder_name] = []
        scenarios[folder_name].append(file_path)
    
    print(f"Znaleziono {len(scenarios)} różnych scenariuszy")
    
    # Pokaż dostępne scenariusze
    print("\nDostępne scenariusze (pierwsze 10):")
    for i, scenario in enumerate(list(scenarios.keys())[:10]):
        files_count = len(scenarios[scenario])
        params = parse_folder_name(scenario)
        param_str = ", ".join([f"{v}" for v in params.values()])
        print(f"{i+1:2d}. {scenario[:40]:40s} ({files_count:2d} plików) - {param_str}")
    
    # Pytanie o tryb przetwarzania
    print(f"\nTryby przetwarzania:")
    print("1. Pojedyncze klatki (szybsze)")
    print("2. Multi-frame (łączenie kilku klatek - dokładniejsze)")
    print("3. Porównanie scenariuszy")
    print("4. Test kątów >90° (112°, 136°)")
    
    choice = input("Wybierz tryb (1/2/3/4) [domyślnie 1]: ").strip()
    
    if choice == "3":
        compare_scenarios(scenarios)
        return
    elif choice == "4":
        test_large_angles(scenarios)
        return
        
    multi_frame = choice == "2"
    
    # Pytanie o liczbę scenariuszy do analizy
    max_scenarios = min(5, len(scenarios))
    num_scenarios = input(f"Ile scenariuszy analizować? (1-{max_scenarios}) [domyślnie 3]: ").strip()
    
    try:
        num_scenarios = int(num_scenarios) if num_scenarios else 3
        num_scenarios = min(num_scenarios, max_scenarios)
    except:
        num_scenarios = 3
    
    # Analizuj wybrane scenariusze
    scenario_names = list(scenarios.keys())[:num_scenarios]
    
    for scenario_name in scenario_names:
        files = scenarios[scenario_name]
        analyze_scenario(scenario_name, files, multi_frame)
    
    print(f"\n=== Analiza zakończona - {num_scenarios} scenariuszy ===")

def compare_scenarios(scenarios, max_compare=4):
    """Porównuje różne scenariusze na jednym wykresie"""
    print("\n=== TRYB PORÓWNANIA SCENARIUSZY ===")
    
    # Wybierz scenariusze o różnych odległościach/kątach
    selected_scenarios = []
    scenario_names = list(scenarios.keys())
    
    # Spróbuj wybrać scenariusze o różnych parametrach
    distances = ['0.9m', '1m', '2m', '3m', '4m']
    angles = ['0', '23', '45', '68', '112', '136']
    
    for distance in distances:
        for angle in angles:
            for name in scenario_names:
                if distance in name and f'{angle}_degres' in name and name not in selected_scenarios:
                    selected_scenarios.append(name)
                    if len(selected_scenarios) >= max_compare:
                        break
            if len(selected_scenarios) >= max_compare:
                break
        if len(selected_scenarios) >= max_compare:
            break
    
    # Jeśli nie znaleziono wystarczająco, dodaj pierwsze dostępne
    while len(selected_scenarios) < max_compare and len(selected_scenarios) < len(scenario_names):
        for name in scenario_names:
            if name not in selected_scenarios:
                selected_scenarios.append(name)
                break
    
    print(f"Porównuję {len(selected_scenarios)} scenariuszy:")
    for i, name in enumerate(selected_scenarios):
        params = parse_folder_name(name)
        print(f"{i+1}. {name} - {params}")
    
    # Wczytaj dane z każdego scenariusza
    fig, axes = plt.subplots(2, len(selected_scenarios), figsize=(5*len(selected_scenarios), 10))
    if len(selected_scenarios) == 1:
        axes = axes.reshape(-1, 1)
    
    for i, scenario_name in enumerate(selected_scenarios):
        files = scenarios[scenario_name]
        first_file = files[0]
        data = load_radar_data(first_file)
        
        if data is not None:
            # Range-Doppler z rzeczywistymi prędkościami
            rd_map = generate_range_doppler_map(data, tx_idx=0, rx_idx=0)
            velocity_axis, max_vel, vel_res = calculate_doppler_axis(rd_map.shape[1])
            vmin_rd = np.percentile(rd_map, 10)
            vmax_rd = np.percentile(rd_map, 90)
            
            axes[0,i].imshow(rd_map, aspect='auto', origin='lower', cmap='viridis', 
                           vmin=vmin_rd, vmax=vmax_rd,
                           extent=[velocity_axis[0], velocity_axis[-1], 0, MAX_RANGE])
            params = parse_folder_name(scenario_name)
            axes[0,i].set_title(f"R-D: {params.get('angle', 'N/A')}, {params.get('distance', 'N/A')}\n±{max_vel:.1f}m/s")
            axes[0,i].set_ylabel('Odległość [m]')
            axes[0,i].set_xlabel('Prędkość [m/s]')
            axes[0,i].axvline(x=0, color='white', alpha=0.7, linewidth=1)  # 0 m/s
            
            # Range-Angle
            ra_map, angle_fft_size = generate_range_angle_map(data, tx_idx=0)
            angle_axis = calculate_angle_axis(angle_fft_size)
            vmin_ra = np.percentile(ra_map, 10)
            vmax_ra = np.percentile(ra_map, 90)
            axes[1,i].imshow(ra_map, aspect='auto', origin='lower', cmap='viridis', 
                           vmin=vmin_ra, vmax=vmax_ra,
                           extent=[angle_axis[0], angle_axis[-1], 0, MAX_RANGE])
            axes[1,i].set_title(f"R-A: {params.get('angle', 'N/A')}, {params.get('distance', 'N/A')}")
            axes[1,i].set_ylabel('Odległość [m]')
            axes[1,i].set_xlabel('Kąt [°]')
            axes[1,i].grid(True, alpha=0.3)
    
    plt.suptitle('Porównanie scenariuszy - Range-Doppler (góra) i Range-Angle (dół)', fontsize=14)
    plt.tight_layout()
    plt.savefig('comparison_scenarios.png', dpi=150, bbox_inches='tight')
    print("Zapisano porównanie: comparison_scenarios.png")
    plt.show()

def test_large_angles(scenarios):
    """Testuje scenariusze z kątami większymi niż 90°"""
    print("\n=== TRYB TESTOWY: KĄTY >90° ===")
    
    # Znajdź scenariusze z kątami 112° i 136°
    test_scenarios = []
    for name in scenarios.keys():
        if '112_degres' in name or '136_degres' in name:
            test_scenarios.append(name)
    
    print(f"Znaleziono {len(test_scenarios)} scenariuszy z kątami >90°:")
    for i, name in enumerate(test_scenarios[:5]):
        params = parse_folder_name(name)
        print(f"{i+1}. {name} - {params}")
    
    if test_scenarios:
        # Analizuj pierwsze 3 scenariusze
        for scenario_name in test_scenarios[:3]:
            files = scenarios[scenario_name]
            if files:
                print(f"\n🧪 TESTUJE: {scenario_name}")
                analyze_scenario(scenario_name, files, multi_frame=False)
    else:
        print("Brak scenariuszy z kątami >90°")

if __name__ == "__main__":
    main()