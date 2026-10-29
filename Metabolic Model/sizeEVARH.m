function Design = sizeEVARH(Profile, Gas, W, C, Separator, DrainPressure_Pa, Settings, GasProperties, AreaSizing)
% Size from coincident EVA states, then test humidity storage in three air nodes.
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
assert(Settings.MaximumSuitRH_percent > Settings.InitialSuitRH_percent ...
    && Settings.InitialSuitRH_percent > 0 && Settings.MaximumSuitRH_percent <= 100, ...
    'RH:RHControl', 'Initial RH must be below the maximum suit RH.');
N = height(Profile);
Source_kg_s = Profile.DesignMoisture_g_min / 60000 * Settings.LoadFOS;
Design.TotalMoisture_kg = sum(Source_kg_s .* Duration_s);
Design.Time_min = Profile.EndTime_min;
Area_m2 = Inf(N, 1);
Cooling_W = NaN(N, 1);
InletFlow_m3_s = zeros(N, 1);
FinTip_C = zeros(N, 1);
FinEfficiency = zeros(N, 1);
PeakResults = cell(N, 1);
ProfileGas = cell(N, 1);
StatusByInterval = strings(N, 1);
BufferGas = cell(N, 1);
NodeTemperature_C = [Profile.NeckMean_C, Profile.TorsoMean_C, Profile.LegMean_C];
mdot = Profile.DryOxygenFlow_kg_s;
PhysicalSource = Profile.PhysicalMoisture_g_min / 60000;
PhysicalOutletW = [Profile.NeckOutletW, Profile.TorsoOutletW, Profile.LegOutletW];
PhysicalZoneSource = mdot .* (PhysicalOutletW - [Profile.SupplyHumidityRatio, PhysicalOutletW(:, 1:2)]);
assert(max(abs(sum(PhysicalZoneSource, 2) - PhysicalSource)) < 2e-8, ...
    'RH:SourceBalance', 'Regional sources do not match exported net vapor.');
% FOS scales the existing regional net sources once, including any negative phase-change terms.
assert(all(Source_kg_s >= 0), 'RH:NegativeSource', 'Net-negative EVA source intervals need a separate condensation inventory treatment.');
Scale = ones(N, 1);
Nonzero = abs(PhysicalSource) > 1e-12;
Scale(Nonzero) = Source_kg_s(Nonzero) ./ PhysicalSource(Nonzero);
ZoneSource_kg_s = PhysicalZoneSource .* Scale;
% Preserve the exported net load exactly after regional state reconstruction.
ZoneSource_kg_s(:, 3) = ZoneSource_kg_s(:, 3) + Source_kg_s - sum(ZoneSource_kg_s, 2);
for Row = 1:N
    TrialGas = Gas;
    TrialGas.SuitTemperature_C = Profile.LegOutlet_C(Row);
    TrialGas.Pressure_kPa = Profile.Pressure_kPa(Row);
    w = Profile.LegOutletW(Row);
    p = TrialGas.Pressure_kPa * 1000 * w / (Gas.MolecularMassRatio + w);
    TrialGas.SuitRH_percent = 100 * p / vaporPressure(TrialGas.SuitTemperature_C);
    Q = mdot(Row) * Gas.Constant_J_kgK * (TrialGas.SuitTemperature_C + 273.15) ...
        / (TrialGas.Pressure_kPa * 1000 - p);
    TrialGas.Flow_CFM = Q * 60 / 0.028316846592;
    TrialGas = GasProperties(TrialGas, W, C);
    TrialWater = W;
    TrialWater.DesignRate_kg_s = Source_kg_s(Row);
    Result = AreaSizing(C.SurfaceTemperature_C, TrialGas, TrialWater, C);
    PeakResults{Row} = Result;
    StatusByInterval(Row) = Result.Status;
    ProfileGas{Row} = TrialGas;
    Area_m2(Row) = Result.RequiredArea_m2;
    Cooling_W(Row) = Result.CoolingDuty_W;
    InletFlow_m3_s(Row) = Q;
    FinTip_C(Row) = TrialGas.FinTipTemperature_C;
    FinEfficiency(Row) = TrialGas.FinEfficiency;
    % Buffer transfer coefficients are evaluated at the permitted return-air RH.
    % Fixed interval coefficients keep the gas-inventory model simple.
    TrialGas.SuitRH_percent = Settings.MaximumSuitRH_percent;
    p = vaporPressure(TrialGas.SuitTemperature_C) * TrialGas.SuitRH_percent / 100;
    Q = mdot(Row) * Gas.Constant_J_kgK * (TrialGas.SuitTemperature_C + 273.15) ...
        / (TrialGas.Pressure_kPa * 1000 - p);
    TrialGas.Flow_CFM = Q * 60 / 0.028316846592;
    BufferGas{Row} = GasProperties(TrialGas, W, C);
