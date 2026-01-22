function [rd_map, vel_axis, rng_axis] = processRangeDoppler(radar_cube, config, tx_idx, rx_idx)
    % processRangeDoppler: Generuje mapę Zasięg-Prędkość dla wybranej pary anten
    
    % 1. Demultipleksacja TDM (Wybieramy chirpy tylko dla konkretnego TX)
    tx_data = radar_cube(tx_idx:config.N_TX:end, :, :);
    
    % Wybór RX i usunięcie singleton dimensions
    adc_data = squeeze(tx_data(:, rx_idx, :)); 
    % Oczekiwany wymiar: [Chirps, Samples]
    
    [n_chirps, n_samples] = size(adc_data);
    
    % Usuwanie składowej stałej (DC Removal)
    adc_data = adc_data - mean(adc_data, 2);
    
    % 2. RANGE FFT (Wzdłuż próbek)
    window_range = blackman(n_samples).'; % Wiersz
    
    % Zabezpieczenie orientacji (broadcasting)
    if size(adc_data, 2) ~= length(window_range)
        adc_data = adc_data.'; 
    end
    
    range_fft = fft(adc_data .* window_range, n_samples * 2, 2);
    range_fft = range_fft(:, 1:n_samples); % Bierzemy połowę widma
    
    % 3. DOPPLER FFT (Wzdłuż chirpów)
    window_doppler = blackman(n_chirps); % Kolumna
    
    % Upewnij się, że range_fft ma chirpy w wierszach
    if size(range_fft, 1) ~= length(window_doppler)
        range_fft = range_fft.';
    end
    
    doppler_fft = fft(range_fft .* window_doppler, n_chirps * 2, 1);
    doppler_fft = fftshift(doppler_fft, 1);
    
    % 4. Wynik i Osie
    rd_map = 20 * log10(abs(doppler_fft).' + 1e-9); % Transpozycja -> [Range, Doppler]
    
    % Osie
    max_range = config.getMaxRange();
    rng_axis = linspace(0, max_range, n_samples);
    
    v_res = config.getVelocityResolution();
    n_vel = size(doppler_fft, 1);
    vel_axis = ((-n_vel/2) : (n_vel/2 - 1)) * v_res;
end