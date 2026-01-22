%% GŁÓWNA FUNKCJA ANALIZY FMCW
% Funkcja main() do uruchamiania analizy radaru
% Data: 2026-01-21

function main()
    % GŁÓWNA FUNKCJA ANALIZY - WKLEJ I URUCHOM!
    
    fprintf('╔══════════════════════════════════════════════════════════════╗\n');
    fprintf('║           FMCW RADAR ANALYZER - MATLAB VERSION              ║\n');
    fprintf('║              Zaawansowana analiza IWR1443                    ║\n');
    fprintf('╚══════════════════════════════════════════════════════════════╝\n\n');
    
    % KONFIGURACJA - ZMIEŃ ŚCIEŻKĘ DO TWOICH DANYCH
    data_folder = '1_one_person_raw_fmcw_data-20250414T204939Z-004';
    
    % Sprawdź czy folder istnieje
    if ~isfolder(data_folder)
        fprintf('❌ BŁĄD: Folder z danymi nie istnieje!\n');
        fprintf('📁 Oczekiwana ścieżka: %s\n', fullfile(pwd, data_folder));
        fprintf('💡 Rozwiązanie: Umieść folder z danymi w bieżącym katalogu lub zmień ścieżkę.\n');
        return;
    end
    
    try
        % Inicjalizacja analizatora
        fprintf('🚀 Inicjalizacja analizatora...\n');
        analyzer = FMCWAnalyzer(data_folder);
        
        % Uruchomienie interaktywnej analizy
        fprintf('✅ Gotowy do analizy!\n\n');
        analyzer.runInteractiveAnalysis();
        
        fprintf('\n🎉 Analiza zakończona pomyślnie!\n');
        
    catch ME
        fprintf('❌ BŁĄD podczas analizy:\n');
        fprintf('Szczegóły: %s\n', ME.message);
        fprintf('\n📋 Sprawdź:\n');
        fprintf('  • Czy masz zainstalowane Signal Processing Toolbox\n');
        fprintf('  • Czy pliki .cf32 są w odpowiednim formacie\n');
        fprintf('  • Czy ścieżki są poprawne\n');
    end
end