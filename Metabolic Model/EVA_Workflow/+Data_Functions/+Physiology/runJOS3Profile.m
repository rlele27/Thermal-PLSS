function Profile = runJOS3Profile(Time_min, HeatGeneration_W, Body, Environment, Step_s, Precondition_min)
% RUNJOS3PROFILE Follow supplied piecewise constant corrected heat-generation demand with continuous thermal history.
% Inputs: Time_min, HeatGeneration_W, Body, Environment, Step_s, Precondition_min.
% Outputs: Profile.
% Units: SI; degC and explicit _min/_hr/_g field suffixes where used.
% Side effects: Uses a bounded exact-input session cache; no file writes.
% Duplicate timestamps mark activity transitions; rates apply until the next knot.
persistent ProfileKeys ProfileCache
validateattributes(Time_min, {'numeric'}, {'vector', 'finite', 'real'});
validateattributes(HeatGeneration_W, {'numeric'}, {'vector', 'finite', 'positive'});
validateattributes(Step_s, {'numeric'}, {'scalar', 'finite', 'positive'});
validateattributes(Precondition_min, {'numeric'}, {'scalar', 'finite', 'nonnegative'});
Time_min = Time_min(:);
HeatGeneration_W = HeatGeneration_W(:);
assert(numel(Time_min) == numel(HeatGeneration_W) && numel(Time_min) >= 2 && ...
    all(diff(Time_min) >= 0) && Time_min(end) > Time_min(1), ...
    'JOS3:Profile', 'Use matching rates and nondecreasing times with positive total duration.');
% Reuse cached results only for identical physical inputs. Clear functions
% after editing numerical models to discard results cached earlier in the session.
if isempty(ProfileKeys)
    ProfileKeys = {}; ProfileCache = {};
end
CacheKey = {Time_min, HeatGeneration_W, Body, Environment, Step_s, Precondition_min};
for CacheIndex = 1:numel(ProfileKeys)
    if isequaln(ProfileKeys{CacheIndex}, CacheKey)
        Profile = ProfileCache{CacheIndex};
        return;
    end
end
Model = Data_Functions.Physiology.createJOS3(Body);
BasalRate_W = sum(Model.Parameters.BasalHeat_W, 'all');
assert(all(HeatGeneration_W >= BasalRate_W), 'JOS3:BelowBasal', ...
    'Corrected heat-generation demand must be at least the JOS-3 basal rate.');

% Validate adjustable control settings once, outside the timestep/search loops.
Control = Environment.LCG.Controller;
validateattributes(Control.Enabled,{'logical'},{'scalar'});
validateattributes(Control.TemperatureBounds_C,{'numeric'},{'vector','numel',2,'real','finite','nonnegative'});
assert(diff(Control.TemperatureBounds_C)>=0,'JOS3:LCGControlBounds','LCG temperature bounds must be ordered (equal bounds fix temperature).');
validateattributes(Control.TargetStoredHeat_kJ_kg,{'numeric'},{'scalar','real','finite'});
validateattributes(Control.LimitStoredHeat_kJ_kg,{'numeric'},{'scalar','real','finite','positive'});
assert(Control.TargetStoredHeat_kJ_kg < Control.LimitStoredHeat_kJ_kg, ...
    'JOS3:LCGControlTarget','Control target must be below the storage limit.');
validateattributes(Control.TemperatureTolerance_C,{'numeric'},{'scalar','finite','positive'});
validateattributes(Control.MaximumSearchIterations,{'numeric'},{'scalar','integer','finite','positive'});
validateattributes(Control.FlowControlEnabled,{'logical'},{'scalar'});
validateattributes(Control.FlowReleaseRate_kg_h_min,{'numeric'},{'scalar','real','finite','positive'});
validateattributes(Control.StorageDeadband_kJ_kg,{'numeric'},{'scalar','real','finite','nonnegative'});
assert(string(Control.UpperTemperatureMode)=="Fixed", ...
    'JOS3:LCGUpperMode','LCG upper inlet bound must use the configured fixed temperature limit.');
