%% Nominal Metabolic Profile (NMP) & Regulated Blow Down Model (RBDM)

clear;
clc;
close all;

%% Import Data
dataFolder = fileparts(mfilename('fullpath'));
filename = fullfile(dataFolder, 'Metabolic.xlsx');
opts = spreadsheetImportOptions('NumVariables', 11);
opts.Sheet = 'Sheet1';
opts.DataRange = 'A4:K36';
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

filename = fullfile(dataFolder, 'Raw_Nominal.csv');
opts = detectImportOptions(filename, 'ReadVariableNames', true);
opts.VariableNames = {'Time_min', 'MetabolicRate_Btu_hr', 'Activity'};
opts = setvartype(opts, 'Activity', 'string');
Nominal = readtable(filename, opts);

% Rates from lookup using its Activity mapping.
Nominal.MetMan_Mapped_Metabolic_rate_kJ_hr = mapMetabolicRates(Nominal.Activity, MetMan);

%% Data Manipulation
MetMan_Time_hours = MetMan.StartTime_hr;
MetMan_MetabolicRate_W = MetMan.MetabolicRate_kJ_hr / 3.6;

Nominal_Time_hours = Nominal.Time_min / 60;
Nominal_MetabolicRate_W = Nominal.MetabolicRate_Btu_hr / 3.412141633;
Mapped_MetabolicRate_W = Nominal.MetMan_Mapped_Metabolic_rate_kJ_hr / 3.6;

%% Constants
FOS = 1.1;
G_Earth = 1;
G_Mars = 0.38;
v_walking = 1; %walking speed (m/s)
M_dot_base = 100; %sedentary metabolic rate (W)
M_dot_activity_earth = Mapped_MetabolicRate_W - M_dot_base; %differential above M_dot_base (W)

%% Martian Metabolic Rate Conversion
C_w_E = 3.531 - 3.374 * v_walking + 1.535 * v_walking^2 + 0.557 * G_Earth;
C_w_M = 3.531 - 3.374 * v_walking + 1.535 * v_walking^2 + 0.557 * G_Mars;
K_g = C_w_M / C_w_E;    
M_dot_mars = M_dot_base + K_g * M_dot_activity_earth;
M_dot_mars = M_dot_mars * FOS;

%% Oxygen Consumption on Mars
% Approximate conversion calibrated to Metabolic.xlsx O2 consumption data.
% 0.0042 g/min/W converts metabolic power (W) to O2 demand (g/min).
% Mars metabolic power already includes the factor of safety.
O2_per_W = 0.0042; % (g/min)/W
O2_mars_g_min = M_dot_mars * O2_per_W;

%% Totals/Calculations
Mars_Duration_hr = Nominal_Time_hours(end) - Nominal_Time_hours(1);
Mars_TotalEnergy_Wh = trapz(Nominal_Time_hours, M_dot_mars);
Mars_AverageRate_W = Mars_TotalEnergy_Wh / Mars_Duration_hr;
Mars_AverageO2_g_min = Mars_AverageRate_W * O2_per_W;
Mars_TotalO2_g = Mars_TotalEnergy_Wh * 60 * O2_per_W;

Mars_Summary = table(Mars_Duration_hr, Mars_AverageRate_W, ...
    Mars_AverageO2_g_min, Mars_TotalO2_g, ...
    'VariableNames', {'Duration_hr', 'AverageRate_W', ...
    'AverageO2_g_min', 'TotalO2_g'});
disp('Final Mars-adjusted profile (including FOS):');
disp(Mars_Summary);
fprintf('Average Mars O2 Consumption Rate: %.3f g/min\n', Mars_AverageO2_g_min);

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

figure;
plot(Nominal_Time_hours, M_dot_mars);
title('Nominal Profile Mapped MetMan, Mars Adjusted');
xlabel('Time (hours)');
ylabel('Metabolic Rate (W)');
grid on;

figure;
plot(Nominal_Time_hours, O2_mars_g_min, 'LineWidth', 1.5);
title('Mars Astronaut O2 Consumption (Including FOS)');
xlabel('Time (hours)');
ylabel('O2 Consumption (g/min)');
grid on;

% Export data for oxygen inventory and regulator-sizing calculations.
O2_Profile = table(Nominal_Time_hours, Nominal.Activity, ...
    M_dot_mars, O2_mars_g_min, ...
    'VariableNames', {'Time_hr', 'Activity', 'MarsMetabolicRate_W', ...
    'O2Consumption_g_min'});
writetable(O2_Profile, fullfile(dataFolder, 'Mars_O2_Profile.csv'));

