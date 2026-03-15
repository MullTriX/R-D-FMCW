%% Inicjalizacja połączenia
clear dca;
try
    dca = dca1000('IWR6843ISK');
catch ME
    error('Nie można połączyć się z DCA1000: %s', ME.message);
end

%% Wyliczanie parametrów fizycznych
c = 3e8; 
fs = dca.ADCSampleRate * 1e3;
fc = dca.CenterFrequency * 1e9;
tpulse = 2 * dca.ChirpCycleTime * 1e-6; 
sweepslope = dca.SweepSlope * 1e6 / 1e-6;
nr = dca.SamplesPerChirp;
lambda = c / fc;

%% Generowanie osi (Zasięg, Prędkość i Kąt)
rangeAxis = (0:nr-1) * (c * fs) / (2 * sweepslope * nr);
idx5m = find(rangeAxis <= 5, 1, 'last');
rangeAxis5m = rangeAxis(1:idx5m);

v_max = lambda / (4 * tpulse);

numAngleBins = 64;
k_vec = -numAngleBins/2 : numAngleBins/2-1;
sin_theta = 2 * k_vec / numAngleBins;
sin_theta(sin_theta > 1) = 1; sin_theta(sin_theta < -1) = -1; 
theta_axis_deg = asind(sin_theta);

%% Przygotowanie wykresów
fig = figure('Name', 'Radar Real-Time: Range-Doppler & Położenie', 'NumberTitle', 'off', 'Position', [100, 100, 1200, 500]);

% Panel 1: Mapa Range-Doppler 
axMap = subplot(1, 2, 1);
hImage = imagesc(axMap, 'XData', [-v_max v_max], 'YData', rangeAxis5m, 'CData', zeros(idx5m, 2));
set(axMap, 'YDir', 'normal');
xlabel(axMap, 'Prędkość (m/s)'); ylabel(axMap, 'Odległość (m)');
title(axMap, 'Mapa Range-Doppler (Zasięg do 5m)');
colormap(axMap, 'jet'); colorbar(axMap);

% Panel 2: Ekran Radaru - Polar Plot (Teraz do 45 stopni)
axPolar = subplot(1, 2, 2); 
hTarget = polarplot(0, 0, 'ro', 'MarkerSize', 12, 'MarkerFaceColor', 'r'); 
axPolar = gca; 
axPolar.ThetaZeroLocation = 'top'; 
axPolar.ThetaDir = 'clockwise';
axPolar.ThetaLim = [-45 45]; % ZWIĘKSZONO DO 45 STOPNI
axPolar.RLim = [0 5];        
title(axPolar, 'Lokalizacja najbliższej przeszkody (\pm45^\circ)');

%% Pętla zbierania danych
stopTime = 150; 
ts = tic();
disp('Zbieranie danych... Czekam na ruch przed radarem.');

winRange = hamming(nr);

while (toc(ts) < stopTime)
   % ZABEZPIECZENIE: Przerwij pętlę, jeśli użytkownik zamknął okno
   if ~isvalid(fig)
       disp('Zamknięto okno. Przerywam zbieranie danych.');
       break;
   end

   % 1. Pobranie ramki
   iqDataRaw = dca();
   iqData4RX = squeeze(iqDataRaw(:, 1:4, 1:2:end));
   numChirps = size(iqData4RX, 3);
   
   % 2. Usunięcie tła statycznego
   iqData4RX = iqData4RX - mean(iqData4RX, 3);
   
   % 3. Range FFT
   iqData4RX_win = iqData4RX .* winRange; 
   rangeFFT = fft(iqData4RX_win, nr, 1);
   rangeFFT_5m = rangeFFT(1:idx5m, :, :);
   
   % 4. Doppler FFT dla 4 anten
   winDoppler = reshape(hamming(numChirps), 1, 1, numChirps);
   dopplerFFT_4RX = fftshift(fft(rangeFFT_5m .* winDoppler, numChirps, 3), 3);
   
   % 5. Wyświetlanie mapy Range-Doppler
   dopplerFFT_RX1 = squeeze(dopplerFFT_4RX(:, 1, :));
   powerDB = 20 * log10(abs(dopplerFFT_RX1) + 1e-6);
   
   set(hImage, 'XData', linspace(-v_max, v_max, numChirps), 'CData', powerDB);
   
   % Logika kontrastu
   maxVal = max(powerDB(:));
   noiseFloor = median(powerDB(:)); 
   snr = maxVal - noiseFloor;       
   
   plotMax = max(maxVal, 75); 
   caxis(axMap, [plotMax - 35, plotMax + 0.1]); 
   
   % 6. WYKRYWANIE OBIEKTU 
   [~, linearIdx] = max(powerDB(:));
   [maxRangeIdx, maxDopplerIdx] = ind2sub(size(powerDB), linearIdx);
   targetRange = rangeAxis5m(maxRangeIdx);
   
   MIN_SNR = 12; 
   
   if snr > MIN_SNR && targetRange > 0.1
       spatialData = squeeze(dopplerFFT_4RX(maxRangeIdx, :, maxDopplerIdx)); 
       
       angleFFT = fftshift(fft(spatialData, numAngleBins));
       [~, maxAngleIdx] = max(abs(angleFFT));
       targetAngleDeg = theta_axis_deg(maxAngleIdx);
       
       % ZWIĘKSZONO ZAKRES DETEKCJI DO 45 STOPNI
       if targetAngleDeg >= -45 && targetAngleDeg <= 45
           set(hTarget, 'ThetaData', deg2rad(targetAngleDeg), 'RData', targetRange);
       else
           set(hTarget, 'ThetaData', 0, 'RData', 0); 
       end
   else
       set(hTarget, 'ThetaData', 0, 'RData', 0); 
   end
   
   drawnow limitrate;
end

clear dca;
disp('Koniec sesji.');