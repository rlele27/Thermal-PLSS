function testEVARHSizing
% Deterministic integration tests for search endpoints, control and water balance.
addpath(fileparts(fileparts(mfilename('fullpath'))));
clear sizeEVARH
propertyCallCount("reset");
ratio = 0.01801528 / 0.0319988;
pressure = 31.7159;
ps = @(T) 611.21 * exp((18.678 - T / 234.5) .* T ./ (257.14 + T));
p = 0.5 * ps(18);
w = ratio * p / (pressure * 1000 - p);
Profile = table(0, 2, 0.18, 0.18, pressure, 0.001, 18, w, ...
    30, 30, 30, 30, 30, 30, w+0.001, w+0.002, w+0.003, ...
    'VariableNames', {'StartTime_min','EndTime_min','DesignMoisture_g_min', ...
    'PhysicalMoisture_g_min','Pressure_kPa','DryOxygenFlow_kg_s', ...
    'SupplyTemperature_C','SupplyHumidityRatio','NeckMean_C','TorsoMean_C', ...
    'LegMean_C','NeckOutlet_C','TorsoOutlet_C','LegOutlet_C', ...
    'NeckOutletW','TorsoOutletW','LegOutletW'});
Gas = struct('MolecularMassRatio', ratio, 'Constant_J_kgK', 259.84);
W = struct('Cp_J_kgK', 4180, 'VaporCp_J_kgK', 1860, 'VaporEnthalpyAtZero_J_kg', 2500900);
C = struct('SurfaceTemperature_C', 1, 'ChannelHeight_m', 0.02, 'ChannelGap_m', 0.002, ...
    'ChannelLength_m', 0.04, 'FinThickness_m', 0.001);
S = struct('EquilibriumCondensation', false, 'UseTransferCache', false, 'Duration_min', 2, 'MaximumSuitRH_percent', 100, ...
    'InitialSuitRH_percent', 50, 'SupplyRH_percent', 50, 'SizeWeight', 1, ...
    'FreeGasVolume_L', 42, 'ChannelBounds', [1, 150], ...
    'RootTemperatureBounds_C', [1, 5], 'RootTemperatureStep_C', 2, ...
    'RHTolerance_percent', 0.5, 'TemperatureTolerance_C', 0.1, ...
    'ControlTemperaturePoints', 32, 'InternalStep_s', 1);
Warmer = @(H, N) struct('Area_m2', N, 'PeakDuty_W', max(H.Instantaneous.Reheat_W));
D = sizeEVARH(Profile, Gas, W, C, S, @properties, Warmer);
assert(D.Feasible, 'Synthetic wet test must be feasible.');
assert(abs(D.BufferMassResidual_kg) < 1e-8);
assert(D.SelectedSummary.MaximumRHError_percent <= S.RHTolerance_percent);
assert(D.SelectedSummary.MaximumTemperatureError_C <= S.TemperatureTolerance_C);
assert(height(D.SelectedHistory{1}.Instantaneous) == 121);
assert(D.SelectedSummary.Channels == min(D.SearchResults.Channels(D.SearchResults.Feasible)));
% Regional humidity states are outlet states; changing mean-temperature
% reporting columns must not change the inventory/selected hardware.
MeanVariant = Profile;
MeanVariant.NeckMean_C = 10;
MeanVariant.TorsoMean_C = 10;
MeanVariant.LegMean_C = 10;
SameOutlet = sizeEVARH(MeanVariant, Gas, W, C, S, @properties, Warmer);
assert(SameOutlet.Feasible && SameOutlet.SelectedSummary.Channels == D.SelectedSummary.Channels);
assert(SameOutlet.RootFloor_C == D.RootFloor_C);
assert(max(SameOutlet.LoadDiagnostics.FormerMeanTemperatureBasisRH_percent) ...
    > max(SameOutlet.LoadDiagnostics.DesignSteadyMaximumRH_percent));
