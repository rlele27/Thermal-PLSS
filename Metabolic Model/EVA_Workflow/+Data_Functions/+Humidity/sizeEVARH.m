function Design = sizeEVARH(Profile, Gas, W, C, Settings, GasProperties, WarmerSizing)
% SIZEEVARH Search whole channels and root-temperature floors for full-EVA outlet control.
% Inputs: Profile, Gas, W, C, Settings, GasProperties, WarmerSizing.
% Outputs: Design.
% Units: SI; degC and explicit _min/_hr/_g field suffixes where used.
% Side effects: None; returns results through its output arguments.
% JOS-3 sources and temperatures are prescribed, not rerun as humidity changes.
Required = {'StartTime_min', 'EndTime_min', 'DesignMoisture_g_min', ...
    'PhysicalMoisture_g_min', 'Pressure_kPa', 'DryOxygenFlow_kg_s', ...
    'SupplyTemperature_C', 'SupplyHumidityRatio', 'NeckMean_C', 'TorsoMean_C', ...
    'LegMean_C', 'NeckOutlet_C', 'TorsoOutlet_C', 'LegOutlet_C', ...
    'NeckOutletW', 'TorsoOutletW', 'LegOutletW'};
assert(all(ismember(Required, Profile.Properties.VariableNames)), ...
    'RH:MissingProfile', 'Rerun the metabolic script to export the full EVA profile.');
assert(all(isfinite(Profile{:, Required}), 'all'), 'RH:ProfileValues', 'Nonfinite EVA profile data.');
Duration_s = (Profile.EndTime_min - Profile.StartTime_min) * 60;
assert(all(Duration_s > 0) && all(abs(Profile.StartTime_min(2:end) - Profile.EndTime_min(1:end-1)) < 1e-8), ...
    'RH:ProfileTime', 'EVA intervals must be positive and contiguous.');
assert(abs(sum(Duration_s) / 60 - Settings.Duration_min) < 1e-6, ...
    'RH:ProfileDuration', 'Summary and full-profile EVA durations do not match.');
validateattributes(Settings.InitialSuitRH_percent, {'numeric'}, {'scalar', 'real', 'finite', '>', 0, '<=', 100});
validateattributes(Settings.MaximumSuitRH_percent, {'numeric'}, {'scalar', 'real', 'finite', 'positive'});
% MaximumSuitRH_percent is a diagnostic reporting threshold, never acceptance.
SearchClock = tic;
assert(all(isfield(Settings, {'EquilibriumCondensation','InitialRegionalLiquid_g', ...
    'AutoRootUpperDewPoint','RootDewPointReduction_fraction','UseTransferCache'})), ...
    'RH:Settings','Define all sizing switches in PLSS_Thermal_Sizing.m.');
validateattributes(Settings.InitialRegionalLiquid_g, {'numeric'}, ...
    {'vector', 'numel', 3, 'real', 'finite', 'nonnegative'});
Settings.InitialRegionalLiquid_g = reshape(Settings.InitialRegionalLiquid_g, 1, 3);
N = height(Profile);
Source_kg_s = Profile.DesignMoisture_g_min / 60000;
Design.TotalMoisture_kg = sum(Source_kg_s .* Duration_s);
Design.Time_min = Profile.EndTime_min;
% Inventory states are regional OUTLETS: the net regional sources below are
% reconstructed from outlet humidity differences, so use coincident outlet T.
NodeTemperature_C = [Profile.NeckOutlet_C, Profile.TorsoOutlet_C, Profile.LegOutlet_C];
mdot = Profile.DryOxygenFlow_kg_s;
PhysicalSource = Profile.PhysicalMoisture_g_min / 60000;
PhysicalOutletW = [Profile.NeckOutletW, Profile.TorsoOutletW, Profile.LegOutletW];
PhysicalZoneSource = mdot .* (PhysicalOutletW - [Profile.SupplyHumidityRatio, PhysicalOutletW(:, 1:2)]);
assert(max(abs(sum(PhysicalZoneSource, 2) - PhysicalSource)) < 2e-8, ...
    'RH:SourceBalance', 'Regional sources do not match exported net vapor.');
% Sensitivity cases may scale regional net sources, including signed phase-change terms.
assert(all(Source_kg_s >= 0), 'RH:NegativeSource', 'Net-negative EVA source intervals need a separate condensation inventory treatment.');
Scale = ones(N, 1);
Nonzero = abs(PhysicalSource) > 1e-12;
Scale(Nonzero) = Source_kg_s(Nonzero) ./ PhysicalSource(Nonzero);
ZoneSource_kg_s = PhysicalZoneSource .* Scale;
% Preserve the exported net load exactly after regional state reconstruction.
ZoneSource_kg_s(:, 3) = ZoneSource_kg_s(:, 3) + Source_kg_s - sum(ZoneSource_kg_s, 2);

% Diagnostic steady states at the exact supply target. These are not an
% automatic transient rejection: brief excesses may be accommodated by storage.
TargetW = humidityRatio(Settings.SupplyRH_percent, Profile.SupplyTemperature_C, ...
    Profile.Pressure_kPa, Gas.MolecularMassRatio);
PhysicalSteadyW = TargetW + cumsum(PhysicalZoneSource, 2) ./ mdot;
DesignSteadyW = TargetW + cumsum(ZoneSource_kg_s, 2) ./ mdot;
MeanTemperature_C = [Profile.NeckMean_C, Profile.TorsoMean_C, Profile.LegMean_C];
PhysicalSteadyRH = relativeHumidity(PhysicalSteadyW, NodeTemperature_C, Profile.Pressure_kPa, Gas.MolecularMassRatio);
DesignSteadyRH = relativeHumidity(DesignSteadyW, NodeTemperature_C, Profile.Pressure_kPa, Gas.MolecularMassRatio);
MeanBasisRH = relativeHumidity(DesignSteadyW, MeanTemperature_C, Profile.Pressure_kPa, Gas.MolecularMassRatio);
Design.LoadDiagnostics = table(Profile.StartTime_min, Profile.EndTime_min, ...
    max(PhysicalSteadyRH, [], 2), max(DesignSteadyRH, [], 2), max(MeanBasisRH, [], 2), ...
    'VariableNames', {'StartTime_min', 'EndTime_min', 'PhysicalSteadyMaximumRH_percent', ...
    'DesignSteadyMaximumRH_percent', 'FormerMeanTemperatureBasisRH_percent'});