end
Design.StatusByInterval = StatusByInterval;
Design.PeakFeasible = all(isfinite(Area_m2)) && all(isfinite(Cooling_W)) ...
    && all(cellfun(@(r) r.Feasible, PeakResults));
[PeakArea_m2, Index] = max(Area_m2);
Design.Peak = PeakResults{Index};
Design.Peak.RequiredArea_m2 = PeakArea_m2;
Design.Peak.CoolingDuty_W = max(Cooling_W);
Design.PeakFlow_m3_s = max(InletFlow_m3_s);
Design.AverageCoolingDuty_W = sum(Cooling_W .* Duration_s) / sum(Duration_s);
Design.PeakSeparatorArea_m2 = separatorArea(max(Source_kg_s), W, Separator, DrainPressure_Pa);
% Check straight-channel pressure loss over the EVA for the installed peak channel count.
if isfinite(PeakArea_m2)
    PressureDrop_Pa = zeros(N, 1);
    for Row = 1:N
        g = ProfileGas{Row};
        v = g.Flow_m3_s / (Design.Peak.ChannelCount * C.ChannelGap_m * C.ChannelHeight_m);
        Re = g.Density_kg_m3 * v * g.HydraulicDiameter_m / g.Viscosity_Pa_s;
        a = g.AspectRatio;
        Po = 96 * (1 - 1.3553*a + 1.9467*a^2 - 1.7012*a^3 + 0.9564*a^4 - 0.2537*a^5);
        PressureDrop_Pa(Row) = Po / Re * C.ChannelLength_m / g.HydraulicDiameter_m * g.Density_kg_m3 * v^2 / 2;
    end
    Design.Peak.ChannelPressureDrop_Pa = max(PressureDrop_Pa);
end

%% Three-Node Humidity Inventory
% Equal free gas volumes. Initial gas density is a fixed reference inventory.
InitialW = humidityRatio(Settings.InitialSuitRH_percent, NodeTemperature_C(1, :), Profile.Pressure_kPa(1), Gas.MolecularMassRatio);
p = Profile.Pressure_kPa(1) * 1000 .* InitialW ./ (Gas.MolecularMassRatio + InitialW);
NodeDryMass_kg = Settings.FreeGasVolume_L / 3000 * (Profile.Pressure_kPa(1) * 1000 - p) ...
    ./ (Gas.Constant_J_kgK * (NodeTemperature_C(1, :) + 273.15));
Model = struct('Duration_s', Duration_s, 'Source_kg_s', ZoneSource_kg_s, ...
    'Temperature_C', NodeTemperature_C, 'ReturnTemperature_C', Profile.LegOutlet_C, ...
    'SupplyTemperature_C', Profile.SupplyTemperature_C, 'Pressure_kPa', Profile.Pressure_kPa, ...
    'DryFlow_kg_s', mdot, 'NodeDryMass_kg', NodeDryMass_kg, 'InitialW', InitialW, ...
    'Gas', {BufferGas}, 'Settings', Settings, 'MolecularRatio', Gas.MolecularMassRatio, ...
    'SurfacePressure_Pa', vaporPressure(C.SurfaceTemperature_C));
Ideal = humidityHistory(Inf, Model);
Design.IdealMaximumRH_percent = Ideal.MaximumRH_percent;
FirstViolation = find(Ideal.MaximumRH_percent > Settings.MaximumSuitRH_percent, 1);
Design.FirstRHViolation_min = NaN;
if ~isempty(FirstViolation)
    Design.FirstRHViolation_min = Profile.StartTime_min(1) + Ideal.FirstViolation_s / 60;
    % Above the allowed limit no accepted operating history is claimed.
    Design.IdealMaximumRH_percent(FirstViolation+1:end) = NaN;