LowReportingThreshold = S;
LowReportingThreshold.MaximumSuitRH_percent = 10;
DiagnosticOnly = sizeEVARH(Profile, Gas, W, C, LowReportingThreshold, @properties, Warmer);
assert(DiagnosticOnly.Feasible && DiagnosticOnly.SelectedSummary.Channels == D.SelectedSummary.Channels);
assert(~DiagnosticOnly.SelectedSummary.RegionalRHConstraintApplied);
% Regional supersaturation may be reported without rejecting an otherwise
% compliant supply. Slower sensible transfer avoids cold-outlet fog in this fixture.
WetRegional = Profile;
WetRegional.DesignMoisture_g_min = 4.5;
WetRegional.PhysicalMoisture_g_min = 4.5;
WetRegional.NeckOutletW = w + 0.025;
WetRegional.TorsoOutletW = w + 0.050;
WetRegional.LegOutletW = w + 0.075;
Regional = sizeEVARH(WetRegional, Gas, W, C, S, @regionalProperties, Warmer);
assert(Regional.Feasible);
assert(Regional.SelectedSummary.MaximumSuitRH_percent > 100);
assert(Regional.SelectedSummary.RegionalSupersaturation_min > 0);
assert(~Regional.SelectedSummary.MeetsRHLimit);
assert(Regional.SelectedSummary.MaximumRHError_percent <= S.RHTolerance_percent);
assert(abs(Regional.BufferMassResidual_kg) < 1e-8);
% The same wet load with equilibrium enabled stores liquid instead of RH >100%.
PhaseSettings = S;
PhaseSettings.EquilibriumCondensation = true;
PhaseSettings.InitialRegionalLiquid_g = [0, 0, 0];
Equilibrium = sizeEVARH(WetRegional, Gas, W, C, PhaseSettings, @regionalProperties, Warmer);
assert(Equilibrium.Feasible);
assert(Equilibrium.SelectedSummary.MaximumSuitRH_percent <= 100 + 1e-6);
assert(Equilibrium.SelectedSummary.FinalRegionalLiquid_g > 0);
assert(Equilibrium.SelectedSummary.TotalRegionalCondensation_g > 0);
assert(abs(Equilibrium.BufferMassResidual_kg) < 1e-8);
assert(abs(Equilibrium.PhaseEnergyResidual_J) < 1e-6);
assert(Equilibrium.SelectedSummary.AveragePhaseHeatSink_W > 0);
PhaseSettings.UseTransferCache = true;
CachedEquilibrium = sizeEVARH(WetRegional, Gas, W, C, PhaseSettings, @regionalProperties, Warmer);
assert(isequaln(CachedEquilibrium.SelectedSummary, Equilibrium.SelectedSummary));
% Stored liquid experiences a prescribed-temperature change; account for its
% sensible heat separately from latent heat and close the phase-energy balance.
TwoIntervals = [Profile; Profile];
TwoIntervals.StartTime_min = [0; 1]; TwoIntervals.EndTime_min = [1; 2];
for Field = ["NeckMean_C", "TorsoMean_C", "LegMean_C", "NeckOutlet_C", "TorsoOutlet_C", "LegOutlet_C"]
    TwoIntervals.(Field)(2) = 25;
end
Stored = PhaseSettings;
Stored.InitialRegionalLiquid_g = [10, 10, 10];
TemperatureChange = sizeEVARH(TwoIntervals, Gas, W, C, Stored, @regionalProperties, Warmer);
assert(TemperatureChange.Feasible);
assert(abs(TemperatureChange.PhaseEnergyResidual_J) < 1e-6);
assert(any(TemperatureChange.SelectedHistory{1}.LiquidSensibleHeat_W < 0));
assert(TemperatureChange.SelectedSummary.TotalRegionalReevaporation_g > 0);
% Cache changes neither the search results nor the selected physical history.
CachedSettings = S;
CachedSettings.UseTransferCache = true;
Cached = sizeEVARH(Profile, Gas, W, C, CachedSettings, @properties, Warmer);
assert(isequaln(Cached.SelectedSummary, D.SelectedSummary));
propertyCallCount("reset");
Repeat = sizeEVARH(Profile, Gas, W, C, CachedSettings, @properties, Warmer);
assert(propertyCallCount("read") == 0, 'An identical response must not recompute wet-fin properties.');
assert(isequaln(Repeat.SearchResults, D.SearchResults));
assert(isequaln(Repeat.SelectedHistory, D.SelectedHistory));
ChangedC = C;
ChangedC.FinThickness_m = C.FinThickness_m * 1.01;
sizeEVARH(Profile, Gas, W, ChangedC, CachedSettings, @properties, Warmer);
assert(propertyCallCount("read") > 0, 'A geometry change must invalidate the transfer cache.');
assert(D.NextSmallerChecked);
Previous = D.SearchResults.RootFloor_C == D.RootFloor_C ...
    & D.SearchResults.Channels == D.SelectedSummary.Channels - 1;