%% Editable design bounds and outlet constraints
validateattributes(Settings.SizeWeight, {'numeric'}, {'scalar', 'real', 'finite', '>=', 0, '<=', 1});
validateattributes(Settings.ChannelBounds, {'numeric'}, {'vector', 'numel', 2, 'integer', 'positive', 'finite'});
assert(Settings.ChannelBounds(2) > Settings.ChannelBounds(1), 'RH:SearchBounds', 'Channel bounds must increase.');
% A single common floor must be below every supply target's dew point.
% Recalculate here as sensitivity cases can change supply temperature or RH.
if Settings.AutoRootUpperDewPoint
    validateattributes(Settings.SupplyRH_percent, {'numeric'}, {'scalar', 'real', 'finite', '>', 0, '<=', 100});
    TargetTemperatures_C = unique(Profile.SupplyTemperature_C);
    TargetDewPoint_C = zeros(size(TargetTemperatures_C));
    for Row = 1:numel(TargetTemperatures_C)
        TargetPressure = Settings.SupplyRH_percent / 100 * vaporPressure(TargetTemperatures_C(Row));
        TargetDewPoint_C(Row) = fzero(@(T) vaporPressure(T) - TargetPressure, ...
            [-80, TargetTemperatures_C(Row)]);
    end
    validateattributes(Settings.RootDewPointReduction_fraction, {'numeric'}, ...
        {'scalar', 'real', 'finite', '>=', 0, '<', 1});
    Settings.RootTemperatureBounds_C(2) = (1 - Settings.RootDewPointReduction_fraction) * min(TargetDewPoint_C);
    Design.TargetDewPoint_C = min(TargetDewPoint_C);
end
Design.RootTemperatureBounds_C = Settings.RootTemperatureBounds_C;
validateattributes(Settings.RootTemperatureBounds_C, {'numeric'}, {'vector', 'numel', 2, 'real', 'finite', 'positive'});
assert(diff(Settings.RootTemperatureBounds_C) > 0 && Settings.RootTemperatureStep_C > 0, ...
    'RH:SearchBounds', 'RH target dew point must exceed the lower root bound; lower it or revise the target. Temperature step must be positive.');
validateattributes(Settings.RootTemperatureStep_C, {'numeric'}, {'scalar', 'real', 'finite', 'positive'});
validateattributes(Settings.ControlTemperaturePoints, {'numeric'}, {'scalar', 'integer', '>=', 3});
validateattributes(Settings.InternalStep_s, {'numeric'}, {'scalar', 'real', 'finite', 'positive'});
validateattributes(Settings.SupplyRH_percent, {'numeric'}, {'scalar', 'real', 'finite', '>', 0, '<=', 100});
validateattributes(Settings.RHTolerance_percent, {'numeric'}, {'scalar', 'finite', 'positive'});
validateattributes(Settings.TemperatureTolerance_C, {'numeric'}, {'scalar', 'finite', 'positive'});
RootFloors = unique([Settings.RootTemperatureBounds_C(1):Settings.RootTemperatureStep_C:Settings.RootTemperatureBounds_C(2), ...
    Settings.RootTemperatureBounds_C(2)]);
InitialW = humidityRatio(Settings.InitialSuitRH_percent, NodeTemperature_C(1, :), Profile.Pressure_kPa(1), Gas.MolecularMassRatio);
p = Profile.Pressure_kPa(1) * 1000 .* InitialW ./ (Gas.MolecularMassRatio + InitialW);
NodeDryMass_kg = Settings.FreeGasVolume_L / 3000 * (Profile.Pressure_kPa(1) * 1000 - p) ...
    ./ (Gas.Constant_J_kgK * (NodeTemperature_C(1, :) + 273.15));
Model = struct('Duration_s', Duration_s, 'Source_kg_s', ZoneSource_kg_s, ...
    'Temperature_C', NodeTemperature_C, 'ReturnTemperature_C', Profile.LegOutlet_C, ...
    'SupplyTemperature_C', Profile.SupplyTemperature_C, 'Pressure_kPa', Profile.Pressure_kPa, ...
    'DryFlow_kg_s', mdot, 'NodeDryMass_kg', NodeDryMass_kg, 'InitialW', InitialW, ...
    'Settings', Settings, 'MolecularRatio', Gas.MolecularMassRatio);
% Cache saturation and latent properties; prescribed region temperatures do not change per substep.
if Settings.EquilibriumCondensation
    assert(all(NodeTemperature_C >= 0, 'all'), 'RH:Freezing', ...
        'Regional liquid equilibrium excludes freezing; prescribed node temperatures must be nonnegative.');
end
Model.NodeSaturationPressure_Pa = vaporPressure(NodeTemperature_C);
Model.SupplySaturationPressure_Pa = vaporPressure(Profile.SupplyTemperature_C);
Model.SaturatedW = humidityRatio(100, NodeTemperature_C, Profile.Pressure_kPa, Gas.MolecularMassRatio);
Model.LatentHeat_J_kg = W.VaporEnthalpyAtZero_J_kg + (W.VaporCp_J_kgK - W.Cp_J_kgK) * NodeTemperature_C;
PerChannelArea = 2 * (C.ChannelHeight_m + C.ChannelGap_m) * C.ChannelLength_m;
volume = @(n) C.ChannelLength_m * C.ChannelHeight_m ...
    * (n * C.ChannelGap_m + (n + 1) * C.FinThickness_m);
