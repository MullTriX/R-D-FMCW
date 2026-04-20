%% FMCW RADAR IWR1443 ANALYZER - MATLAB VERSION (FIXED)
classdef FMCWAnalyzer < handle
    properties
        config;
        data_folder;
        scenarios;
    end
    
    methods
        function obj = FMCWAnalyzer(data_folder)
            obj.config = RadarConfig(); 
            obj.data_folder = data_folder;
            obj.scenarios = containers.Map();
            obj.scanScenarios();
            
            % Automatyczna estymacja parametrów
            obj.performAutoCalibration();
        end
        
        function performAutoCalibration(obj)
            scenario_names = keys(obj.scenarios);
            if isempty(scenario_names)
                fprintf('⚠️ Brak danych do automatycznej kalibracji\n');
                return;
            end
            
            % Wybierz pierwszy scenariusz do kalibracji
            files = obj.scenarios(scenario_names{1});
            radar_cube = obj.loadRadarData(files{1});
            
            % Spróbuj wyciągnąć oczekiwane wartości z nazwy (jeśli są)
            params = obj.parseFolderName(scenario_names{1});
            dist = obj.parseDistance(params);
            
            % Uruchom autokalibrację w Configu
            obj.config = obj.config.autoEstimateFromData(radar_cube, dist, []);
        end
        
        function scanScenarios(obj)
            if ~isfolder(obj.data_folder)
                error('Folder z danymi nie istnieje: %s', obj.data_folder);
            end
            
            subfolders = dir(fullfile(obj.data_folder, '*'));
            % Filtrowanie tylko folderów, ignorowanie . i ..
            subfolders = subfolders([subfolders.isdir] & ~ismember({subfolders.name}, {'.', '..'}));
            
            for i = 1:length(subfolders)
                folder_name = subfolders(i).name;
                folder_path = fullfile(obj.data_folder, folder_name);
                cf32_files = dir(fullfile(folder_path, '*.cf32'));
                
                if ~isempty(cf32_files)
                    file_paths = cell(length(cf32_files), 1);
                    for j = 1:length(cf32_files)
                        file_paths{j} = fullfile(folder_path, cf32_files(j).name);
                    end
                    obj.scenarios(folder_name) = file_paths;
                end
            end
        end
        
        function radar_cube = loadRadarData(obj, filepath)
            % Wczytywanie danych .cf32 z automatyczną detekcją wymiarów
            fid = fopen(filepath, 'rb');
            if fid == -1, error('Nie można otworzyć pliku: %s', filepath); end
            raw_data = fread(fid, inf, 'float32');
            fclose(fid);
            
            % Konwersja I/Q
            if mod(length(raw_data), 2) ~= 0, raw_data = raw_data(1:end-1); end
            complex_data = raw_data(1:2:end) + 1i * raw_data(2:2:end);
            
            n_rx = obj.config.N_RX; 
            
            % Zgadywanie liczby próbek (256, 128 lub 512)
            possible_samples = [256, 128, 512];
            detected_samples = 256; 
            valid_chirps = 0;
            
            for s = possible_samples
                block_size = n_rx * s;
                chirps = length(complex_data) / block_size;
                if floor(chirps) == chirps && chirps > 0
                    detected_samples = s;
                    valid_chirps = chirps;
                    break;
                end
            end
            
            if valid_chirps == 0
                detected_samples = 256;
                block_size = n_rx * detected_samples;
                valid_chirps = floor(length(complex_data) / block_size);
                complex_data = complex_data(1 : valid_chirps * block_size);
            end
            
            % Aktualizacja configu
            obj.config.updateFrameParams(detected_samples, valid_chirps);
            
            % Reshape: [Samples, RX, Chirps] -> [Chirps, RX, Samples]
            radar_cube = reshape(complex_data, detected_samples, n_rx, valid_chirps);
            radar_cube = permute(radar_cube, [3, 2, 1]); 
        end
        
        function [rd_map, velocity_axis] = generateRangeDopplerMap(obj, radar_cube, tx_idx, rx_idx)
            % Demultipleksacja TDM
            tx_data = radar_cube(tx_idx:obj.config.N_TX:end, :, :);
            if isempty(tx_data), error('Puste dane po demultipleksacji TX'); end
            
            adc_data = squeeze(tx_data(:, rx_idx, :));
            [n_chirps, n_samples] = size(adc_data);
            
            % Usuwanie DC
            adc_data = adc_data - mean(adc_data, 2);
            
            % --- 1. RANGE FFT ---
            range_win = blackman(n_samples); 
            range_win = range_win(:).'; % Wiersz [1 x Samples]
            
            % Dopasowanie wymiarów (broadcasting safe)
            if size(adc_data, 2) ~= length(range_win)
                adc_data = adc_data.';
            end
            % adc_data jest teraz [Chirps, Samples]
            
            range_fft = fft(adc_data .* range_win, n_samples * 2, 2);
            range_fft = range_fft(:, 1:n_samples); 
            
            % --- 2. DOPPLER FFT ---
            doppler_win = blackman(n_chirps); % Kolumna [Chirps x 1]
            
            % Upewnij się, że range_fft ma Chirpy w wierszach (dim 1)
            if size(range_fft, 1) ~= length(doppler_win)
                range_fft = range_fft.'; 
            end
            
            doppler_fft = fft(range_fft .* doppler_win, n_chirps * 2, 1);
            doppler_fft = fftshift(doppler_fft, 1);
            
            % Transpozycja wyniku dla wykresu: [Range (Samples), Velocity (Chirps)]
            doppler_fft = doppler_fft.'; 
            
            % --- POPRAWKA: Obliczanie osi ---
            % Oś prędkości (wymiar 2 po transpozycji)
            n_vel_bins = size(doppler_fft, 2);
            vel_res = (obj.config.LAMBDA / (2 * obj.config.chirp_time * obj.config.N_TX)) / n_vel_bins;
            
            % Przypisanie do poprawnej zmiennej wyjściowej (velocity_axis zamiast vel_axis)
            velocity_axis = ((-n_vel_bins/2) : (n_vel_bins/2 - 1)) * vel_res;
            
            rd_map = 20 * log10(abs(doppler_fft) + 1e-9);
        end
        
        function [ra_map, angle_axis] = generateRangeAngleMap(obj, radar_cube, tx_idx)
            % Pobranie danych dla wybranego TX
            tx_data = radar_cube(tx_idx:obj.config.N_TX:end, :, :);
            
            % Uśrednianie po chirpach (Non-Coherent lub Coherent)
            averaged_data = squeeze(mean(tx_data, 1));
            
            [dim1, dim2] = size(averaged_data);
            
            % Oczekujemy [RX, Samples]. Jeśli jest [Samples, RX], obróć.
            n_rx = obj.config.N_RX;
            if dim1 ~= n_rx && dim2 == n_rx
                 averaged_data = averaged_data.';
                 [dim1, dim2] = size(averaged_data);
            end
            n_samples = dim2;
            
            % --- RANGE FFT ---
            range_win = blackman(n_samples).'; % Wiersz
            
            range_fft = fft(averaged_data .* range_win, n_samples * 2, 2);
            range_fft = range_fft(:, 1:n_samples);
            
            % --- ANGLE FFT ---
            angle_win = hamming(n_rx); % Kolumna
            
            angle_fft_size = 128;
            angle_fft = fft(range_fft .* angle_win, angle_fft_size, 1);
            angle_fft = fftshift(angle_fft, 1);
            
            angle_step = 180 / angle_fft_size; 
            angle_axis = -90 : angle_step : (90 - angle_step);
            
            ra_map = 20 * log10(abs(angle_fft).' + 1e-9); % Transpozycja na koniec: [Range, Angle]
        end
        
        function [corrected_config, cal_info] = calibrateRange(obj, radar_cube, expected_distance, scenario_name)
            fprintf('🔍 Kalibracja dla: %s\n', scenario_name);
            
            % Bierzemy dane z TX1
            tx_data = radar_cube(1:obj.config.N_TX:end, :, :);
            
            % Uśredniamy wszystko do jednego wektora zasięgu
            averaged_data = squeeze(mean(mean(tx_data, 1), 2));
            
            n_samples = length(averaged_data);
            range_win = blackman(n_samples);
            
            % Bezpieczne wektory kolumnowe
            averaged_data = averaged_data(:);
            range_win = range_win(:);
            
            range_fft = fft(averaged_data .* range_win, n_samples * 4);
            range_profile = abs(range_fft(1:end/2));
            
            % Oś zasięgu
            range_res = obj.config.range_resolution / 4; 
            range_axis = (0:(length(range_profile)-1)) * range_res;
            
            % Znajdź piki
            [peaks, locs] = findpeaks(range_profile, 'SortStr', 'descend');
            
            if isempty(locs)
                detected_ranges = [0];
            else
                detected_ranges = range_axis(locs);
            end
            
            if ~isempty(expected_distance)
                fprintf('   Oczekiwane: %.2fm, Wykryte (top): %.2fm\n', expected_distance, detected_ranges(1));
            end
            
            corrected_config = obj.config;
            cal_info = struct('corrected', false, 'range_profile', range_profile, ...
                              'range_axis', range_axis, 'detected_ranges', detected_ranges);
        end
        
        % Funkcje pomocnicze
        function runInteractiveAnalysis(obj)
            fprintf('Dostępne scenariusze: %d\n', obj.scenarios.Count);
            scenarios = keys(obj.scenarios);
            if ~isempty(scenarios)
                obj.analyzeScenario(scenarios{1}); 
            end
        end
        
        function analyzeScenario(obj, name, multi_frame)
            if nargin < 3, multi_frame = false; end
            files = obj.scenarios(name);
            data = obj.loadRadarData(files{1});
            
            params = obj.parseFolderName(name);
            dist = obj.parseDistance(params);
            
            [~, cal_info] = obj.calibrateRange(data, dist, name);
            [rd, v_ax] = obj.generateRangeDopplerMap(data, 1, 1);
            [ra, a_ax] = obj.generateRangeAngleMap(data, 1);
            
            obj.plotResults(name, params, rd, rd, ra, ra, v_ax, a_ax, cal_info, dist, []);
        end
        
        function plotResults(obj, name, params, rd1, rd2, ra1, ra2, v_ax, a_ax, cal, dist, angle)
            figure('Name', name, 'Position', [100, 100, 1200, 800]);
            sgtitle(name, 'Interpreter', 'none');
            
            % Range-Doppler
            subplot(2,2,1);
            % Sprawdzenie wymiarów osi vs dane
            if length(v_ax) ~= size(rd1, 2)
                 % Jeśli coś się nie zgadza, generuj nową oś na szybko dla wyświetlenia
                 v_ax = linspace(min(v_ax), max(v_ax), size(rd1, 2));
            end
            
            imagesc(v_ax, linspace(0, obj.config.max_range, size(rd1,1)), rd1);
            axis xy; title('Range-Doppler'); xlabel('V [m/s]'); ylabel('Range [m]');
            colorbar;
            
            % Range Profile
            subplot(2,2,2);
            plot(cal.range_axis, cal.range_profile); 
            title('Range Profile'); grid on; xlabel('Range [m]');
            xlim([0, obj.config.max_range]);
            
            % Range-Angle
            subplot(2,2,3);
            imagesc(a_ax, linspace(0, obj.config.max_range, size(ra1,1)), ra1);
            axis xy; title('Range-Angle'); xlabel('Angle [deg]'); ylabel('Range [m]');
            colorbar;
            
            drawnow;
        end
        
        function params = parseFolderName(~, name), params = struct(); end
        function d = parseDistance(~, ~), d = []; end
    end
end