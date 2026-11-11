clearvars;
clc;
close all;

%% Inputs - files and reporting
DataFile = "+Data_Functions/EVA_Data.mat";
PlotResults = true;

%% Inputs - metabolic demand and margins
G_Earth = 1;
G_Mars = 0.38;
v_walking = 1; % Walking speed (m/s).
Suit.LightFactor = 1.1;
Suit.ManualFactor = 1.1;
Suit.WalkingFactor = 1.1;
MetabolicFOS = 1.2; % Post-simulation sizing-load multiplier; e.g. 1.2 adds 20%.
HeatStorageScreeningLimit_kJ_kg = 3.0; % NASA V2 11011 nominal EVA screening reference.
% BVAD Rev. 2 (2022), Table 3-26: 95th-percentile sleep and awake rates.
RestingMetabolicRate_W = 367 / 3.6; % 95th-percentile sleep-rate proxy.
NominalMetabolicRate_W = 580 / 3.6; % Nominal awake lookup reference.

%% Inputs - METMAN external work correction (ICES-2021-365 Tables 7-8)
ExternalWork.Nominal_W = 0;
ExternalWork.Aerobic_W = 201;
ExternalWork.Resistance_W = 45;
ExternalWork.AboveNominalFraction = 0.8; % Same extrapolation as the metabolic activity mapping.
% Subtracted AFTER Mars/suit adjustment; published device work is not rescaled.
% Exercise work is applied to our EVA proxies by assumption, including walk-back.


%% Inputs - astronaut physiology
% Astronaut: BVAD Rev2 (2022), pp.48,50; 95th-percentile high-fitness male.
% METMAN exercise lookup assumes VO2max = 55 mL/kg/min (Rev1 p.49).
Body.Height_m = 1.84;
Body.Weight_kg = 100;
Body.Fat_percent = 15; % Retained JOS-3 assumption; percentile value not specified.
Body.Age_years = 30; % Retained scenario assumption; percentile value not specified.
Body.Sex = "male";
Body.SurfaceAreaEquation = "dubois";
Body.BasalMetabolicEquation = "harris-benedict";
Body.CardiacIndex_L_min_m2 = 2.59; % Retained JOS-3 assumption; not a percentile datum.

%% Inputs - suit air and garment
BodyMicroclimate.AirTemperature_C = 18;
BodyMicroclimate.RelativeHumidity_percent = 50; % Assumed bulk air RH.
BodyMicroclimate.Pressure_kPa = 31.7159;
BodyMicroclimate.RadiantTemperature_C = BodyMicroclimate.AirTemperature_C;
% Preliminary liner properties. Replace with thermal-network or test values.
BodyMicroclimate.Liner.Enabled = true;
BodyMicroclimate.Liner.InitialTemperature_C = BodyMicroclimate.RadiantTemperature_C;
BodyMicroclimate.Liner.ReferenceTemperature_C = 16; % Prescribed downstream thermal boundary.
BodyMicroclimate.Liner.HeatCapacity_J_K = 5000;
BodyMicroclimate.Liner.Conductance_W_K = 5;
BodyMicroclimate.AirSpeed_m_s = 0.1; % Assumed local skin air speed (m/s).
BodyMicroclimate.Clothing_clo = 0.2; % Assumed light-garment insulation, not measured LCG data.
BodyMicroclimate.VaporPermeationEfficiency = 0.45; % Assumed garment permeability; affects evaporative resistance.
BodyMicroclimate.Posture = "standing";
BodyMicroclimate.QgenIncludesThermogenesis = true; % Complete prescribed heat source; no extra cold-defense heat.

%% Inputs - LCG calibration and control
LCGWaterCp_J_kgK = 4180;
LCGFitSettings.Candidates = ["Linear","LogAdditive","PowerLaw"];
LCGFitSettings.SelectedFamily = "Linear"; % Restore original bounded linear regression; CV remains diagnostic.
LCGFitSettings.HeldOutDay = 12;
LCGFitSettings.ReferenceMetabolic_W = 400; % Numerical feature scale, not a physiological threshold.
LCGFitSettings.ReferenceFlow_kg_s = 80/3600; % Numerical feature scale.

BodyMicroclimate.LCG.Enabled = true;
BodyMicroclimate.LCG.Model = "LiteratureDynamicUA";
BodyMicroclimate.LCG.InletTemperature_C = 18.3; % Preconditioning/fixed-mode reference.
% Ideal temperature actuator; air supply temperature and RH remain independent.
BodyMicroclimate.LCG.Controller.Enabled = true;
BodyMicroclimate.LCG.Controller.TemperatureBounds_C = [10,18.3]; % Fixed minimum and maximum inlet temperatures.
BodyMicroclimate.LCG.Controller.TargetStoredHeat_kJ_kg = 0; % Control target reserves headroom below limit.
BodyMicroclimate.LCG.Controller.LimitStoredHeat_kJ_kg = HeatStorageScreeningLimit_kJ_kg;
BodyMicroclimate.LCG.Controller.TemperatureTolerance_C = 0.25;
BodyMicroclimate.LCG.Controller.MaximumSearchIterations = 6;
BodyMicroclimate.LCG.Controller.FlowControlEnabled = true;
BodyMicroclimate.LCG.Controller.UpperTemperatureMode = "Fixed"; % Fixed upper inlet temperature limit.
BodyMicroclimate.LCG.Controller.MaximumFlow_kg_h = 130; % Editable pump/garment design cap, not a validated limit.
BodyMicroclimate.LCG.Controller.FlowTolerance_kg_h = 0.5;
BodyMicroclimate.LCG.Controller.FlowReleaseRate_kg_h_min = 10; % Maximum flow reduction per minute.
BodyMicroclimate.LCG.Controller.StorageDeadband_kJ_kg = 0.05; % Hold flow near target; ramp down below band.
% Baseline flow uses NASA calibration when empty; enter kg/h to override.
LCGBaselineFlow_kg_h = 0;

%% Inputs - ventilation
Ventilation.Flow_CFM = 6;
BodyMicroclimate.Ventilation = Ventilation;

%% Inputs - physiology integration and EVA schedule
BodyMicroclimate.TrackRetainedSweat = true; % Later evaporation retained; runoff excluded.
JOS3_Step_s = 30;
JOS3_Precondition_min = 60; % Excluded from EVA duration.
OffNominalWalkingDuration_min = 250; % Final 4 hr 10 min walking at resistance reference rate.


%% Load the shared database
if ~isfile(DataFile)
    Data_Functions.Data.buildEVAData(DataFile);
end
Loaded = load(DataFile,'Data');
Data = Loaded.Data;
if ~isfield(Data.Source.LCGReference,'DynamicRawTable10')
    Data = Data_Functions.Data.buildEVAData(DataFile);
end


%% Calibrate garment models and validate source data

validateattributes(MetabolicFOS, {'numeric'}, {'scalar','real','finite','>=',1});
validateattributes(RestingMetabolicRate_W, {'numeric'}, {'scalar','real','finite','positive'});
validateattributes(NominalMetabolicRate_W, {'numeric'}, {'scalar','real','finite','>',RestingMetabolicRate_W});

% LCG
% NASA EMU constant-UA calibration and independent held-out garment benchmark.

