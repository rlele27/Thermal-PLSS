function [Model, MoistureRate_g_s, Output] = stepJOS3(Model, Environment, ActivityRatio, Step_s, Passive)
% Advance the native JOS-3 state by one implicit temperature step.
% ActivityRatio is total basal-plus-work demand divided by basal metabolism.
% Rates use the starting temperatures; returned temperatures end the step.
% Port of TanabeLab/JOS-3, commit 3c74ee2 (MIT). See LICENSE and README.md.
if nargin < 5
    Passive = false;
end
validateattributes(Step_s, {'numeric'}, {'scalar', 'finite', 'positive'});
validateattributes(ActivityRatio, {'numeric'}, {'scalar', 'finite', '>=', 1});
P = Model.Parameters;
C = P.Coefficients;
Core_C = Model.Temperature_C(P.Node(:, 4));
Skin_C = Model.Temperature_C(P.Node(:, 7));

%% Environment and Heat Transfer
Air_C = segmentValues(Environment.AirTemperature_C);
Radiant_C = segmentValues(Environment.RadiantTemperature_C);
Humidity_percent = segmentValues(Environment.RelativeHumidity_percent); % Bulk / inspired air.
AirSpeed_m_s = segmentValues(Environment.AirSpeed_m_s);
Clothing_clo = segmentValues(Environment.Clothing_clo);
Permeation = segmentValues(Environment.VaporPermeationEfficiency);
Pressure_kPa = Environment.Pressure_kPa;
validateattributes(Pressure_kPa, {'numeric'}, {'scalar', 'finite', 'positive'});
assert(all(Humidity_percent >= 0 & Humidity_percent <= 100) && ...
    all(AirSpeed_m_s >= 0) && all(Clothing_clo >= 0) && all(Permeation > 0 & Permeation <= 1), ...
    'JOS3:Environment', 'Invalid humidity, air speed, clothing or vapor permeation.');
switch lower(Environment.Posture)
    case 'standing'
        NaturalConvection = C.NaturalConvectionStanding;
        Radiation = C.RadiationStanding;
    case {'sitting', 'sedentary'}
        NaturalConvection = C.NaturalConvectionSitting;
        Radiation = C.RadiationSitting;
    case {'lying', 'supine'}
        NaturalConvection = C.LyingConvectionScale .* abs(Air_C - Skin_C).^C.LyingConvectionExponent;
        Radiation = C.RadiationLying;
    otherwise
        error('JOS3:Posture', 'Posture must be standing, sitting or lying.');
end
ForcedConvection = C.ForcedConvectionScale .* AirSpeed_m_s.^C.ForcedConvectionExponent;
Convection = NaturalConvection;
Forced = AirSpeed_m_s >= 0.2;
Convection(Forced) = ForcedConvection(Forced);
MeanAirSpeed_m_s = weightedMean(AirSpeed_m_s, C.StandardArea_m2);
Convection = Convection * max(3, 8.600001 * MeanAirSpeed_m_s^0.53) / weightedMean(Convection, C.StandardArea_m2);
Radiation = Radiation * 4.7 / weightedMean(Radiation, C.StandardArea_m2);
ClothingAreaFactor = 1 + 0.2 * Clothing_clo;
Clothed = Clothing_clo >= 0.5;
ClothingAreaFactor(Clothed) = 1.05 + 0.1 * Clothing_clo(Clothed);
ClothingResistance_m2_K_W = 0.155 * Clothing_clo;
CorrectedConvection = Convection * (Pressure_kPa / 101.33)^0.55;
% Use the same pressure-corrected coefficient in the balance and its split.
Operative_C = (CorrectedConvection .* Air_C + Radiation .* Radiant_C) ./ (CorrectedConvection + Radiation);
DryResistance_m2_K_W = 1 ./ (CorrectedConvection + Radiation) ./ ClothingAreaFactor + ClothingResistance_m2_K_W;
EvaporativeTransfer = Convection * 16.5 * (101.33 / Pressure_kPa)^0.45;
WetResistance_m2_kPa_W = 1 ./ EvaporativeTransfer ./ ClothingAreaFactor ...
    + ClothingResistance_m2_K_W ./ (16.5 * Permeation);