VolumeBounds = volume(Settings.ChannelBounds);
CandidateRows = cell(numel(RootFloors) * (Settings.ChannelBounds(2) - Settings.ChannelBounds(1) + 1), 1);
CandidateCount = 0;
Options = cell(numel(RootFloors), 1);
OptionCount = 0;
Design.Feasible = false;
Design.SelectedHistory = {};
Design.SelectedSummary = table();
for Floor = RootFloors
    if Floor >= min(Profile.LegOutlet_C) - 0.01
        RowResult = table(Floor, NaN, NaN, NaN, NaN, Inf, false, NaN, NaN, NaN, ...
            "Root floor is not colder than every prescribed return state.", ...
            'VariableNames', {'RootFloor_C', 'Channels', 'CoreVolume_L', 'SizeCost', 'ColdCost', ...
            'Objective', 'Feasible', 'MaximumRHError_percent', 'MaximumTemperatureError_C', 'LimitingTime_min', 'Reason'});
        RowResult.FailureSupplyRH_percent = NaN;
        RowResult.FailureSupplyTemperature_C = NaN;
        RowResult.FailureColdRH_percent = NaN;
        RowResult.FailureColdTemperature_C = NaN;
        RowResult.FailureMaximumSuitRH_percent = NaN;
        CandidateCount = CandidateCount + 1;
        CandidateRows{CandidateCount} = RowResult;
        continue;
    end
    TrialC = C;
    TrialC.SurfaceTemperature_C = Floor;
    [Model.Gas, Model.Response] = prepareResponse(Profile, Gas, W, TrialC, Settings, GasProperties);
    Dh = 2 * C.ChannelGap_m * C.ChannelHeight_m / (C.ChannelGap_m + C.ChannelHeight_m);
    ReTimesChannels = max(cellfun(@(g) g.Density_kg_m3 * g.Flow_m3_s * Dh ...
        / (C.ChannelGap_m * C.ChannelHeight_m * g.Viscosity_Pa_s), Model.Gas));
    for Channels = Settings.ChannelBounds(1):Settings.ChannelBounds(2)
        if ReTimesChannels / Channels >= 2300
            H = struct('Feasible', false, 'Failure', "Condenser channels exceed the laminar correlation.", ...
                'MaximumRHError_percent', NaN, 'MaximumTemperatureError_C', NaN, ...
                'WorstTargetTime_min', Profile.StartTime_min(1), 'FailureSupplyRH_percent', NaN, ...
                'FailureSupplyTemperature_C', NaN, 'FailureColdRH_percent', NaN, ...
                'FailureColdTemperature_C', NaN, 'FailureMaximumSuitRH_percent', NaN);
        else
            H = controlledHumidityHistory(Channels * PerChannelArea, Model, Profile, W);
        end
        Pass = H.Feasible;
        Reason = H.Failure;
        Warmer = struct();
        if Pass
            try
                Warmer = WarmerSizing(H, Channels);
            catch ME
                if startsWith(ME.identifier, 'RH:AirWarmer')
                    Pass = false;
                    Reason = string(ME.message);
                else
                    rethrow(ME);
                end
            end
        end
        SizeCost = (volume(Channels) - VolumeBounds(1)) / diff(VolumeBounds);
        ColdCost = (Settings.RootTemperatureBounds_C(2) - Floor) / diff(Settings.RootTemperatureBounds_C);
        Score = Settings.SizeWeight * SizeCost + (1 - Settings.SizeWeight) * ColdCost;
        if ~Pass, Score = Inf; end
        RowResult = table(Floor, Channels, volume(Channels) * 1000, SizeCost, ColdCost, Score, Pass, ...
            H.MaximumRHError_percent, H.MaximumTemperatureError_C, H.WorstTargetTime_min, Reason, ...
            'VariableNames', {'RootFloor_C', 'Channels', 'CoreVolume_L', 'SizeCost', 'ColdCost', ...
            'Objective', 'Feasible', 'MaximumRHError_percent', 'MaximumTemperatureError_C', 'LimitingTime_min', 'Reason'});
        RowResult.FailureSupplyRH_percent = H.FailureSupplyRH_percent;
        RowResult.FailureSupplyTemperature_C = H.FailureSupplyTemperature_C;
        RowResult.FailureColdRH_percent = H.FailureColdRH_percent;
        RowResult.FailureColdTemperature_C = H.FailureColdTemperature_C;
        RowResult.FailureMaximumSuitRH_percent = H.FailureMaximumSuitRH_percent;
        CandidateCount = CandidateCount + 1;
        CandidateRows{CandidateCount} = RowResult;
        if Pass
            % Counts are enumerated: the immediately smaller allowed count has failed.
            % For a fixed floor, larger counts cannot improve the defined objective.
            OptionCount = OptionCount + 1;
            Options{OptionCount} = struct('RootFloor_C', Floor, 'Channels', Channels, ...
                'History', H, 'Warmer', Warmer, 'SearchRow', CandidateCount, ...
                'Summary', summarizeDesign(Channels, Floor, H, Profile, C, Model.Gas, PerChannelArea));
            Design.Feasible = true;
            break;
        end
    end
end
Design.SearchResults = vertcat(CandidateRows{1:CandidateCount});
Design.FeasibleOptions = Options(1:OptionCount);
Design.ChannelBounds = Settings.ChannelBounds;
Design.TimeHistoryBase = [Profile(:, {'StartTime_min', 'EndTime_min'}), ...
    table(Source_kg_s * 60000, 'VariableNames', {'DesignMoisture_g_min'})];
Design.Time_min = Profile.EndTime_min;
if ~Design.Feasible
    Design.Runtime_s = toc(SearchClock);
    Design.Failure = "No feasible condenser/warmer in the configured channel and temperature bounds. Inspect SearchResults reasons and limiting times.";
    return;
end
Design = Data_Functions.Humidity.reweightEVADesign(Design, Settings.SizeWeight);
Design.Runtime_s = toc(SearchClock);
end

function [Gases, Responses] = prepareResponse(Profile, Gas, W, C, Settings, GasProperties)
persistent CacheKey Floors GasCache ResponseCache
UseCache = Settings.UseTransferCache;
Geometry = rmfield(C, 'SurfaceTemperature_C');
Key = {Profile.LegOutlet_C, Profile.Pressure_kPa, Profile.DryOxygenFlow_kg_s, ...
    Gas, W, Geometry, Settings.ControlTemperaturePoints, GasProperties};