Reference = Data.Source.LCGReference;
% Calibrate with NASA days 2/4/3/5 and compare against held-out days 6/7/8.
Raw = Reference.Raw;
assert(isequal(size(Raw), [7, 8]), 'EVA:ReferenceData', 'Expected seven NASA EMU observations.');
LiteratureData = array2table(Raw, 'VariableNames', {'Day', 'Flow_lbm_hr', 'Inlet_F', ...
    'Outlet_F', 'Skin_F', 'UA_Btu_hr_F', 'Heat_Btu_hr', 'Metabolic_Btu_hr'});
LiteratureData.SourceTable = [repmat(5, 4, 1); repmat(7, 3, 1)];
LiteratureData.Split = [repmat("Calibration", 4, 1); repmat("Held-out", 3, 1)];
LiteratureData.Flow_kg_s = LiteratureData.Flow_lbm_hr * 0.45359237 / 3600;
LiteratureData.Inlet_C = (LiteratureData.Inlet_F - 32) / 1.8;
LiteratureData.Outlet_C = (LiteratureData.Outlet_F - 32) / 1.8;
LiteratureData.Skin_C = (LiteratureData.Skin_F - 32) / 1.8;
LiteratureData.UA_W_K = LiteratureData.UA_Btu_hr_F * 0.2930710701722222 * 1.8;
LiteratureData.Heat_W = LiteratureData.Heat_Btu_hr * 0.2930710701722222;
Train = LiteratureData.Split == "Calibration";
validateattributes(LCGWaterCp_J_kgK,{'numeric'},{'scalar','finite','positive'});
LCGCalibration = struct('UA_W_K',mean(LiteratureData.UA_W_K(Train)), ...
    'MassFlow_kg_s',mean(LiteratureData.Flow_kg_s(Train)));
% Invert Eq.8 to predict outlet water and heat removal without using test UA.
C = LiteratureData.Flow_kg_s * LCGWaterCp_J_kgK;
Predicted_W = C .* (-expm1(-LCGCalibration.UA_W_K ./ C)) .* (LiteratureData.Skin_C - LiteratureData.Inlet_C);
PredictedOutlet_C = LiteratureData.Inlet_C + Predicted_W ./ C;
MeanStateCalorimetry_W = C .* (LiteratureData.Outlet_C - LiteratureData.Inlet_C);
Comparison = table(LiteratureData.Day, LiteratureData.Split, LiteratureData.Heat_W, Predicted_W, ...
    100 * (Predicted_W - LiteratureData.Heat_W) ./ LiteratureData.Heat_W, LiteratureData.Outlet_C, ...
    PredictedOutlet_C, MeanStateCalorimetry_W, ...
    'VariableNames', {'Day', 'Split', 'MeasuredHeat_W', 'PredictedHeat_W', ...
    'HeatError_percent', 'MeasuredOutlet_C', 'PredictedOutlet_C', 'MeanStateCalorimetry_W'});
Test = ~Train;
Error = Predicted_W(Test) - LiteratureData.Heat_W(Test);
Metrics = table(LCGCalibration.UA_W_K, sqrt(mean(Error.^2)), mean(Error), ...
    mean(abs(100 * Error ./ LiteratureData.Heat_W(Test))), ...
    sqrt(mean((PredictedOutlet_C(Test)-LiteratureData.Outlet_C(Test)).^2)), ...
    'VariableNames', {'CalibratedUA_W_K', 'HeldOutHeatRMSE_W', 'HeldOutHeatBias_W', ...
    'HeldOutHeatMAPE_percent', 'HeldOutOutletRMSE_C'});
BodyMicroclimate.LCG.UA_W_K = LCGCalibration.UA_W_K;
BodyMicroclimate.LCG.MassFlow_kg_s = LCGCalibration.MassFlow_kg_s;
if ~isempty(LCGBaselineFlow_kg_h)
    validateattributes(LCGBaselineFlow_kg_h,{'numeric'},{'scalar','real','finite','nonnegative'});
    BodyMicroclimate.LCG.MassFlow_kg_s = LCGBaselineFlow_kg_h/3600;
end
BodyMicroclimate.LCG.WaterCp_J_kgK = LCGWaterCp_J_kgK;
% Empirical condition-dependent UA: our regression of NASA Table 10 data.
% Training: days 9/10/11 (three subjects). Day 12 is held out completely.
DynamicRaw = Data.Source.LCGReference.DynamicRawTable10;
assert(isequal(size(DynamicRaw),[16,4]) && all(isfinite(DynamicRaw),'all'), ...
    'EVA:DynamicLCGData','Expected 16 paired NASA Table 10 observations.');
DynamicData = array2table(DynamicRaw,'VariableNames', ...
    {'Day','UA_Btu_hr_F','Metabolic_Btu_hr','Flow_lbm_hr'});
DynamicData.UA_W_K = DynamicData.UA_Btu_hr_F*0.2930710701722222*1.8;
DynamicData.Metabolic_W = DynamicData.Metabolic_Btu_hr*0.2930710701722222;
DynamicData.Flow_kg_s = DynamicData.Flow_lbm_hr*0.45359237/3600;
DynamicTrain = DynamicData.Day ~= LCGFitSettings.HeldOutDay;
CalibrationDays = unique(DynamicData.Day(DynamicTrain));
Family = LCGFitSettings.Candidates(:);
CV_RMSE_W_K = zeros(numel(Family),1);
Monotonic = true(numel(Family),1);
CandidateFits = cell(numel(Family),1);
for Candidate = 1:numel(Family)
    FoldErrors = zeros(sum(DynamicTrain),1);
    ErrorIndex = 0;
    for Fold = 1:numel(CalibrationDays)
        FoldTrain = DynamicTrain & DynamicData.Day ~= CalibrationDays(Fold);
        FoldTest = DynamicTrain & DynamicData.Day == CalibrationDays(Fold);
        Fit = Data_Functions.Physiology.fitLCGDynamicUA( ...
            DynamicData.Metabolic_W(FoldTrain),DynamicData.Flow_kg_s(FoldTrain), ...
            DynamicData.UA_W_K(FoldTrain),Family(Candidate), ...
            LCGFitSettings.ReferenceMetabolic_W,LCGFitSettings.ReferenceFlow_kg_s);
        TrialLCG = BodyMicroclimate.LCG;
        TrialLCG.DynamicFit = Fit;
        TrialLCG.Model = "LiteratureDynamicUA";
        TrialLCG.MassFlow_kg_s = DynamicData.Flow_kg_s(FoldTest);
        FoldPrediction = Data_Functions.Physiology.lcgGarmentUA(TrialLCG,DynamicData.Metabolic_W(FoldTest));
        Count = sum(FoldTest);
        FoldErrors(ErrorIndex+(1:Count)) = FoldPrediction-DynamicData.UA_W_K(FoldTest);
        ErrorIndex = ErrorIndex+Count;
        Monotonic(Candidate) = Monotonic(Candidate) && Fit.Monotonic;
    end
    CV_RMSE_W_K(Candidate) = sqrt(mean(FoldErrors.^2));
    CandidateFits{Candidate} = Data_Functions.Physiology.fitLCGDynamicUA( ...
        DynamicData.Metabolic_W(DynamicTrain),DynamicData.Flow_kg_s(DynamicTrain), ...
        DynamicData.UA_W_K(DynamicTrain),Family(Candidate), ...
        LCGFitSettings.ReferenceMetabolic_W,LCGFitSettings.ReferenceFlow_kg_s);
    Monotonic(Candidate) = Monotonic(Candidate) && CandidateFits{Candidate}.Monotonic;