validateattributes(Control.MaximumFlow_kg_h,{'numeric'},{'scalar','real','finite','positive'});
validateattributes(Control.FlowTolerance_kg_h,{'numeric'},{'scalar','real','finite','positive'});
if Control.Enabled && Control.FlowControlEnabled
    assert(Control.MaximumFlow_kg_h >= Environment.LCG.MassFlow_kg_s*3600, ...
        'JOS3:LCGFlowBounds','Maximum flow must be at least the baseline flow.');
end

assert(Environment.QgenIncludesThermogenesis, ...
    'JOS3:HeatSourceAssumption','This model treats supplied Qgen as the complete tissue heat source.');

LinerEnabled = isfield(Environment,'Liner') && Environment.Liner.Enabled;
if LinerEnabled
    Liner = Environment.Liner;
    validateattributes(Liner.HeatCapacity_J_K,{'numeric'},{'scalar','real','finite','positive'});
    validateattributes(Liner.Conductance_W_K,{'numeric'},{'scalar','real','finite','nonnegative'});
    validateattributes(Liner.InitialTemperature_C,{'numeric'},{'scalar','real','finite'});
    validateattributes(Liner.ReferenceTemperature_C,{'numeric'},{'scalar','real','finite'});
    Liner_C = Liner.InitialTemperature_C;
end

%% Preconditioning
FirstInterval = find(diff(Time_min) > 0, 1);
InitialRatio = HeatGeneration_W(FirstInterval) / BasalRate_W;
PreconditionEnvironment = Environment;
Elapsed_s = 0;
while Elapsed_s < Precondition_min * 60
    Duration_s = min(Step_s, Precondition_min * 60 - Elapsed_s);
    if LinerEnabled
        PreconditionEnvironment.RadiantTemperature_C = Liner_C;
    end
    [Model,~,PreconditionOutput] = stepVentilatedJOS3(Model, PreconditionEnvironment, InitialRatio, Duration_s);
    if LinerEnabled
        Liner_C = advanceLiner(Liner_C,PreconditionOutput.Radiation_W,Duration_s,Liner);
    end
    
    Elapsed_s = Elapsed_s + Duration_s;
end

%% EVA Profile
Intervals_s = diff(Time_min) * 60;
NumberOfSteps = sum(ceil(Intervals_s / Step_s));
StartTime_min = zeros(NumberOfSteps, 1);
EndTime_min = zeros(NumberOfSteps, 1);
CombinedMoisture_g_min = zeros(NumberOfSteps, 1);
Names = {'Respiratory_g_min', 'SweatSecreted_g_min', 'SweatEvaporated_g_min', ...
    'SkinDiffusion_g_min', 'RetainedEvaporation_g_min', 'UnevaporatedSweat_g_min', ...
    'VaporToSuit_g_min', 'RetainedStart_g', 'RetainedEnd_g', ...
    'LCGCooling_W', 'SkinEvaporation_W', 'MeanSkin_C', 'HeadCore_C', 'EnergyBalanceResidual_W', ...
    'MetabolicHeat_W', 'Radiation_W', 'RespiratoryLatent_W', 'BodyStorage_W', ...
    'MeanBodyTemperature_C', 'LCGOutletTemperature_C', ...
    'Convection_W', 'RespiratorySensible_W', 'CondenserInletTemperature_C', ...
    'CondenserInletRH_percent', 'LocalGarmentRH_percent', 'MaximumGarmentRH_percent', ...
    'GasEnergyResidual_W', 'GasWaterResidual_g_min', ...
    'NeckAirTemperature_C', 'TorsoAirTemperature_C', 'LegAirTemperature_C', ...
    'NeckAirRH_percent', 'TorsoAirRH_percent', 'LegAirRH_percent', ...
    'VaporToPLSS_g_min', 'Condensation_g_min', 'CondensateEvaporation_g_min', ...
    'CondensateStart_g', 'CondensateEnd_g', 'CondensateLatentHeat_W', ...
    'NeckCondensateStart_g', 'TorsoCondensateStart_g', 'LegCondensateStart_g', ...
    'NeckCondensateEnd_g', 'TorsoCondensateEnd_g', 'LegCondensateEnd_g', ...
    'NeckOutlet_C', 'TorsoOutlet_C', 'LegOutlet_C', ...
    'NeckOutletW', 'TorsoOutletW', 'LegOutletW','LCGUA_W_K','LCGOutsideCalibration', ...
    'LCGInletTemperature_C','BodyStoredHeat_kJ_kg','LCGControlTargetMet', ...
    'HeatStorageLimitExceeded','LCGControlAtMinimum','LCGControllerEvaluations', ...
    'LCGMassFlow_kg_s','LCGFlowAtMaximum','RemainingCoolingShortfall_W', ...
    'LCGInletUpperBound_C','HeatStorageBelowZero'};
