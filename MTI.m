function data_mti = MTI(dataRaw)
    % Aplikuje filtr MTI oraz korekcję DC Offsetu.
    % Działa zarówno dla macierzy 2D (Offline, 1 Antena) jak i 3D (Live, N Anten).
    
    % 1. Korekcja DC (usunięcie błędu sprzętowego ADC wzdłuż 1. wymiaru - próbek)
    data_dc = dataRaw - mean(dataRaw, 1);
    
    % 2. Filtr MTI (usunięcie statycznych odbić od ścian)
    % ndims automatycznie zwraca 2 dla offline i 3 dla live. 
    % Chirpy zawsze są w ostatnim wymiarze.
    dim_chirps = ndims(dataRaw); 
    static_clutter = mean(data_dc, dim_chirps); 
    
    % Odejmujemy tło od całego sygnału
    data_mti = data_dc - static_clutter; 
end