if UseCache
    if isempty(CacheKey) || ~isequaln(CacheKey, Key)
        CacheKey = Key; Floors = []; GasCache = {}; ResponseCache = {};
    end
    Index = find(Floors == C.SurfaceTemperature_C, 1);
    if ~isempty(Index)
        Gases = GasCache{Index}; Responses = ResponseCache{Index};
        return;
    end
end
N = height(Profile);
Gases = cell(N, 1);
Responses = cell(N, 1);
for Row = 1:N
    g = Gas;
    g.SuitTemperature_C = Profile.LegOutlet_C(Row);
    g.Pressure_kPa = Profile.Pressure_kPa(Row);
    g.SuitRH_percent = 100; % Fixed saturated reference for transfer properties, not a constraint.
    p = vaporPressure(g.SuitTemperature_C) * g.SuitRH_percent / 100;
    g.Flow_CFM = Profile.DryOxygenFlow_kg_s(Row) * Gas.Constant_J_kgK * (g.SuitTemperature_C + 273.15) ...
        / (g.Pressure_kPa * 1000 - p) * 60 / 0.028316846592;
    g = GasProperties(g, W, C);
    Gases{Row} = g;
    Root_C = linspace(C.SurfaceTemperature_C, g.SuitTemperature_C - 0.01, Settings.ControlTemperaturePoints);
    MassExponent = zeros(size(Root_C));
    HeatExponent = zeros(size(Root_C));
    SurfaceW = zeros(size(Root_C));
    CapacityRate = g.DryFlow_kg_s * (g.Cp_J_kgK + g.InletHumidityRatio * W.VaporCp_J_kgK);
    for Point = 1:numel(Root_C)
        TrialC = C;
        TrialC.SurfaceTemperature_C = Root_C(Point);
        tg = GasProperties(g, W, TrialC);
        MassExponent(Point) = tg.MassTransfer_m_s * tg.SurfaceMassEfficiency / tg.Flow_m3_s;
        HeatExponent(Point) = tg.HeatTransfer_W_m2K * tg.SurfaceHeatEfficiency / CapacityRate;
        p = vaporPressure(Root_C(Point));
        SurfaceW(Point) = Gas.MolecularMassRatio * p / (g.Pressure_kPa * 1000 - p);
    end
    Responses{Row} = struct('Root_C', Root_C, 'MassExponent', MassExponent, ...
        'HeatExponent', HeatExponent, 'SurfaceW', SurfaceW);
end
if UseCache
    % Keep cache bounded for interactive reruns with many temperature settings.
    if numel(Floors) >= 16
        Floors(1) = []; GasCache(1) = []; ResponseCache(1) = [];
    end
    Floors(end+1) = C.SurfaceTemperature_C;
    GasCache{end+1} = Gases; ResponseCache{end+1} = Responses;
end
end

function S = summarizeDesign(Channels, Floor, H, Profile, C, Gases, PerArea)
d = (Profile.EndTime_min - Profile.StartTime_min) * 60;
avg = @(x) sum(x .* d) / sum(d);
S = table("Weighted outlet-control design", true, Channels * PerArea, Channels, ...
    C.ChannelLength_m * 1000, (Channels * C.ChannelGap_m + (Channels+1) * C.FinThickness_m) * 1000, ...
    C.ChannelHeight_m * 1000, 'VariableNames', {'Case', 'MeetsRHLimit', 'InstalledArea_m2', 'Channels', ...
    'CoreLength_mm', 'CoreWidth_mm', 'CoreHeight_mm'});
S.CoreVolume_L = S.CoreLength_mm * S.CoreWidth_mm * S.CoreHeight_mm / 1e6;
S.PeakCooling_W = max(H.Instantaneous.Cooling_W);
S.AverageCooling_W = avg(H.Cooling_W);
S.AverageRemoval_g_min = H.TotalRemoved_kg * 60000 / sum(d);
S.PeakRemoval_g_min = max(H.Instantaneous.Removal_kg_s) * 60000;
S.CollectedWater_g = H.TotalRemoved_kg * 1000;
S.MaximumSuitRH_percent = max(H.MaximumRH_percent);
S.MeetsRHLimit = S.MaximumSuitRH_percent <= 100 + 1e-6; % Diagnostic only.
S.RegionalRHConstraintApplied = false;
S.RegionalSupersaturation_min = H.RegionalSupersaturation_s / 60;
S.AverageCondenserOutlet_C = avg(H.CondenserOutlet_C);
S.AverageCondenserOutletRH_percent = avg(H.CondenserOutletRH_percent);
S.ReheatedTemperature_C = avg(H.ReheatedTemperature_C);
S.AverageReheatedRH_percent = avg(H.ReheatedRH_percent);
S.PeakReheatedRH_percent = max(H.PeakReheatedRH_percent);
S.AverageReheat_W = avg(H.Reheat_W);
S.PeakReheat_W = max(H.Instantaneous.Reheat_W);
S.AverageRootTemperature_C = avg(H.RootTemperature_C);
S.MinimumRootTemperature_C = min(H.MinimumRootTemperature_C);
S.MaximumRootTemperature_C = max(H.MaximumRootTemperature_C);
S.SupplyTargetMiss_min = H.TargetMiss_s / 60;
S.AverageSuitRH_percent = avg(H.AverageRH_percent);
S.PeakIntervalAverageSuitRH_percent = max(H.AverageRH_percent);
S.RootFloor_C = Floor;
S.MaximumRHError_percent = H.MaximumRHError_percent;
S.MaximumTemperatureError_C = H.MaximumTemperatureError_C;
S.LimitingTime_min = H.WorstTargetTime_min;
S.InitialRegionalLiquid_g = sum(H.InitialRegionLiquid_g);
S.FinalRegionalLiquid_g = sum(H.FinalRegionLiquid_g);
S.WaterBalanceResidual_kg = H.MassResidual_kg;
S.TotalRegionalCondensation_g = sum(H.Condensed_kg, 'all') * 1000;
S.TotalRegionalReevaporation_g = sum(H.Reevaporated_kg, 'all') * 1000;
S.MaximumStoredRegionalLiquid_g = H.MaximumStoredRegionalLiquid_g;
S.AveragePhaseHeatSink_W = avg(H.RequiredPhaseHeatSink_W);
S.PeakIntervalPhaseHeatSink_W = max(H.RequiredPhaseHeatSink_W);
S.MaximumPreEquilibriumRH_percent = max(H.UncorrectedMaximumRH_percent);
S.PhaseEnergyResidual_J = H.PhaseEnergyResidual_J;
S.Note = "Targets met at internal steps and interval endpoints; ideal control; isothermal regional equilibrium with retained liquid and explicit heat-exchange accounting; no drainage/carryover. Cold-outlet fog still rejects.";
S.MaximumSaturatedCapacity_g_min = max(cellfun(@(g) g.DryFlow_kg_s * max(0, ...
    humidityRatio(100, g.SuitTemperature_C, g.Pressure_kPa, g.MolecularMassRatio) ...
    - humidityRatio(100, Floor, g.Pressure_kPa, g.MolecularMassRatio)) ...
    * (1 - exp(-g.MassTransfer_m_s * g.SurfaceMassEfficiency * S.InstalledArea_m2 / g.Flow_m3_s)), Gases)) * 60000;