%% Thermal Control Signals
CoreError_C = Core_C - Model.CoreSetpoint_C;
SkinError_C = Skin_C - Model.SkinSetpoint_C;
if Passive
    CoreError_C(:) = 0;
    SkinError_C(:) = 0;
end
WarmSignal_C = sum(max(SkinError_C, 0) .* C.SkinReceptors);
ColdSignal_C = sum(max(-SkinError_C, 0) .* C.SkinReceptors);
SkinSignal_C = WarmSignal_C - ColdSignal_C;

%% Sweating and Evaporation
AirVaporPressure_kPa = saturationPressure(Air_C) .* Humidity_percent / 100;
SkinVaporPressure_kPa = saturationPressure(Skin_C);
% This extension handles evaporation only, not condensation onto the body.
MaximumEvaporation_W = max(0, (SkinVaporPressure_kPa - AirVaporPressure_kPa) ...
    ./ WetResistance_m2_kPa_W .* P.Area_m2);
SweatSignal_W = max(371.2 * CoreError_C(1) + 33.64 * SkinSignal_C, 0) * P.AreaRatio;
SecretedSweatEquivalent_W = C.SweatDistribution .* SweatSignal_W .* P.SweatAgeFactor .* 2.^(SkinError_C / 10);
Wettedness = min(0.06 + 0.94 * SecretedSweatEquivalent_W ./ max(MaximumEvaporation_W, eps), 1);
SkinEvaporation_W = Wettedness .* MaximumEvaporation_W;
EffectiveSweat_W = (Wettedness - 0.06) / 0.94 .* MaximumEvaporation_W;

%% Vapor Sources and Retained Sweat
% ASSUMPTION: unevaporated sweat remains available for later evaporation.
% No runoff, liquid collection, garment capacity or intersegment wicking model.
LatentHeat_J_g = 2418;
Sweat_g_s = SecretedSweatEquivalent_W / LatentHeat_J_g;
EvaporatedSweat_g_s = EffectiveSweat_W / LatentHeat_J_g;
Diffusion_g_s = (SkinEvaporation_W - EffectiveSweat_W) / LatentHeat_J_g;
RetainedStart_g = zeros(17, 1);
RetainedEvaporation_g_s = zeros(17, 1);
TrackLiquid = isfield(Environment, 'TrackRetainedSweat') && Environment.TrackRetainedSweat && ~Passive;
if TrackLiquid
    if ~isfield(Model, 'RetainedLiquid_g')
        Model.RetainedLiquid_g = zeros(17, 1);
    end
    RetainedStart_g = Model.RetainedLiquid_g;
    Available_g = RetainedStart_g + max(0, Sweat_g_s - EvaporatedSweat_g_s) * Step_s;
    SpareEvaporation_g_s = max(0, MaximumEvaporation_W - SkinEvaporation_W) / LatentHeat_J_g;
    RetainedEvaporation_g_s = min(Available_g / Step_s, SpareEvaporation_g_s);
    Model.RetainedLiquid_g = max(0, Available_g - RetainedEvaporation_g_s * Step_s);
    % ASSUMPTION: retained sweat is at skin temperature; no separate garment node.
    SkinEvaporation_W = SkinEvaporation_W + RetainedEvaporation_g_s * LatentHeat_J_g;
end