Components = zeros(NumberOfSteps, numel(Names));
StepEnvironment = Environment;
if LinerEnabled
    LinerHistory = zeros(NumberOfSteps,6);
    LinerEVAStart_C = Liner_C;
end
Step = 0;
StoredHeat_J = 0; % Reference is the completed preconditioning state at EVA start.
for Interval = 1:numel(Intervals_s)
    ActivityRatio = HeatGeneration_W(Interval) / BasalRate_W;
    Elapsed_s = 0;
    while Elapsed_s < Intervals_s(Interval)
        Duration_s = min(Step_s, Intervals_s(Interval) - Elapsed_s);
        if LinerEnabled
            StepEnvironment.RadiantTemperature_C = Liner_C;
        end
        [Model,MoistureRate_g_s,Output] = Data_Functions.Physiology.controlLCGStep( ...
            Model,StepEnvironment,ActivityRatio,Duration_s,StoredHeat_J,@stepVentilatedJOS3);
        StoredHeat_J = StoredHeat_J+Output.BodyStorage_W*Duration_s;
        Step = Step + 1;
        if LinerEnabled
            [NextLiner_C,LinerStorage_W,LinerOnward_W] = ...
                advanceLiner(Liner_C,Output.Radiation_W,Duration_s,Liner);
            LinerHistory(Step,:) = [Liner_C,NextLiner_C,Liner.ReferenceTemperature_C, ...
                LinerStorage_W,LinerOnward_W,Liner.HeatCapacity_J_K*(NextLiner_C-LinerEVAStart_C)/1000];
            Liner_C = NextLiner_C;
        end
        StartTime_min(Step) = Time_min(Interval) + Elapsed_s / 60;
        EndTime_min(Step) = StartTime_min(Step) + Duration_s / 60;
        CombinedMoisture_g_min(Step) = MoistureRate_g_s * 60;
        Components(Step, :) = [60 * [Output.Respiratory_g_s, Output.SweatSecreted_g_s, ...
            Output.SweatEvaporated_g_s, Output.SkinDiffusion_g_s, Output.RetainedEvaporation_g_s, ...
            Output.UnevaporatedSweat_g_s, Output.VaporToSuit_g_s], ...
            Output.RetainedStart_g, Output.RetainedEnd_g, Output.LCGCooling_W, ...
            Output.SkinEvaporation_W, Output.MeanSkin_C, Output.HeadCore_C, Output.EnergyBalanceResidual_W, ...
            Output.MetabolicHeat_W, Output.Radiation_W, Output.RespiratoryLatent_W, ...
            Output.BodyStorage_W, Output.MeanBodyTemperature_C, Output.LCGOutletTemperature_C, ...
            Output.Convection_W, Output.RespiratorySensible_W, Output.CondenserInletTemperature_C, ...
            Output.CondenserInletRH_percent, Output.LocalGarmentRH_percent, Output.MaximumGarmentRH_percent, ...
            Output.GasEnergyResidual_W, Output.GasWaterResidual_g_min, ...
            Output.ZoneMeanTemperature_C', Output.ZoneMeanRH_percent', ...
            Output.VaporToPLSS_g_s * 60, Output.Condensation_g_s * 60, Output.CondensateEvaporation_g_s * 60, ...
            sum(Output.CondensateStart_g), sum(Output.CondensateEnd_g), Output.CondensateLatentHeat_W, ...
            Output.CondensateStart_g', Output.CondensateEnd_g', ...
            Output.ZoneOutletTemperature_C', Output.ZoneOutletHumidityRatio', ...
            Output.LCGUA_W_K,double(Output.LCGOutsideCalibration), ...
            Output.LCGInletTemperature_C,Output.BodyStoredHeat_kJ_kg, ...
            double(Output.LCGControlTargetMet),double(Output.HeatStorageLimitExceeded), ...
            double(Output.LCGControlAtMinimum),Output.LCGControllerEvaluations, ...
            Output.LCGMassFlow_kg_s,double(Output.LCGFlowAtMaximum), ...
            Output.RemainingCoolingShortfall_W,Output.LCGInletUpperBound_C, ...
            double(Output.HeatStorageBelowZero)];
        Elapsed_s = Elapsed_s + Duration_s;
    end