end

function Result = controlledHumidityHistory(Area_m2, Model, Profile, W)
% CONTROLLEDHUMIDITYHISTORY Ideal temperature control, with no thermal inertia or feedback into JOS-3.
% Inputs: Area_m2, Model, Profile, W.
% Outputs: Result.
% Units: SI; degC and explicit _min/_hr/_g field suffixes where used.
% Side effects: None; returns results through its output arguments.
% Interpolate heat/mass-transfer response between root-temperature states.
N = height(Profile);
validateattributes(Model.Settings.ControlTemperaturePoints, {'numeric'}, {'scalar', 'integer', '>=', 3});
w = Model.InitialW;
Liquid_kg = Model.Settings.InitialRegionalLiquid_g / 1000;
InitialMass_kg = sum(Model.NodeDryMass_kg .* w + Liquid_kg);
InitialLiquidEnergy_J = sum(Liquid_kg .* W.Cp_J_kgK .* Model.Temperature_C(1, :));
PreviousTemperature_C = Model.Temperature_C(1, :);
PhaseVaporEnergy_J = 0;
PhaseBoundaryHeat_J = 0;
Names = {'MaximumRH_percent', 'AverageRH_percent', 'Removal_kg_s', 'MeanOutletW', ...
    'CondenserOutlet_C', 'PeakCondenserOutlet_C', 'CondenserOutletRH_percent', ...
    'PeakCondenserOutletRH_percent', 'Cooling_W', 'PeakCooling_W', ...
    'Reheat_W', 'PeakReheat_W', 'ReheatedTemperature_C', 'ReheatedRH_percent', ...
    'PeakReheatedRH_percent', 'RootTemperature_C', 'MinimumRootTemperature_C', ...
    'MaximumRootTemperature_C'};
for Index = 1:numel(Names)
    Result.(Names{Index}) = zeros(N, 1);
