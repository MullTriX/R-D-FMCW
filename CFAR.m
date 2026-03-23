function [target_found, target_r, target_v] = CFAR(power_matrix, cfar_obj, CUTIdx, r_grid, v_grid)
    % Wykonuje detekcję CFAR i zwraca współrzędne najsilniejszego celu
    
    target_found = false;
    target_r = 0;
    target_v = 0;
    
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
        
        % --- ROZWIĄZANIE BŁĘDU (Wymuszanie wektorów poziomych) ---
        ranges = r_grid(det_rows);
        
        % Gwarantujemy, że zmienne logiczne to płaskie wektory 1D
        valid_range = ranges(:)' <= 2.5; 
        valid_power = detected_powers_db(:)' >= 85; 
        
        % Teraz operator '&' poprawnie porówna element po elemencie
        valid_targets = valid_range & valid_power;
        % ----------------------------------------------------------
        
        % Aplikacja masek
        det_rows = det_rows(valid_targets);
        det_cols = det_cols(valid_targets);
        
        % Wymuszamy poziom również na mocach, żeby indeksowanie zadziałało
        detected_powers = detected_powers(:)'; 
        detected_powers = detected_powers(valid_targets);
        
        % Jeśli zostały jakieś prawowite cele, wybierz najsilniejszy
        if ~isempty(detected_powers)
            [~, max_idx] = max(detected_powers);
            target_r = r_grid(det_rows(max_idx));
            target_v = v_grid(det_cols(max_idx));
            target_found = true;
        end
    end
end