end
Profile = [table(StartTime_min, EndTime_min, CombinedMoisture_g_min), ...
    array2table(Components, 'VariableNames', Names)];
if LinerEnabled
    Profile = [Profile,array2table(LinerHistory,'VariableNames', ...
        {'LinerStartTemperature_C','LinerEndTemperature_C','LinerReferenceTemperature_C', ...
        'LinerStorage_W','LinerOnwardHeat_W','LinerStoredEnergy_kJ'})];
    assert(max(abs(Profile.Radiation_W-Profile.LinerStorage_W-Profile.LinerOnwardHeat_W))<1e-8, ...
        'JOS3:LinerBalance','Liner radiation, storage and onward transfer must balance.');
end
IntegratedStorage_kJ_kg = cumsum(Profile.BodyStorage_W.*(Profile.EndTime_min-Profile.StartTime_min)*60) ...
    /(1000*Body.Weight_kg);
assert(max(abs(IntegratedStorage_kJ_kg-Profile.BodyStoredHeat_kJ_kg)) < 1e-8, ...
    'JOS3:LCGControlStorage','Controller storage must equal integrated tissue storage.');
if Environment.LCG.Enabled
    WaterDuty_W = Profile.LCGMassFlow_kg_s*Environment.LCG.WaterCp_J_kgK ...
        .*(Profile.LCGOutletTemperature_C-Profile.LCGInletTemperature_C);
    assert(max(abs(WaterDuty_W-Profile.LCGCooling_W)) < 1e-7, ...
        'JOS3:LCGWaterBalance','Controlled water flow and temperature must conserve LCG heat.');
end
assert(all(abs(Profile.EnergyBalanceResidual_W) < 1e-6), ...
    'JOS3:EnergyBalance', 'Body heat storage does not match heat inputs and losses.');
assert(all(abs(Profile.GasEnergyResidual_W) < 2e-5) && ...
    all(abs(Profile.GasWaterResidual_g_min) < 2e-6), ...
    'JOS3:GasBalance', 'Suit-air heat or moisture balance did not close.');
CondensateBalance_g = (Profile.VaporToSuit_g_min - Profile.VaporToPLSS_g_min) ...
    .* (Profile.EndTime_min - Profile.StartTime_min) ...
    - (Profile.CondensateEnd_g - Profile.CondensateStart_g);
assert(all(abs(CondensateBalance_g) < 1e-8), 'JOS3:CondensateBalance', 'Air-node condensate does not balance.');
if isfield(Environment, 'TrackRetainedSweat') && Environment.TrackRetainedSweat
    Balance_g = (Profile.CombinedMoisture_g_min - Profile.VaporToSuit_g_min) ...
        .* (Profile.EndTime_min - Profile.StartTime_min) ...
        - (Profile.RetainedEnd_g - Profile.RetainedStart_g);
    assert(all(abs(Balance_g) < 1e-8), 'JOS3:WaterBalance', 'Moisture inventory does not balance.');