end
Result.NodeRH_percent = zeros(N, 3);
Result.InitialRegionLiquid_g = Liquid_kg * 1000;
Result.RegionLiquidEnd_g = zeros(N, 3);
Result.Condensed_kg = zeros(N, 3);
Result.Reevaporated_kg = zeros(N, 3);
Result.PhaseChangeHeat_W = zeros(N, 1);
Result.LiquidSensibleHeat_W = zeros(N, 1);
Result.RequiredPhaseHeatSink_W = zeros(N, 1);
Result.UncorrectedMaximumRH_percent = zeros(N, 1);
Result.CondensationActive_s = 0;
Result.MaximumStoredRegionalLiquid_g = sum(Liquid_kg) * 1000;
Result.FirstViolation_s = NaN;
Result.TargetMiss_s = 0;
Result.TotalRemoved_kg = 0;
Result.Feasible = true;
Result.Failure = "";
Result.MaximumRHError_percent = 0;
Result.MaximumTemperatureError_C = 0;
Result.WorstTargetTime_min = Profile.StartTime_min(1);
Result.RHError_percent = zeros(N, 1);
Result.TemperatureError_C = zeros(N, 1);
Result.PeakColdRH_percent = 0;
Result.MassResidual_kg = NaN;
Result.RegionalSupersaturation_s = 0;
Result.FailureSupplyRH_percent = NaN;
Result.FailureSupplyTemperature_C = NaN;
Result.FailureColdRH_percent = NaN;
Result.FailureColdTemperature_C = NaN;
Result.FailureMaximumSuitRH_percent = NaN;
SampleCount = sum(ceil(Model.Duration_s / Model.Settings.InternalStep_s)) + N;
Samples = zeros(SampleCount, 9);
SampleIndex = 0;
Elapsed_s = 0;
for Row = 1:N
    g = Model.Gas{Row};
    NodeTemperature = Model.Temperature_C(Row, :);
    Pressure_Pa = Model.Pressure_kPa(Row) * 1000;
    NodeSaturationPressure = Model.NodeSaturationPressure_Pa(Row, :);
    StartTime_min = Profile.StartTime_min(Row);
    SaturatedVapor_kg = Model.NodeDryMass_kg .* Model.SaturatedW(Row, :);
    LatentHeat = Model.LatentHeat_J_kg(Row, :);
    VaporEnthalpy = W.VaporEnthalpyAtZero_J_kg + W.VaporCp_J_kgK * NodeTemperature;
    Condensed_kg = zeros(1, 3);
    Reevaporated_kg = zeros(1, 3);
    PhaseHeat_J = 0;
    % Fixed JOS-3 temperatures imply an explicit thermal boundary for retained water.
    LiquidSensible_J = sum(Liquid_kg .* W.Cp_J_kgK .* (NodeTemperature - PreviousTemperature_C));
    PhaseBoundaryHeat_J = PhaseBoundaryHeat_J - LiquidSensible_J;
    PreviousTemperature_C = NodeTemperature;
    RawPeakRH = max(100 * Pressure_Pa * w ./ (Model.MolecularRatio + w) ./ NodeSaturationPressure);
    if Model.Settings.EquilibriumCondensation
        [Vapor_kg, Liquid_kg, Phase_kg, Heat_J] = Data_Functions.Humidity.equilibrateSuitAir( ...
            Model.NodeDryMass_kg .* w, Liquid_kg, SaturatedVapor_kg, LatentHeat);
        w = Vapor_kg ./ Model.NodeDryMass_kg;
        Result.MaximumStoredRegionalLiquid_g = max(Result.MaximumStoredRegionalLiquid_g, sum(Liquid_kg) * 1000);
        Condensed_kg = Condensed_kg + max(Phase_kg, 0);
        Reevaporated_kg = Reevaporated_kg + max(-Phase_kg, 0);
        PhaseHeat_J = PhaseHeat_J + sum(Heat_J);
        PhaseBoundaryHeat_J = PhaseBoundaryHeat_J + sum(Heat_J);
        PhaseVaporEnergy_J = PhaseVaporEnergy_J + sum(Phase_kg .* VaporEnthalpy);
    end
    TargetRH = Model.Settings.SupplyRH_percent;
    TargetW = humidityRatio(TargetRH, Model.SupplyTemperature_C(Row), Model.Pressure_kPa(Row), Model.MolecularRatio);
    Response = Model.Response{Row};
    Root_C = Response.Root_C;
    Effectiveness = 1 - exp(-Response.MassExponent * Area_m2);
    HeatTransmission = exp(-Response.HeatExponent * Area_m2);
    SurfaceW = Response.SurfaceW;
    Transfer = struct('Root_C', Root_C, 'Effectiveness', Effectiveness, ...
        'HeatTransmission', HeatTransmission, 'SurfaceW', SurfaceW, ...
        'TargetW', TargetW, 'Inlet_C', g.SuitTemperature_C);
    Steps = ceil(Model.Duration_s(Row) / Model.Settings.InternalStep_s);
    dt = Model.Duration_s(Row) / Steps;
    Result.InternalStep_s(Row, 1) = dt;
    assert(dt * Model.DryFlow_kg_s(Row) <= min(Model.NodeDryMass_kg), ...
        'RH:TimeStep', 'Internal timestep exceeds the smallest air-node residence time.');
    IntervalRHError = 0;
    IntervalTemperatureError = 0;
    Sums = zeros(1, 8);
    Peaks = zeros(1, 5);
    MinRoot_C = Inf;
    MaxRoot_C = -Inf;
    PeakRH = 0;
    SuitRHSum = 0;
    for Step = 1:Steps
        [wSupply, Root, Cold_C] = controlledOutlet(w(3), Transfer);
        pOut = Model.Pressure_kPa(Row) * 1000 * wSupply / (Model.MolecularRatio + wSupply);
        ColdRH = 100 * pOut / vaporPressure(Cold_C);
        Warm_C = max(Cold_C, Model.SupplyTemperature_C(Row));
        if Warm_C == Model.SupplyTemperature_C(Row)
            WarmRH = 100 * pOut / Model.SupplySaturationPressure_Pa(Row);
        else
            WarmRH = 100 * pOut / vaporPressure(Warm_C);
        end
        Removal = Model.DryFlow_kg_s(Row) * (w(3) - wSupply);
        hIn = g.Cp_J_kgK * g.SuitTemperature_C ...
            + w(3) * (W.VaporEnthalpyAtZero_J_kg + W.VaporCp_J_kgK * g.SuitTemperature_C);
        hOut = g.Cp_J_kgK * Cold_C ...
            + wSupply * (W.VaporEnthalpyAtZero_J_kg + W.VaporCp_J_kgK * Cold_C);
        Cooling = Model.DryFlow_kg_s(Row) * (hIn - hOut) - Removal * W.Cp_J_kgK * Root;
        Reheat = Model.DryFlow_kg_s(Row) * (g.Cp_J_kgK + wSupply * W.VaporCp_J_kgK) * (Warm_C - Cold_C);
        NodeRH = 100 * Pressure_Pa * w ./ (Model.MolecularRatio + w) ./ NodeSaturationPressure;
        ReturnRH = NodeRH(3);
        InstantSuitRH = max([NodeRH, WarmRH, ReturnRH]);
        if max([NodeRH, ReturnRH]) > 100 + 1e-6
            Result.RegionalSupersaturation_s = Result.RegionalSupersaturation_s + dt;
        end
        SuitRHSum = SuitRHSum + InstantSuitRH;
        PeakRH = max(PeakRH, InstantSuitRH);
        if isnan(Result.FirstViolation_s) && PeakRH > Model.Settings.MaximumSuitRH_percent
            Result.FirstViolation_s = Elapsed_s + (Step - 1) * dt;
        end
        RHError = abs(WarmRH - TargetRH);
        TemperatureError = abs(Warm_C - Model.SupplyTemperature_C(Row));
        IntervalRHError = max(IntervalRHError, RHError);
        IntervalTemperatureError = max(IntervalTemperatureError, TemperatureError);
        if RHError > Result.MaximumRHError_percent
            Result.WorstTargetTime_min = StartTime_min + (Step - 1) * dt / 60;
        end
        Result.MaximumRHError_percent = max(Result.MaximumRHError_percent, RHError);
        Result.MaximumTemperatureError_C = max(Result.MaximumTemperatureError_C, TemperatureError);
        Result.PeakColdRH_percent = max(Result.PeakColdRH_percent, ColdRH);
        if RHError > Model.Settings.RHTolerance_percent || TemperatureError > Model.Settings.TemperatureTolerance_C
            Result.TargetMiss_s = Result.TargetMiss_s + dt;
            Result.Feasible = false;
            Result.Failure = "Supply RH/temperature target missed (no humidifier or post-warmer cooling).";
        elseif ColdRH > 100 + 1e-6
            Result.Feasible = false;
            Result.Failure = "Cold condenser outlet supersaturated; fog transport is not modelled.";

        end
        if ~Result.Feasible
            Result.FailureSupplyRH_percent = WarmRH;
            Result.FailureSupplyTemperature_C = Warm_C;
            Result.FailureColdRH_percent = ColdRH;
            Result.FailureColdTemperature_C = Cold_C;
            Result.FailureMaximumSuitRH_percent = InstantSuitRH;
            Result.WorstTargetTime_min = StartTime_min + (Step - 1) * dt / 60;
            return; % Early rejection only; accepted designs always integrate the full EVA.
        end
        SampleIndex = SampleIndex + 1;
        Samples(SampleIndex, :) = [StartTime_min + (Step - 1) * dt / 60, ...
            Model.DryFlow_kg_s(Row), wSupply, Cold_C, Warm_C, Reheat, Cooling, Root, Removal];
        Incoming = [wSupply, w(1:2)];
        TrialW = w + dt * (Model.DryFlow_kg_s(Row) * (Incoming - w) ...
            + Model.Source_kg_s(Row, :)) ./ Model.NodeDryMass_kg;
        RawPeakRH = max(RawPeakRH, max(100 * Pressure_Pa * TrialW ...
            ./ (Model.MolecularRatio + TrialW) ./ NodeSaturationPressure));
        if Model.Settings.EquilibriumCondensation
            [Vapor_kg, Liquid_kg, Phase_kg, Heat_J] = Data_Functions.Humidity.equilibrateSuitAir( ...
                Model.NodeDryMass_kg .* TrialW, Liquid_kg, SaturatedVapor_kg, LatentHeat);
            w = Vapor_kg ./ Model.NodeDryMass_kg;
            Result.MaximumStoredRegionalLiquid_g = max(Result.MaximumStoredRegionalLiquid_g, sum(Liquid_kg) * 1000);
            Condensed_kg = Condensed_kg + max(Phase_kg, 0);
            Reevaporated_kg = Reevaporated_kg + max(-Phase_kg, 0);
            PhaseHeat_J = PhaseHeat_J + sum(Heat_J);
            PhaseBoundaryHeat_J = PhaseBoundaryHeat_J + sum(Heat_J);
            PhaseVaporEnergy_J = PhaseVaporEnergy_J + sum(Phase_kg .* VaporEnthalpy);
            if any(Phase_kg > 1e-15), Result.CondensationActive_s = Result.CondensationActive_s + dt; end
        else
            w = TrialW;
        end
        assert(all(w >= -1e-10), 'RH:Inventory', 'Negative humidity in the controlled inventory.');
        Sums = Sums + [Removal, wSupply, Cold_C, ColdRH, Cooling, Reheat, Warm_C, WarmRH];
        Peaks = max(Peaks, [Cold_C, ColdRH, Cooling, Reheat, WarmRH]);
        Result.RootTemperature_C(Row) = Result.RootTemperature_C(Row) + Root / Steps;
        MinRoot_C = min(MinRoot_C, Root);
        MaxRoot_C = max(MaxRoot_C, Root);
    end
    Result.RegionLiquidEnd_g(Row, :) = Liquid_kg * 1000;
    Result.Condensed_kg(Row, :) = Condensed_kg;
    Result.Reevaporated_kg(Row, :) = Reevaporated_kg;
    Result.PhaseChangeHeat_W(Row) = PhaseHeat_J / Model.Duration_s(Row);
    Result.LiquidSensibleHeat_W(Row) = LiquidSensible_J / Model.Duration_s(Row);
    Result.RequiredPhaseHeatSink_W(Row) = (PhaseHeat_J - LiquidSensible_J) / Model.Duration_s(Row);
    Result.UncorrectedMaximumRH_percent(Row) = RawPeakRH;
    Result.NodeRH_percent(Row, :) = relativeHumidity(w, Model.Temperature_C(Row, :), ...
        Model.Pressure_kPa(Row), Model.MolecularRatio);
    [wSupply, EndRoot, Cold_C] = controlledOutlet(w(3), Transfer);
    WarmRH = relativeHumidity(wSupply, max(Cold_C, Model.SupplyTemperature_C(Row)), ...
        Model.Pressure_kPa(Row), Model.MolecularRatio);
    ReturnRH = relativeHumidity(w(3), Model.ReturnTemperature_C(Row), Model.Pressure_kPa(Row), Model.MolecularRatio);
    EndRHError = abs(WarmRH - TargetRH);
    EndTemperatureError = abs(max(Cold_C, Model.SupplyTemperature_C(Row)) - Model.SupplyTemperature_C(Row));
    EndColdRH = relativeHumidity(wSupply, Cold_C, Model.Pressure_kPa(Row), Model.MolecularRatio);
    Result.MaximumRHError_percent = max(Result.MaximumRHError_percent, EndRHError);
    Result.MaximumTemperatureError_C = max(Result.MaximumTemperatureError_C, EndTemperatureError);
    Result.PeakColdRH_percent = max(Result.PeakColdRH_percent, EndColdRH);
    Result.RHError_percent(Row) = max(IntervalRHError, EndRHError);
    Result.TemperatureError_C(Row) = max(IntervalTemperatureError, EndTemperatureError);
    if EndRHError > Model.Settings.RHTolerance_percent || EndTemperatureError > Model.Settings.TemperatureTolerance_C ...
            || EndColdRH > 100 + 1e-6
        Result.Feasible = false;
        Result.Failure = "Interval-end target or saturation constraint failed.";
        Result.FailureSupplyRH_percent = WarmRH;
        Result.FailureSupplyTemperature_C = max(Cold_C, Model.SupplyTemperature_C(Row));
        Result.FailureColdRH_percent = EndColdRH;
        Result.FailureColdTemperature_C = Cold_C;
        Result.FailureMaximumSuitRH_percent = max([Result.NodeRH_percent(Row, :), ReturnRH, WarmRH]);
        Result.WorstTargetTime_min = Profile.EndTime_min(Row);
        return;
    end
    SampleIndex = SampleIndex + 1;
    EndCapacity = Model.DryFlow_kg_s(Row) * (g.Cp_J_kgK + wSupply * W.VaporCp_J_kgK);
    EndCooling = Model.DryFlow_kg_s(Row) * (g.Cp_J_kgK * (g.SuitTemperature_C - Cold_C) ...
        + w(3) * (W.VaporEnthalpyAtZero_J_kg + W.VaporCp_J_kgK * g.SuitTemperature_C) ...
        - wSupply * (W.VaporEnthalpyAtZero_J_kg + W.VaporCp_J_kgK * Cold_C)) ...
        - Model.DryFlow_kg_s(Row) * (w(3) - wSupply) * W.Cp_J_kgK * EndRoot;
    MinRoot_C = min(MinRoot_C, EndRoot);
    MaxRoot_C = max(MaxRoot_C, EndRoot);
    Samples(SampleIndex, :) = [Profile.EndTime_min(Row), Model.DryFlow_kg_s(Row), ...
        wSupply, Cold_C, max(Cold_C, Model.SupplyTemperature_C(Row)), ...
        EndCapacity * max(0, Model.SupplyTemperature_C(Row) - Cold_C), EndCooling, EndRoot, Model.DryFlow_kg_s(Row) * (w(3) - wSupply)];
    Result.MaximumRH_percent(Row) = max([PeakRH, Result.NodeRH_percent(Row, :), WarmRH, ReturnRH]);
    Result.AverageRH_percent(Row) = SuitRHSum / Steps;
    Means = Sums / Steps;
    Result.Removal_kg_s(Row) = Means(1);
    Result.MeanOutletW(Row) = Means(2);
    Result.CondenserOutlet_C(Row) = Means(3);
    Result.CondenserOutletRH_percent(Row) = Means(4);
    Result.Cooling_W(Row) = Means(5);
    Result.Reheat_W(Row) = Means(6);
    Result.ReheatedTemperature_C(Row) = Means(7);
    Result.ReheatedRH_percent(Row) = Means(8);
    Result.PeakCondenserOutlet_C(Row) = Peaks(1);
    Result.PeakCondenserOutletRH_percent(Row) = Peaks(2);
    Result.PeakCooling_W(Row) = Peaks(3);
    Result.PeakReheat_W(Row) = Peaks(4);
    Result.PeakReheatedRH_percent(Row) = Peaks(5);
    Result.MinimumRootTemperature_C(Row) = MinRoot_C;
    Result.MaximumRootTemperature_C(Row) = MaxRoot_C;
    Result.TotalRemoved_kg = Result.TotalRemoved_kg + Means(1) * Model.Duration_s(Row);
    Elapsed_s = Elapsed_s + Model.Duration_s(Row);
