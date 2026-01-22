classdef RadarConfig < handle
    properties
        % Parametry sprzętowe (IWR1443)
        FREQ_CENTER = 77e9;
        LAMBDA = 3e8 / 77e9;
        
        % Parametry ramki (DYNAMICZNE - aktualizowane przy wczytaniu)
        N_RX = 4;            
        N_TX = 3;            
        N_SAMPLES = 256;     
        N_CHIRPS = 128;      % Liczba chirpów na jedną antenę TX
        TOTAL_CHIRPS = 384;  % Całkowita liczba chirpów w pliku
        
        % Parametry fizyczne
        bandwidth = 4e9;     % Domyślne 4 GHz
        chirp_time = 60e-6;  % Domyślne 60 us
    end
    
    methods
        function updateFromData(obj, n_samples, total_chirps)
            % Aktualizuje wymiary na podstawie rzeczywistego pliku
            obj.N_SAMPLES = n_samples;
            obj.TOTAL_CHIRPS = total_chirps;
            obj.N_CHIRPS = total_chirps / obj.N_TX; 
        end
        
        function res = getRangeResolution(obj)
            res = 3e8 / (2 * obj.bandwidth);
        end
        
        function res = getVelocityResolution(obj)
            res = (obj.LAMBDA / (2 * obj.chirp_time * obj.N_TX)) / obj.N_CHIRPS;
        end
        
        function max_r = getMaxRange(obj)
            max_r = obj.getRangeResolution() * (obj.N_SAMPLES / 2);
        end
    end
end