end
if numel(ProfileKeys) >= 4
    ProfileKeys(1) = []; ProfileCache(1) = [];
end
ProfileKeys{end+1} = CacheKey;
ProfileCache{end+1} = Profile;
end

function [End_C,Storage_W,Onward_W] = advanceLiner(Start_C,Radiation_W,Step_s,Liner)
% Exact liner update with the accepted interval radiation held constant.
G = Liner.Conductance_W_K;
C = Liner.HeatCapacity_J_K;
NetStart_W = Radiation_W-G*(Start_C-Liner.ReferenceTemperature_C);
if G == 0
    Change_C = NetStart_W*Step_s/C;
else
    Change_C = NetStart_W*(-expm1(-G*Step_s/C))/G;
end
End_C = Start_C+Change_C;
Storage_W = C*Change_C/Step_s;
Onward_W = Radiation_W-Storage_W;
end

function [Model, MoistureRate_g_s, Output] = stepVentilatedJOS3(StartModel, Environment, ActivityRatio, Step_s)
% STEPVENTILATEDJOS3 Three series air zones; steady gas balances within each body timestep.
% Inputs: StartModel, Environment, ActivityRatio, Step_s.
% Outputs: Model, MoistureRate_g_s, Output.
% Units: SI; degC and explicit _min/_hr/_g field suffixes where used.
% Side effects: None; returns results through its output arguments.
% Supply conditions remain fixed. Every trial starts from the SAME body state.
if ~isfield(Environment, 'Ventilation')
    [Model, MoistureRate_g_s, Output] = Data_Functions.Physiology.stepJOS3(StartModel, Environment, ActivityRatio, Step_s);
    Output.CondenserInletTemperature_C = Environment.AirTemperature_C;
    Output.CondenserInletRH_percent = Environment.RelativeHumidity_percent;
    Output.VaporToPLSS_g_s = Output.VaporToSuit_g_s;
    Output.Condensation_g_s = 0;
    Output.CondensateEvaporation_g_s = 0;
    Output.CondensateStart_g = zeros(3, 1);
    Output.CondensateEnd_g = zeros(3, 1);
    Output.CondensateLatentHeat_W = 0;
    Output.GasEnergyResidual_W = 0;
    Output.GasWaterResidual_g_min = 0;
    Output.ZoneMeanTemperature_C = repmat(mean(Environment.AirTemperature_C(:)), 3, 1);
    Output.ZoneMeanRH_percent = repmat(mean(Environment.RelativeHumidity_percent(:)), 3, 1);
    Output.ZoneOutletTemperature_C = Output.ZoneMeanTemperature_C;
    SupplyPv_kPa = exp(16.6536 - 4030.183 ./ (Output.ZoneMeanTemperature_C + 235)) ...
        .* Output.ZoneMeanRH_percent / 100;
    Output.ZoneOutletHumidityRatio = (0.01801528 / 0.0319988) * SupplyPv_kPa ...
        ./ (Environment.Pressure_kPa - SupplyPv_kPa);
    return;
end
Supply_C = Environment.AirTemperature_C;
SupplyRH_percent = Environment.RelativeHumidity_percent;
validateattributes(Environment.Ventilation.Flow_CFM, {'numeric'}, {'scalar', 'finite', 'positive'});
Flow_m3_s = Environment.Ventilation.Flow_CFM * 0.028316846592 / 60;
SupplyPressure_Pa = exp(16.6536 - 4030.183 / (Supply_C + 235)) * SupplyRH_percent / 100 * 1000;
DryFlow_kg_s = (Environment.Pressure_kPa * 1000 - SupplyPressure_Pa) * Flow_m3_s / (259.84 * (Supply_C + 273.15));
VaporFlow_kg_s = SupplyPressure_Pa * Flow_m3_s / (461.52 * (Supply_C + 273.15));
assert(DryFlow_kg_s > 0, 'JOS3:SupplyPressure', 'Supply vapor pressure must be below total pressure.');
% Use the same molecular-mass ratio as the RH sizing/export psychrometrics.
SupplyHumidityRatio = (0.01801528 / 0.0319988) * SupplyPressure_Pa ...
    / (Environment.Pressure_kPa * 1000 - SupplyPressure_Pa);
