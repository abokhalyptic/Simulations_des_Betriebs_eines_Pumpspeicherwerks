% Pfad und Dateien manuell eingeben
% Wenn file_paths oder file_extensions leer sind werden diese durch
% Standard-Werte ergaenzt
file_paths      = "";
file_names      = ["Datensatz_1", "Datensatz_2", "Datensatz_3", "Datensatz_4"];
file_extensions = "";

% Bedingungen fuer falsche Daten festlegen
frequency_condition = @(frequency) isnan(frequency) | frequency < 45 | frequency > 55;
intraday_condition  = @(price) isnan(price);

% Erstelle vollen string aus Dateipfad, Dateiname und Dateiendung;
% vervollstaendige unvollstaendige Eingaben
full_file_paths = generate_file_paths(file_paths, file_names, file_extensions);

% Datenstruct erstellen
data = struct;

% Gehe alle Dateien der Reihe nach durch und wende das Program an die Daten
% an
for f=1:length(file_names)
    % Extrahiere Frequenz und Intraday Price aus dem Datensatz
    [frequency , intraday_price] = read_file(full_file_paths(f));
    % Speicher Laenge von Datensatz
    array_length = length(frequency);
    
    % Speicher alle Daten
    data.(file_names(f)).frequency      = frequency;
    data.(file_names(f)).intraday_price = intraday_price;
    
    % Frequenz und intraday price korrigieren
    frequency      = correct_data(frequency,     frequency_condition);
    intraday_price = correct_data(intraday_price, intraday_condition);
    
    % Glaettung der Frequenz
    smoothed_frequency = smoothdata(frequency, 'movmedian','SmoothingFactor',0.7);
    
    % Maxima / Minima von geglaetteten Daten bestimmen
    [max_mask , min_mask] = extrema(smoothed_frequency);
    
    
    % Speicher korrigierte Daten
    data.(file_names(f)).corrected_frequency      = frequency;
    data.(file_names(f)).corrected_intraday_price = intraday_price;
    
    % Speicher geglaettete Frequenz
    data.(file_names(f)).smoothed_frequency = smoothed_frequency;
    
    % Maxima / Minima speichern
    data.(file_names(f)).max_mask = max_mask;
    data.(file_names(f)).min_mask = min_mask;
    
    
    % Alles plotten wie in fig 2
    %plot_frequency(frequency, smoothed_frequency, max_mask, min_mask, file_names(f));


    % Erstelle arrays fuer die Fuellstaende und den Kontostand
    fill_level_upper_basin = zeros(array_length,1);
    fill_level_lower_basin = zeros(array_length,1);
    account_balance = zeros(array_length,1);
    
    % Initialisiere Fuellstaende
    fill_level_upper_basin(1) = 250E3;
    fill_level_lower_basin(1) = 150E3;

   
    % plotte alles nach fig 3
    %plot_status(fill_level_upper_basin, fill_level_lower_basin, ...
    %          frequency, intraday_price, ... 
    %          account_balance, file_names(f));

                
    % bestimme fuer alle Frequenz/Intraday-Preispaare ob Pumpe oder Turbine
    % verwendet werden soll und aktualisiere Kontostand entsprechend
    for k=1:array_length-1
        % bestimme um wie viel sich der Fuellstand des unteren Beckens
        % aendert
        filling_change_lower = calculate_filling_change_lower(fill_level_upper_basin(k), ...
                                               fill_level_lower_basin(k), ...
                                               intraday_price(k));
                              
        % Berechne Gewinn / Kosten fuer das aktuelle Frequenz/Intraday-Preispaar
        account_change = calculate_earnings(filling_change_lower, ...
                                  frequency(k), intraday_price(k), ...
                                  max_mask(k), min_mask(k));
        
        
        % Aktualisiere Fuellstand der Becken fuer den naechsten Schritt
        fill_level_lower_basin(k+1) = fill_level_lower_basin(k) + filling_change_lower;
        fill_level_upper_basin(k+1) = fill_level_upper_basin(k) - filling_change_lower;
        
        % Aktualisiere Kontostand
        account_balance(k+1) = account_balance(k) + account_change;
    end

    % Speicher Ergebnisse in struct
    data.(file_names(f)).fill_level_upper_basin = fill_level_upper_basin ;
    data.(file_names(f)).fill_level_lower_basin = fill_level_lower_basin ;
    data.(file_names(f)).account_balance        = account_balance;
    
    
    % plotte alles nach fig 4
    %plot_status(fill_level_upper_basin, fill_level_lower_basin, ...
    %          frequency, intraday_price, ...
    %          account_balance, ...
    %          file_names(f));