end
Design.BufferedFeasible = max(Ideal.MaximumRH_percent) <= Settings.MaximumSuitRH_percent + 1e-6;
BufferedArea_m2 = Inf;
BufferedCooling_W = NaN;
BufferedSeparatorArea_m2 = Inf;
BufferedChannels = NaN;
BufferedWidth_mm = NaN;
BufferedRH = max(Ideal.MaximumRH_percent);
if ~Design.BufferedFeasible
    BufferedRH = NaN; % No physically accepted full-EVA maximum after exceeding the limit.
end
Design.BufferedMaximumRH_percent = NaN(N, 1);
Buffered = [];
Status = "No finite area meets the selected RH ceiling at the supplied airflow and root temperature.";
if Design.BufferedFeasible
    Low = 0;
    High = PeakArea_m2;
    if ~isfinite(High), High = 0.1; end
    Trial = humidityHistory(High, Model);
    while max(Trial.MaximumRH_percent) > Settings.MaximumSuitRH_percent && High < 100 * PeakArea_m2
        High = High * 2;
        Trial = humidityHistory(High, Model);
    end
    for Iteration = 1:24
        Mid = (Low + High) / 2;
        Trial = humidityHistory(Mid, Model);
        if max(Trial.MaximumRH_percent) <= Settings.MaximumSuitRH_percent
            High = Mid;
        else
            Low = Mid;
        end
    end
    BufferedArea_m2 = High;
    Buffered = humidityHistory(High, Model);
    Design.BufferedMaximumRH_percent = Buffered.MaximumRH_percent;
    Design.BufferedCollectedWater_kg = Buffered.TotalRemoved_kg;
    BufferedRH = max(Buffered.MaximumRH_percent);
    BufferedSeparatorArea_m2 = separatorArea(max(Buffered.Removal_kg_s), W, Separator, DrainPressure_Pa);
    PerChannelArea = 2 * (C.ChannelHeight_m + C.ChannelGap_m) * C.ChannelLength_m;
    BufferedChannels = ceil(High / PerChannelArea);
    BufferedWidth_mm = (BufferedChannels * C.ChannelGap_m + (BufferedChannels + 1) * C.FinThickness_m) * 1000;
    % Include sensible cooling at installed area and latent removal from the transient balance.
    Duty = zeros(N, 1);
    for Row = 1:N
        g = BufferGas{Row};
        CapacityRate = g.DryFlow_kg_s * (g.Cp_J_kgK + g.InletHumidityRatio * W.VaporCp_J_kgK);
        TOut = C.SurfaceTemperature_C + (g.SuitTemperature_C - C.SurfaceTemperature_C) ...
            * exp(-g.HeatTransfer_W_m2K * g.SurfaceHeatEfficiency * High / CapacityRate);
        Duty(Row) = CapacityRate * (g.SuitTemperature_C - TOut) + Buffered.Removal_kg_s(Row) ...
            * (W.VaporEnthalpyAtZero_J_kg + (W.VaporCp_J_kgK - W.Cp_J_kgK) * C.SurfaceTemperature_C);
    end
    BufferedCooling_W = max(Duty);
    Status = "Selected RH ceiling met at all modelled nodes; prescribed source/temperature approximation.";
end
PeakRH = 100 * Profile.Pressure_kPa * 1000 .* PhysicalOutletW ...
    ./ (Gas.MolecularMassRatio + PhysicalOutletW) ./ vaporPressure([Profile.NeckOutlet_C, Profile.TorsoOutlet_C, Profile.LegOutlet_C]);
