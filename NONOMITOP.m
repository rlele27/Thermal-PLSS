%% (N.O.N.O.M.I.T.O.P) Nominal & Off Nominal O2 metabolic Intake & Total O2 Profile
% Replacement for the former inventory/blowdown script.
% The default two cases reproduce the metabolic inputs of the uploaded

% Nominal_Metabolic_Profile.m (2026-11 version):
%   1. Nominal: current 8-hour activity schedule
%   2. Off-nominal: same schedule, final 120 minutes at METMAN aerobic rate

% Only metabolic oxygen DEMAND is modeled here. Ventilation gas recirculation,
% tank pressure, leakage, regulator cutoff, and oxygen inventory are NOT
% inferred from metabolic power.

% Required inputs next to this file: Metabolic.xlsx, Raw_Nominal.csv.
% Outputs in O2_Model_Results:
%   O2_EVA_Summary.csv
%   Nominal_O2_Profile.csv
%   OffNominal_O2_Profile.csv
%   O2_Exertion_and_Cumulative_Consumption.png

clear;
clc;
close all;

%% USER SETTINGS
Folder = fileparts(mfilename('fullpath'));
if isempty(Folder), Folder = pwd; end
ResultsFolder = fullfile(Folder, 'O2_Model_Results');
if ~exist(ResultsFolder, 'dir'), mkdir(ResultsFolder); end

% Match the supplied Nominal_Metabolic_Profile.m precisely.
MarsGravity_g = 0.38;
EarthGravity_g = 1.0;
ThermalWalkingSpeed_m_s = 1.0;
RestingPower_W = 367 / 3.6;  % 95th-percentile male BVAD resting rate
Suit.LightFactor = 1.10;
Suit.ManualFactor = 1.10;
Suit.WalkingFactor = 1.10;

% Engineering screening band (not a claim of a human physiological limit).
O2Limit.Min_g_min = 0.5;
O2Limit.Max_g_min = 4.0;

% Default produces final-2h high-aerobic case.
OffNominal.Mode = "Thermal";       % "Thermal" or "PacedWalkback"
OffNominal.ThermalAerobicDuration_min = 120;

% 10-km walkback alternate (used ONLY in PacedWalkback mode).
% BVAD Rev2 Table 4-71: lunar-analogue 10-km walkback, mean 2505 kJ/h.
% It is already a suited measured/reference workload; do not apply a second
% suit or gravity multiplier. The 2-h mean is below 4 g/min at this O2 factor.
OffNominal.WalkbackStart_min = 360;           % time of abort from EVA start
OffNominal.WalkbackDistance_km = 10;
OffNominal.WalkbackReferenceDistance_km = 10;
OffNominal.WalkbackReferenceDuration_min = 120;
OffNominal.WalkbackMeanPower_kJ_hr = 2505;
OffNominal.WalkbackRequestedDuration_min = 120;
OffNominal.AutoLengthenWalkback = true;       % only if rate > max limit

%% Pulling Metabolic profile from Thermals updated numbers
Workbook = fullfile(Folder, 'Metabolic.xlsx');
Schedule = fullfile(Folder, 'Raw_Nominal.csv');
assert(isfile(Workbook) && isfile(Schedule), 'O2:Inputs', ...
    'Metabolic.xlsx and Raw_Nominal.csv must be next to NMP_RBDM.m.');

Mopts = spreadsheetImportOptions('NumVariables', 11);
Mopts.Sheet = 'Sheet1';
Mopts.DataRange = 'A4:K36';
Mopts.VariableNames = {'StartTime_hr','EndTime_hr','Duration_hr','Activity', ...
    'MetabolicRate_kJ_hr','SensibleHeat_kJ_hr','LatentHeat_kJ_hr', ...
    'WaterVapor_g_min','Sweat_g_min','O2Consumption_g_min','CO2Output_g_min'};
Mopts.VariableTypes = {'double','double','double','string','double', ...
    'double','double','double','double','double','double'};
MetMan = readtable(Workbook, Mopts);

Copts = detectImportOptions(Schedule, 'ReadVariableNames', true);
Copts.VariableNames = {'Time_min','MetabolicRate_Btu_hr','Activity'};
Copts = setvartype(Copts, 'Activity', 'string');
Raw = readtable(Schedule, Copts);