end









%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%  FUNKTIONEN  %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

% Bestimme die Gewinne/Kosten des Turbinen-/Pumpenbetriebs fuer das
% aktuelle Frequenz/Intraday-Preispaar
function winnings = calculate_earnings(filling_level_change_lower, frequency, intraday_price, is_max, is_min)
    % Kosten und Gewinn durch das Pumpen des Wassers
    % 1000 m^3 <-> 1MWh, zum aktuellen intraday Preis gehandelt
    winnings = filling_level_change_lower * intraday_price / 1000;
    
    % Bonus fuer Entnahme von Strom bei hoher Netzfrequenz (lokalem
    % Frequenzmaxima)
    if(filling_level_change_lower < 0 && frequency > 50 && is_max)
        winnings = winnings + 50;
        return;
    end
    
    % Bonus fuer Stromversorgung bei niedriger Netzfrequenz (lokalem
    % Frequenzminima)
    if(filling_level_change_lower > 0 && frequency < 50 && is_min)
        winnings = winnings + 50;
        return;
    end
end

% Bestimme die Aenderung des Fuellstandes des niedrigeren Beckens anhand
% des aktuellen Intraday-Preises sowie der minimalen
% Fuellstaende
% Gibt entweder -1000, 0, +1000 zurueck
function filling_change_lower = calculate_filling_change_lower(fill_level_upper_basin, fill_level_lower_basin, intraday_price)
    % Bei Betrieb der Turbine/Pumpe werden 1000m^3 Wasser pro MWh bewegt
    water_delta  = 1000;
    % Der Minimale Fuellstand betraegt 50.000 m^3
    minimum_fill_level_basin = 50E3;
    
    % Bestimme ob Wasser vom oberen in das untere Becken fliesst
    if(intraday_price > 40 && fill_level_upper_basin > minimum_fill_level_basin)
        filling_change_lower = + water_delta;
        return;
    end
    
    % Bestimme ob Wasser vom unteren in das obere Becken gepumpt wird
    if(intraday_price < 10 && fill_level_lower_basin > minimum_fill_level_basin)
        filling_change_lower = - water_delta;
        return;
    end
    
    % Sonst veraendert sich der Fuellstand der Becken nicht
    filling_change_lower = 0;
    return
end


% Erstelle Abbildung nach fig. 3, 4 in Aufgabenbeschreibung
% Verlauf von Fuellstand, Frequenz, Intraday Price und Kontostand
% aktueller Fuellstand des oberen und unteren Beckens
function plot_status(fill_level_upper_basin, fill_level_lower_basin, ...
                     frequency, intraday_price, account_balance, figure_title)
    % Farbcode von "Matlab Blau"
    mat_blue = [0 0.4470 0.7410];
    
    % Definiere Grenzen fuer die subplots
    time_limits    = [0 length(frequency)];
    basin_limits   = [0 4E5];
    account_limits = [0 Inf];
    
    % Erstelle Fenster fuer die figure
    figure('Name',figure_title,'NumberTitle','off');
    set(gcf, 'Position',  [100, 100, 1300, 600])
    
    % Erstelle subplot fuer den Fuellstandverlauf
    subplot(2,4,[1,5]);
    hold on
    plot(fill_level_lower_basin,'Color',mat_blue);
    plot(fill_level_upper_basin,'r');
    xlim(time_limits);
    ylim(basin_limits);
    legend("Unteres Becken", "Oberes Becken");
    title("Fuellstand Verlauf");
    ylabel("m^3");
    grid on;
    
    % Erstelle subplot fuer das obere Becken
    subplot(2,4,2);
    % Zeige letzten Fuellstand an der nicht-Null ist (da das Becken nicht
    % komplett geleert werden kann)
    last_nonzero = find(fill_level_upper_basin,1,'last');
    area([0 1], [fill_level_upper_basin(last_nonzero) fill_level_upper_basin(last_nonzero)],'LineStyle','none');
    xlim([0 1]);
    ylim(basin_limits);
    title("Oberes Becken");
    ylabel("m^3");
    set(gca,'xtick',[])
    yline(50E3,'r--','Min limit','Linewidth',3);
    
    % Erstelle subplot fuer das obere Becken
    subplot(2,4,6);
    % Zeige letzten Fuellstand an der nicht-Null ist (da das Becken nicht
    % komplett geleert werden kann)
    area([0 1], [fill_level_lower_basin(last_nonzero) fill_level_lower_basin(last_nonzero)],'LineStyle','none');
    xlim([0 1]);
    ylim(basin_limits);
    title("Unteres Becken");
    ylabel("m^3");
    set(gca,'xtick',[])
    yline(50E3,'r--','Min limit','Linewidth',3);
    
    
    % Erstelle subplot fuer die Frequenz
    subplot(2,4,3);
    plot(frequency);
    xlim(time_limits);
    title("Frequenz");
    ylabel("Frequenz, Hz");
    xlabel("Zeit");
    grid on;
    
    % Erstelle subplot fuer den Intraday-Price
    subplot(2,4,4);
    plot(intraday_price);
    xlim(time_limits);
    title("Intraday Price");
    ylabel("Euro");
    xlabel("Zeit");
    grid on;
    
    % Erstelle subplot fuer den Kontostandverlauf
    subplot(2,4,[7,8]);
    plot(account_balance / 1000);
    xlim(time_limits);
    ylim(account_limits);
    title("Kontostand");
    ylabel("Geld [1000€]");
    xlabel("Zeit");
    grid on;
    
    % Oeffne Fenster mit figure
    shg