%% Simplified LCG Boundary - PLSS LOAD ASSUMPTION
% The supplied garment removes an assumed fraction of activity heat while
% water is below skin temperature. Garment hardware and control are out of scope.
LCGConductance_W_K = zeros(17, 1);
LCGInlet_C = 0;
if isfield(Environment, 'LCG') && Environment.LCG.Enabled && ~Passive
    LCG = Environment.LCG;
    validateattributes(LCG.InletTemperature_C, {'numeric'}, {'scalar', 'finite'});
    validateattributes(LCG.ActivityCoolingFraction, {'numeric'}, {'scalar', 'finite', '>=', 0, '<=', 1});
    validateattributes(LCG.BaselineMetabolism_W, {'numeric'}, {'scalar', 'finite', 'nonnegative'});
    LCGInlet_C = LCG.InletTemperature_C;
    % Fixed body-area allocation excludes head, neck, hands and feet.
    ContactArea_m2 = P.LCGContactArea_m2;
    ContactArea_m2(Skin_C <= LCGInlet_C) = 0;
    if sum(ContactArea_m2) > 0
        MeanContact_C = weightedMean(Skin_C, ContactArea_m2);
        ReferenceSkin_C = weightedMean(Model.SkinSetpoint_C, ContactArea_m2);
        TemperatureFactor = min(1, max(0, (MeanContact_C - LCGInlet_C) ...
            / max(ReferenceSkin_C - LCGInlet_C, eps)));
        MetabolicDemand_W = ActivityRatio * P.BasalTotal_W;
        LCGTarget_W = LCG.ActivityCoolingFraction * max(0, MetabolicDemand_W - LCG.BaselineMetabolism_W) ...
            * TemperatureFactor;
        TotalConductance_W_K = LCGTarget_W / max(MeanContact_C - LCGInlet_C, eps);
        LCGConductance_W_K = TotalConductance_W_K * ContactArea_m2 / sum(ContactArea_m2);
    end
end

%% Skin and Arteriovenous Blood Flow
DilationSignal = max(100.5 * CoreError_C(1) + 6.4 * SkinSignal_C, 0);
ConstrictionSignal = max(-10.8 * CoreError_C(1) - 10.8 * SkinSignal_C, 0);
DilationAgeFactor = ones(17, 1);
if P.Body.Age_years >= 60
    DilationAgeFactor = C.DilationAgeFactor;
end
SkinFlow_L_hr = (1 + C.SkinDilation .* DilationAgeFactor * DilationSignal) ...
    ./ (1 + C.SkinConstriction * ConstrictionSignal) .* C.BasalSkinFlow_L_hr ...
    .* 2.^(SkinError_C / 6) * P.BloodFlowRatio;
TrunkError_C = weightedMean(CoreError_C(3:5), [10.2975; 9.3935; 13.834]);
MeanSkinError_C = weightedMean(SkinError_C, C.StandardArea_m2);
HandOpening = min(max(0.265 * (MeanSkinError_C + 0.43) + 0.953 * (TrunkError_C + 0.1905) + 0.9126, 0), 1);
FootOpening = min(max(0.265 * (MeanSkinError_C - 0.997) + 0.953 * (TrunkError_C + 0.0095) + 0.9126, 0), 1);
HandFlow_L_hr = 1.71 * P.BloodFlowRatio * HandOpening;
FootFlow_L_hr = 2.16 * P.BloodFlowRatio * FootOpening;
if Passive
    HandFlow_L_hr = 0;
    FootFlow_L_hr = 0;
end

%% Shivering Thermogenesis
ShiveringSignal_W = max(24.36 * ColdSignal_C * (-CoreError_C(1)), 0);
Shivering_W = C.ShiveringDistribution * P.AreaRatio * P.ShiveringAgeFactor * ShiveringSignal_W;

%% Nonshivering Thermogenesis
NonshiveringSignal_W = min(2.8 * ColdSignal_C, P.NonshiveringLimit_W);
Nonshivering_W = P.AreaRatio * C.NonshiveringDistribution * NonshiveringSignal_W;