end
BestCandidate = find(Family == LCGFitSettings.SelectedFamily,1);
assert(~isempty(BestCandidate) && Monotonic(BestCandidate), ...
    'EVA:DynamicLCGFit','Configured UA fit must be a monotonic candidate.');
BestCV_RMSE_W_K = CV_RMSE_W_K(BestCandidate);
Selected = (1:numel(Family))' == BestCandidate;
DynamicCrossValidation = table(Family,CV_RMSE_W_K,Monotonic,Selected);
DynamicFit = CandidateFits{BestCandidate};
BodyMicroclimate.LCG.DynamicFit = DynamicFit;
% The previous linear fit is retained only as an error benchmark, not a graph.
LinearFit = Data_Functions.Physiology.fitLCGDynamicUA( ...
    DynamicData.Metabolic_W(DynamicTrain),DynamicData.Flow_kg_s(DynamicTrain), ...
    DynamicData.UA_W_K(DynamicTrain),"Linear", ...
    LCGFitSettings.ReferenceMetabolic_W,LCGFitSettings.ReferenceFlow_kg_s);
LinearLCG = BodyMicroclimate.LCG;
LinearLCG.Model = "LiteratureDynamicUA";
LinearLCG.DynamicFit = LinearFit;
LinearLCG.MassFlow_kg_s = DynamicData.Flow_kg_s(~DynamicTrain);
LinearHeldOutPrediction = Data_Functions.Physiology.lcgGarmentUA(LinearLCG,DynamicData.Metabolic_W(~DynamicTrain));
LinearHeldOutError = LinearHeldOutPrediction-DynamicData.UA_W_K(~DynamicTrain);
DynamicPredictedUA_W_K = zeros(height(DynamicData),1);
DynamicOutside = false(height(DynamicData),1);
for Row = 1:height(DynamicData)
    TrialLCG = BodyMicroclimate.LCG;
    TrialLCG.Model = "LiteratureDynamicUA";
    TrialLCG.MassFlow_kg_s = DynamicData.Flow_kg_s(Row);
    [DynamicPredictedUA_W_K(Row),DynamicOutside(Row)] = ...
        Data_Functions.Physiology.lcgGarmentUA(TrialLCG,DynamicData.Metabolic_W(Row));
end
DynamicData.PredictedUA_W_K = DynamicPredictedUA_W_K;
DynamicData.OutsideCalibration = DynamicOutside;
DynamicData.Split = repmat("Calibration",height(DynamicData),1);
DynamicData.Split(~DynamicTrain) = "Held-out";
DynamicError = DynamicPredictedUA_W_K(~DynamicTrain)-DynamicData.UA_W_K(~DynamicTrain);
DynamicMetrics = table(sqrt(mean(DynamicError.^2)),mean(DynamicError), ...
    'VariableNames',{'HeldOutUARMSE_W_K','HeldOutUABias_W_K'});
DynamicMetrics.PreviousLinearHeldOutRMSE_W_K = sqrt(mean(LinearHeldOutError.^2));
DynamicMetrics.CalibrationCV_RMSE_W_K = BestCV_RMSE_W_K;
DynamicMetrics.SelectedFamily = DynamicFit.Family;
% Quasi-steady parameter fit, not a validated transient/wetness-memory law.
Inputs = struct('Body', Body, 'Environment', BodyMicroclimate, 'Suit', Suit, ...
    'MetabolicFOS', MetabolicFOS, 'ExternalWork',ExternalWork,'LCGFitSettings',LCGFitSettings, ...
    'HeatStorageScreeningLimit_kJ_kg', HeatStorageScreeningLimit_kJ_kg, ...
    'EarthGravity', G_Earth, 'MarsGravity', G_Mars, 'WalkingSpeed_m_s', v_walking, ...
    'RestingMetabolicRate_W', RestingMetabolicRate_W, ...
    'NominalMetabolicRate_W', NominalMetabolicRate_W, ...
    'Step_s', JOS3_Step_s, 'Precondition_min', JOS3_Precondition_min, ...
    'OffNominalWalkingDuration_min', OffNominalWalkingDuration_min, 'PlotResults', PlotResults);

%% Calculate and persist complete nominal/off-nominal histories
Source = Data.Source;
Body = Inputs.Body; BodyMicroclimate = Inputs.Environment;
G_Earth = Inputs.EarthGravity; G_Mars = Inputs.MarsGravity;
Suit = Inputs.Suit; v_walking = Inputs.WalkingSpeed_m_s;
RestingMetabolicRate_W = Inputs.RestingMetabolicRate_W;
JOS3_Step_s = Inputs.Step_s; JOS3_Precondition_min = Inputs.Precondition_min;
OffNominalWalkingDuration_min = Inputs.OffNominalWalkingDuration_min;
M = Source.MetMan;
MetMan = table(M.StartTime_hr(:), M.EndTime_hr(:), string(M.Activity(:)), ...
    M.MetabolicRate_kJ_hr(:), 'VariableNames', {'StartTime_hr','EndTime_hr','Activity','MetabolicRate_kJ_hr'});
N = Source.Nominal;
Nominal = table(N.Time_min(:), N.MetabolicRate_Btu_hr(:), string(N.Activity(:)), ...
    'VariableNames', {'Time_min','MetabolicRate_Btu_hr','Activity'});
assert(all(MetMan.MetabolicRate_kJ_hr(MetMan.Activity == "Nominal") == NominalMetabolicRate_W * 3.6) ...
    && all(MetMan.MetabolicRate_kJ_hr(MetMan.Activity == "Exercise - Resistance") == 1452) ...
    && all(MetMan.MetabolicRate_kJ_hr(MetMan.Activity == "Exercise - Aerobic") == 5197), ...
    'EVA:CrewMismatch', 'The lookup must use the BVAD 95th-percentile reference.');
%% Metabolic Model - Calculations
% Data Manipulation
Mapped_MetabolicRate_W = Data_Functions.Metabolism.mapMetabolicRates(Nominal.Activity, MetMan, ExternalWork.AboveNominalFraction) / 3.6;

% Task-Based Mars/Suit Conversion
% Aerobic exercise is an assumed walking/traverse proxy, not a measured EVA task.
% Manual/light work receives no walking-derived gravity reduction.
Activity = lower(strtrim(string(Nominal.Activity)));
LightTask = Activity == "nominal";
ManualTask = Activity == "above nominal" | Activity == "exercise - resistance";
WalkingTask = Activity == "exercise - aerobic";
assert(all(LightTask | ManualTask | WalkingTask), ...
    'MetabolicProfile:UnmappedTask', 'Add a task class for every activity label.');
validateattributes([Suit.LightFactor, Suit.ManualFactor, Suit.WalkingFactor], ...
    {'numeric'}, {'vector', 'numel', 3, 'real', 'finite', '>=', 1});