end


% Erstelle Abbildung nach fig. 2 in Aufgabenbeschreibung
% Verlauf von Frequenz gegen geglaettete Frequenz
% Lokale Maxima und Minima der geglaetteten Frequenz
function plot_frequency(frequency, smoothed_frequency, max_mask, min_mask, frequency_title)
    % Erstelle Fenster fuer die figure
    figure();
    % Erstelle subplot fuer die Frequenz gegen geglaettete Frequenz
    subplot(1,2,1);
    hold on;
    plot(frequency,"-b","LineWidth",0.5);
    plot(smoothed_frequency,"-r","LineWidth",2);
    legend("Input data","Smoothed data");
    title(frequency_title, 'Interpreter', 'none');
    
    % Erstelle subplot fuer die Extrema der geglaetteten Frequenz
    subplot(1,2,2);
    hold on;
    plot(smoothed_frequency,"-b","LineWidth",0.5);
    indices = 1:length(smoothed_frequency);
    scatter(indices(max_mask), smoothed_frequency(max_mask),25,"^r","filled");
    scatter(indices(min_mask), smoothed_frequency(min_mask),25,"vy","filled");
    title(["Number of extrema: ", num2str(sum(max_mask) + sum(min_mask))]);
    legend("Input data", "Local maxima", "Local minima");
    
    % Oeffne Fenster mit figure
    shg
end


% Erstelle Maske fuer die lokalen Maxima und Minima der gegebenen Frequenz
% Beispiel: max_mask = [0,0,0,1,0,0,1,0] fuer Maxima an Index 4 und 7
function [max_mask, min_mask] = extrema(frequency)
    max_mask = islocalmax(frequency);
    min_mask = islocalmin(frequency);
end

% Liest die gegebene Datei ein und extrahiert Frequenz und Intraday-Preis
function [frequency, intraday_price] = read_file(filename)
    % Oeffne die Datei mit verschiedenen Methoden abhaengig von dem
    % Dateiformat
	[~,~,ext] = fileparts(filename);
    if(ext == ".mat")
        % hier matlab Datei einlesen
        file = load(filename);
        frequency = file.data.frequency;
        intraday_price = file.data.intraday_price;
        return
    end
    if(ext == ".csv")
        % hier .csv Datei einlesen
        file = readmatrix(filename);
        frequency = file(:,1);
        intraday_price = file(:,2);
        return
    end
    if(ext == ".json")
        % hier .json Datei einlesen
        text = fileread(filename);
        values = jsondecode(text);
        frequency = values.frequency;
        intraday_price = values.intraday_price;
        return
    end
end

