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

% 1. Obiekt do Odległości (Range)
rangeresp = phased.RangeResponse('RangeMethod', 'FFT', ...
    'RangeFFTLengthSource', 'Property', 'RangeFFTLength', nr, ...
    'SampleRate', fs, 'SweepSlope', sweepSlope, ...
    'ReferenceRangeCentered', false);

% 2. Obiekt do mapy R-D (Range-Doppler)
rd_response = phased.RangeDopplerResponse(...
    'SweepSlope', sweepSlope, 'SampleRate', fs, ...
    'DopplerOutput', 'Speed', 'OperatingFrequency', fc, ...
    'PRFSource', 'Property', 'PRF', prf, ...
    'RangeMethod', 'FFT', ...
    'RangeFFTLengthSource', 'Property', ...
    'RangeFFTLength', nr, ...
    'ReferenceRangeCentered', false);

% =========================================================================
% INICJALIZACJA WYKRESÓW I OSI
% =========================================================================
fr = dca1000FileReader('RecordLocation', recordLocation);

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
figure('Name', 'Analiza Offline - FMCW Radar z CFAR', 'Position', [100, 100, 1200, 500]);

% --- SUBPLOT 1: Profil Odległości ---
subplot(1, 2, 1);
h_plot = plot(r_grid_half, zeros(half_idx, 1), 'b', 'LineWidth', 1.5);
grid on; title('Profil Odległości (Zasięg)');
xlabel('Odległość [m]'); ylabel('Moc [dB]');
ylim([40 120]); 

% --- SUBPLOT 2: Mapa Range-Doppler z MTI ---
subplot(1, 2, 2);
h_img = imagesc(v_grid, r_grid_half, zeros(half_idx, length(v_grid)));
axis xy; colormap('jet'); colorbar;
title('Mapa Range-Doppler');
xlabel('Prędkość [m/s]'); ylabel('Odległość [m]');
clim([50 120]); 

% =========================================================================
% INICJALIZACJA DETEKTORA CFAR 2D
% =========================================================================
guard_size = [2 2]; % Margines wokół badanego punktu
train_size = [4 4]; % Liczba komórek do obliczenia średniego szumu tła

cfar2D = phased.CFARDetector2D('GuardBandSize', guard_size, ...
    'TrainingBandSize', train_size, ...
    'ProbabilityFalseAlarm', 1e-8, ... % Czułość (1e-4 do 1e-6)
    'Method', 'CA'); % Metoda uśredniania okna tła

% Obliczenie siatki dla CFAR (CUT - Cell Under Test). 
% Zapobiega wyjściu okna wirtualnego poza krawędzie obrazu.
row_start = train_size(1) + guard_size(1) + 1;
row_end   = half_idx - (train_size(1) + guard_size(1));
col_start = train_size(2) + guard_size(2) + 1;
col_end   = length(v_grid) - (train_size(2) + guard_size(2));

[c_grid, r_grid_cfar] = meshgrid(col_start:col_end, row_start:row_end);
CUTIdx = [r_grid_cfar(:) c_grid(:)]';

% Dodajemy znacznik CFAR na prawym wykresie (Czerwone kółko)
hold on;
h_target = plot(0, 0, 'ro', 'MarkerSize', 15, 'LineWidth', 3, 'Visible', 'off');
hold off;

% =========================================================================
% GŁÓWNA PĘTLA PRZETWARZANIA
% =========================================================================
disp('Odtwarzanie pliku rozpoczęte...');
fr = dca1000FileReader('RecordLocation', recordLocation); % Otwieramy plik od nowa
total_frames = fr.NumDataCubes;

while (fr.CurrentPosition <= total_frames)
    
    current_frame = fr.CurrentPosition;
    
    iqData = read(fr, 1);
    iqData = iqData{1};
    
    % --- 1. DANE ODLEGŁOŚCIOWE ---
    iqDataRx1 = squeeze(iqData(:,1,:));
    iqDataRx1 = iqDataRx1 - mean(iqDataRx1, 1); 
    
    resp_range = rangeresp(iqDataRx1);
    resp_range_half = resp_range(1:half_idx, 1);
    resp_range_db = 20 * log10(abs(resp_range_half) + 1e-6);
    
    % --- 2. DANE RANGE-DOPPLER Z MTI ---
    iqDataRx1Tx1 = squeeze(iqData(:,1,1:2:end));
    iqDataRx1Tx1 = iqDataRx1Tx1 - mean(iqDataRx1Tx1, 1); 
    
    static_clutter = mean(iqDataRx1Tx1, 2); 
    iqData_mti = iqDataRx1Tx1 - static_clutter; 
    
    resp_rd = rd_response(iqData_mti);
    resp_rd_half = resp_rd(1:half_idx, :);
    resp_rd_db = 20 * log10(abs(resp_rd_half) + 1e-6);
    
    % --- 3. ALGORYTM CFAR NA MACIERZY 2D ---
    % CFAR działa na skali liniowej mocy!
    power_matrix = abs(resp_rd_half).^2;
    
    % Uruchamiamy CFAR dla wszystkich zdefiniowanych punktów (CUT)
    detections = cfar2D(power_matrix, CUTIdx);
    
    % Szukamy indeksów, dla których CFAR wyrzucił "1" (wykryto cel)
    det_indices = find(detections == 1);
    
    if ~isempty(det_indices)
        % Mapujemy wynik z powrotem na współrzędne 2D (wiersz, kolumna)
        det_rows = CUTIdx(1, det_indices);
        det_cols = CUTIdx(2, det_indices);
        
        % Opcjonalne: Gdy CFAR wykryje dużą chmurę punktów, bierzemy najsilniejszy pik
        lin_indices = sub2ind(size(power_matrix), det_rows, det_cols);
        detected_powers = power_matrix(lin_indices);
        [~, max_idx] = max(detected_powers);
        
        best_r_idx = det_rows(max_idx);
        best_v_idx = det_cols(max_idx);
        
        % Aktywujemy czerwone kółko i ustawiamy w miejscu najsilniejszego piku
        set(h_target, 'XData', v_grid(best_v_idx), 'YData', r_grid_half(best_r_idx), 'Visible', 'on');
    else
        % Jeśli nic nie wykryto - wygaszamy kółko
        set(h_target, 'Visible', 'off');
    end
    
    % --- 4. BŁYSKAWICZNA AKTUALIZACJA EKRANU ---
    set(h_plot, 'YData', resp_range_db);
    set(h_img, 'CData', resp_rd_db);
    
    title(subplot(1,2,2), sprintf('Mapa Range-Doppler z CFAR | Klatka: %d/%d', current_frame, total_frames));
    
    drawnow;
    pause(0.05); 
    
end
disp('Koniec odtwarzania.');