GravityFactor = ones(size(Activity));
SuitFactor = ones(size(Activity));
TaskClass = strings(size(Activity));
SuitFactor(LightTask) = Suit.LightFactor;
SuitFactor(ManualTask) = Suit.ManualFactor;
SuitFactor(WalkingTask) = Suit.WalkingFactor;
TaskClass(LightTask) = "Light";
TaskClass(ManualTask) = "Manual";
TaskClass(WalkingTask) = "Walking";
C_w_E = 3.531 - 3.374 * v_walking + 1.535 * v_walking^2 + 0.557 * G_Earth;
C_w_M = 3.531 - 3.374 * v_walking + 1.535 * v_walking^2 + 0.557 * G_Mars;
K_g = C_w_M / C_w_E;
GravityFactor(WalkingTask) = K_g;
ActivityRate_W = max(Mapped_MetabolicRate_W - RestingMetabolicRate_W, 0);
PhysicalMetabolicRate_W = RestingMetabolicRate_W + SuitFactor .* GravityFactor .* ActivityRate_W;
validateattributes([ExternalWork.Nominal_W,ExternalWork.Aerobic_W,ExternalWork.Resistance_W], ...
    {'numeric'},{'vector','real','finite','nonnegative'});
validateattributes(ExternalWork.AboveNominalFraction,{'numeric'},{'scalar','real','finite','>=',0,'<=',1});
ExternalWork_W = zeros(size(Activity));
ExternalWork_W(LightTask) = ExternalWork.Nominal_W;
ExternalWork_W(Activity == "above nominal") = ExternalWork.AboveNominalFraction*ExternalWork.Resistance_W;
ExternalWork_W(Activity == "exercise - resistance") = ExternalWork.Resistance_W;
ExternalWork_W(WalkingTask) = ExternalWork.Aerobic_W;
HeatGeneration_W = PhysicalMetabolicRate_W-ExternalWork_W;
assert(all(HeatGeneration_W>0),'EVA:ExternalWork','External work must leave positive body heat generation.');
Metabolic_Task_Mapping = table(Nominal.Time_min, Nominal.Activity, TaskClass, ...
    GravityFactor, SuitFactor, Mapped_MetabolicRate_W, PhysicalMetabolicRate_W, ...
    ExternalWork_W,HeatGeneration_W, ...
    'VariableNames', {'Time_min','Activity','TaskClass','GravityFactor', ...
    'SuitFactor','EarthMetabolicRate_W','PhysicalMetabolicRate_W','ExternalWork_W','HeatGeneration_W'});

% Separate physiological runs: replace the final 250 minutes with walking.
Nominal_Moisture_Profile = Data_Functions.Physiology.runJOS3Profile(Nominal.Time_min, HeatGeneration_W, ...
    Body, BodyMicroclimate, JOS3_Step_s, JOS3_Precondition_min);
WalkingReferenceEarthRate_W = Data_Functions.Metabolism.mapMetabolicRates("Exercise - Resistance", MetMan, ExternalWork.AboveNominalFraction) / 3.6;
OffNominalWalkingRate_W = RestingMetabolicRate_W + Suit.WalkingFactor * K_g ...
    * max(WalkingReferenceEarthRate_W - RestingMetabolicRate_W, 0);
%% Off-nominal end-of-EVA walking block
Time_min = Nominal.Time_min; Activity = Nominal.Activity;
Rate_W = HeatGeneration_W; Duration_min = OffNominalWalkingDuration_min;
WalkingRate_W = OffNominalWalkingRate_W-ExternalWork.Resistance_W;
Time_min = Time_min(:); Activity = string(Activity(:)); Rate_W = Rate_W(:);
validateattributes(Duration_min, {'numeric'}, {'scalar', 'finite', 'positive'});
validateattributes(WalkingRate_W, {'numeric'}, {'scalar', 'finite', 'positive'});
assert(numel(Time_min) == numel(Activity) && numel(Time_min) == numel(Rate_W) ...
    && numel(Time_min) >= 2 && all(isfinite(Time_min)) && all(diff(Time_min) >= 0), ...
    'EVA:ScenarioInputs', 'Use matching arrays and nondecreasing finite times.');
Boundary = Time_min(end) - Duration_min;
assert(Boundary >= Time_min(1), 'EVA:ScenarioDuration', 'Walking duration exceeds the EVA.');
% Retain duplicate transition knots. Add the exact boundary even inside an interval.
Keep = Time_min < Boundary;
ScenarioTime = [Time_min(Keep); Boundary; Time_min(end)];
ScenarioActivity = [Activity(Keep); "Walking - Resistance Reference"; "Walking - Resistance Reference"];
ScenarioRate = [Rate_W(Keep); WalkingRate_W; WalkingRate_W];
ScenarioMetabolic_W = [PhysicalMetabolicRate_W(Keep);OffNominalWalkingRate_W;OffNominalWalkingRate_W];
ScenarioWork_W = [ExternalWork_W(Keep);ExternalWork.Resistance_W;ExternalWork.Resistance_W];
Scenario = table(ScenarioTime, ScenarioActivity, ScenarioMetabolic_W,ScenarioWork_W,ScenarioRate, ...
    'VariableNames', {'Time_min','Activity','MetabolicRate_W','ExternalWork_W','HeatGeneration_W'});
OffNominal = Scenario;

OffNominal_Moisture_Profile = Data_Functions.Physiology.runJOS3Profile(OffNominal.Time_min, OffNominal.HeatGeneration_W, ...
    Body, BodyMicroclimate, JOS3_Step_s, JOS3_Precondition_min);
% Each scenario receives its own complete downstream sizing and reporting.

EVA = struct();
EVA.Inputs = Inputs;
EVA.Nominal = struct('Case', "Nominal", 'Metabolic', ...
    table(Nominal.Time_min, Nominal.Activity, PhysicalMetabolicRate_W,ExternalWork_W,HeatGeneration_W, ...
    'VariableNames', {'Time_min','Activity','MetabolicRate_W','ExternalWork_W','HeatGeneration_W'}), 'Physiology', Nominal_Moisture_Profile);
EVA.OffNominal = struct('Case', "Off-nominal", 'Metabolic', OffNominal, ...
    'Physiology', OffNominal_Moisture_Profile);
EVA.TaskMapping = Metabolic_Task_Mapping;
EVA.SourceProfiles = struct('MetMan', MetMan, 'RawNominal', Nominal);
EVA.Validation = struct('LiteratureData', LiteratureData, 'Comparison', Comparison, 'Metrics', Metrics, ...
    'DynamicData',DynamicData,'DynamicMetrics',DynamicMetrics, ...
    'DynamicCrossValidation',DynamicCrossValidation);
EVA.Nominal.SizingProfile = Data_Functions.Data.buildSizingProfile(EVA, "Nominal");
EVA.OffNominal.SizingProfile = Data_Functions.Data.buildSizingProfile(EVA, "OffNominal");
% Physical transfer tables for downstream thermal-network models.
for TransferCase = ["Nominal","OffNominal"]
    EVA.(TransferCase).ThermalInterface = Data_Functions.Data.buildThermalInterface(EVA,TransferCase);
end
%% Body energy budget and temperature diagnostics
Profiles = {EVA.Nominal.Physiology,EVA.OffNominal.Physiology};
CaseNames = ["Nominal","Off-nominal"];
Terms = ["Prescribed Qgen"; "LCG"; "Air convection"; ...
    "Heat transferred to suit interior (radiation)"; "Skin evaporation"; "Respiration sensible"; ...
    "Respiration latent"; "Body heat storage"; "Closure residual"];
