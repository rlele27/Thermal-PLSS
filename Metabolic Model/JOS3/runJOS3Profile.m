function Profile = runJOS3Profile(Time_min, MetabolicRate_W, Body, Environment, Step_s, Precondition_min)
% Follow piecewise constant Earth metabolic demand with continuous thermal history.
% Duplicate timestamps mark activity transitions; rates apply until the next knot.
validateattributes(Time_min, {'numeric'}, {'vector', 'finite', 'real'});
validateattributes(MetabolicRate_W, {'numeric'}, {'vector', 'finite', 'positive'});
validateattributes(Step_s, {'numeric'}, {'scalar', 'finite', 'positive'});
validateattributes(Precondition_min, {'numeric'}, {'scalar', 'finite', 'nonnegative'});
Time_min = Time_min(:);
MetabolicRate_W = MetabolicRate_W(:);
assert(numel(Time_min) == numel(MetabolicRate_W) && numel(Time_min) >= 2 && ...
    all(diff(Time_min) >= 0) && Time_min(end) > Time_min(1), ...
    'JOS3:Profile', 'Use matching rates and nondecreasing times with positive total duration.');
Model = createJOS3(Body);
BasalRate_W = sum(Model.Parameters.BasalHeat_W, 'all');
assert(all(MetabolicRate_W >= BasalRate_W), 'JOS3:BelowBasal', ...
    'Metabolic demand must be at least the JOS-3 basal rate.');

%% Preconditioning
FirstInterval = find(diff(Time_min) > 0, 1);
InitialRatio = MetabolicRate_W(FirstInterval) / BasalRate_W;
Elapsed_s = 0;
while Elapsed_s < Precondition_min * 60
    Duration_s = min(Step_s, Precondition_min * 60 - Elapsed_s);
    Model = stepVentilatedJOS3(Model, Environment, InitialRatio, Duration_s);
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
    'Convection_W', 'RespiratorySensible_W', 'CondenserInletTemperature_C', ...
    'CondenserInletRH_percent', 'LocalGarmentRH_percent', 'MaximumGarmentRH_percent', ...
    'GasEnergyResidual_W', 'GasWaterResidual_g_min', ...
    'NeckAirTemperature_C', 'TorsoAirTemperature_C', 'LegAirTemperature_C', ...
    'NeckAirRH_percent', 'TorsoAirRH_percent', 'LegAirRH_percent', ...
    'VaporToPLSS_g_min', 'Condensation_g_min', 'CondensateEvaporation_g_min', ...
    'CondensateStart_g', 'CondensateEnd_g', 'CondensateLatentHeat_W', ...
    'NeckCondensateStart_g', 'TorsoCondensateStart_g', 'LegCondensateStart_g', ...
    'NeckCondensateEnd_g', 'TorsoCondensateEnd_g', 'LegCondensateEnd_g'};
Components = zeros(NumberOfSteps, numel(Names));
Step = 0;
for Interval = 1:numel(Intervals_s)
    ActivityRatio = MetabolicRate_W(Interval) / BasalRate_W;
    Elapsed_s = 0;
    while Elapsed_s < Intervals_s(Interval)
        Duration_s = min(Step_s, Intervals_s(Interval) - Elapsed_s);
        [Model, MoistureRate_g_s, Output] = stepVentilatedJOS3(Model, Environment, ActivityRatio, Duration_s);
        Step = Step + 1;
        StartTime_min(Step) = Time_min(Interval) + Elapsed_s / 60;
        EndTime_min(Step) = StartTime_min(Step) + Duration_s / 60;
        CombinedMoisture_g_min(Step) = MoistureRate_g_s * 60;
        Components(Step, :) = [60 * [Output.Respiratory_g_s, Output.SweatSecreted_g_s, ...
            Output.SweatEvaporated_g_s, Output.SkinDiffusion_g_s, Output.RetainedEvaporation_g_s, ...
            Output.UnevaporatedSweat_g_s, Output.VaporToSuit_g_s], ...
            Output.RetainedStart_g, Output.RetainedEnd_g, Output.LCGCooling_W, ...
            Output.SkinEvaporation_W, Output.MeanSkin_C, Output.HeadCore_C, Output.EnergyBalanceResidual_W, ...
            Output.Convection_W, Output.RespiratorySensible_W, Output.CondenserInletTemperature_C, ...
            Output.CondenserInletRH_percent, Output.LocalGarmentRH_percent, Output.MaximumGarmentRH_percent, ...
            Output.GasEnergyResidual_W, Output.GasWaterResidual_g_min, ...
            Output.ZoneMeanTemperature_C', Output.ZoneMeanRH_percent', ...
            Output.VaporToPLSS_g_s * 60, Output.Condensation_g_s * 60, Output.CondensateEvaporation_g_s * 60, ...
            sum(Output.CondensateStart_g), sum(Output.CondensateEnd_g), Output.CondensateLatentHeat_W, ...
            Output.CondensateStart_g', Output.CondensateEnd_g'];
        Elapsed_s = Elapsed_s + Duration_s;
    end
end
Profile = [table(StartTime_min, EndTime_min, CombinedMoisture_g_min), ...
    array2table(Components, 'VariableNames', Names)];
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
end

function [Model, MoistureRate_g_s, Output] = stepVentilatedJOS3(StartModel, Environment, ActivityRatio, Step_s)
% Three series air zones; steady gas balances within each body timestep.
% Supply conditions remain fixed. Every trial starts from the SAME body state.
if ~isfield(Environment, 'Ventilation')
    [Model, MoistureRate_g_s, Output] = stepJOS3(StartModel, Environment, ActivityRatio, Step_s);
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
SupplyHumidityRatio = VaporFlow_kg_s / DryFlow_kg_s;
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
    [Model, MoistureRate_g_s, Output] = stepJOS3(StartModel, TrialEnvironment, ActivityRatio, Step_s);
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
% Instantaneous equilibrium at local gas temperature, not a suit-wall model.
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
if abs(DryTemperature_C - Dewpoint_C) > 1e-10
    Temperature_C = fzero(Balance, sort([DryTemperature_C, Dewpoint_C]));
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