HeatCapacityRate_W_K = DryFlow_kg_s * 918 + VaporFlow_kg_s * 1860;

% Series approximation: fresh supply at head/neck, then torso/arms, then leg return.
% JOS-3 segment order: head, neck, chest, back, pelvis, arms, legs.
ZoneSegments = {1:2, 3:11, 12:17};
Outlet_C = repmat(Supply_C, 3, 1);
OutletHumidityRatio = repmat(SupplyHumidityRatio, 3, 1);
if isfield(StartModel, 'ZoneOutletTemperature_C')
    Outlet_C = StartModel.ZoneOutletTemperature_C;
    OutletHumidityRatio = StartModel.ZoneOutletHumidityRatio;
end
% Separate from retained sweat: liquid stays in its air node; no drainage.
CondensateStart_g = zeros(3, 1);
if isfield(StartModel, 'ZoneCondensate_g')
    CondensateStart_g = StartModel.ZoneCondensate_g;
end
LatentHeat_J_kg = 2418000; % Same latent heat used for JOS-3 evaporation.
for Iteration = 1:300
    Inlet_C = [Supply_C; Outlet_C(1:2)];
    InletHumidityRatio = [SupplyHumidityRatio; OutletHumidityRatio(1:2)];
    Mean_C = (Inlet_C + Outlet_C) / 2;
    MeanHumidityRatio = (InletHumidityRatio + OutletHumidityRatio) / 2;
    VaporPressure_kPa = Environment.Pressure_kPa * MeanHumidityRatio ./ (0.01801528 / 0.0319988 + MeanHumidityRatio);
    MeanRH_percent = 100 * VaporPressure_kPa ./ exp(16.6536 - 4030.183 ./ (Mean_C + 235));
    TrialEnvironment = Environment;
    TrialEnvironment.AirTemperature_C = zeros(17, 1);
    TrialEnvironment.RelativeHumidity_percent = zeros(17, 1);
    for Zone = 1:3
        TrialEnvironment.AirTemperature_C(ZoneSegments{Zone}) = Mean_C(Zone);
        TrialEnvironment.RelativeHumidity_percent(ZoneSegments{Zone}) = min(100, MeanRH_percent(Zone));
    end
    [Model, MoistureRate_g_s, Output] = Data_Functions.Physiology.stepJOS3(StartModel, TrialEnvironment, ActivityRatio, Step_s);
    ZoneHeat_W = zeros(3, 1);
    ZoneVapor_kg_s = zeros(3, 1);
    for Zone = 1:3
        ZoneHeat_W(Zone) = sum(Output.ConvectionBySegment_W(ZoneSegments{Zone}));
        ZoneVapor_kg_s(Zone) = sum(Output.SkinVaporBySegment_g_s(ZoneSegments{Zone})) / 1000;
    end
    % Respiration enters only the head/neck air zone.
    ZoneHeat_W(1) = ZoneHeat_W(1) + Output.RespiratorySensible_W;
    ZoneVapor_kg_s(1) = ZoneVapor_kg_s(1) + Output.Respiratory_g_s / 1000;
    Target_C = zeros(3, 1);
    TargetHumidityRatio = zeros(3, 1);
    PhaseRate_kg_s = zeros(3, 1); % Positive = condensation; negative = re-evaporation.
    NodeInlet_C = Supply_C;
    NodeInletHumidityRatio = SupplyHumidityRatio;
    for Zone = 1:3
        DryTemperature_C = NodeInlet_C + ZoneHeat_W(Zone) / HeatCapacityRate_W_K;
        IncomingHumidityRatio = NodeInletHumidityRatio + ZoneVapor_kg_s(Zone) / DryFlow_kg_s;
        [Target_C(Zone), TargetHumidityRatio(Zone), PhaseRate_kg_s(Zone)] = airNodeCondensation( ...
            DryTemperature_C, IncomingHumidityRatio, CondensateStart_g(Zone), Step_s, ...
            DryFlow_kg_s, HeatCapacityRate_W_K, Environment.Pressure_kPa, LatentHeat_J_kg);
        NodeInlet_C = Target_C(Zone);
        NodeInletHumidityRatio = TargetHumidityRatio(Zone);
    end
    HeatResidual_W = HeatCapacityRate_W_K * (Outlet_C - Inlet_C) ...
        - ZoneHeat_W - PhaseRate_kg_s * LatentHeat_J_kg;
    WaterResidual_g_min = (DryFlow_kg_s * (OutletHumidityRatio - InletHumidityRatio) ...
        - ZoneVapor_kg_s + PhaseRate_kg_s) * 60000;
    if max(abs(HeatResidual_W)) < 1e-6 && max(abs(WaterResidual_g_min)) < 1e-7
        OutletPressure_kPa = Environment.Pressure_kPa * OutletHumidityRatio ./ (0.01801528 / 0.0319988 + OutletHumidityRatio);
        OutletRH_percent = 100 * OutletPressure_kPa ./ exp(16.6536 - 4030.183 ./ (Outlet_C + 235));
        assert(all(OutletRH_percent <= 100 + 1e-5), 'JOS3:SaturationBalance', ...
            'Condensation balance left supersaturated outlet air.');
        CondensateEnd_g = max(0, CondensateStart_g + PhaseRate_kg_s * Step_s * 1000);
        Model.ZoneCondensate_g = CondensateEnd_g;
        Output.CondensateStart_g = CondensateStart_g;
        Output.CondensateEnd_g = CondensateEnd_g;
        Output.Condensation_g_s = sum(max(PhaseRate_kg_s, 0)) * 1000;
        Output.CondensateEvaporation_g_s = sum(max(-PhaseRate_kg_s, 0)) * 1000;
        Output.CondensateLatentHeat_W = sum(PhaseRate_kg_s) * LatentHeat_J_kg;
        % Net vapor added to the recirculating stream, after condensation/re-evaporation.
        Output.VaporToPLSS_g_s = Output.VaporToSuit_g_s - sum(PhaseRate_kg_s) * 1000;
        Model.ZoneOutletTemperature_C = Outlet_C;
        Model.ZoneOutletHumidityRatio = OutletHumidityRatio;
        Output.ZoneOutletTemperature_C = Outlet_C;
        Output.ZoneOutletHumidityRatio = OutletHumidityRatio;
        Output.CondenserInletTemperature_C = Outlet_C(3);
        Output.CondenserInletRH_percent = min(100, OutletRH_percent(3));
        Output.ZoneMeanTemperature_C = Mean_C;
        Output.ZoneMeanRH_percent = min(100, MeanRH_percent);
        Output.GasEnergyResidual_W = sum(HeatResidual_W);
        Output.GasWaterResidual_g_min = sum(WaterResidual_g_min);
        return;
    end
    % Numerical relaxation only; no extra engineering inputs.
    Outlet_C = Outlet_C + 0.3 * (Target_C - Outlet_C);
    OutletHumidityRatio = OutletHumidityRatio + 0.3 * (TargetHumidityRatio - OutletHumidityRatio);