SourceActivity = lower(strtrim(string(MetMan.Activity)));
assert(any(SourceActivity == "nominal") && ...
    any(SourceActivity == "exercise - resistance") && ...
    any(SourceActivity == "exercise - aerobic"), ...
    'O2:Activities', 'Missing METMAN activity in lookup workbook.');
assert(abs(lookupMetabolic_W("Nominal", MetMan) * 3.6 - 580) < 1e-7 && ...
    abs(lookupMetabolic_W("Exercise - Resistance", MetMan) * 3.6 - 1452) < 1e-7 && ...
    abs(lookupMetabolic_W("Exercise - Aerobic", MetMan) * 3.6 - 5197) < 1e-7, ...
    'O2:CrewCase', 'Metabolic.xlsx is not the supplied 95th-percentile METMAN case.');

% Deriving O2 per watt 
Valid = isfinite(MetMan.MetabolicRate_kJ_hr) & ...
    isfinite(MetMan.O2Consumption_g_min) & ...
    MetMan.MetabolicRate_kJ_hr > 0 & MetMan.O2Consumption_g_min > 0;
assert(any(Valid), 'O2:Coefficient', 'No valid power/O2 pairs in Metabolic.xlsx.');
Ratios = MetMan.O2Consumption_g_min(Valid) ./ ...
    (MetMan.MetabolicRate_kJ_hr(Valid) / 3.6);
O2_per_W = median(Ratios);  % units: (g/min)/W
assert(all(abs(Ratios ./ O2_per_W - 1) < 0.02), ...
    'O2:Coefficient', 'METMAN power-to-oxygen ratios vary by over 2%%.');

%% Mars corrections done by thermal
Time_min = Raw.Time_min(:);
Labels = string(Raw.Activity(:));
assert(numel(Time_min) == numel(Labels) && numel(Time_min) > 1 && ...
    all(isfinite(Time_min)) && all(diff(Time_min) >= 0) && ...
    abs(Time_min(1)) < 1e-9 && abs(Time_min(end)-480) < 1e-9, ...
    'O2:Schedule', 'Current thermal schedule must span 0 to 480 minutes.');

MappedPower_W = lookupMetabolic_W(Labels, MetMan);
Keys = lower(strtrim(Labels));
Light = Keys == "nominal";
Manual = Keys == "above nominal" | Keys == "exercise - resistance";
Walking = Keys == "exercise - aerobic";
assert(all(Light | Manual | Walking), ...
    'O2:TaskClass', 'Unknown task label in Raw_Nominal.csv.');

v = ThermalWalkingSpeed_m_s;
CwEarth = 3.531 - 3.374*v + 1.535*v^2 + 0.557*EarthGravity_g;
CwMars  = 3.531 - 3.374*v + 1.535*v^2 + 0.557*MarsGravity_g;
WalkingGravityFactor = CwMars / CwEarth;

GravityFactor = ones(size(MappedPower_W));
GravityFactor(Walking) = WalkingGravityFactor;
SuitFactor = ones(size(MappedPower_W));
SuitFactor(Light) = Suit.LightFactor;
SuitFactor(Manual) = Suit.ManualFactor;
SuitFactor(Walking) = Suit.WalkingFactor;

PhysicalPower_W = RestingPower_W + SuitFactor .* GravityFactor .* ...
    max(MappedPower_W - RestingPower_W, 0);

Duration_min = diff(Time_min);
Idx = find(Duration_min > 0);
assert(~isempty(Idx), 'O2:Intervals', 'No nonzero EVA activity intervals.');
Nominal = table(Time_min(Idx), Time_min(Idx+1), Labels(Idx), ...
    PhysicalPower_W(Idx), ...
    'VariableNames', {'StartTime_min','EndTime_min','Activity','MetabolicPower_W'});
assert(all(abs(Nominal.StartTime_min(2:end) - Nominal.EndTime_min(1:end-1)) < 1e-8), ...
    'O2:Continuity', 'Nominal task intervals are not continuous.');

