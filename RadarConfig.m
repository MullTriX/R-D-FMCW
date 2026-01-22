%% KONFIGURACJA RADARU IWR1443 - WERSJA DYNAMICZNA
classdef RadarConfig < handle
    properties (Constant)
        % Parametry sprzętowe stałe dla IWR1443
        FREQ_CENTER = 77e9;
        LAMBDA = 3e8 / 77e9;
        ANTENNA_SPACING = (3e8 / 77e9) / 2;
        
        % Domyślne wartości startowe (jeśli estymacja zawiedzie)
        BANDWIDTH_INITIAL = 4e9;
        CHIRP_TIME_INITIAL = 60e-6;
    end
    
    properties
        % Parametry DYNAMICZNE (mogą się zmieniać dla każdego pliku)
        N_RX = 4;            % Liczba odbiorników (zazwyczaj 4)
        N_TX = 3;            % Liczba nadajników (zazwyczaj 3 dla MIMO)
        N_ADC_SAMPLES = 256; % Próbki ADC (może być 128, 256, 512)
        TOTAL_CHIRPS = 256;  % Liczba chirpów w pliku (zmienna!)
        
        % Parametry fizyczne (wyliczane)
        bandwidth;
        chirp_time;
        range_resolution;
        max_range;
        prf;
        frame_period;
    end
    
    methods
        function obj = RadarConfig()
            % Inicjalizacja domyślna
            obj.bandwidth = obj.BANDWIDTH_INITIAL;
            obj.chirp_time = obj.CHIRP_TIME_INITIAL;
            obj.updateParameters();
        end
        
        function updateFrameParams(obj, n_samples, total_chirps)
            % Aktualizacja wymiarów ramki na podstawie wczytanego pliku
            if nargin > 1
                obj.N_ADC_SAMPLES = n_samples;
                obj.TOTAL_CHIRPS = total_chirps;
                
                % Przeliczenie parametrów zależnych
                obj.updateParameters();
            end
        end
        
        function obj = autoEstimateFromData(obj, radar_cube, expected_ranges, expected_angles)
            % Prosta estymacja pasma na podstawie pików
             obj.bandwidth = obj.estimateBandwidth(radar_cube, expected_ranges);
             obj.chirp_time = obj.estimateChirpTime(radar_cube);
             obj.updateParameters();
        end
        
        function bandwidth = estimateBandwidth(obj, radar_cube, expected_ranges)
             bandwidth = obj.BANDWIDTH_INITIAL; % Domyślnie
             % Tu można dodać logikę estymacji, na razie zostawiamy domyślną
        end

        function chirp_time = estimateChirpTime(obj, radar_cube)
             chirps_per_tx = size(radar_cube, 1) / obj.N_TX;
             if chirps_per_tx > 100
                chirp_time = 30e-6;
             elseif chirps_per_tx > 50
                chirp_time = 60e-6;
             else
                chirp_time = 100e-6;
             end
        end
        
        function updateParameters(obj)
            % Aktualizacja parametrów fizycznych
            obj.range_resolution = 3e8 / (2 * obj.bandwidth);
            obj.max_range = obj.range_resolution * (obj.N_ADC_SAMPLES / 2);
            
            if obj.N_TX > 0 && obj.chirp_time > 0
                obj.prf = 1 / (obj.N_TX * obj.chirp_time);
                obj.frame_period = obj.TOTAL_CHIRPS * obj.chirp_time;
            end
        end
        
        function displayConfig(obj)
            fprintf('=== KONFIGURACJA RADARU ===\n');
            fprintf('Wymiary danych: [%d próbek x %d chirpów x %d RX]\n', ...
                obj.N_ADC_SAMPLES, obj.TOTAL_CHIRPS, obj.N_RX);
            fprintf('Rozdzielczość: %.3f m, Max zasięg: %.1f m\n', ...
                obj.range_resolution, obj.max_range);
        end
    end
end