Case = ["Peak: original JOS-3 air states"; "Allow suit RH up to selected ceiling"];
Feasible = [Design.PeakFeasible; Design.BufferedFeasible];
CondenserArea_m2 = [PeakArea_m2; BufferedArea_m2];
SeparatorArea_m2 = [Design.PeakSeparatorArea_m2; BufferedSeparatorArea_m2];
Channels = [Design.Peak.ChannelCount; BufferedChannels];
CoreLength_mm = repmat(C.ChannelLength_m * 1000, 2, 1);
CoreHeight_mm = repmat(C.ChannelHeight_m * 1000, 2, 1);
CoreWidth_mm = [Design.Peak.CoreWidth_m * 1000; BufferedWidth_mm];
PeakCooling_W = [Design.Peak.CoolingDuty_W; BufferedCooling_W];
MaximumSuitRH_percent = [max(PeakRH, [], 'all'); BufferedRH];
MinimumFinEfficiency = [min(FinEfficiency); NaN];
WarmestFin_C = [max(FinTip_C); NaN];
PeakNote = "Sized over every interval; original air profile is not constrained to the selected RH ceiling.";
if ~Design.PeakFeasible
    PeakNote = "Wall-transfer requirements only: some intervals predict fog; complete hardware size is not validated.";
end
Note = [PeakNote; Status];
Design.Summary = table(Case, Feasible, CondenserArea_m2, SeparatorArea_m2, Channels, ...
    CoreLength_mm, CoreWidth_mm, CoreHeight_mm, PeakCooling_W, MaximumSuitRH_percent, ...
    MinimumFinEfficiency, WarmestFin_C, Note);
Design.TimeHistory = table(Profile.StartTime_min, Profile.EndTime_min, Source_kg_s * 60000, ...
    Area_m2, Cooling_W, FinTip_C, FinEfficiency, Ideal.MaximumRH_percent, ...
    'VariableNames', {'StartTime_min', 'EndTime_min', 'DesignMoisture_g_min', ...
    'RequiredArea_m2', 'RequiredCooling_W', 'WarmestFin_C', 'FinEfficiency', 'IdealSinkMaximumRH_percent'});
%% Selected Condensers - Minimum Area and Near-Capacity Area
% Exact equilibrium capacity needs infinite area. Use 99% approach instead.
CapacityFraction = Settings.CapacityFraction;
assert(CapacityFraction > 0 && CapacityFraction < 1, 'RH:CapacityFraction', ...
    'Capacity fraction must be between zero and one.');
PerChannelArea = 2 * (C.ChannelHeight_m + C.ChannelGap_m) * C.ChannelLength_m;
CapacityArea_m2 = max(cellfun(@(g) -g.Flow_m3_s ...
    / (g.MassTransfer_m_s * g.SurfaceMassEfficiency) * log(1 - CapacityFraction), BufferGas));
