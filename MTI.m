function iqData_mti = MTI(iqDataRx1Tx1)
    % Aplikuje filtr MTI oraz korekcję DC Offsetu na surowych danych
    
    % 1. Korekcja DC (usunięcie błędu na 0 metrach)
    iqData_dc_corrected = iqDataRx1Tx1 - mean(iqDataRx1Tx1, 1);
    
    % 2. Filtr MTI (usunięcie statycznych odbić od ścian)
    static_clutter = mean(iqData_dc_corrected, 2); 
    iqData_mti = iqData_dc_corrected - static_clutter; 
end