end
Result.Instantaneous = array2table(Samples(1:SampleIndex, :), 'VariableNames', ...
    {'Time_min', 'DryOxygenFlow_kg_s', 'OutletHumidityRatio', 'ColdTemperature_C', 'SupplyTemperature_C', 'Reheat_W', 'Cooling_W', 'RootTemperature_C', 'Removal_kg_s'});
Generated_kg = sum(sum(Model.Source_kg_s, 2) .* Model.Duration_s);
Result.MassResidual_kg = sum(Model.NodeDryMass_kg .* w + Liquid_kg) - InitialMass_kg ...
    - Generated_kg + Result.TotalRemoved_kg;
assert(abs(Result.MassResidual_kg) < 1e-8, 'RH:ControlledBalance', 'Vapor + stored liquid + collected water balance did not close.');
Result.FinalRegionLiquid_g = Liquid_kg * 1000;
FinalLiquidEnergy_J = sum(Liquid_kg .* W.Cp_J_kgK .* PreviousTemperature_C);
Result.PhaseEnergyResidual_J = PhaseBoundaryHeat_J + FinalLiquidEnergy_J ...
    - InitialLiquidEnergy_J - PhaseVaporEnergy_J;
assert(abs(Result.PhaseEnergyResidual_J) < 1e-6 * max(1, abs(PhaseVaporEnergy_J)), ...
    'RH:PhaseEnergyBalance', 'Phase-change/retained-liquid energy accounting did not close.');
