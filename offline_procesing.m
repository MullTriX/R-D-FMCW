% Zdefiniowanie ścieżki do folderu (upewnij się, że nie ma problemów ze znakami '/')
recordLocation = '/Users/mateuszkazmierczak/R-D-FMCW/Dataset/10s_nic_plus_machanie/';
filePath = fullfile(recordLocation, 'iqData_RecordingParameters.mat');

% Zabezpieczenie przed złą ścieżką
if ~isfile(filePath)
    error('Nie znaleziono pliku z parametrami: %s', filePath);
end

temp = load(filePath);
dcaRecordingParams = temp.RecordingParameters;

% Konwersja jednostek dla obiektów przetwarzających
fs = dcaRecordingParams.ADCSampleRate * 1e3;
sweepSlope = dcaRecordingParams.SweepSlope * 1e12; % GHz/us to Hz/s
nr = dcaRecordingParams.SamplesPerChirp;
fc = dcaRecordingParams.CenterFrequency * 1e9;
tpulse = 2 * dcaRecordingParams.ChirpCycleTime * 1e-6;
prf = 1 / tpulse;
nrx = dcaRecordingParams.NumReceivers;
nchirp = dcaRecordingParams.NumChirps;

% Utworzenie obiektu RangeResponse (do analizy samej odległości)
rangeresp = phased.RangeResponse('RangeMethod', 'FFT', ...
    'RangeFFTLengthSource', 'Property', ...
    'RangeFFTLength', nr, ...
    'SampleRate', fs, ...
    'SweepSlope', sweepSlope, ...
    'ReferenceRangeCentered', false);

% Utworzenie obiektu RangeDopplerScope do mapy R-D
rdscope = phased.RangeDopplerScope('IQDataInput', true, ...
    'SweepSlope', sweepSlope, 'SampleRate', fs, ...
    'DopplerOutput', 'Speed', 'OperatingFrequency', fc, ...
    'PRFSource', 'Property', 'PRF', prf, ...
    'RangeMethod', 'FFT', 'RangeFFTLength', nr, ...
    'ReferenceRangeCentered', false);

% =====================================================================
% ROZWIĄZANIE PROBLEMU Z RECORD LOCATION (Klasyczna składnia)
% =====================================================================
fr = dca1000FileReader('RecordLocation', recordLocation);

% Pętla odczytująca klatki offline
while (fr.CurrentPosition <= fr.NumDataCubes)
    
    % Odczyt surowej klatki danych
    iqData = read(fr, 1);
    iqData = iqData{1};
    
    % --- 1. WYKRES RANGE RESPONSE ---
    iqDataRx1 = squeeze(iqData(:,1,:));
    
    % Opcjonalne usunięcie błędu sprzętowego ADC (Zero-DC Offset)
    iqDataRx1 = iqDataRx1 - mean(iqDataRx1, 1);
    
    % Rysowanie profilu odległości
    plotResponse(rangeresp, iqDataRx1);
    
    
    % --- 2. WYKRES RANGE-DOPPLER Z FILTREM MTI ---
    % Pobranie danych dla pary RX1 i TX1
    iqDataRx1Tx1 = squeeze(iqData(:,1,1:2:end));
    
    % KROK A: Korekcja ADC DC Offset (Zapobiega paskom na odległości 0 m)
    iqDataRx1Tx1 = iqDataRx1Tx1 - mean(iqDataRx1Tx1, 1);
    
    % KROK B: Filtr MTI (Moving Target Indicator)
    % Uśredniamy sygnał wzdłuż chirpów (wymiar 2), aby uzyskać idealnie statyczne tło
    static_clutter = mean(iqDataRx1Tx1, 2);
    
    % Odejmujemy to tło od sygnału – wymazujemy wszystko co ma prędkość 0 m/s
    iqData_mti = iqDataRx1Tx1 - static_clutter;
    
    % Wyświetlenie odszumionego obrazu na Scope
    rdscope(iqData_mti);
    
    % =====================================================================
    % Wymuszenie aktualizacji okien w trakcie pętli while
    % Bez tego MATLAB zawiesi się i wyrysuje tylko ostatnią klatkę!
    % =====================================================================
    drawnow limitrate;
    
end