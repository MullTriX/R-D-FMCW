%% INICJALIZACJA I KONFIGURACJA
recordLocation = 'Dataset/10s_nic_plus_machanie/';
filePath = fullfile(recordLocation, 'iqData_RecordingParameters.mat');
if ~isfile(filePath), error('Nie znaleziono pliku: %s', filePath); end

temp = load(filePath);
dcaRecordingParams = temp.RecordingParameters;
fs = dcaRecordingParams.ADCSampleRate * 1e3;
sweepSlope = dcaRecordingParams.SweepSlope * 1e12; 
nr = dcaRecordingParams.SamplesPerChirp;
fc = dcaRecordingParams.CenterFrequency * 1e9;
tpulse = 2 * dcaRecordingParams.ChirpCycleTime * 1e-6;
prf = 1 / tpulse;

% Obiekty przetwarzające
rangeresp = phased.RangeResponse('RangeMethod', 'FFT', 'RangeFFTLengthSource', 'Property', 'RangeFFTLength', nr, 'SampleRate', fs, 'SweepSlope', sweepSlope, 'ReferenceRangeCentered', false);
rd_response = phased.RangeDopplerResponse('SweepSlope', sweepSlope, 'SampleRate', fs, 'DopplerOutput', 'Speed', 'OperatingFrequency', fc, 'PRFSource', 'Property', 'PRF', prf, 'RangeMethod', 'FFT', 'RangeFFTLengthSource', 'Property', 'RangeFFTLength', nr, 'ReferenceRangeCentered', false);

% Inicjalizacja CFAR
guard_size = [2 2]; 
train_size = [4 4]; 
cfar2D = phased.CFARDetector2D('GuardBandSize', guard_size, 'TrainingBandSize', train_size, 'ProbabilityFalseAlarm', 1e-5, 'Method', 'CA');

%% PRZYGOTOWANIE GUI
fr = dca1000FileReader('RecordLocation', recordLocation);
iqData = read(fr, 1);
[~, r_grid_1d] = rangeresp(squeeze(iqData{1}(:,1,:)));
[~, r_grid_2d, v_grid] = rd_response(squeeze(iqData{1}(:,1,1:2:end)));

half_idx = floor(length(r_grid_2d) / 2);
r_grid_half = r_grid_2d(1:half_idx);

% Tworzenie siatki dla CFAR
row_start = train_size(1) + guard_size(1) + 1;
row_end   = half_idx - (train_size(1) + guard_size(1));
col_start = train_size(2) + guard_size(2) + 1;
col_end   = length(v_grid) - (train_size(2) + guard_size(2));
[c_grid, r_grid_cfar] = meshgrid(col_start:col_end, row_start:row_end);
CUTIdx = [r_grid_cfar(:) c_grid(:)]';

% Rysowanie okien
figure('Name', 'Analiza Offline - Modułowa', 'Position', [100, 100, 1200, 500]);
subplot(1, 2, 1);
h_plot = plot(r_grid_half, zeros(half_idx, 1), 'b', 'LineWidth', 1.5);
grid on; title('Profil Odległości'); xlabel('Odległość [m]'); ylabel('Moc [dB]'); ylim([40 120]); 

subplot(1, 2, 2);
h_img = imagesc(v_grid, r_grid_half, zeros(half_idx, length(v_grid)));
axis xy; colormap('jet'); colorbar; title('Mapa Range-Doppler'); xlabel('Prędkość [m/s]'); ylabel('Odległość [m]'); clim([50 120]); 
hold on; h_target = plot(0, 0, 'ro', 'MarkerSize', 15, 'LineWidth', 3, 'Visible', 'off'); hold off;

%% PĘTLA GŁÓWNA
disp('Odtwarzanie pliku rozpoczęte...');
fr = dca1000FileReader('RecordLocation', recordLocation); 
total_frames = fr.NumDataCubes;

while (fr.CurrentPosition <= total_frames)
    current_frame = fr.CurrentPosition;
    iqData = read(fr, 1); iqData = iqData{1};
    
    % 1. Przetwarzanie Range (Lewy wykres)
    iqDataRx1 = squeeze(iqData(:,1,:)) - mean(squeeze(iqData(:,1,:)), 1); 
    resp_range = rangeresp(iqDataRx1);
    resp_range_db = 20 * log10(abs(resp_range(1:half_idx, 1)) + 1e-6);
    
    % 2. Przetwarzanie Range-Doppler z MTI
    iqDataRx1Tx1 = squeeze(iqData(:,1,1:2:end));
    iqData_mti = MTI(iqDataRx1Tx1); % <-- WYWOŁANIE FUNKCJI MTI
    
    resp_rd = rd_response(iqData_mti);
    resp_rd_half = resp_rd(1:half_idx, :);
    resp_rd_db = 20 * log10(abs(resp_rd_half) + 1e-6);
    
    % 3. Detekcja CFAR
    power_matrix = abs(resp_rd_half).^2;
    [found, tgt_r, tgt_v] = CFAR(power_matrix, cfar2D, CUTIdx, r_grid_half, v_grid); % <-- WYWOŁANIE FUNKCJI CFAR
    
    % 4. Aktualizacja GUI
    set(h_plot, 'YData', resp_range_db);
    set(h_img, 'CData', resp_rd_db);
    
    if found
        set(h_target, 'XData', tgt_v, 'YData', tgt_r, 'Visible', 'on');
    else
        set(h_target, 'Visible', 'off');
    end
    
    title(subplot(1,2,2), sprintf('Mapa Range-Doppler | Klatka: %d/%d', current_frame, total_frames));
    drawnow; pause(0.05); 
end
disp('Koniec odtwarzania.');