%% Tissue Heat Production and Perfusion
Work_W = (ActivityRatio - 1) * P.BasalTotal_W * C.WorkDistribution;
Activity_W = Work_W + Shivering_W;
HasMuscle = P.HasMuscle;
TissueHeat_W = P.BasalHeat_W;
TissueHeat_W(~HasMuscle, 1) = TissueHeat_W(~HasMuscle, 1) + Activity_W(~HasMuscle);
TissueHeat_W(HasMuscle, 2) = TissueHeat_W(HasMuscle, 2) + Activity_W(HasMuscle);
TissueHeat_W(:, 1) = TissueHeat_W(:, 1) + Nonshivering_W;
MetabolicRate_W = sum(TissueHeat_W, 'all');
TissueFlow_L_hr = P.BloodFlowRatio * [C.BasalCoreFlow_L_hr, C.BasalMuscleFlow_L_hr, C.BasalFatFlow_L_hr];
TissueFlow_L_hr(~HasMuscle, 1) = TissueFlow_L_hr(~HasMuscle, 1) + Activity_W(~HasMuscle) / 1.163;
TissueFlow_L_hr(HasMuscle, 2) = TissueFlow_L_hr(HasMuscle, 2) + Activity_W(HasMuscle) / 1.163;
TissueFlow_L_hr(:, 4) = SkinFlow_L_hr;
RespiratorySensible_W = 0.0014 * MetabolicRate_W * (34 - Air_C(1));
RespiratoryLatent_W = 0.0173 * MetabolicRate_W * (5.87 - AirVaporPressure_kPa(1));

%% Implicit Heat Balance
BloodTransport_W_K = jos3Bloodflow(P, TissueFlow_L_hr, HandFlow_L_hr, FootFlow_L_hr);
Transport = (P.Conductance_W_K + BloodTransport_W_K) ./ P.Capacity_J_K * Step_s;
Boundary = zeros(P.NumberOfNodes, 1);
Boundary(P.Node(:, 7)) = P.Area_m2 ./ DryResistance_m2_K_W;
Boundary = Boundary ./ P.Capacity_J_K * Step_s;
LCGBoundary = zeros(P.NumberOfNodes, 1);
LCGBoundary(P.Node(:, 7)) = LCGConductance_W_K;
LCGBoundary = LCGBoundary ./ P.Capacity_J_K * Step_s;
TemperatureMatrix = -Transport + diag(sum(Transport, 2) + Boundary + LCGBoundary + 1);
Heat_W = zeros(P.NumberOfNodes, 1);
Heat_W(P.TissueNodes(P.TissueMask)) = TissueHeat_W(P.TissueMask);
Heat_W(P.Node(3, 4)) = Heat_W(P.Node(3, 4)) - RespiratorySensible_W - RespiratoryLatent_W;
Heat_W(P.Node(:, 7)) = Heat_W(P.Node(:, 7)) - SkinEvaporation_W;
Ambient_C = zeros(P.NumberOfNodes, 1);
Ambient_C(P.Node(:, 7)) = Operative_C;
RightHandSide_C = Model.Temperature_C + Boundary .* Ambient_C + LCGBoundary * LCGInlet_C + Heat_W ./ P.Capacity_J_K * Step_s;
PreviousTemperature_C = Model.Temperature_C;
Model.Temperature_C = TemperatureMatrix \ RightHandSide_C;
assert(all(isfinite(Model.Temperature_C)), 'JOS3:NumericalFailure', 'Nonfinite body temperature.');

