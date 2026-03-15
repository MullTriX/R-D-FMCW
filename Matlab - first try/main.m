%% MAIN SCRIPT - FMCW RADAR ANALYSIS
clear; clc; close all;

% 1. Konfiguracja ścieżek
data_folder = '1_one_person_raw_fmcw_data-20250414T204939Z-004'; % Nazwa Twojego folderu (dostosuj jeśli inna)
search_path = fullfile(pwd, data_folder, '**', '*.cf32');
files = dir(search_path);

if isempty(files)
    error('Nie znaleziono plików .cf32 w folderze: %s', data_folder);
end

% 2. Inicjalizacja Configu
radar_conf = RadarConfig();

fprintf('Znaleziono %d plików. Przetwarzam pierwszy jako demo...\n', length(files));

% --- PRZETWARZANIE PIERWSZEGO PLIKU ---
file_idx = 1; 
full_path = fullfile(files(file_idx).folder, files(file_idx).name);

try
    % A. Wczytaj
    fprintf('📥 Wczytywanie: %s\n', files(file_idx).name);
    [cube, radar_conf] = loadRadarData(full_path, radar_conf);
    
    % B. Oblicz Range-Doppler
    fprintf('⚙️ Obliczanie Range-Doppler...\n');
    [rd_map, v_ax, r_ax] = processRangeDoppler(cube, radar_conf, 1, 1);
    
    % C. Oblicz Range-Angle
    fprintf('⚙️ Obliczanie Range-Angle...\n');
    [ra_map, a_ax, ~] = processRangeAngle(cube, radar_conf, 1);
    
    % D. Wizualizacja
    figure('Position', [100, 100, 1200, 500], 'Name', files(file_idx).name);
    
    subplot(1, 2, 1);
    imagesc(v_ax, r_ax, rd_map);
    axis xy; colormap('jet'); colorbar;
    title('Range-Doppler Map');
    xlabel('Velocity [m/s]'); ylabel('Range [m]');
    
    subplot(1, 2, 2);
    imagesc(a_ax, r_ax, ra_map);
    axis xy; colormap('jet'); colorbar;
    title('Range-Angle Map');
    xlabel('Angle [deg]'); ylabel('Range [m]');
    
    fprintf('✅ Gotowe!\n');
    
catch ME
    fprintf('❌ BŁĄD: %s\n', ME.message);
    fprintf('W linii: %d pliku: %s\n', ME.stack(1).line, ME.stack(1).name);
end