end
error('JOS3:VentilationConvergence', 'Suit-air heat and moisture balances did not converge.');
end

function [Temperature_C, HumidityRatio, PhaseRate_kg_s] = airNodeCondensation( ...
    DryTemperature_C, IncomingHumidityRatio, Retained_g, Step_s, DryFlow_kg_s, HeatCapacityRate_W_K, Pressure_kPa, LatentHeat_J_kg)
% AIRNODECONDENSATION Instantaneous equilibrium at local gas temperature, not a suit-wall model.
% Inputs: DryTemperature_C, IncomingHumidityRatio, Retained_g, Step_s, DryFlow_kg_s, HeatCapacityRate_W_K, Pressure_kPa, LatentHeat_J_kg.
% Outputs: Temperature_C, HumidityRatio, PhaseRate_kg_s.
% Units: SI; degC and explicit _min/_hr/_g field suffixes where used.
% Side effects: None; returns results through its output arguments.
% Condensate is retained locally and can re-evaporate up to its available mass.
Temperature_C = DryTemperature_C;
HumidityRatio = IncomingHumidityRatio;
PhaseRate_kg_s = 0;
SaturatedRatio = saturationHumidityRatio(DryTemperature_C, Pressure_kPa);
if IncomingHumidityRatio <= SaturatedRatio && Retained_g == 0
    return;