%% Off Nominal EVA case
Mode = string(OffNominal.Mode);
if Mode == "Thermal"
    AerobicEarthPower_W = lookupMetabolic_W("Exercise - Aerobic", MetMan);
    AerobicMarsSuitedPower_W = RestingPower_W + ...
        Suit.WalkingFactor * WalkingGravityFactor * ...
        max(AerobicEarthPower_W - RestingPower_W, 0);
    ChangeTime_min = Nominal.EndTime_min(end) - ...
        OffNominal.ThermalAerobicDuration_min;
    assert(ChangeTime_min >= 0 && ChangeTime_min < Nominal.EndTime_min(end), ...
        'O2:OffNominalDuration', 'Aerobic extension must fit within eight hours.');
    OffProfile = appendActivityAfter(Nominal, ChangeTime_min, ...
        Nominal.EndTime_min(end)-ChangeTime_min, ...
        AerobicMarsSuitedPower_W, "Thermal off-nominal: aerobic exercise");
    OffCaseLabel = "Thermal off-nominal";
elseif Mode == "PacedWalkback"
    % Alternative if the team REPLACES thermal off-nominal exercise with a
    % suited 10-km return walk. It is not identical to thermal JOS-3 inputs.
    assert(OffNominal.WalkbackReferenceDistance_km > 0 && ...
        abs(OffNominal.WalkbackDistance_km - OffNominal.WalkbackReferenceDistance_km) < 1e-9, ...
        'O2:WalkDistance', 'BVAD power reference only supports the 10-km case.');
    assert(OffNominal.WalkbackRequestedDuration_min > 0 && ...
        OffNominal.WalkbackReferenceDuration_min > 0, ...
        'O2:WalkDuration', 'Walkback durations must be positive.');
    ReferencePower_W = OffNominal.WalkbackMeanPower_kJ_hr / 3.6;
    % First-order pacing assumption: excess work above resting is fixed
    % for the specified distance. This needs validation at Mars gravity.
    ExcessWork_Wmin = (ReferencePower_W-RestingPower_W) * ...
        OffNominal.WalkbackReferenceDuration_min;
    assert(ExcessWork_Wmin > 0, 'O2:WalkReference', 'Invalid walkback energy basis.');
    WalkDuration_min = OffNominal.WalkbackRequestedDuration_min;
    if OffNominal.AutoLengthenWalkback
        MaxPower_W = O2Limit.Max_g_min / O2_per_W;
        assert(MaxPower_W > RestingPower_W, 'O2:MaxFlow', ...
            'Maximum O2 flow is below resting demand.');
        RequiredDuration_min = ExcessWork_Wmin / (MaxPower_W-RestingPower_W);
        WalkDuration_min = max(WalkDuration_min, RequiredDuration_min);
    end
    WalkPower_W = RestingPower_W + ExcessWork_Wmin / WalkDuration_min;
    assert(OffNominal.WalkbackStart_min >= 0 && ...
        OffNominal.WalkbackStart_min <= Nominal.EndTime_min(end), ...
        'O2:WalkStart', 'Walkback start must lie in the nominal EVA.');
    OffProfile = appendActivityAfter(Nominal, ...
        OffNominal.WalkbackStart_min, WalkDuration_min, WalkPower_W, ...
        "10-km walkback (BVAD lunar analogue, paced)");
    OffCaseLabel = "Paced walkback alternative";
    fprintf('Walkback time: %.2f h for 10 km (%.2f km/h); demand %.3f g/min.\n', ...
        WalkDuration_min/60, 600/WalkDuration_min, WalkPower_W*O2_per_W);
    if WalkDuration_min > OffNominal.WalkbackRequestedDuration_min + 1e-9
        fprintf(2, 'WARNING: Walk duration was extended by a nonvalidated pacing law.\n');
    end
else
    error('O2:Mode', 'Use OffNominal.Mode = "Thermal" or "PacedWalkback".');
end

%% EXACT DURATION-WEIGHTED O2 INTEGRATION FOR BOTH CASES
Nominal_O2_Profile = makeO2Profile(Nominal, O2_per_W);
OffNominal_O2_Profile = makeO2Profile(OffProfile, O2_per_W);

Nominal_MeanMetabolicPower_W = weightedMean(Nominal_O2_Profile.MetabolicPower_W, ...
    Nominal_O2_Profile.Duration_min);
Nominal_MeanO2_g_min = weightedMean(Nominal_O2_Profile.O2Consumption_g_min, ...
    Nominal_O2_Profile.Duration_min);
Nominal_TotalO2_kg = Nominal_O2_Profile.CumulativeO2_kg(end);
OffNominal_MeanMetabolicPower_W = weightedMean(OffNominal_O2_Profile.MetabolicPower_W, ...
    OffNominal_O2_Profile.Duration_min);
