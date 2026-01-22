function [radar_cube, config] = loadRadarData(filepath, config)
    % loadRadarData: Wczytuje plik .cf32 i aktualizuje config
    
    if ~isfile(filepath)
        error('Plik nie istnieje: %s', filepath);
    end

    fid = fopen(filepath, 'rb');
    raw = fread(fid, inf, 'float32');
    fclose(fid);

    % 1. Konwersja na liczby zespolone
    if mod(length(raw), 2) ~= 0, raw = raw(1:end-1); end
    data_complex = raw(1:2:end) + 1i * raw(2:2:end);
    
    % 2. Autodetekcja liczby próbek (rozwiązanie problemu size mismatch)
    % Sprawdzamy, dla jakiej liczby próbek (128, 256, 512) dane dzielą się całkowicie
    possible_samples = [256, 128, 512];
    detected_samples = 256; % Domyślne
    
    for s = possible_samples
        block = config.N_RX * s;
        chirps = length(data_complex) / block;
        if floor(chirps) == chirps && chirps > 0
            detected_samples = s;
            break;
        end
    end
    
    % 3. Obliczenie rzeczywistej liczby chirpów
    block_size = config.N_RX * detected_samples;
    total_chirps = floor(length(data_complex) / block_size);
    
    % Przycięcie nadmiarowych danych (jeśli plik jest uszkodzony na końcu)
    data_complex = data_complex(1 : total_chirps * block_size);
    
    % 4. Aktualizacja Configu
    config.updateFromData(detected_samples, total_chirps);
    
    % 5. Reshape do [Samples, RX, Chirps] -> Permute do [Chirps, RX, Samples]
    radar_cube = reshape(data_complex, detected_samples, config.N_RX, total_chirps);
    radar_cube = permute(radar_cube, [3, 2, 1]);
end