end
VaporPressure_kPa = Pressure_kPa * IncomingHumidityRatio / (0.01801528 / 0.0319988 + IncomingHumidityRatio);
Dewpoint_C = 4030.183 / (16.6536 - log(VaporPressure_kPa)) - 235;
% Solve heat and water together: condensation warms; evaporation cools.
Balance = @(T) HeatCapacityRate_W_K * (T - DryTemperature_C) ...
    - LatentHeat_J_kg * DryFlow_kg_s * (IncomingHumidityRatio - saturationHumidityRatio(T, Pressure_kPa));
% At near-saturation the analytic dew point can round to the same side
% of the root as the dry temperature. Accept a converged endpoint before
% requesting a strict sign-changing bracket from fzero.
Bounds_C = sort([DryTemperature_C,Dewpoint_C]);
Residual_W = [Balance(Bounds_C(1)),Balance(Bounds_C(2))];
[SmallestResidual_W,Endpoint] = min(abs(Residual_W));
if SmallestResidual_W <= 1e-10
    Temperature_C = Bounds_C(Endpoint);
else
    if sign(Residual_W(1)) == sign(Residual_W(2))
        % Guard inverse-saturation roundoff without crossing the vapor-pressure
        % singularity. This does not modify the heat/water balance equation.
        SaturationLimit_C = 4030.183/(16.6536-log(Pressure_kPa))-235;
        Bounds_C = [max(-234,Bounds_C(1)-1e-6), ...
            min(SaturationLimit_C-1e-6,Bounds_C(2)+1e-6)];
        Residual_W = [Balance(Bounds_C(1)),Balance(Bounds_C(2))];
    end
    assert(all(isfinite(Residual_W)) && Bounds_C(1) < Bounds_C(2) ...
        && sign(Residual_W(1)) ~= sign(Residual_W(2)), ...
        'JOS3:CondensationBracket', ...
        'Cannot bracket air equilibrium: dry %.12g C, dew %.12g C, incoming W %.12g, pressure %.12g kPa.', ...
        DryTemperature_C,Dewpoint_C,IncomingHumidityRatio,Pressure_kPa);
    Temperature_C = fzero(Balance,Bounds_C);
end
HumidityRatio = saturationHumidityRatio(Temperature_C, Pressure_kPa);
PhaseRate_kg_s = DryFlow_kg_s * (IncomingHumidityRatio - HumidityRatio);
MaximumEvaporation_kg_s = Retained_g / 1000 / Step_s;
if PhaseRate_kg_s < -MaximumEvaporation_kg_s
    PhaseRate_kg_s = -MaximumEvaporation_kg_s;
    Temperature_C = DryTemperature_C + PhaseRate_kg_s * LatentHeat_J_kg / HeatCapacityRate_W_K;
    HumidityRatio = IncomingHumidityRatio - PhaseRate_kg_s / DryFlow_kg_s;
end
end

function HumidityRatio = saturationHumidityRatio(Temperature_C, Pressure_kPa)
VaporPressure_kPa = exp(16.6536 - 4030.183 / (Temperature_C + 235));
HumidityRatio = (0.01801528 / 0.0319988) * VaporPressure_kPa / (Pressure_kPa - VaporPressure_kPa);
end