%% PLSS Regulated Oxygen Tank Depletion (Isothermal, Ideal Gas)
% Tank pressure decreases with the cumulative O2 mass withdrawn.
% The downstream regulator setpoint does NOT determine tank depletion
% directly; it is an independent delivery constraint to verify.
P_initial_psig = 2100;             % psi gauge (change if tank spec is psia)
P_atm_psi = 14.696;                % psi, gauge-pressure reference
P_suit_psia = 4.3;                 % psi absolute (nominal setpoint)
V_tank_m3 = 3.82e-3;               % m^3 (3.82 L)
T_tank_K = 293.15;                 % K (fixed-temperature approximation)
R_O2 = 259.8;                     % J/(kg*K)
psi_to_Pa = 6894.757293;          % Pa/psi

P_initial_Pa = (P_initial_psig + P_atm_psi) * psi_to_Pa;
time_s = Nominal_Time_hours(:) * 3600;        % seconds
mdot_O2_kg_s = O2_mars_g_min(:) / 60000;     % g/min -> kg/s

assert(all(isfinite(time_s)) && all(diff(time_s) >= 0), ...
    'EVA times must be finite and nondecreasing.');
assert(all(isfinite(mdot_O2_kg_s)) && all(mdot_O2_kg_s >= 0), ...
    'O2 consumption must be finite and nonnegative.');

% Trapezoidal integral accommodates duplicate timestamps for step transitions.
mass_consumed_kg = cumtrapz(time_s, mdot_O2_kg_s);
mass_initial_kg = P_initial_Pa * V_tank_m3 / (R_O2 * T_tank_K);
mass_remaining_raw_kg = mass_initial_kg - mass_consumed_kg;

% Negative pressure/mass is nonphysical: report depletion rather than
% plotting invalid results. No prediction beyond empty-tank event.
depleted = mass_remaining_raw_kg <= 0;
mass_remaining_kg = mass_remaining_raw_kg;
mass_remaining_kg(depleted) = NaN;
P_tank_psia = mass_remaining_kg * R_O2 * T_tank_K / ...
    (V_tank_m3 * psi_to_Pa);

fprintf('\n--- Regulated PLSS Tank Depletion (ideal gas / isothermal) ---\n');
fprintf('Initial tank inventory: %.3f kg O2\n', mass_initial_kg);
fprintf('Total O2 demand: %.3f kg\n', mass_consumed_kg(end));
if any(depleted)
    i_first = find(depleted, 1, 'first');
    fprintf(2, 'WARNING: Tank empty by %.2f hr; demanded O2 exceeds inventory.\n', ...
        time_s(i_first) / 3600);
else
    fprintf('Remaining O2: %.3f kg\n', mass_remaining_kg(end));
    fprintf('Final tank pressure: %.1f psia\n', P_tank_psia(end));
end
fprintf('Suit regulator setpoint: %.1f psia (not modeled dynamically)\n', ...
    P_suit_psia);

figure;
plot(Nominal_Time_hours, P_tank_psia, 'LineWidth', 1.5);
title('PLSS Oxygen Tank Pressure vs EVA Time');
xlabel('EVA Time (hours)');
ylabel('Tank Pressure (psia)');
grid on;

% A regulator inlet-pressure cutoff should be added once manufacturer
% minimum inlet pressure at the required flow is known. The pressure curve
% alone does not verify 4.3 psia regulated delivery at all times.

%% Activity Mapping (Vibe Coded but functional)
function rates = mapMetabolicRates(activities, MetMan)
% MAPMETABOLICRATES Look up each nominal activity's rate in Metabolic.xlsx.
% Repeated activities are allowed only when their metabolic rates agree.
% Above Nominal is defined as 80% of the source resistance exercise rate.
% Other MetMan outputs vary over time and require separate mapping rules.

sourceActivities = lower(strtrim(string(MetMan.Activity)));
requestedActivities = strtrim(string(activities));
keys = lower(requestedActivities);

rates = zeros(size(keys));
aboveNominal = keys == "above nominal";
if any(aboveNominal)
    resistanceRate = mapMetabolicRates("Exercise - Resistance", MetMan);
    rates(aboveNominal) = 0.8 * resistanceRate;
end

for activity = reshape(unique(keys(~aboveNominal)), 1, [])
    requested = keys == activity;
    matches = sourceActivities == activity;
    if ~any(matches)
        label = requestedActivities(find(requested, 1));
        error('MetabolicProfile:UnmappedActivity', ...
            ['Activity "%s" in Raw_Nominal.csv was not found in ' ...
             'Metabolic.xlsx. Update the activity mapping or add a ' ...
             'corresponding source activity.'], char(label));
    end

    sourceRates = MetMan.MetabolicRate_kJ_hr(matches);
    if any(~isfinite(sourceRates) | sourceRates < 0)
        error('MetabolicProfile:InvalidRate', ...
            'Activity "%s" has a missing or invalid metabolic rate.', ...
            char(activity));
    end
    if numel(unique(sourceRates)) ~= 1
        error('MetabolicProfile:ConflictingRates', ...
            ['Activity "%s" has multiple metabolic rates in ' ...
             'Metabolic.xlsx. Use an unambiguous activity mapping.'], ...
            char(activity));
    end
    rates(requested) = sourceRates(1);
end
end