end

function [wOut, Root, Cold_C] = controlledOutlet(wIn, Transfer)
% CONTROLLEDOUTLET Warm the roots until supply moisture reaches its target; never humidify.
% Inputs: wIn, Transfer.
% Outputs: wOut, Root, Cold_C.
% Units: SI; degC and explicit _min/_hr/_g field suffixes where used.
% Side effects: None; returns results through its output arguments.
% A dry inlet still needs sensible cooling. Target its existing humidity ratio
% so the controller selects a non-condensing root state instead of bypassing heat transfer.
TargetW = min(wIn, Transfer.TargetW);
Candidates = wIn - Transfer.Effectiveness .* max(0, wIn - Transfer.SurfaceW);
Upper = find(Candidates >= TargetW, 1);
if isempty(Upper)
    Upper = numel(Candidates);
end
Lower = max(1, Upper - 1);
Fraction = 0;
if Upper > Lower
    Fraction = (TargetW - Candidates(Lower)) / (Candidates(Upper) - Candidates(Lower));
    Fraction = min(1, max(0, Fraction));
end
% Piecewise linear response between neighbouring temperature states.
wOut = Candidates(Lower) + Fraction * (Candidates(Upper) - Candidates(Lower));
Root = Transfer.Root_C(Lower) + Fraction * (Transfer.Root_C(Upper) - Transfer.Root_C(Lower));
HeatTransmission = Transfer.HeatTransmission(Lower) ...
    + Fraction * (Transfer.HeatTransmission(Upper) - Transfer.HeatTransmission(Lower));
Cold_C = Root + (Transfer.Inlet_C - Root) * HeatTransmission;
end

function w = humidityRatio(RH, Temperature_C, Pressure_kPa, Ratio)
p = RH / 100 .* vaporPressure(Temperature_C);
w = Ratio * p ./ (Pressure_kPa * 1000 - p);
end

function RH = relativeHumidity(w, Temperature_C, Pressure_kPa, Ratio)
p = Pressure_kPa * 1000 .* w ./ (Ratio + w);
RH = 100 * p ./ vaporPressure(Temperature_C);
end

function p = vaporPressure(T)
p = 611.21 * exp((18.678 - T / 234.5) .* T ./ (257.14 + T));
end
