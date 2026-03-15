% Definicja ścieżki i wczytanie parametrów
recordLocation = 'Dataset/10s_nic_plus_machanie/';
filePath = fullfile(recordLocation, 'iqData_RecordingParameters.mat');

if ~isfile(filePath)
    error('Nie znaleziono pliku: %s', filePath);
end

temp = load(filePath);
dcaRecordingParams = temp.RecordingParameters;

% Konwersja parametrów
fs = dcaRecordingParams.ADCSampleRate * 1e3;
sweepSlope = dcaRecordingParams.SweepSlope * 1e12; 
nr = dcaRecordingParams.SamplesPerChirp;
fc = dcaRecordingParams.CenterFrequency * 1e9;
tpulse = 2 * dcaRecordingParams.ChirpCycleTime * 1e-6;
prf = 1 / tpulse;
nrx = dcaRecordingParams.NumReceivers;
nchirp = dcaRecordingParams.NumChirps;

% 1. Obiekt do Odległości (Range) - ZWRACA DANE
rangeresp = phased.RangeResponse('RangeMethod', 'FFT', ...
    'RangeFFTLengthSource', 'Property', 'RangeFFTLength', nr, ...
    'SampleRate', fs, 'SweepSlope', sweepSlope, ...
    'ReferenceRangeCentered', false);

% 2. Obiekt do mapy R-D (Range-Doppler) - ZWRACA DANE
rd_response = phased.RangeDopplerResponse(...
    'SweepSlope', sweepSlope, 'SampleRate', fs, ...
    'DopplerOutput', 'Speed', 'OperatingFrequency', fc, ...
    'PRFSource', 'Property', 'PRF', prf, ...
    'RangeMethod', 'FFT', ...
    'RangeFFTLengthSource', 'Property', ...
    'RangeFFTLength', nr, ...
    'ReferenceRangeCentered', false);

fr = dca1000FileReader('RecordLocation', recordLocation);

% =========================================================================
% INICJALIZACJA WŁASNEGO INTERFEJSU GRAFICZNEGO (GUI)
% =========================================================================
% Wczytujemy jedną klatkę "na sucho", żeby zdobyć osie X i Y
iqData = read(fr, 1);
iqData = iqData{1};
iqDataRx1 = squeeze(iqData(:,1,:));
iqDataRx1Tx1 = squeeze(iqData(:,1,1:2:end));

[~, r_grid_1d] = rangeresp(iqDataRx1);
[~, r_grid_2d, v_grid] = rd_response(iqDataRx1Tx1);

% Ucinamy osie o połowę (usuwamy lustrzane odbicie)
half_idx = floor(length(r_grid_2d) / 2);
r_grid_half = r_grid_2d(1:half_idx);

% Tworzymy główne okno
figure('Name', 'Analiza Offline - FMCW Radar', 'Position', [100, 100, 1200, 500]);

% --- SUBPLOT 1: Profil Odległości ---
subplot(1, 2, 1);
h_plot = plot(r_grid_half, zeros(half_idx, 1), 'b', 'LineWidth', 1.5);
grid on; title('Profil Odległości (Zasięg)');
xlabel('Odległość [m]'); ylabel('Moc [dB]');
ylim([40 120]); % Sztywne osie Y dla profilu 1D

% --- SUBPLOT 2: Mapa Range-Doppler z MTI ---
subplot(1, 2, 2);
h_img = imagesc(v_grid, r_grid_half, zeros(half_idx, length(v_grid)));
axis xy; colormap('jet'); colorbar;
title('Mapa Range-Doppler (Filtr MTI)');
xlabel('Prędkość [m/s]'); ylabel('Odległość [m]');

% BLOKUJEMY SKALĘ KOLORÓW! Odcinamy pomarańczowy szum.
% Jeśli nadal jest za jasno, zmień dół skali na wyższy (np. 60 lub 70)
clim([70 120]); 

% Resetujemy wskaźnik czytnika plików do początku?
fr = dca1000FileReader('RecordLocation', recordLocation);

% =========================================================================
% GŁÓWNA PĘTLA PRZETWARZANIA
% =========================================================================
disp('Odtwarzanie pliku rozpoczęte...');

% Tworzymy czytnik od nowa, żeby na pewno zaczął od 1 klatki
fr = dca1000FileReader('RecordLocation', recordLocation);
total_frames = fr.NumDataCubes;

while (fr.CurrentPosition <= total_frames)
    
    current_frame = fr.CurrentPosition;
    
    iqData = read(fr, 1);
    iqData = iqData{1};
    
    % --- 1. DANE ODLEGŁOŚCIOWE (LEWY WYKRES) ---
    iqDataRx1 = squeeze(iqData(:,1,:));
    iqDataRx1 = iqDataRx1 - mean(iqDataRx1, 1); 
    
    resp_range = rangeresp(iqDataRx1);
    resp_range_half = resp_range(1:half_idx, 1);
    resp_range_db = 20 * log10(abs(resp_range_half) + 1e-6);
    
    % --- 2. DANE RANGE-DOPPLER Z MTI (PRAWY WYKRES) ---
    iqDataRx1Tx1 = squeeze(iqData(:,1,1:2:end));
    iqDataRx1Tx1 = iqDataRx1Tx1 - mean(iqDataRx1Tx1, 1); 
    
    static_clutter = mean(iqDataRx1Tx1, 2); 
    iqData_mti = iqDataRx1Tx1 - static_clutter; 
    
    resp_rd = rd_response(iqData_mti);
    resp_rd_half = resp_rd(1:half_idx, :);
    resp_rd_db = 20 * log10(abs(resp_rd_half) + 1e-6);
    
    % --- 3. BŁYSKAWICZNA AKTUALIZACJA EKRANU ---
    set(h_plot, 'YData', resp_range_db);
    set(h_img, 'CData', resp_rd_db);
    
    % Dynamiczna aktualizacja tytułu, żebyś widział postęp
    title(subplot(1,2,2), sprintf('Mapa Range-Doppler (Filtr MTI) | Klatka: %d/%d', current_frame, total_frames));
    
    % Wymuszamy narysowanie klatki (bez limitrate, żeby nie omijał klatek)
    drawnow;
    
    % SPOWOLNIENIE ODTWARZANIA (ok. 20 FPS)
    % Bez tego pętla wykona się w 0.5 sekundy!
    pause(0.05); 
    
end

disp('Koniec odtwarzania.');