% Pruefe Daten nach Bedingung, ersetze fehlerhafte Werte mit dem
% arithmetischen Mittel der ersten nicht-fehlerhaften Werte die links und
% rechts von dem fehlerhaften Wert sind
function corrected_data = correct_data(data, condition)
    corrected_data = data;
    
    % Ueberpruefe den ersten Wert und ersetze den (falls fehlerhaft) durch
    % den ersten nicht-fehlerhaften Wert
    if(condition(data(1)))
        k = 2;
        while(condition(data(k)))
            k = k+1;
        end
        corrected_data(1) = data(k);
    end
    % Ueberpruefe den letzten Wert und ersetze den (falls fehlerhaft) durch
    % den letzten nicht-fehlerhaften Wert
    if(condition(data(end)))
        k = size(data,1)-1;
        while(condition(data(k)))
            k = k-1;
        end
        corrected_data(end) = data(k);
    end
    
    % Maske mit fehlerhaften Werten
    mask = condition(corrected_data);
    % Indexe der fehlerhaften Werte
    indx = find(mask);
    % Bestimme Indexe der naechsten Nachbarn von fehlerhaften Werten, die
    % nicht selbst fehlerhaft sind
    [correct_left_indx, correct_right_indx] = correct_data_index(mask, indx);
    
    % Ersetze fehlerhafte Werte durch das arithmetische Mittel der
    % naechsten nicht-fehlerhaften Werte
    corrected_data(indx) = (data(correct_left_indx) + data(correct_right_indx))/2;
    return
end

% Hilfsfunktion von correct_data(data, condition)
% Findet naechste benachbarte Indexe von fehlerhaften Werten die nicht
% fehlerhaft sind
function [left_indices, right_indices] = correct_data_index(mask, indices)
    % Anzahl der zu durchsuchenden Werte
    array_length = length(mask);
    % Anzahl als fehlerhaft markierten Werte
    index_length = length(indices);
    % Indexe der naechsten nicht-fehlerhaften Werte
    left_indices  = zeros(index_length,1);
    right_indices = zeros(index_length,1);
    
    % Fuer jeden fehlerhaften Wert...
    for i = 1:index_length
        left_index = indices(i)-1;
        right_index = indices(i)+1;
        % Diese Schleifen werden nur dann ausgefuehrt wenn zwei fehlerhafte
        % Werte nebeneinander sind, gehe so viele Indexe nach links
        % (rechts) bis ein nicht-fehlerhafter Wert gefunden ist oder die
        % Grenzen der Werteliste erreicht sind
        while(left_index > 1 && mask(left_index) == 1)
            left_index = left_index - 1;
        end
        while(right_index < array_length && mask(right_index) == 1)
            right_index = right_index + 1;
        end
        
        left_indices(i)  = left_index;
        right_indices(i) = right_index;
    end
    return
end

% Fuehrt Aneinanderkettung der strings durch, falls kein Pfad oder kein
% Dateiformat gegeben ist, benutze Standards
function full_file_paths = generate_file_paths(file_paths, file_names, file_extensions)
    % Valide Dateiformate
    extensions = [".csv", ".json", ".mat"];

    % Anzahl gegebener Dateien
    file_count = length(file_names);
    
    % dynamisch den Ordner des Programms als Stammpfad aller Dateien nehmen
    % falls keiner gegeben ist
    if(file_paths == "")
        [program_path, ~, ~] = fileparts(matlab.desktop.editor.getActiveFilename);
        file_paths = strings(file_count,1);
        for f = 1:file_count
            file_paths(f) = program_path + "\Datensatz";
        end
    end

    % dynamisch ein zufaelliges valides Dateiformat waehlen falls keins 
    % gegeben ist (nimmt an dass alle Dateien in allen Dateiformaten 
    % vorhanden sind)
    if(file_extensions == "")
        file_extensions = strings(file_count,1);
        % Waehle beliebiges Dateiformat aus den vorgegebenen
        for f = 1:file_count
            file_extensions(f) = extensions(1 + mod(f,3));
        end
    end
    
    % Baue vollen Dateipfad aus dem Pfad der Datei, dem Dateinamen und des
    % Dateiformats
    full_file_paths = strings(file_count,1);
    for f = 1:file_count
        full_file_paths(f) = file_paths(f) + '\' + file_names(f) + file_extensions(f);
    end
end