AverageWater = W;
AverageWater.DesignRate_kg_s = Design.TotalMoisture_kg / sum(Duration_s);
AverageDesign = AreaSizing(C.SurfaceTemperature_C, Gas, AverageWater, C);
SelectedArea = [AverageDesign.RequiredArea_m2; CapacityArea_m2];
Case = ["Minimum area for average moisture load"; "99% of air carrying capacity"];
Channels = ceil(SelectedArea / PerChannelArea);
InstalledArea_m2 = Channels * PerChannelArea;
CoreWidth_mm = (Channels * C.ChannelGap_m + (Channels + 1) * C.FinThickness_m) * 1000;
PeakCooling_W = NaN(2, 1);
AverageCooling_W = NaN(2, 1);
CollectedWater_g = NaN(2, 1);
MaximumSuitRH_percent = NaN(2, 1);
PeakRemoval_g_min = NaN(2, 1);
MaximumSaturatedCapacity_g_min = NaN(2, 1);
AverageRemoval_g_min = NaN(2, 1);
AverageCondenserOutlet_C = NaN(2, 1);
PeakCondenserOutlet_C = NaN(2, 1);
AverageCondenserOutletRH_percent = NaN(2, 1);
PeakCondenserOutletRH_percent = NaN(2, 1);
MeetsRHLimit = false(2, 1);
Note = strings(2, 1);
FirstLimitExceeded_min = NaN(2, 1);
FirstSaturation_min = NaN(2, 1);
Design.SelectedHistory = cell(2, 1);
Design.SelectedPressureDrop_Pa = NaN(2, 1);
for Selection = 1:2
    if ~isfinite(InstalledArea_m2(Selection))
        Note(Selection) = "Average moisture exceeds the inlet air carrying capacity; no finite area.";
        continue;
    end
    History = humidityHistory(InstalledArea_m2(Selection), Model);
    if isfinite(History.FirstViolation_s)
        FirstLimitExceeded_min(Selection) = Profile.StartTime_min(1) + History.FirstViolation_s / 60;
    end
    Duty = zeros(N, 1);
    for Row = 1:N
        g = BufferGas{Row};
        CapacityRate = g.DryFlow_kg_s * (g.Cp_J_kgK + g.InletHumidityRatio * W.VaporCp_J_kgK);
        History.CondenserOutlet_C(Row, 1) = C.SurfaceTemperature_C ...
            + (Profile.LegOutlet_C(Row) - C.SurfaceTemperature_C) ...
            * exp(-g.HeatTransfer_W_m2K * g.SurfaceHeatEfficiency * InstalledArea_m2(Selection) / CapacityRate);
        Duty(Row) = CapacityRate * (Profile.LegOutlet_C(Row) - History.CondenserOutlet_C(Row)) ...
            + History.Removal_kg_s(Row) * (W.VaporEnthalpyAtZero_J_kg ...
            + (W.VaporCp_J_kgK - W.Cp_J_kgK) * C.SurfaceTemperature_C);
    end
    % Cold gas leaving the condenser, before the assumed external reheating.
    OutletSaturation_Pa = vaporPressure(History.CondenserOutlet_C);
    History.CondenserOutletRH_percent = 100 * History.MeanOutletVaporPressure_Pa ./ OutletSaturation_Pa;
    History.PeakCondenserOutletRH_percent = 100 * History.PeakOutletVaporPressure_Pa ./ OutletSaturation_Pa;
    AverageCondenserOutlet_C(Selection) = sum(History.CondenserOutlet_C .* Duration_s) / sum(Duration_s);
    PeakCondenserOutlet_C(Selection) = max(History.CondenserOutlet_C);
    AverageCondenserOutletRH_percent(Selection) = sum(History.CondenserOutletRH_percent .* Duration_s) / sum(Duration_s);
    PeakCondenserOutletRH_percent(Selection) = max(History.PeakCondenserOutletRH_percent);
    % Recalculate straight-channel friction for the selected installed stack.
    PressureDrop_Pa = zeros(N, 1);
    for Row = 1:N
        g = ProfileGas{Row};
        Velocity_m_s = g.Flow_m3_s / (Channels(Selection) * C.ChannelGap_m * C.ChannelHeight_m);
        Re = g.Density_kg_m3 * Velocity_m_s * g.HydraulicDiameter_m / g.Viscosity_Pa_s;
        a = g.AspectRatio;
        Po = 96 * (1 - 1.3553*a + 1.9467*a^2 - 1.7012*a^3 + 0.9564*a^4 - 0.2537*a^5);
        PressureDrop_Pa(Row) = Po / Re * C.ChannelLength_m / g.HydraulicDiameter_m ...
            * g.Density_kg_m3 * Velocity_m_s^2 / 2;
    end
    Design.SelectedPressureDrop_Pa(Selection) = max(PressureDrop_Pa);
    % Continue the inventory through RH excursions; above 100% is a diagnostic,
    % not a physical vapor state. This calculation does not add fog/liquid transport.
    Invalid = find(History.MaximumRH_percent > 100, 1);
    PeakCooling_W(Selection) = max(Duty);
    AverageCooling_W(Selection) = sum(Duty .* Duration_s) / sum(Duration_s);
    CollectedWater_g(Selection) = History.TotalRemoved_kg * 1000;
    MaximumSuitRH_percent(Selection) = max(History.MaximumRH_percent);
    PeakRemoval_g_min(Selection) = max(History.Removal_kg_s) * 60000;
    AverageRemoval_g_min(Selection) = History.TotalRemoved_kg * 60000 / sum(Duration_s);
    % Physical transfer ceiling at saturated return air, using each interval's T/flow.
    SaturatedW = humidityRatio(100, Profile.LegOutlet_C, Profile.Pressure_kPa, Gas.MolecularMassRatio);
    SurfaceW = Gas.MolecularMassRatio * Model.SurfacePressure_Pa ...
        ./ (Profile.Pressure_kPa * 1000 - Model.SurfacePressure_Pa);
    Effectiveness = cellfun(@(g) 1 - exp(-g.MassTransfer_m_s * g.SurfaceMassEfficiency ...
        * InstalledArea_m2(Selection) / g.Flow_m3_s), BufferGas);
    MaximumSaturatedCapacity_g_min(Selection) = max(mdot .* max(0, SaturatedW - SurfaceW) .* Effectiveness) * 60000;
    MeetsRHLimit(Selection) = MaximumSuitRH_percent(Selection) <= Settings.MaximumSuitRH_percent + 1e-6;
    Note(Selection) = "Full diagnostic run; prescribed body temperatures/sources.";
    if ~isempty(Invalid)
        FirstSaturation_min(Selection) = Profile.StartTime_min(Invalid);
        Note(Selection) = "Above 100% RH: diagnostic vapor inventory only; removal/cooling may be overstated.";
    end
    Design.SelectedHistory{Selection} = History;