assert(any(Previous) && ~any(D.SearchResults.Feasible(Previous)));
S.SizeWeight = 0.5;
Balanced = sizeEVARH(Profile, Gas, W, C, S, @properties, Warmer);
assert(Balanced.Feasible);
assert(abs(Balanced.Objective - min(Balanced.SearchResults.Objective)) < 1e-12);
Auto = S;
Auto.AutoRootUpperDewPoint = true;
Auto.RootDewPointReduction_fraction = 0.25;
Auto.RootTemperatureBounds_C(2) = 99; % Must be replaced by target dew point.
Auto.ChannelBounds = [1, 2]; % Only bounds calculation is under test here.
AutoD = sizeEVARH(Profile, Gas, W, C, Auto, @properties, Warmer);
assert(abs(ps(AutoD.RootTemperatureBounds_C(2) / 0.75) - 0.5 * ps(18)) < 1e-6);
WarmerTarget = Profile;
WarmerTarget.SupplyTemperature_C = 19;
AutoWarm = sizeEVARH(WarmerTarget, Gas, W, C, Auto, @properties, Warmer);
assert(AutoWarm.RootTemperatureBounds_C(2) > AutoD.RootTemperatureBounds_C(2));
S.SizeWeight = 0;
Warm = sizeEVARH(Profile, Gas, W, C, S, @properties, Warmer);
assert(Warm.Feasible);
assert(Warm.RootFloor_C == max(Warm.SearchResults.RootFloor_C(Warm.SearchResults.Feasible)));
assert(Warm.SelectedSummary.Channels >= D.SelectedSummary.Channels);
Rescored = reweightEVADesign(D, 0);
assert(isequaln(Rescored.SelectedSummary, Warm.SelectedSummary));
assert(isequaln(Rescored.SelectedHistory, Warm.SelectedHistory));
% No humidifier: dry initial air must fail, even with a large condenser.
S.InitialSuitRH_percent = 5;
Dry = sizeEVARH(Profile, Gas, W, C, S, @properties, Warmer);
assert(~Dry.Feasible && isempty(Dry.SelectedSummary));
% A failing warmer cannot be accepted as a feasible condenser/system design.
S.InitialSuitRH_percent = 50;
Blocked = sizeEVARH(Profile, Gas, W, C, S, @rejectWarmer);
assert(~Blocked.Feasible);
fprintf('Weighted EVA sizing integration tests PASSED.\n');
end

function g = properties(g, W, C) %#ok<INUSD>
% Controlled analytical transfer fixture; no claim of physical O2 properties.
propertyCallCount("increment");
p = 611.21 * exp((18.678 - g.SuitTemperature_C / 234.5) * g.SuitTemperature_C / (257.14 + g.SuitTemperature_C));
g.InletHumidityRatio = g.MolecularMassRatio * p / (g.Pressure_kPa * 1000 - p);
g.DryFlow_kg_s = 0.001;
g.Flow_m3_s = 0.001;
g.Density_kg_m3 = 0.4;
g.Viscosity_Pa_s = 2e-5;
g.Cp_J_kgK = 918;
g.MassTransfer_m_s = 0.015;
g.SurfaceMassEfficiency = 1;
g.SurfaceHeatEfficiency = 1;
g.HeatTransfer_W_m2K = 15 * g.DryFlow_kg_s * (g.Cp_J_kgK + g.InletHumidityRatio * W.VaporCp_J_kgK);
end

function D = rejectWarmer(H, N) %#ok<STOUT,INUSD>
error('RH:AirWarmerSupply', 'Synthetic heating-water failure.');
end

function g = regionalProperties(g, W, C)
g = properties(g, W, C);
g.HeatTransfer_W_m2K = 0.6 * g.HeatTransfer_W_m2K;
end

function Value = propertyCallCount(Action)
persistent Count
if isempty(Count), Count = 0; end
switch Action
    case "reset", Count = 0;
    case "increment", Count = Count + 1;
end
Value = Count;
end