OffNominal_MeanO2_g_min = weightedMean(OffNominal_O2_Profile.O2Consumption_g_min, ...
    OffNominal_O2_Profile.Duration_min);
OffNominal_TotalO2_kg = OffNominal_O2_Profile.CumulativeO2_kg(end);

Scenario = ["Nominal EVA"; OffCaseLabel];
Duration_hr = [sum(Nominal_O2_Profile.Duration_min); ...
    sum(OffNominal_O2_Profile.Duration_min)] / 60;
MeanMetabolicPower_W = [Nominal_MeanMetabolicPower_W; OffNominal_MeanMetabolicPower_W];
MeanO2_g_min = [Nominal_MeanO2_g_min; OffNominal_MeanO2_g_min];
TotalO2_kg = [Nominal_TotalO2_kg; OffNominal_TotalO2_kg];
MinimumO2_g_min = [min(Nominal_O2_Profile.O2Consumption_g_min); ...
    min(OffNominal_O2_Profile.O2Consumption_g_min)];
PeakO2_g_min = [max(Nominal_O2_Profile.O2Consumption_g_min); ...
    max(OffNominal_O2_Profile.O2Consumption_g_min)];
TimeAboveLimit_min = [sum(Nominal_O2_Profile.Duration_min( ...
    Nominal_O2_Profile.O2Consumption_g_min > O2Limit.Max_g_min)); ...
    sum(OffNominal_O2_Profile.Duration_min( ...
    OffNominal_O2_Profile.O2Consumption_g_min > O2Limit.Max_g_min))];
TimeBelowLimit_min = [sum(Nominal_O2_Profile.Duration_min( ...
    Nominal_O2_Profile.O2Consumption_g_min < O2Limit.Min_g_min)); ...
    sum(OffNominal_O2_Profile.Duration_min( ...
    OffNominal_O2_Profile.O2Consumption_g_min < O2Limit.Min_g_min))];
O2_EVA_Summary = table(Scenario, Duration_hr, MeanMetabolicPower_W, ...
    MeanO2_g_min, TotalO2_kg, MinimumO2_g_min, PeakO2_g_min, ...
    TimeAboveLimit_min, TimeBelowLimit_min);

% Only three simple output tables: one summary and two full time histories.
writetable(O2_EVA_Summary, fullfile(ResultsFolder, 'O2_EVA_Summary.csv'));
writetable(Nominal_O2_Profile, fullfile(ResultsFolder, 'Nominal_O2_Profile.csv'));
writetable(OffNominal_O2_Profile, fullfile(ResultsFolder, 'OffNominal_O2_Profile.csv'));

fprintf('\n================ O2 METABOLIC CONSUMPTION ================\n');
fprintf('Profile basis: supplied thermal-team METMAN / EVA schedule\n');
fprintf('O2 conversion: %.8f (g/min)/W (from Metabolic.xlsx)\n', O2_per_W);
fprintf('----------------------------------------------------------\n');
fprintf('NOMINAL       Mean O2: %.4f g/min | Total: %.4f kg | %.2f hr\n', ...
    Nominal_MeanO2_g_min, Nominal_TotalO2_kg, Duration_hr(1));
fprintf('OFF-NOMINAL   Mean O2: %.4f g/min | Total: %.4f kg | %.2f hr\n', ...
    OffNominal_MeanO2_g_min, OffNominal_TotalO2_kg, Duration_hr(2));
fprintf('Off-nominal mode: %s\n', char(OffCaseLabel));
fprintf('==========================================================\n');
disp(O2_EVA_Summary);
if any(TimeAboveLimit_min > 0 | TimeBelowLimit_min > 0)
    fprintf(2, ['WARNING: The source activity profiles exceed the editable ' ...
        '%.1f-%.1f g/min design band. No rates were clipped or scaled.\n'], ...
        O2Limit.Min_g_min, O2Limit.Max_g_min);
    fprintf(2, ['The METMAN high-aerobic input is NOT ordinary walking. ' ...
        'Coordinate any pacing/activity change with thermals.\n']);
end

%% O2 Consumption Profile & Consumption over time
%figure('Name', 'PLSS O2 demand: nominal and off-nominal', 'NumberTitle', 'off');
figure('Name', 'PLSS O2 demand: Nominal profile', 'NumberTitle', 'off');
tiledlayout(2, 1);