end
CoreLength_mm = repmat(C.ChannelLength_m * 1000, 2, 1);
CoreHeight_mm = repmat(C.ChannelHeight_m * 1000, 2, 1);
CoreVolume_L = CoreLength_mm .* CoreWidth_mm .* CoreHeight_mm / 1e6;
Design.SelectedSummary = table(Case, MeetsRHLimit, InstalledArea_m2, Channels, ...
    CoreLength_mm, CoreWidth_mm, CoreHeight_mm, CoreVolume_L, PeakCooling_W, AverageCooling_W, AverageRemoval_g_min, PeakRemoval_g_min, MaximumSaturatedCapacity_g_min, ...
    CollectedWater_g, MaximumSuitRH_percent, FirstLimitExceeded_min, FirstSaturation_min, ...
    AverageCondenserOutlet_C, PeakCondenserOutlet_C, AverageCondenserOutletRH_percent, PeakCondenserOutletRH_percent, Note);
Design.NodeTemperature_C = NodeTemperature_C;
Design.ReturnTemperature_C = Profile.LegOutlet_C;
Design.SupplyTemperature_C = Profile.SupplyTemperature_C;

Design.BufferMassResidual_kg = Ideal.MassResidual_kg;
if isfield(Settings, 'Verbose') && Settings.Verbose
fprintf('RH storage model: %.2f L free gas, equal node volumes; maximum RH checked in neck, torso, legs and supply.\n', Settings.FreeGasVolume_L);
if ~Design.BufferedFeasible
    fprintf('Ideal sink first exceeds the selected RH ceiling at %.2f min; no finite design is reported.\n', Design.FirstRHViolation_min);
end
end
end

