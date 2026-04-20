function [target_found, target_r, target_v, target_r_idx, target_v_idx] = CFAR(power_matrix, cfar_obj, CUTIdx, r_grid, v_grid, max_range, min_power_db)
    % Wykonuje detekcję CFAR i zwraca współrzędne najsilniejszego celu.
    % Pozwala na dynamiczne definiowanie filtrów odległości i mocy dla różnych scenariuszy.
    
    % Ustawienia domyślne, jeśli nie przekazano limitów z zewnątrz
    if nargin < 6 || isempty(max_range), max_range = 5.0; end
    if nargin < 7 || isempty(min_power_db), min_power_db = 75; end
    
    target_found = false;
    target_r = 0; target_v = 0;
    target_r_idx = 1; target_v_idx = 1;
    
    % Uruchamiamy CFAR
    detections = cfar_obj(power_matrix, CUTIdx);
    det_indices = find(detections == 1);
    
    if ~isempty(det_indices)
        % Mapujemy indeksy na wiersze i kolumny
        det_rows = CUTIdx(1, det_indices);
        det_cols = CUTIdx(2, det_indices);
        
        % Pobieramy moce
        lin_indices = sub2ind(size(power_matrix), det_rows, det_cols);
        detected_powers = power_matrix(lin_indices);
        detected_powers_db = 10 * log10(detected_powers + 1e-6);
        
        % --- FILTRACJA DUCHÓW (Z użyciem argumentów z zewnątrz) ---
        ranges = r_grid(det_rows);
        
        % Porównujemy z parametrami przekazanymi do funkcji
        valid_range = ranges(:)' <= max_range; 
        valid_power = detected_powers_db(:)' >= min_power_db; 
        valid_targets = valid_range & valid_power;
        
        % Aplikacja masek
        det_rows = det_rows(valid_targets);
        det_cols = det_cols(valid_targets);
        detected_powers = detected_powers(:)'; 
        detected_powers = detected_powers(valid_targets);
        
        % Jeśli zostały jakieś prawowite cele, wybierz najsilniejszy
        if ~isempty(detected_powers)
            [~, max_idx] = max(detected_powers);
            target_r_idx = det_rows(max_idx);
            target_v_idx = det_cols(max_idx);
            target_r = r_grid(target_r_idx);
            target_v = v_grid(target_v_idx);
            target_found = true;
        end
    end
end