Average = zeros(9, numel(Profiles)); Energy = Average;
HistoryParts = cell(1,numel(Profiles)); TemperatureParts = cell(1,numel(Profiles));
for Index = 1:numel(Profiles)
    P = Profiles{Index};
    dt = (P.EndTime_min-P.StartTime_min) * 60;
    Losses = [P.LCGCooling_W, P.Convection_W, P.Radiation_W, P.SkinEvaporation_W, ...
        P.RespiratorySensible_W, P.RespiratoryLatent_W, P.BodyStorage_W];
    Residual = P.MetabolicHeat_W - sum(Losses, 2);
    Q = [P.MetabolicHeat_W, Losses, Residual];
    assert(max(abs(Residual)) < 1e-5, 'EVA:HeatBalance', 'Body heat balance does not close.');
    Average(:, Index) = (sum(Q .* dt, 1) / sum(dt))';
    Energy(:, Index) = (sum(Q .* dt, 1) / 3600)';
    H = array2table(Q, 'VariableNames', {'Metabolic_W', 'LCG_W', 'Convection_W', ...
        'Radiation_W', 'SkinEvaporation_W', 'RespSensible_W', 'RespLatent_W', ...
        'Storage_W', 'Residual_W'});
    HistoryParts{Index} = [table(repmat(CaseNames(Index), height(P), 1), P.StartTime_min, P.EndTime_min, ...
        'VariableNames', {'Case', 'StartTime_min', 'EndTime_min'}), H];
    TemperatureParts{Index} = table(CaseNames(Index), ...
        P.HeadCore_C(1), P.HeadCore_C(end), min(P.HeadCore_C), max(P.HeadCore_C), ...
        P.MeanSkin_C(1), P.MeanSkin_C(end), P.MeanBodyTemperature_C(end)-P.MeanBodyTemperature_C(1), ...
        max(abs(Residual)), 'VariableNames', {'Case', 'FirstCore_C', 'FinalCore_C', ...
        'MinCore_C', 'MaxCore_C', 'FirstSkin_C', 'FinalSkin_C', ...
        'MeanBodyChangeAfterFirstStep_C', 'MaximumResidual_W'});
end
History = vertcat(HistoryParts{:});
Temperatures = vertcat(TemperatureParts{:});
Summary = table(Terms, Average(:, 1), Average(:, 2), Energy(:, 1), Energy(:, 2), ...
    'VariableNames', {'Term', 'NominalAverage_W', 'OffNominalAverage_W', ...
    'NominalEnergy_Wh', 'OffNominalEnergy_Wh'});

EVA.HeatBalance = struct('Summary',Summary,'History',History,'Temperatures',Temperatures);
%% Nominal/off-nominal summary tables
Names = ["Nominal","OffNominal"];
Stats = zeros(3,2); LCGValues = zeros(27,2); AirValues = cell(1,2);
MoistureValues = cell(1,2); CondensateValues = zeros(4,2);
for Index = 1:2
    Scenario = EVA.(Names(Index)); P = Scenario.Physiology;
    dt = P.EndTime_min-P.StartTime_min;
    M = Scenario.Metabolic;
    MetDt = diff(M.Time_min); Active = MetDt > 0;
    Rates = M.HeatGeneration_W(1:end-1);
    Stats(:,Index) = [min(Rates(Active));sum(Rates.*MetDt)/sum(MetDt);max(Rates(Active))];
    L = EVA.Inputs.Environment.LCG;
    LCGValues(:,Index) = [sum(P.LCGCooling_W.*dt)/sum(dt); max(P.LCGCooling_W); ...
        sum(P.LCGCooling_W.*dt)/60; sum(P.LCGUA_W_K.*dt)/sum(dt); sum(P.LCGMassFlow_kg_s.*dt)/sum(dt)*3600; sum(P.LCGInletTemperature_C.*dt)/sum(dt); ...
        sum(P.LCGOutletTemperature_C.*dt)/sum(dt); ...
        min(P.LCGOutletTemperature_C); max(P.LCGOutletTemperature_C); min(P.LCGUA_W_K); ...
        max(P.LCGUA_W_K); 100*sum(P.LCGOutsideCalibration.*dt)/sum(dt); ...
        min(P.LCGInletTemperature_C); max(P.LCGInletTemperature_C); ...
        max([0;P.BodyStoredHeat_kJ_kg]); ...
        sum(P.HeatStorageLimitExceeded.*dt); sum(P.LCGControlAtMinimum.*dt); ...
        all(~P.HeatStorageLimitExceeded); L.Controller.TargetStoredHeat_kJ_kg; ...
        L.Controller.LimitStoredHeat_kJ_kg; min(P.LCGMassFlow_kg_s)*3600; ...
        max(P.LCGMassFlow_kg_s)*3600; sum(P.LCGFlowAtMaximum.*dt); ...
        max(P.RemainingCoolingShortfall_W); ...
        sum(P.RemainingCoolingShortfall_W.*dt)/sum(dt); ...
        min([0;P.BodyStoredHeat_kJ_kg]);sum(P.HeatStorageBelowZero.*dt)];
    Summary = Data_Functions.Reporting.summarizeEVAScenario(P,EVA.Inputs);
    A = Summary.AirSummary; W = Summary.MoistureSummary;
    AirValues{Index} = [A.Overall(3:end); A.SuitInlet(3:end); A.SuitOutlet(3:end)];
    MoistureValues{Index} = [W.Average_g_min; W.Peak_g_min; W.Total_g];
    CondensateValues(:,Index) = [P.CondensateEnd_g(end); max(P.CondensateEnd_g); ...
        sum(P.Condensation_g_min.*dt); sum(P.CondensateEvaporation_g_min.*dt)];
end
EVA.Reports.MetabolicRates = table(["Qgen minimum";"Qgen average";"Qgen maximum"], Stats(:,1), Stats(:,2), ...
    'VariableNames', {'Statistic','Nominal_W','OffNominal_W'});
EVA.Reports.LCG = table(["Average cooling (W)";"Peak cooling (W)";"Cooling energy (Wh)"; ...
    "Average garment UA (W/K)";"Average water flow (kg/h)";"Average water inlet (C)";"Average water outlet (C)"; ...
    "Minimum water outlet (C)";"Maximum water outlet (C)"; ...
    "Minimum garment UA (W/K)";"Maximum garment UA (W/K)";"Time outside dynamic calibration (%)"; ...
    "Minimum controlled water inlet (C)"; "Maximum controlled water inlet (C)"; ...
    "Peak stored heat (kJ/kg)"; "Time above heat-storage limit (min)"; ...
    "Time at cold control bound (min)"; "Heat-storage screening met (1=yes)"; ...
    "Storage control target (kJ/kg)"; "Storage screening limit (kJ/kg)"; "Minimum LCG flow (kg/h)"; ...
    "Maximum LCG flow (kg/h)"; "Time at maximum LCG flow (min)"; ...
    "Remaining storage-target deficit: peak (W)";"Remaining storage-target deficit: average (W)"; ...
    "Minimum stored heat (kJ/kg)";"Time below zero stored heat (min)"], ...
    LCGValues(:,1), LCGValues(:,2), 'VariableNames', {'Parameter','Nominal','OffNominal'});
EVA.Reports.Air = table(["Overall: "+A.Quantity(3:end); "Suit inlet: "+A.Quantity(3:end); ...
    "Suit outlet: "+A.Quantity(3:end)], AirValues{1}, AirValues{2}, ...
    'VariableNames', {'Parameter','Nominal','OffNominal'});
EVA.Reports.Moisture = table([W.Component+" average (g/min)"; W.Component+" peak (g/min)"; ...
    W.Component+" total (g)"], MoistureValues{1}, MoistureValues{2}, ...
    'VariableNames', {'Parameter','Nominal','OffNominal'});
