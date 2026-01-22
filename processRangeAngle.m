function [ra_map, ang_axis, rng_axis] = processRangeAngle(radar_cube, config, tx_idx)
    % processRangeAngle: Generuje mapę Zasięg-Kąt
    
    % 1. Pobranie danych dla TX i uśrednienie chirpów (Non-Coherent Integration)
    tx_data = radar_cube(tx_idx:config.N_TX:end, :, :);
    avg_chirp = squeeze(mean(tx_data, 1)); % [RX, Samples]
    
    [n_rx, n_samples] = size(avg_chirp);
    
    % Jeśli wymiary są odwrócone [Samples, RX], napraw to
    if n_rx > n_samples 
        avg_chirp = avg_chirp.';
        [n_rx, n_samples] = size(avg_chirp);
    end
    
    % 2. RANGE FFT
    win_rng = blackman(n_samples).';
    range_fft = fft(avg_chirp .* win_rng, n_samples * 2, 2);
    range_fft = range_fft(:, 1:n_samples);
    
    % 3. ANGLE FFT
    win_ang = hamming(n_rx);
    n_angle_fft = 128; % Rozdzielczość FFT kątowego
    
    angle_fft = fft(range_fft .* win_ang, n_angle_fft, 1);
    angle_fft = fftshift(angle_fft, 1);
    
    % 4. Wynik
    ra_map = 20 * log10(abs(angle_fft).' + 1e-9);
    
    % Osie
    max_range = config.getMaxRange();
    rng_axis = linspace(0, max_range, n_samples);
    ang_axis = linspace(-90, 90, n_angle_fft);
end