%% 1. INICJALIZACJA I WCZYTANIE PARAMETRÓW
clear all; close all;

recordLocation = 'Dataset/10s_nic_plus_machanie/';
filePath = fullfile(recordLocation, 'iqData_RecordingParameters.mat');
if ~isfile(filePath), error('Nie znaleziono pliku: %s', filePath); end

temp = load(filePath);
dcaRecordingParams = temp.RecordingParameters;

% Parametry fizyczne
c = 3e8; 
fs = dcaRecordingParams.ADCSampleRate * 1e3;
fc = dcaRecordingParams.CenterFrequency * 1e9;
tpulse = 2 * dcaRecordingParams.ChirpCycleTime * 1e-6;
sweepslope = dcaRecordingParams.SweepSlope * 1e12; 
nr = dcaRecordingParams.SamplesPerChirp;
lambda = c / fc;
nchirp = dcaRecordingParams.NumChirps;

%% 2. GENEROWANIE OSI (Zasięg, Prędkość i Kąt)
% Oś Zasięgu (odcięcie na 5 metrach)
rangeAxis = (0:nr-1) * (c * fs) / (2 * sweepslope * nr);
idx5m = find(rangeAxis <= 5, 1, 'last');
rangeAxis5m = rangeAxis(1:idx5m);

% Oś Prędkości
v_max = lambda / (4 * tpulse);
numChirps = nchirp / 2; % Bierzemy tylko nadajnik TX1 (co drugi chirp)
v_grid = linspace(-v_max, v_max, numChirps);

% Oś Kąta
numAngleBins = 64;
k_vec = -numAngleBins/2 : numAngleBins/2-1;
sin_theta = 2 * k_vec / numAngleBins;
sin_theta(sin_theta > 1) = 1; sin_theta(sin_theta < -1) = -1; 
theta_axis_deg = asind(sin_theta);

%% 3. INICJALIZACJA CFAR 2D
guard_size = [2 2]; 
train_size = [4 4]; 
cfar2D = phased.CFARDetector2D('GuardBandSize', guard_size, 'TrainingBandSize', train_size, ...
    'ProbabilityFalseAlarm', 1e-5, 'Method', 'CA');

% Siatka CFAR
row_start = train_size(1) + guard_size(1) + 1;
row_end   = idx5m - (train_size(1) + guard_size(1));
col_start = train_size(2) + guard_size(2) + 1;
col_end   = numChirps - (train_size(2) + guard_size(2));
[c_grid, r_grid_cfar] = meshgrid(col_start:col_end, row_start:row_end);
CUTIdx = [r_grid_cfar(:) c_grid(:)]';

%% 4. PRZYGOTOWANIE INTERFEJSU (GUI)
fig = figure('Name', 'Analiza Offline: CFAR & Kąt', 'Position', [100, 100, 1200, 500]);

% Panel 1: Mapa Range-Doppler
axMap = subplot(1, 2, 1);
hImage = imagesc(axMap, 'XData', v_grid, 'YData', rangeAxis5m, 'CData', zeros(idx5m, numChirps));
set(axMap, 'YDir', 'normal');
xlabel(axMap, 'Prędkość (m/s)'); ylabel(axMap, 'Odległość (m)');
title(axMap, 'Mapa Range-Doppler');
colormap(axMap, 'jet'); colorbar(axMap);
clim(axMap, [50 110]); % Zablokowanie skali kolorów (dostosuj jeśli trzeba)

% Panel 2: Wykres Polarny (Kąt)
axPolar = subplot(1, 2, 2); 
hTarget = polarplot(0, 0, 'ro', 'MarkerSize', 15, 'MarkerFaceColor', 'r', 'LineWidth', 2); 
axPolar = gca; 
axPolar.ThetaZeroLocation = 'top'; 
axPolar.ThetaDir = 'clockwise';
axPolar.ThetaLim = [-45 45]; 
axPolar.RLim = [0 5];        
title(axPolar, 'Lokalizacja Ruchu (\pm45^\circ)');

%% 5. GŁÓWNA PĘTLA PRZETWARZANIA OFFLINE
disp('Odtwarzanie pliku rozpoczęte...');
fr = dca1000FileReader('RecordLocation', recordLocation);
total_frames = fr.NumDataCubes;

% Okna wygładzające dla FFT
winRange = hamming(nr);
winDoppler = reshape(hamming(numChirps), 1, 1, numChirps);

while (fr.CurrentPosition <= total_frames)
    current_frame = fr.CurrentPosition;
    
    % --- A. Wczytanie ramki danych ---
    iqDataRaw = read(fr, 1);
    iqDataRaw = iqDataRaw{1};
    
    % Wyciągamy WSZYSTKIE 4 anteny dla nadajnika TX1
    iqData4RX = squeeze(iqDataRaw(:, 1:4, 1:2:end)); 
    
    % --- B. Filtry MTI (Zewnętrzna funkcja) ---
    iqData4RX_mti = MTI(iqData4RX);
    
    % --- C. FFT Odległości i Prędkości ---
    % Range FFT
    iqData4RX_win = iqData4RX_mti .* winRange; 
    rangeFFT = fft(iqData4RX_win, nr, 1);
    rangeFFT_5m = rangeFFT(1:idx5m, :, :);
    
    % Doppler FFT
    dopplerFFT_4RX = fftshift(fft(rangeFFT_5m .* winDoppler, numChirps, 3), 3);
    
    % --- D. Mapa dla Anteny 1 ---
    dopplerFFT_RX1 = squeeze(dopplerFFT_4RX(:, 1, :));
    powerDB = 20 * log10(abs(dopplerFFT_RX1) + 1e-6);
    
    % --- E. Detekcja CFAR (Zewnętrzna funkcja) ---
    power_linear = abs(dopplerFFT_RX1).^2;
    % Szukamy do 2.5m, minimalna moc 85 dB (Dostrój te wartości!)
    [found, tgt_r, tgt_v, r_idx, v_idx] = CFAR(power_linear, cfar2D, CUTIdx, rangeAxis5m, v_grid, 2.5, 85);
    
    % --- F. Obliczenie Kąta (Tylko jeśli CFAR coś znalazł) ---
    if found && tgt_r > 0.1
        % Wyciągamy dane z 4 anten dla konkretnego piku wyznaczonego przez CFAR
        spatialData = squeeze(dopplerFFT_4RX(r_idx, :, v_idx)); 
        
        % Angle FFT
        angleFFT = fftshift(fft(spatialData, numAngleBins));
        [~, maxAngleIdx] = max(abs(angleFFT));
        targetAngleDeg = theta_axis_deg(maxAngleIdx);
        
        % Aktualizacja kropki
        if targetAngleDeg >= -45 && targetAngleDeg <= 45
            set(hTarget, 'ThetaData', deg2rad(targetAngleDeg), 'RData', tgt_r, 'Visible', 'on');
        else
            set(hTarget, 'Visible', 'off'); 
        end
    else
        set(hTarget, 'Visible', 'off'); 
    end
    
    % --- G. Aktualizacja Ekranu ---
    set(hImage, 'CData', powerDB);
    title(subplot(1,2,2), sprintf('Lokalizacja Ruchu | Klatka: %d/%d', current_frame, total_frames));
    
    drawnow;
    pause(0.05); % Spowolnienie do ~20 FPS dla płynnego wideo
end

disp('Koniec odtwarzania.');