%% Separated Moisture and Cooling Outputs
% Generation counts each new gram once. Vapor can include old retained water.
Respiratory_g_s = RespiratoryLatent_W / LatentHeat_J_g;
MoistureRate_g_s = sum(Sweat_g_s + Diffusion_g_s) + Respiratory_g_s;
Output.Respiratory_g_s = Respiratory_g_s;
Output.SweatSecreted_g_s = sum(Sweat_g_s);
Output.SweatEvaporated_g_s = sum(EvaporatedSweat_g_s);
Output.SkinDiffusion_g_s = sum(Diffusion_g_s);
Output.RetainedEvaporation_g_s = sum(RetainedEvaporation_g_s);
Output.UnevaporatedSweat_g_s = sum(max(0, Sweat_g_s - EvaporatedSweat_g_s));
Output.VaporToSuit_g_s = Respiratory_g_s + sum(EvaporatedSweat_g_s + Diffusion_g_s + RetainedEvaporation_g_s);
Output.SkinVaporBySegment_g_s = EvaporatedSweat_g_s + Diffusion_g_s + RetainedEvaporation_g_s;
Output.RetainedStart_g = sum(RetainedStart_g);
Output.RetainedEnd_g = sum(RetainedStart_g);
if TrackLiquid
    Output.RetainedEnd_g = sum(Model.RetainedLiquid_g);
end
Output.LCGCooling_W = sum(LCGConductance_W_K .* (Model.Temperature_C(P.Node(:, 7)) - LCGInlet_C));
Output.SkinEvaporation_W = sum(SkinEvaporation_W);
% Estimate RH at the outer garment surface from the air-film vapor drop.
% Garment and air resistance already control evaporation; do not apply twice.
AirWetResistance = 1 ./ EvaporativeTransfer ./ ClothingAreaFactor;
GarmentVaporPressure_kPa = AirVaporPressure_kPa + SkinEvaporation_W ./ P.Area_m2 .* AirWetResistance;
% Diagnostic: body storage must equal tissue heat minus all boundary losses.
DryLossBySegment_W = P.Area_m2 ./ DryResistance_m2_K_W ...
    .* (Model.Temperature_C(P.Node(:, 7)) - Operative_C);
DryLoss_W = sum(DryLossBySegment_W);
GarmentTemperature_C = Model.Temperature_C(P.Node(:, 7)) ...
    - DryLossBySegment_W ./ P.Area_m2 .* ClothingResistance_m2_K_W;
GarmentRH_percent = 100 * GarmentVaporPressure_kPa ./ saturationPressure(GarmentTemperature_C);
Output.LocalGarmentRH_percent = weightedMean(min(100, GarmentRH_percent), P.Area_m2);
% Preserve the uncapped value to identify possible condensation in the garment.
Output.MaximumGarmentRH_percent = max(GarmentRH_percent);
% Split the modelled dry loss between air convection and radiation.
% Equal air/radiant temperatures reduce this to the conductance fractions.
Output.ConvectionBySegment_W = DryLossBySegment_W .* CorrectedConvection ./ (CorrectedConvection + Radiation) ...
    + P.Area_m2 .* ClothingAreaFactor .* CorrectedConvection .* (Operative_C - Air_C);
Output.Convection_W = sum(Output.ConvectionBySegment_W);
Output.RespiratorySensible_W = RespiratorySensible_W;
Storage_W = sum(P.Capacity_J_K .* (Model.Temperature_C - PreviousTemperature_C)) / Step_s;
Output.EnergyBalanceResidual_W = Storage_W - (sum(Heat_W) - DryLoss_W - Output.LCGCooling_W);
Output.MeanSkin_C = weightedMean(Model.Temperature_C(P.Node(:, 7)), P.Area_m2);
Output.HeadCore_C = Model.Temperature_C(P.Node(1, 4));
end

function Values = segmentValues(Input)
validateattributes(Input, {'numeric'}, {'real', 'finite', 'nonempty'});
assert(isscalar(Input) || numel(Input) == 17, 'JOS3:Segments', 'Use a scalar or 17 segment values.');
Values = Input(:);
if isscalar(Values)
    Values = repmat(Values, 17, 1);
end
end

function Mean = weightedMean(Values, Weights)
Mean = sum(Values .* Weights) / sum(Weights);
end

function Pressure_kPa = saturationPressure(Temperature_C)
Pressure_kPa = exp(16.6536 - 4030.183 ./ (Temperature_C + 235));
end