nexttile;
hold on;
plotStepRate(Nominal_O2_Profile, 'Nominal EVA', '-', 1.6);
plotStepRate(OffNominal_O2_Profile, char(OffCaseLabel), '--', 1.7);
yline(O2Limit.Max_g_min, ':', '4 g/min design reference', ...
    'HandleVisibility', 'off');
yline(O2Limit.Min_g_min, ':', '0.5 g/min reference', ...
    'HandleVisibility', 'off');
ylabel('O2 metabolic rate (g/min)');
title('Astronaut O2 consumption rate (95th Percentile Male)');
legend('Location', 'best');
grid on;
hold off;

nexttile;
hold on;
plot([0; Nominal_O2_Profile.EndTime_min] / 60, ...
    [0; Nominal_O2_Profile.CumulativeO2_kg], ...
    '-', 'LineWidth', 1.8, 'DisplayName', 'Nominal EVA');
plot([0; OffNominal_O2_Profile.EndTime_min] / 60, ...
    [0; OffNominal_O2_Profile.CumulativeO2_kg], ...
    '--', 'LineWidth', 1.8, 'DisplayName', char(OffCaseLabel));
ylabel('Cumulative O2 consumed (kg)');
xlabel('Elapsed EVA time (h)');
title('Integrated metabolic oxygen consumption (95th Percentile Male)');
legend('Location', 'middle');
grid on;
hold off;

saveas(gcf, fullfile(ResultsFolder, 'O2_Exertion_and_Cumulative_Consumption.png'));
fprintf('Outputs saved in: %s\n', ResultsFolder);

%% Local functions
function W = lookupMetabolic_W(Activities, MetMan)
% Same source mapping as Nominal_Metabolic_Profile.m.
    Keys = lower(strtrim(string(Activities(:))));
    Source = lower(strtrim(string(MetMan.Activity)));
    W = zeros(size(Keys));
    for k = 1:numel(Keys)
        Scale = 1;
        Key = Keys(k);
        if Key == "above nominal"
            Key = "exercise - resistance";
            Scale = 0.8;
        end
        V = MetMan.MetabolicRate_kJ_hr(Source == Key);
        assert(~isempty(V) && all(isfinite(V)) && all(V >= 0) && ...
            all(abs(V-V(1)) < 1e-7), ...
            'O2:Mapping', 'Missing/ambiguous METMAN activity: %s', char(Key));
        W(k) = Scale * V(1) / 3.6;
    end
end

function P = appendActivityAfter(Base, Start_min, ActivityDuration_min, Power_W, Label)
% Keep all nominal tasks before Start_min, then replace subsequent activity.
    assert(isfinite(Start_min) && isfinite(ActivityDuration_min) && ...
        ActivityDuration_min > 0 && isfinite(Power_W) && Power_W > 0);
    Before = Base(Base.StartTime_min < Start_min, :);
    if ~isempty(Before)
        Before.EndTime_min = min(Before.EndTime_min, Start_min);
        Before = Before(Before.EndTime_min > Before.StartTime_min, :);
    end
    After = table(Start_min, Start_min + ActivityDuration_min, ...
        string(Label), Power_W, ...
        'VariableNames', {'StartTime_min','EndTime_min','Activity','MetabolicPower_W'});
    P = [Before; After];
end

function P = makeO2Profile(Base, OxygenPerW)
% Piecewise-constant metabolic rate integrated over positive task durations.
    P = Base;
    P.Duration_min = P.EndTime_min-P.StartTime_min;
    assert(all(P.Duration_min > 0) && ...
        all(abs(P.StartTime_min(2:end)-P.EndTime_min(1:end-1)) < 1e-8), ...
        'O2:Profile', 'Nonpositive or noncontiguous activity intervals.');
    P.O2Consumption_g_min = P.MetabolicPower_W * OxygenPerW;
    P.IntervalO2_g = P.O2Consumption_g_min .* P.Duration_min;
    P.CumulativeO2_g = cumsum(P.IntervalO2_g);
    P.CumulativeO2_kg = P.CumulativeO2_g / 1000;
end

function M = weightedMean(Value, Duration)
    M = sum(Value .* Duration) / sum(Duration);
end

function plotStepRate(P, Label, Style, Width)
    X = [P.StartTime_min; P.EndTime_min(end)] / 60;
    Y = [P.O2Consumption_g_min; P.O2Consumption_g_min(end)];
    stairs(X, Y, Style, 'LineWidth', Width, 'DisplayName', Label);
end
