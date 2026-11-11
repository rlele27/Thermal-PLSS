function plotBodyHeatBalance(BodyHeatHistory,Inputs,CaseName,FigureNumber)
% PLOTBODYHEATBALANCE Display one case's physical power and stored-heat history.
% Inputs: saved histories/settings, case label and ordered figure number.
% Outputs: None. Units: W, kJ/kg, hours. Side effects: Creates the specified figure.
figure(FigureNumber); clf;
set(gcf,'Name',sprintf('%d. %s EVA Body Heat Balance',FigureNumber,CaseName), ...
    'NumberTitle','off');
    H = BodyHeatHistory(BodyHeatHistory.Case == CaseName, :);
    % Original physiological results only; output-load FOS does not apply here.
    OtherCooling_W = sum(H{:, {'Convection_W', ...
        'SkinEvaporation_W','RespSensible_W','RespLatent_W'}}, 2);
    StorageDuration_s = (H.EndTime_min-H.StartTime_min)*60;
    CumulativeStorage_kJ_kg = [0; cumsum(H.Storage_W.*StorageDuration_s)] ...
        / (1000*Inputs.Body.Weight_kg);
    StorageTime_hr = [H.StartTime_min(1);H.EndTime_min]/60;
    tiledlayout(2, 1, 'TileSpacing', 'compact');
    nexttile;
    plot(H.EndTime_min/60, [H.Metabolic_W, H.LCG_W, H.Radiation_W, OtherCooling_W], 'LineWidth', 1.5);
    ylabel('Power (W)'); grid on;
    title('Heat Production and Removal');
    legend('Qgen', 'LCG cooling', 'Radiation to suit interior', 'Other cooling combined', ...
        'Location', 'northoutside', 'Orientation', 'horizontal');
    nexttile;
    plot(StorageTime_hr,CumulativeStorage_kJ_kg, 'Color', [0.6,0.2,0.6], ...
        'LineWidth',1.5,'DisplayName','Accumulated heat'); hold on;
    yline(Inputs.HeatStorageScreeningLimit_kJ_kg,'r--', ...
        'DisplayName',sprintf('Nominal screening reference: %.1f kJ/kg',Inputs.HeatStorageScreeningLimit_kJ_kg));
    yline(Inputs.Environment.LCG.Controller.TargetStoredHeat_kJ_kg,'--', ...
        'Color',[.4,.6,.4],'DisplayName','Control target');
    yline(0,':','HandleVisibility','off');
    [PeakStorage_kJ_kg,PeakStorageIndex] = max(CumulativeStorage_kJ_kg);
    plot(StorageTime_hr(PeakStorageIndex),PeakStorage_kJ_kg,'ro', ...
        'MarkerFaceColor','r','DisplayName',sprintf('Peak: %.2f kJ/kg',PeakStorage_kJ_kg));
    hold off;
    title('Accumulated since EVA Start: JOS-3 Screening Comparison');
    xlabel('EVA time (hours)'); ylabel('Stored heat (kJ/kg)'); grid on;
    legend('Location','northwest');
    sgtitle(CaseName+" EVA Body Heat Balance");
end
