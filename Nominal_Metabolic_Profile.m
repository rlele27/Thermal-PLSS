clear;
clc;
close all;

%% Import Data
filename = 'Metabolic.xlsx';
opts = spreadsheetImportOptions('NumVariables', 11);
opts.Sheet = 'Sheet1';
opts.DataRange = 'A4:K37';
opts.VariableNames = { ...
    'StartTime_hr', ...
    'EndTime_hr', ...
    'Duration_hr', ...
    'Activity', ...
    'MetabolicRate_kJ_hr', ...
    'SensibleHeat_kJ_hr', ...
    'LatentHeat_kJ_hr', ...
    'WaterVapor_g_min', ...
    'Sweat_g_min', ...
    'O2Consumption_g_min', ...
    'CO2Output_g_min'};
opts.VariableTypes = { ...
    'double', 'double', 'double', 'string', ...
    'double', 'double', 'double', 'double', ...
    'double', 'double', 'double'};
MetMan = readtable(filename, opts);
MetMan.Duration_hr = MetMan.EndTime_hr - MetMan.StartTime_hr;

filename = 'Raw_Nominal.csv';
opts = detectImportOptions(filename, 'ReadVariableNames', false);
opts.VariableNames = {'Time_min', 'MetabolicRate_Btu_hr'};
Nominal = readtable(filename, opts);



%% Data Manipulation
MetMan_Time_hours = MetMan.StartTime_hr;
MetMan_MetabolicRate_W = MetMan.MetabolicRate_kJ_hr / 3.6;
MetMan_SensibleHeat_W = MetMan.SensibleHeat_kJ_hr / 3.6;
MetMan_LatentHeat_W = MetMan.LatentHeat_kJ_hr / 3.6;

Nominal_Time_hours = Nominal.Time_min / 60;
Nominal_MetabolicRate_W = Nominal.MetabolicRate_Btu_hr / 3.412141633;

%% Graphing
figure;
stairs(MetMan_Time_hours, MetMan_MetabolicRate_W);
hold on;
plot(Nominal_Time_hours, Nominal_MetabolicRate_W);
title('Metabolic profiles');
legend('MetMan', 'Raw Nominal');
xlabel('Time (hours)');
ylabel('Metabolic Rate (W)');
ylim([0 1000]);
grid on;
hold off;