EVA.Reports.Condensate = table(["Final suit-air liquid (g)";"Peak suit-air liquid (g)"; ...
    "Total condensation (g)";"Total re-evaporation (g)"], CondensateValues(:,1), ...
    CondensateValues(:,2), 'VariableNames', {'Parameter','Nominal','OffNominal'});
EVA.Reports.BodyHeatBalance = EVA.HeatBalance.Summary;
EVA.Reports.LCGLiteratureComparison = EVA.Validation.Comparison;
EVA.Reports.LCGValidationMetrics = EVA.Validation.Metrics;
EVA.Reports.BodyTemperatures = EVA.HeatBalance.Temperatures;
EVA.Reports.LCGDynamicComparison = DynamicData;
EVA.Reports.LCGDynamicMetrics = DynamicMetrics;

%% Apply design FOS only after both simulations and physical reports are complete
EVA.Sizing.Nominal = Data_Functions.Data.buildFactoredSizingCase(EVA,"Nominal");
EVA.Sizing.OffNominal = Data_Functions.Data.buildFactoredSizingCase(EVA,"OffNominal");
%% Thermal-system sizing summary: physical states and separate design allowances
ThermalSummaryParts = cell(1,2);
for Index = 1:2
    CaseName = Names(Index); P = EVA.(CaseName).Physiology;
    dt = P.EndTime_min-P.StartTime_min;
    Quantities = strings(width(P),1); Units = strings(width(P),1);
    Values = zeros(height(P),width(P)); QuantityCount = 0;
    % Include every dimensional physical history, including closure diagnostics.
    % Gross M and external work are intentionally excluded; Qgen is the heat source.
    Suffixes = ["_kJ_kg","_W_K","_kg_s","_g_min","_percent","_W","_C","_g","_kJ"];
    SuffixUnits = ["kJ/kg","W/K","kg/s","g/min","%","W","C","g","kJ"];
    for Variable = string(P.Properties.VariableNames)
        Match = find(cellfun(@(Suffix) endsWith(Variable,Suffix),cellstr(Suffixes)),1);
        if isempty(Match), continue; end
        QuantityCount = QuantityCount+1;
        Quantities(QuantityCount) = Variable;
        Units(QuantityCount) = SuffixUnits(Match);
        Values(:,QuantityCount) = P.(Variable);
    end
    Quantities = Quantities(1:QuantityCount); Units = Units(1:QuantityCount);
    Values = Values(:,1:QuantityCount);
    Quantities(Quantities=="MetabolicHeat_W") = "Body heat generation Qgen";
    Quantities(Quantities=="Radiation_W") = "Heat transferred to suit interior (radiation)";
    Transfer = EVA.(CaseName).ThermalInterface;
    B = Transfer.BoundaryConditions; V = Transfer.Ventilation;
    Extra = [V.DryOxygenFlow_kg_s,V.SupplyTemperature_C, ...
        repmat(EVA.Inputs.Environment.RelativeHumidity_percent,height(P),1), ...
        V.SupplyHumidityRatio,V.ReturnHumidityRatio,V.Pressure_kPa, ...
        P.LCGMassFlow_kg_s*3600, ...
        P.LCGOutletTemperature_C-P.LCGInletTemperature_C, ...
        P.LCGMassFlow_kg_s*EVA.Inputs.Environment.LCG.WaterCp_J_kgK, ...
        P.Convection_W+P.RespiratorySensible_W, ...
        P.SkinEvaporation_W+P.RespiratoryLatent_W];
    ExtraNames = ["Ventilation dry oxygen flow";"Supply air temperature";"Supply air RH"; ...
        "Supply humidity ratio";"Return humidity ratio";"Suit gas pressure"; ...
        "LCG water flow";"LCG outlet minus inlet temperature";"LCG water heat capacity rate"; ...
        "Body to ventilation sensible heat";"Body to ventilation latent heat"];
    ExtraUnits = ["kg/s";"C";"%";"kg/kg dry oxygen";"kg/kg dry oxygen";"kPa"; ...
        "kg/h";"K";"W/K";"W";"W"];
    RadiantCount = size(B.AssumedInnerRadiantTemperature_C,2);
    AllExtra = [Extra,B.AssumedInnerRadiantTemperature_C];
    AllExtraNames = [ExtraNames;"Inner radiant boundary temperature: component "+(1:RadiantCount)'];
    AllExtraUnits = [ExtraUnits;repmat("C",RadiantCount,1)];
    PhysicalSummary = Data_Functions.Reporting.summarizeThermalSeries( ...
        [Quantities;AllExtraNames],[Units;AllExtraUnits],"Physical",[Values,AllExtra],dt,CaseName);
    % Cumulative energy extrema include EVA start; average integrates the
    % piecewise-linear accumulated-energy history, not just endpoint values.
    EnergyRates = [P.MetabolicHeat_W,P.LCGCooling_W,P.Radiation_W, ...
        P.Convection_W+P.RespiratorySensible_W,P.SkinEvaporation_W+P.RespiratoryLatent_W];
    EndEnergy_Wh = cumsum(EnergyRates.*dt/60,1);
    StartEnergy_Wh = [zeros(1,5);EndEnergy_Wh(1:end-1,:)];
    EnergyNames = ["Cumulative Qgen energy";"Cumulative LCG heat pickup"; ...
        "Cumulative heat to suit interior";"Cumulative ventilation sensible heat"; ...
        "Cumulative ventilation latent heat"];
    EnergySummary = Data_Functions.Reporting.summarizeThermalSeries(EnergyNames, ...
        repmat("Wh",5,1),"Physical cumulative energy", ...
        (StartEnergy_Wh+EndEnergy_Wh)/2,dt,CaseName);
    CaseColumns = CaseName+["Minimum","Average","Maximum"];
    EnergySummary{:,CaseColumns(1)} = min([zeros(1,5);EndEnergy_Wh],[],1)';
    EnergySummary{:,CaseColumns(3)} = max([zeros(1,5);EndEnergy_Wh],[],1)';
    Loads = EVA.Sizing.(CaseName).ThermalPathwayLoads;
    LoadNames = string(Loads.Properties.VariableNames(3:end))';
    DesignSummary = Data_Functions.Reporting.summarizeThermalSeries(LoadNames, ...
        repmat("W",numel(LoadNames),1),"FOS design allowance (already factored)", ...
        Loads{:,3:end},dt,CaseName);
    ThermalSummaryParts{Index} = [PhysicalSummary;EnergySummary;DesignSummary];
end
EVA.Reports.ThermalSystemSizing = ThermalSummaryParts{1};
OffColumns = ["OffNominalMinimum","OffNominalAverage","OffNominalMaximum"];
assert(isequal(ThermalSummaryParts{1}(:,1:3),ThermalSummaryParts{2}(:,1:3)), ...
    'EVA:ThermalSummaryRows','Thermal summary cases must have matching quantities.');
EVA.Reports.ThermalSystemSizing{:,OffColumns} = ThermalSummaryParts{2}{:,OffColumns};

% The original cases/reports/plots remain unfactored physiological results.
Data_Functions.Data.validateEVAInterface(EVA);

Data.Simulation = EVA;
% Keep only the current simulation; clear the previous hardware result.
Data.Hardware = struct();
save(DataFile,'Data','-v7');

%% Report and plot only after calculations and data saving finish
Data_Functions.Reporting.printEVAReports(EVA.Reports);
if Inputs.PlotResults
    ScenarioNames = ["Nominal", "Off-nominal"];
    ScenarioProfiles = {EVA.Nominal.Physiology, EVA.OffNominal.Physiology};
    Nominal_Moisture_Profile = EVA.Nominal.Physiology;
    OffNominal_Moisture_Profile = EVA.OffNominal.Physiology;
    MetMan = EVA.SourceProfiles.MetMan; Nominal = EVA.Nominal.Metabolic;
    OffNominal = EVA.OffNominal.Metabolic;
    Nominal_Time_hours = Nominal.Time_min/60;
    HeatGeneration_W = Nominal.HeatGeneration_W;
    Nominal_MetabolicRate_W = EVA.SourceProfiles.RawNominal.MetabolicRate_Btu_hr/3.412141633;
    OffNominalWalkingDuration_min = EVA.Inputs.OffNominalWalkingDuration_min;
    BodyHeatHistory = EVA.HeatBalance.History;
%% Metabolic Model - Graphs
    % These comparisons use the two immutable physiological profiles, once only.
    MetMan_Time_hours = [MetMan.StartTime_hr; MetMan.EndTime_hr(end)];
    MetMan_MetabolicRate_W = [MetMan.MetabolicRate_kJ_hr; MetMan.MetabolicRate_kJ_hr(end)] / 3.6;

    % Source Profiles
    figure(1); clf;
    set(gcf, 'Name', '1. Metabolic Sources', 'NumberTitle', 'off');
    stairs(MetMan_Time_hours, MetMan_MetabolicRate_W);
    hold on;
    plot(Nominal_Time_hours, Nominal_MetabolicRate_W);
    title('Source Metabolic Profiles: M before Work Correction');
    legend('MetMan', 'Raw Nominal');
    xlabel('Time (hours)');
    ylabel('Metabolic Rate (W)');
    grid on;

    % Nominal Mars EVA
    figure(2); clf;
    set(gcf, 'Name', '2. Nominal Mars EVA', 'NumberTitle', 'off');
    tiledlayout(3, 1);
    sgtitle('Nominal Mars EVA: 95th-percentile male', 'FontSize', 16, 'FontWeight', 'bold');
    nexttile;
    stairs(Nominal_Time_hours, HeatGeneration_W);
    title('Mars Body Heat Generation: Qgen = M - Wext');
    xlabel('Time (hours)');
    ylabel('Qgen (W)');
    grid on;
    nexttile;
    stairs([Nominal_Moisture_Profile.StartTime_min; Nominal_Moisture_Profile.EndTime_min(end)] / 60, ...
        [Nominal_Moisture_Profile.VaporToPLSS_g_min; Nominal_Moisture_Profile.VaporToPLSS_g_min(end)]);
    title('Suit Outlet Moisture Rate');
    xlabel('Time (hours)');
    ylabel('Vapor rate (g/min)');
    grid on;
    nexttile;
    stairs([Nominal_Moisture_Profile.StartTime_min; Nominal_Moisture_Profile.EndTime_min(end)] / 60, ...
        [Nominal_Moisture_Profile.CondenserInletTemperature_C; Nominal_Moisture_Profile.CondenserInletTemperature_C(end)]);
    title('Suit Outlet Air Temperature');
    xlabel('Time (hours)');
    ylabel('Air temperature (C)');
    grid on;

    % LCG cooling comparison (created after figures 1 and 2).
    figure(3); clf;
    set(gcf, 'Name', '3. LCG Simulation Comparison', 'NumberTitle', 'off');
    tiledlayout(3, 1);
    LCGCaseColors = lines(numel(ScenarioNames));
    for LCGCase = 1:2
        P = ScenarioProfiles{LCGCase};
        nexttile(1); hold on;
        stairs([P.StartTime_min; P.EndTime_min(end)] / 60, ...
            [P.LCGCooling_W; P.LCGCooling_W(end)], 'LineWidth', 1.3, ...
            'Color',LCGCaseColors(LCGCase,:),'DisplayName',ScenarioNames(LCGCase)+" LCG");
        nexttile(2); hold on;
        stairs([P.StartTime_min;P.EndTime_min(end)]/60, ...
            [P.LCGInletTemperature_C;P.LCGInletTemperature_C(end)],'LineWidth',1.3);
        nexttile(3); hold on;
        stairs([P.StartTime_min;P.EndTime_min(end)]/60, ...
            [P.LCGMassFlow_kg_s;P.LCGMassFlow_kg_s(end)]*3600,'LineWidth',1.3);
    end
    nexttile(1); ylabel('Cooling duty (W)'); grid on;
    legend('Location','best');
    nexttile(2); ylabel('LCG water inlet (C)'); xlabel('EVA time (hours)'); grid on;
    legend(ScenarioNames, 'Location', 'best');
    nexttile(3); ylabel('LCG water flow (kg/h)'); xlabel('EVA time (hours)'); grid on;
    legend(ScenarioNames, 'Location', 'best');
    sgtitle('LCG Cooling and Water Control: Nominal and Off-Nominal EVA');

    % Nominal Astronaut Vapor Sources
    NominalPlotTime_hr = [Nominal_Moisture_Profile.StartTime_min; Nominal_Moisture_Profile.EndTime_min(end)] / 60;
    NominalComponentRates_g_min = Nominal_Moisture_Profile{:, ...
        {'Respiratory_g_min', 'SweatEvaporated_g_min', 'SkinDiffusion_g_min', ...
        'RetainedEvaporation_g_min', 'VaporToSuit_g_min'}};
    figure(4); clf;
    set(gcf, 'Name', '4. Astronaut Moisture', 'NumberTitle', 'off');
    VaporLines = stairs(NominalPlotTime_hr, ...
        [NominalComponentRates_g_min; NominalComponentRates_g_min(end, :)], ...
        'LineStyle', '--', 'LineWidth', 1.1);
    % Distinguish the solid green total from the thinner dashed components.
    set(VaporLines(end), 'Color', [0, 0.6, 0], 'LineStyle', '-', 'LineWidth', 2.8);
    title('Nominal EVA Astronaut Vapor Sources');
    legend('Respiration', 'Fresh sweat evaporation', 'Skin diffusion', 'Retained sweat evaporation', 'Total astronaut vapor');
    xlabel('Time (hours)');
    ylabel('Vapor Rate (g/min)');
    grid on;

    % Five stations comprise three regional means and the inlet/return boundaries.
    figure(5); clf;
    set(gcf, 'Name', '5. Suit Air Temperature and RH', 'NumberTitle', 'off');
    tiledlayout(2, 2);
    AirProfiles = {Nominal_Moisture_Profile, OffNominal_Moisture_Profile};
    AirCaseNames = ["Nominal", "Off-nominal"];
    AirStationNames = {'Suit inlet', 'Head/neck mean', 'Torso/arms mean', ...
        'Legs mean', 'Suit outlet / PLSS return'};
    for AirCaseIndex = 1:2
        AirProfile = AirProfiles{AirCaseIndex};
        AirDuration_min = AirProfile.EndTime_min - AirProfile.StartTime_min;
        AirTemperatures_C = [repmat(EVA.Inputs.Environment.AirTemperature_C, height(AirProfile), 1), ...
            AirProfile{:, {'NeckAirTemperature_C', 'TorsoAirTemperature_C', 'LegAirTemperature_C'}}, ...
            AirProfile.CondenserInletTemperature_C];
        AirRH_percent = [repmat(EVA.Inputs.Environment.RelativeHumidity_percent, height(AirProfile), 1), ...
            AirProfile{:, {'NeckAirRH_percent', 'TorsoAirRH_percent', 'LegAirRH_percent'}}, ...
            AirProfile.CondenserInletRH_percent];
        % Weight averages by timestep duration over the complete EVA.
        AirTemperatureStats_C = [min(AirTemperatures_C, [], 1); ...
            sum(AirTemperatures_C .* AirDuration_min, 1) / sum(AirDuration_min); ...
            max(AirTemperatures_C, [], 1)]';
        AirRHStats_percent = [min(AirRH_percent, [], 1); ...
            sum(AirRH_percent .* AirDuration_min, 1) / sum(AirDuration_min); ...
            max(AirRH_percent, [], 1)]';
        nexttile(AirCaseIndex);
        plot(1:5, AirTemperatureStats_C, '-o', 'LineWidth', 1.2);
        title(AirCaseNames(AirCaseIndex) + " EVA: Air Temperature");
        ylabel('Temperature (C)'); xlabel('Suit zone'); grid on;
        xticks(1:5); xticklabels(AirStationNames); xtickangle(20);
        legend('Minimum', 'Time-weighted average', 'Maximum', 'Location', 'best');
        nexttile(AirCaseIndex + 2);
        plot(1:5, AirRHStats_percent, '-o', 'LineWidth', 1.2);
        title(AirCaseNames(AirCaseIndex) + " EVA: Relative Humidity");
        ylabel('Relative humidity (%)'); xlabel('Suit zone'); grid on;
        xticks(1:5); xticklabels(AirStationNames); xtickangle(20);
        legend('Minimum', 'Time-weighted average', 'Maximum', 'Location', 'best');
    end
    sgtitle('Whole-EVA Suit Air Temperature and RH by Zone');
%% Off-Nominal EVA - Separate Comparison Graph
    figure(6); clf;
    set(gcf, 'Name', '6. Off-Nominal EVA Comparison', 'NumberTitle', 'off');
    tiledlayout(3, 1);
    nexttile;
    stairs(Nominal.Time_min / 60, HeatGeneration_W, 'LineWidth', 1.2); hold on;
    stairs(OffNominal.Time_min / 60, OffNominal.HeatGeneration_W, '--', 'LineWidth', 1.5);
    ylabel('Qgen (W)'); title('Body Heat Generation after External Work');
    legend('Nominal', 'Off-nominal', 'Location', 'best');
    xline((OffNominal.Time_min(end) - OffNominalWalkingDuration_min) / 60, ':', 'Walking start', 'HandleVisibility', 'off'); grid on;
    nexttile;
    plot(Nominal_Moisture_Profile.EndTime_min / 60, Nominal_Moisture_Profile.VaporToPLSS_g_min, 'LineWidth', 1.2); hold on;
    plot(OffNominal_Moisture_Profile.EndTime_min / 60, OffNominal_Moisture_Profile.VaporToPLSS_g_min, '--', 'LineWidth', 1.5);
    ylabel('Net vapor (g/min)'); title('Moisture Delivered to PLSS');
    legend('Nominal', 'Off-nominal', 'Location', 'best');
    xline((OffNominal.Time_min(end) - OffNominalWalkingDuration_min) / 60, ':', 'HandleVisibility', 'off'); grid on;
    nexttile;
    plot(Nominal_Moisture_Profile.EndTime_min / 60, Nominal_Moisture_Profile.CondenserInletTemperature_C, 'LineWidth', 1.2); hold on;
    plot(OffNominal_Moisture_Profile.EndTime_min / 60, OffNominal_Moisture_Profile.CondenserInletTemperature_C, '--', 'LineWidth', 1.5);
    ylabel('Air temperature (C)'); xlabel('EVA time (hours)'); title('Suit Outlet Temperature');
    legend('Nominal', 'Off-nominal', 'Location', 'best');
    xline((OffNominal.Time_min(end) - OffNominalWalkingDuration_min) / 60, ':', 'HandleVisibility', 'off'); grid on;
    sgtitle('Off-Nominal EVA: Final 4 hr 10 min Walking at Resistance Reference Rate');

    Data_Functions.Reporting.plotBodyHeatBalance(BodyHeatHistory,EVA.Inputs,"Nominal",7);
    Data_Functions.Reporting.plotBodyHeatBalance(BodyHeatHistory,EVA.Inputs,"Off-nominal",8);
    figure(9); clf;
    set(gcf, 'Name', '9. Dynamic LCG Conductance Validation', 'NumberTitle', 'off');
    tiledlayout(1,2,'TileSpacing','compact');
    nexttile;
    DynamicHeldOut = EVA.Validation.DynamicData(EVA.Validation.DynamicData.Split == "Held-out",:);
    bar(1:height(DynamicHeldOut),[DynamicHeldOut.UA_W_K,DynamicHeldOut.PredictedUA_W_K]);
    xticks(1:height(DynamicHeldOut));
    xticklabels(compose('%.0f W',DynamicHeldOut.Metabolic_W));
    xlabel(sprintf('Held-out NASA day %g operating point',EVA.Inputs.LCGFitSettings.HeldOutDay)); ylabel('Garment UA (W/K)');
    legend('Published measurement','Selected bounded fit','Location','best'); grid on;
    title(sprintf('Dynamic-UA %s: Held-out RMSE %.2f W/K', ...
        EVA.Validation.DynamicMetrics.SelectedFamily,EVA.Validation.DynamicMetrics.HeldOutUARMSE_W_K));

    nexttile;
    FitLCG = EVA.Inputs.Environment.LCG;
    FitLCG.Model = "LiteratureDynamicUA";
    Fit = FitLCG.DynamicFit;
    FitData = EVA.Validation.DynamicData;
    FitDemand_W = linspace(Fit.MetabolicBounds_W(1),max(FitData.Metabolic_W),150)';
    FitFlows_kg_h = [Fit.FlowBounds_kg_s(1)*3600, ...
        EVA.Inputs.Environment.LCG.MassFlow_kg_s*3600, ...
        FitLCG.Controller.MaximumFlow_kg_h];
    hold on;
    for Curve = 1:numel(FitFlows_kg_h)
        FitLCG.MassFlow_kg_s = FitFlows_kg_h(Curve)/3600;
        CurveUA_W_K = Data_Functions.Physiology.lcgGarmentUA(FitLCG,FitDemand_W);
        plot(FitDemand_W,CurveUA_W_K,'LineWidth',1.5, ...
            'DisplayName',sprintf('Fit at %.1f kg/h',FitFlows_kg_h(Curve)));
    end
    Calibration = FitData.Split == "Calibration";
    scatter(FitData.Metabolic_W(Calibration),FitData.UA_W_K(Calibration), ...
        45,'k','filled','DisplayName','Calibration: varying flow');
    scatter(FitData.Metabolic_W(~Calibration),FitData.UA_W_K(~Calibration), ...
        65,'r','filled','DisplayName','Held-out: varying flow');
    xline(Fit.MetabolicBounds_W(2),'k:','Calibration upper bound','HandleVisibility','off');
    hold off;
    xlabel('NASA calibration metabolic rate M (W)'); ylabel('Garment UA (W/K)');
    title('Bounded Linear UA Fit: Fixed-Flow Slices');
    legend('Location','best'); grid on;

    figure(1);



end