function Result = humidityHistory(Area_m2, Model)
% Stable explicit gas balances with finite air inventory and continuous condenser operation.
N = numel(Model.Duration_s);
w = Model.InitialW;
InitialMass = sum(Model.NodeDryMass_kg .* w);
Result.MaximumRH_percent = zeros(N, 1);
Result.Removal_kg_s = zeros(N, 1);
Result.NodeRH_percent = zeros(N, 3);
Result.EndMaximumSuitRH_percent = zeros(N, 1);
Result.MeanOutletVaporPressure_Pa = zeros(N, 1);
Result.PeakOutletVaporPressure_Pa = zeros(N, 1);
TotalRemoved_kg = 0;
Elapsed_s = 0;
Result.FirstViolation_s = NaN;
for Row = 1:N
    g = Model.Gas{Row};
    wSurface = Model.MolecularRatio * Model.SurfacePressure_Pa ...
        / (Model.Pressure_kPa(Row) * 1000 - Model.SurfacePressure_Pa);
    VaporTransmission = exp(-g.MassTransfer_m_s * g.SurfaceMassEfficiency * Area_m2 / g.Flow_m3_s);
    Steps = ceil(Model.Duration_s(Row) / min(Model.Settings.MaximumStep_s, ...
        0.2 * min(Model.NodeDryMass_kg) / Model.DryFlow_kg_s(Row)));
    dt = Model.Duration_s(Row) / Steps;
    Removed = 0;
    PeakRH = 0;
    OutletPressureSum_Pa = 0;
    PeakOutletPressure_Pa = 0;
    for Step = 1:Steps
        NodeRH = relativeHumidity(w, Model.Temperature_C(Row, :), Model.Pressure_kPa(Row), Model.MolecularRatio);
        beta = VaporTransmission;
        wSupply = w(3) - (1 - beta) * max(0, w(3) - wSurface);
        OutletPressure_Pa = Model.Pressure_kPa(Row) * 1000 * wSupply / (Model.MolecularRatio + wSupply);
        OutletPressureSum_Pa = OutletPressureSum_Pa + OutletPressure_Pa;
        PeakOutletPressure_Pa = max(PeakOutletPressure_Pa, OutletPressure_Pa);
        SupplyRH = relativeHumidity(wSupply, Model.SupplyTemperature_C(Row), Model.Pressure_kPa(Row), Model.MolecularRatio);
        ReturnRH = relativeHumidity(w(3), Model.ReturnTemperature_C(Row), Model.Pressure_kPa(Row), Model.MolecularRatio);
        PeakRH = max([PeakRH, NodeRH, SupplyRH, ReturnRH]);
        if isnan(Result.FirstViolation_s) && PeakRH > Model.Settings.MaximumSuitRH_percent
            Result.FirstViolation_s = Elapsed_s + (Step - 1) * dt;
        end
        Removal = Model.DryFlow_kg_s(Row) * (w(3) - wSupply);
        Incoming = [wSupply, w(1:2)];
        w = w + dt * (Model.DryFlow_kg_s(Row) * (Incoming - w) ...
            + Model.Source_kg_s(Row, :)) ./ Model.NodeDryMass_kg;
        assert(all(w >= -1e-10), 'RH:Inventory', 'Negative node humidity; revise timestep or source approximation.');
        Removed = Removed + Removal * dt;
    end
    PeakRH = max([PeakRH, relativeHumidity(w, Model.Temperature_C(Row, :), ...
        Model.Pressure_kPa(Row), Model.MolecularRatio)]);
    Result.MaximumRH_percent(Row) = PeakRH;
    Result.NodeRH_percent(Row, :) = relativeHumidity(w, Model.Temperature_C(Row, :), ...
        Model.Pressure_kPa(Row), Model.MolecularRatio);
    wSupply = w(3) - (1 - VaporTransmission) * max(0, w(3) - wSurface);
    Result.MeanOutletVaporPressure_Pa(Row) = OutletPressureSum_Pa / Steps;
    EndOutletPressure_Pa = Model.Pressure_kPa(Row) * 1000 * wSupply / (Model.MolecularRatio + wSupply);
    Result.PeakOutletVaporPressure_Pa(Row) = max(PeakOutletPressure_Pa, EndOutletPressure_Pa);
    Result.EndMaximumSuitRH_percent(Row) = max([Result.NodeRH_percent(Row, :), ...
        relativeHumidity(wSupply, Model.SupplyTemperature_C(Row), Model.Pressure_kPa(Row), Model.MolecularRatio), ...
        relativeHumidity(w(3), Model.ReturnTemperature_C(Row), Model.Pressure_kPa(Row), Model.MolecularRatio)]);
    Result.Removal_kg_s(Row) = Removed / Model.Duration_s(Row);
    TotalRemoved_kg = TotalRemoved_kg + Removed;
    Elapsed_s = Elapsed_s + Model.Duration_s(Row);
end
Generated = sum(sum(Model.Source_kg_s, 2) .* Model.Duration_s);
Result.TotalRemoved_kg = TotalRemoved_kg;
Result.MassResidual_kg = sum(Model.NodeDryMass_kg .* w) - InitialMass - Generated + TotalRemoved_kg;
assert(abs(Result.MassResidual_kg) < 1e-8, 'RH:TransientBalance', 'Transient water balance did not close.');
end

function A = separatorArea(Rate_kg_s, W, Separator, Pressure_Pa)
A = Rate_kg_s / W.Density_kg_m3 * W.Viscosity_Pa_s * Separator.Thickness_m ...
    / (Separator.Permeability_m2 * Separator.PermeabilityRetention * Pressure_Pa);
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
