clearvars;
% Retain stage 1 command-window tables and figures when running sequentially.

%% Inputs - files, reporting and sensitivity
DataFile = "+Data_Functions/EVA_Data.mat";
PlotResults = true;
RunSensitivity = true;
SensitivityChanges_percent = [-50,-10,10,50];

%% Inputs - condenser geometry
% Condenser Geometry and Material
Condenser.SurfaceTemperature_C = 1; % Minimum fin-root temperature; control may warm the roots.
Condenser.ChannelGap_m = 0.08 * 0.0254;
Condenser.FinThickness_m = 0.07 * 0.0254;
Condenser.ChannelHeight_m = 0.7 * 0.0254;
Condenser.ChannelLength_m = 1.72 * 0.0254;
Condenser.FinConductivity_W_mK = 70; % ASSUMED porous-graphite proxy, not measured PG-45.
Condenser.FinNodes = 12; % Conduction intervals over half the fin height.


%% Inputs - humidity inventory and condenser control
EVA_Sizing.FreeGasVolume_L = 1.5 * 28.316846592; % NASA EMU range: 1.5-2.0 ft3; editable analogue.
EVA_Sizing.MaximumSuitRH_percent = 100; % Reporting threshold only; not a sizing constraint.
EVA_Sizing.UseTransferCache = true; % Reuse identical wet-fin responses across sensitivity cases.
EVA_Sizing.EquilibriumCondensation = true; % Isothermal phase equilibrium at prescribed JOS-3 temperatures.
EVA_Sizing.InitialRegionalLiquid_g = [0, 0, 0]; % Additional local liquid, separate from JOS-3 condensate.
EVA_Sizing.InitialSuitRH_percent = []; % Empty: inherit saved EVA supply RH; numeric value overrides.
EVA_Sizing.Verbose = false;

%% Inputs - condenser search
% Weighted search: 1 favours small size; 0 favours warmer allowed root floors.
EVA_Sizing.SizeWeight = 0.5;
EVA_Sizing.ChannelBounds = [1, 200]; % Inclusive whole-channel search bounds.
EVA_Sizing.RootDewPointReduction_fraction = 0.25; % Applied to dew-point value in deg C.
RootLowerBound_C = 1; % Editable minimum root-floor search bound.
EVA_Sizing.AutoRootUpperDewPoint = true; % Recompute for each sensitivity target.
EVA_Sizing.RootTemperatureStep_C = 2; % Grid resolution; not continuous optimisation.
EVA_Sizing.RHTolerance_percent = 1; % Absolute RH percentage points at final supply.
EVA_Sizing.TemperatureTolerance_C = 0.5; % Final supply temperature tolerance.
EVA_Sizing.ControlTemperaturePoints = 8; % Root-temperature response points; ideal control without lag.
EVA_Sizing.InternalStep_s = 1; % Fixed RH inventory and condenser-control timestep (s).

%% Inputs - water-vapor property model
VaporCp_J_kgK = 1860;
VaporEnthalpyAtZero_J_kg = 2500900;
VaporGasConstant_J_kgK = 461.51805;

%% Inputs - packaging, reheater and liquid storage
% Package and Material
GraphiteDensity_kg_m3 = 1500; % ASSUMED PG-45 bulk density; confirm selected material.
AluminiumDensity_kg_m3 = 2700; % NASA 6061 material reference; see sources file.
PorousBaseThickness_m = 0.001; % ASSUMED top/bottom porous bases; no separate casing.
CondenserRoutingDepth_m = 0.010; % ASSUMED rectangular allowance below fins for separate water-removal and cooling-fluid routes.
% Routing hardware material and mass are unselected; this allowance adds volume only.

%% Inputs - air warmer
% NASA PLSS 2.0 Counterflow Plate-Fin Package Estimate
% Quinn et al. (2013), Table 3 test 10; see RH_Component_Sizing_Sources.md.
AirWarmer.WaterInlet_C = []; % Empty: inherit saved EVA LCG reference inlet; numeric value overrides.
AirWarmer.WaterFlow_kg_h = []; % Empty: use latest off-nominal peak LCG flow as a sizing assumption.
% Independent, constant reheater circuit flow; not the instantaneous LCG flow.
% Reheater branch and bypass recombine in their own circuit.
% LCG inlet control is independent; the shared heat-rejection plant is not modeled.
AirWarmer.ReferenceEffectiveness = 0.95;
AirWarmer.ReferenceGasPressure_Pa = 4.1 * 6894.757293;
AirWarmer.ReferenceGasTemperature_K = (91 - 32) / 1.8 + 273.15;
AirWarmer.ReferenceGasFlow_m3_s = 6 * 0.028316846592 / 60;
AirWarmer.ReferenceGasCp_J_kgK = 1006; % Air approximation at NASA test 10.
AirWarmer.ReferenceGasConstant_J_kgK = 287.05;
AirWarmer.ReferenceWaterFlow_kg_s = 196 * 0.45359237 / 3600;
AirWarmer.ReferenceWaterCp_J_kgK = 4180;
% Report axes as flow length, stack width, channel height; envelope aspect assumed.
AirWarmer.ReferenceDimensions_m = [6.87, 3.2, 1.78] * 0.0254;
AirWarmer.ReferenceDryMass_kg = 2.0 * 0.45359237; % Core + headers, excluding fittings.
AirWarmer.ConductanceMargin = 1.0; % Editable multiplier; no extra margin by default.

% Minimum package estimate uses the maximum required UA over the design EVA.
% NASA reference package includes headers; fittings and external routing are excluded.

%% Inputs - liquid storage
StorageFillFraction = 0.90; % ASSUMED useful liquid volume / internal tank volume.
ExternalPressure_kPa = 0.6; % ASSUMED Mars ambient; set suit pressure for internal installation.
TankMinimumWall_m = 0.0005; % ASSUMED manufacturing/handling minimum.
TankAllowableStress_Pa = 50e6; % ASSUMED derated aluminium allowable, not a code rating.
TankJointEfficiency = 0.8; % ASSUMED.
TankFittingsMass_kg = 0.05; % ASSUMED ports, bladder and supports.


%% Load saved physiology and derive dependent configuration
Loaded = load(DataFile,'Data');
Data = Loaded.Data;
assert(isfield(Data,'Simulation') && isfield(Data.Simulation,'Inputs'), ...
    'EVA:RunSimulationFirst','Complete Metabolic_EVA_Sim.m before thermal sizing.');
EVA = Data.Simulation;
Data_Functions.Data.validateEVAInterface(EVA);

BodyMicroclimate = EVA.Inputs.Environment;
if isempty(EVA_Sizing.InitialSuitRH_percent)
    EVA_Sizing.InitialSuitRH_percent = BodyMicroclimate.RelativeHumidity_percent;
end
if isempty(AirWarmer.WaterInlet_C)
    AirWarmer.WaterInlet_C = BodyMicroclimate.LCG.InletTemperature_C;
end
% Buck saturation equation: upper root-floor bound follows the supply dew point.
SupplyDewPoint_C = fzero(@(T) Data_Functions.Properties.saturationPressure(T) ...
    - BodyMicroclimate.RelativeHumidity_percent / 100 ...
    * Data_Functions.Properties.saturationPressure(BodyMicroclimate.AirTemperature_C), ...
    [-80, BodyMicroclimate.AirTemperature_C]);
EVA_Sizing.RootTemperatureBounds_C = [RootLowerBound_C, ...
    (1 - EVA_Sizing.RootDewPointReduction_fraction) * SupplyDewPoint_C]; % Editable lower bound.
if isempty(AirWarmer.WaterFlow_kg_h)
    AirWarmer.WaterFlow_kg_h = max(EVA.OffNominal.Physiology.LCGMassFlow_kg_s)*3600;
end
assert(isscalar(AirWarmer.WaterFlow_kg_h) && isfinite(AirWarmer.WaterFlow_kg_h) ...
    && AirWarmer.WaterFlow_kg_h > 0, 'RH:AirWarmerFlowInput', ...
    'Set AirWarmer.WaterFlow_kg_h to a positive independent circuit flow when the EVA has no LCG flow.');

Packaging = struct('GraphiteDensity_kg_m3', GraphiteDensity_kg_m3, ...
    'AluminiumDensity_kg_m3', AluminiumDensity_kg_m3, 'PorousBaseThickness_m', PorousBaseThickness_m, ...
    'CondenserRoutingDepth_m', CondenserRoutingDepth_m, 'StorageFillFraction', StorageFillFraction, ...
    'ExternalPressure_kPa', ExternalPressure_kPa, 'TankMinimumWall_m', TankMinimumWall_m, ...
    'TankAllowableStress_Pa', TankAllowableStress_Pa, 'TankJointEfficiency', TankJointEfficiency, ...
    'TankFittingsMass_kg', TankFittingsMass_kg);
Inputs = struct('Condenser', Condenser, 'Search', EVA_Sizing, 'AirWarmer', AirWarmer, ...
    'Packaging', Packaging, 'SensitivityChanges_percent', SensitivityChanges_percent, ...
    'RunSensitivity', RunSensitivity, 'PlotResults', PlotResults);

%% Size hardware and run sensitivity without rerunning JOS-3
Profile = EVA.Sizing.OffNominal.SizingProfile;
State = Data_Functions.Reporting.summarizeEVAScenario(EVA.OffNominal.Physiology, EVA.Inputs);
C = Inputs.Condenser; Settings = Inputs.Search; A = Inputs.AirWarmer;
Settings.Duration_min = sum(Profile.EndTime_min-Profile.StartTime_min);
Settings.SupplyRH_percent = EVA.Inputs.Environment.RelativeHumidity_percent;
Inputs.Search = Settings;
Gas = struct('SuitTemperature_C',State.AverageCondenserInlet_C, ...
    'SuitRH_percent',State.InletRH_percent,'Flow_CFM',State.InletFlow_CFM, ...
    'Pressure_kPa',EVA.Inputs.Environment.Pressure_kPa);
W = Data_Functions.Properties.liquidWaterProperties(C.SurfaceTemperature_C);
W.VaporCp_J_kgK = VaporCp_J_kgK; W.VaporEnthalpyAtZero_J_kg = VaporEnthalpyAtZero_J_kg;
W.VaporGasConstant_J_kgK = VaporGasConstant_J_kgK;
W.DesignRate_kg_s = sum(Profile.DesignMoisture_g_min ...
    .*(Profile.EndTime_min-Profile.StartTime_min)) ...
    /sum(Profile.EndTime_min-Profile.StartTime_min)/60000;
validateattributes(Gas.SuitRH_percent, {'numeric'}, {'scalar','finite','>',0,'<=',100});
assert(C.SurfaceTemperature_C < Gas.SuitTemperature_C, ...
    'RH:Temperature', 'The condenser root floor must be colder than the return air.');
Gas = Data_Functions.HeatExchangers.condenserGasProperties(Gas,W,C);
WarmerSizing = @(History,Channels) Data_Functions.HeatExchangers.sizeAirWarmer(A,History,Profile,W.VaporCp_J_kgK);
Design = Data_Functions.Humidity.sizeEVARH(Profile,Gas,W,C,Settings,@Data_Functions.HeatExchangers.condenserGasProperties,WarmerSizing);
Hardware = struct('Scenario',"Off-nominal", 'Feasible',Design.Feasible, ...
    'Inputs',Inputs,'Profile',Profile,'Design',Design, ...
    'DesignLoads',EVA.Sizing.OffNominal);
% Physical gas states are the condenser boundary. Do not add body air-side
% pathway duties to condenser duty again. Factored pathway loads are an
% alternative external-network interface, not extra loads for this sizing run.
Hardware.ThermalInterface = EVA.OffNominal.ThermalInterface;
Hardware.ThermalPathwayLoads = EVA.Sizing.OffNominal.ThermalPathwayLoads;
Hardware.PhysiologyHeatStorageFeasible = ~any(EVA.OffNominal.Physiology.HeatStorageLimitExceeded);
Hardware.SystemScreeningFeasible = Design.Feasible && Hardware.PhysiologyHeatStorageFeasible;
% Retain physical case summaries even if no feasible hardware is found.
Hardware.Reports.ThermalSystemSizing = EVA.Reports.ThermalSystemSizing;
if ~Design.Feasible
    Hardware.Reports.Feasibility = table("Off-nominal",false,string(Design.Failure), ...
        'VariableNames',{'Case','Feasible','Reason'});
else
    Hardware.Design.SelectedSummary.Case(:) = "Off-nominal";
    SelectedWater = Data_Functions.Properties.liquidWaterProperties(Design.RootFloor_C);
    WStorage = W;
    WStorage.Density_kg_m3 = SelectedWater.Density_kg_m3;
    WStorage.Cp_J_kgK = SelectedWater.Cp_J_kgK;
%% Component packaging and water storage
    Design = Hardware.Design; Water = WStorage;
    Condenser = Inputs.Condenser; Packaging = Inputs.Packaging;
    AirWarmer_Design = Design.AirWarmer;
    RH.ChannelCount = Design.SelectedSummary.Channels;
    RH.TotalCollectedWater_kg = Design.SelectedSummary.CollectedWater_g / 1000;
    RH.WaterDensity_kg_m3 = Water.Density_kg_m3;
    RH.GasPressure_kPa = Profile.Pressure_kPa(1);
    RH.ChannelGap_m = Condenser.ChannelGap_m; RH.FinThickness_m = Condenser.FinThickness_m;
    RH.ChannelHeight_m = Condenser.ChannelHeight_m; RH.ChannelLength_m = Condenser.ChannelLength_m;
    GraphiteDensity_kg_m3 = Packaging.GraphiteDensity_kg_m3;
    AluminiumDensity_kg_m3 = Packaging.AluminiumDensity_kg_m3;
    PorousBaseThickness_m = Packaging.PorousBaseThickness_m;
    CondenserRoutingDepth_m = Packaging.CondenserRoutingDepth_m;
    StorageFillFraction = Packaging.StorageFillFraction;
    ExternalPressure_kPa = Packaging.ExternalPressure_kPa;
    TankMinimumWall_m = Packaging.TankMinimumWall_m;
    TankAllowableStress_Pa = Packaging.TankAllowableStress_Pa;
    TankJointEfficiency = Packaging.TankJointEfficiency;
    TankFittingsMass_kg = Packaging.TankFittingsMass_kg;
    % Assumption Checks
    assert(StorageFillFraction > 0 && StorageFillFraction < 1 ...
        && TankJointEfficiency > 0 && TankJointEfficiency <= 1, ...
        'RH:Assumptions', 'Check tank fill and joint efficiency.');
    assert(isfinite(CondenserRoutingDepth_m) && CondenserRoutingDepth_m >= 0 ...
        && ExternalPressure_kPa < RH.GasPressure_kPa, ...
        'RH:Geometry', 'Check routing depth and tank external pressure.');

    % RH Condenser - Integrated Porous Fins and Separator
    CoreWidth_m = RH.ChannelCount * RH.ChannelGap_m ...
        + (RH.ChannelCount + 1) * RH.FinThickness_m;
    CoreHeight_m = RH.ChannelHeight_m + 2 * PorousBaseThickness_m;
    CoreLength_m = RH.ChannelLength_m;
    FinVolume_m3 = (RH.ChannelCount + 1) * RH.FinThickness_m ...
        * RH.ChannelHeight_m * CoreLength_m;
    BaseVolume_m3 = 2 * CoreWidth_m * CoreLength_m * PorousBaseThickness_m;
    CondenserEnvelope_m = [CoreLength_m, CoreWidth_m, CoreHeight_m + CondenserRoutingDepth_m];
    CondenserMass_kg = (FinVolume_m3 + BaseVolume_m3) * GraphiteDensity_kg_m3;
    % ASSUMPTION: separation is integrated within this substrate envelope/mass.
    % Detailed embedded separator construction and gas/liquid manifolds are not sized.

    % Collected-Water Storage
    WaterStored_kg = RH.TotalCollectedWater_kg;
    TankInternalVolume_m3 = WaterStored_kg / RH.WaterDensity_kg_m3 / StorageFillFraction;
    TankRadius_m = (3 * TankInternalVolume_m3 / (4 * pi))^(1/3);
    TankPressure_Pa = (RH.GasPressure_kPa - ExternalPressure_kPa) * 1000;
    TankWall_m = max(TankMinimumWall_m, TankPressure_Pa * TankRadius_m ...
        / (2 * TankAllowableStress_Pa * TankJointEfficiency));
    TankOuterRadius_m = TankRadius_m + TankWall_m;
    TankEnvelope_m = 2 * TankOuterRadius_m * [1, 1, 1];
    TankMass_kg = 4 * pi / 3 * (TankOuterRadius_m^3 - TankRadius_m^3) ...
        * AluminiumDensity_kg_m3 + TankFittingsMass_kg;

%% Hardware Sizing - Results
    Component = ["RH condenser"; "Air warmer"; "Liquid storage tank"];
    Dimensions_m = [CondenserEnvelope_m; AirWarmer_Design.Dimensions_m; TankEnvelope_m];
    Length_mm = Dimensions_m(:, 1) * 1000;
    Width_mm = Dimensions_m(:, 2) * 1000;
    Height_mm = Dimensions_m(:, 3) * 1000;
    ComponentVolume_L = [prod(CondenserEnvelope_m); AirWarmer_Design.Volume_m3; ...
        4 * pi / 3 * TankOuterRadius_m^3] * 1000;
    DryMass_kg = [CondenserMass_kg; AirWarmer_Design.DryMass_kg; TankMass_kg];
    StoredWater_kg = [0; 0; WaterStored_kg];
    Component_Summary = table(Component, Length_mm, Width_mm, Height_mm, ...
        ComponentVolume_L, DryMass_kg, StoredWater_kg);



    Component_Summary.Case = repmat("Off-nominal", height(Component_Summary), 1);
    Components = struct('Summary', Component_Summary, ...
        'CondenserEnvelope_m', CondenserEnvelope_m, 'TankEnvelope_m', TankEnvelope_m, ...
        'StoredWater_kg', WaterStored_kg);
    Hardware.Components = Components;

%% Off-nominal hardware sensitivity
    AirWarmer = A; Baseline = Hardware;
    Changes = Inputs.SensitivityChanges_percent(:);
    validateattributes(Changes,{'numeric'},{'vector','real','finite','>',-100});
    Factors = ["Moisture load";"Supply temperature (C)";"Supply RH"];
    if ~Inputs.RunSensitivity
        Changes = zeros(0,1);
    end
    Count = numel(Factors)*numel(Changes);
    Input = repelem(Factors,numel(Changes));
    Change_percent = repmat(Changes,numel(Factors),1);
    Feasible = false(Count,1); FailureReason = strings(Count,1);
    AverageCooling_W = NaN(Count,1); PeakCooling_W = NaN(Count,1);
    CondenserVolume_L = NaN(Count,1); ReheaterVolume_L = NaN(Count,1);
    BaselineVolume_L = Baseline.Components.Summary.ComponentVolume_L(1) ...
        + Baseline.Design.AirWarmer.Volume_m3*1000;
    for Index = 1:Count
        Multiplier = 1+Change_percent(Index)/100;
        TrialProfile = Profile; TrialSettings = Settings;
        switch Input(Index)
            case "Moisture load"
                TrialProfile.DesignMoisture_g_min = Profile.DesignMoisture_g_min*Multiplier;
            case "Supply temperature (C)"
                TrialProfile.SupplyTemperature_C = Profile.SupplyTemperature_C*Multiplier;
            case "Supply RH"
                TrialSettings.SupplyRH_percent = Settings.SupplyRH_percent*Multiplier;
        end
        if TrialSettings.SupplyRH_percent <= 0 || TrialSettings.SupplyRH_percent > 100
            FailureReason(Index) = "Supply RH lies outside (0,100] percent.";
            continue;
        end
        TargetPressure = TrialSettings.SupplyRH_percent/100 ...
            * Data_Functions.Properties.saturationPressure(min(TrialProfile.SupplyTemperature_C));
        DewPoint_C = fzero(@(T) Data_Functions.Properties.saturationPressure(T)-TargetPressure,[-80,80]);
        UpperRoot_C = (1-TrialSettings.RootDewPointReduction_fraction)*DewPoint_C;
        if UpperRoot_C <= TrialSettings.RootTemperatureBounds_C(1)
            FailureReason(Index) = "Supply dew point incompatible with permitted root-temperature bounds.";
            continue;
        end
        WarmerSizing = @(History,Channels) Data_Functions.HeatExchangers.sizeAirWarmer(AirWarmer,History,TrialProfile,W.VaporCp_J_kgK);
        Trial = Data_Functions.Humidity.sizeEVARH(TrialProfile,Gas,W,C,TrialSettings,@Data_Functions.HeatExchangers.condenserGasProperties,WarmerSizing);
        Feasible(Index) = Trial.Feasible;
        if ~Trial.Feasible
            FailureReason(Index) = Trial.Failure;
            continue;
        end
        AverageCooling_W(Index) = Trial.SelectedSummary.AverageCooling_W;
        PeakCooling_W(Index) = Trial.SelectedSummary.PeakCooling_W;
        Width_m = Trial.SelectedSummary.Channels*C.ChannelGap_m ...
            +(Trial.SelectedSummary.Channels+1)*C.FinThickness_m;
        CondenserVolume_L(Index) = C.ChannelLength_m*Width_m ...
            *(C.ChannelHeight_m+2*Inputs.Packaging.PorousBaseThickness_m ...
            +Inputs.Packaging.CondenserRoutingDepth_m)*1000;
        ReheaterVolume_L(Index) = Trial.AirWarmer.Volume_m3*1000;
    end
    TotalVolumeChange_percent = 100*(CondenserVolume_L+ReheaterVolume_L-BaselineVolume_L)/BaselineVolume_L;
    Results = table(Input,Change_percent,AverageCooling_W,PeakCooling_W,CondenserVolume_L, ...
        ReheaterVolume_L,Feasible,TotalVolumeChange_percent,FailureReason);
    Hardware.Sensitivity = Results;

%% Component sizing, performance and sensitivity tables
    S = Hardware.Design.SelectedSummary;
    A = Hardware.Design.AirWarmer;
    Duration_hr = sum(Hardware.Profile.EndTime_min-Hardware.Profile.StartTime_min)/60;
    Hardware.Reports.ComponentSizing = Hardware.Components.Summary;
    Hardware.Reports.ComponentPerformance = table(["Condenser average cooling (W)";"Condenser peak cooling (W)"; ...
        "Condenser EVA cooling energy (Wh)";"Reheater average heating (W)";"Reheater peak heating (W)"; ...
        "Reheater EVA heating energy (Wh)";"Average water removal (g/min)";"Peak water removal (g/min)"; ...
        "Collected water (g)";"Average root temperature (C)";"Minimum root temperature (C)"; ...
        "Maximum root temperature (C)";"Maximum supply RH error (percentage points)"; ...
        "Maximum supply temperature error (C)";"Available water mass flow (kg/h)"; ...
        "Minimum controlled LCG inlet (C)";"Peak controlled LCG flow (kg/h)";"Fixed reheater water inlet (C)";"Post-simulation load FOS";"Physiological heat-storage screening met (1/0)"; ...
        "Peak remaining storage-target deficit (W)"], ...
        [S.AverageCooling_W;S.PeakCooling_W;S.AverageCooling_W*Duration_hr; ...
        S.AverageReheat_W;S.PeakReheat_W;S.AverageReheat_W*Duration_hr; ...
        S.AverageRemoval_g_min;S.PeakRemoval_g_min;S.CollectedWater_g; ...
        S.AverageRootTemperature_C;S.MinimumRootTemperature_C;S.MaximumRootTemperature_C; ...
        S.MaximumRHError_percent;S.MaximumTemperatureError_C;Hardware.Inputs.AirWarmer.WaterFlow_kg_h; ...
        min(EVA.OffNominal.Physiology.LCGInletTemperature_C); ...
        max(EVA.OffNominal.Physiology.LCGMassFlow_kg_s)*3600; max(A.WaterInlet_C); ...
        Hardware.DesignLoads.FOS; double(Hardware.PhysiologyHeatStorageFeasible); ...
        max(EVA.OffNominal.Physiology.RemainingCoolingShortfall_W)], ...
        'VariableNames',{'Parameter','OffNominal'});
%% Off-nominal PLSS air and water temperatures
    History = Hardware.Design.SelectedHistory{1};
    Samples = History.Instantaneous;
    IntervalDuration_min = Hardware.Profile.EndTime_min-Hardware.Profile.StartTime_min;
    % Endpoints duplicate the next interval's start: give them zero duration.
    SampleDuration_min = [diff(Samples.Time_min); 0];
    assert(all(SampleDuration_min >= 0) ...
        && abs(sum(SampleDuration_min)-sum(IntervalDuration_min)) < 1e-8, ...
        'EVA:SampleDuration', 'Internal samples must span the complete EVA.');
    Physiology = EVA.OffNominal.Physiology;
    WaterSupply_C = A.WaterInlet_C;
    LCGSupply_C = Physiology.LCGInletTemperature_C;
    Parameter = ["Air between condenser and reheater"; ...
        "Air RH between condenser and reheater"; ...
        "Controlled LCG inlet"; "LCG outlet"; ...
        "Reheater water inlet"; "Reheater branch water outlet"; ...
        "Condenser fin root (liquid boundary)"; ...
        "Condenser water-property reference"; "Stored-water property reference"; ...
        "Reheater branch water flow"; "Bypass water flow"; "Bypass fraction"];
    Unit = ["C"; "%"; repmat("C",7,1); "kg/h"; "kg/h"; "%"];
    OffNominalAverage = [ ...
        sum(History.CondenserOutlet_C.*IntervalDuration_min)/sum(IntervalDuration_min); ...
        sum(History.CondenserOutletRH_percent.*IntervalDuration_min)/sum(IntervalDuration_min); ...
        sum(LCGSupply_C.*IntervalDuration_min)/sum(IntervalDuration_min); ...
        sum(Physiology.LCGOutletTemperature_C.*IntervalDuration_min)/sum(IntervalDuration_min); ...
        sum(WaterSupply_C.*SampleDuration_min)/sum(SampleDuration_min); ...
        sum(A.WaterReturn_C.*SampleDuration_min)/sum(SampleDuration_min); ...
        S.AverageRootTemperature_C; W.Temperature_C; Hardware.Design.RootFloor_C; ...
        sum(A.WaterFlow_kg_h.*SampleDuration_min)/sum(SampleDuration_min); ...
        sum(A.BypassWaterFlow_kg_h.*SampleDuration_min)/sum(SampleDuration_min); ...
        100*sum(A.BypassFraction.*SampleDuration_min)/sum(SampleDuration_min)];
    ColdRH_percent = 100 * Hardware.Profile.Pressure_kPa(1)*1000 ...
        .* Samples.OutletHumidityRatio ./ (Gas.MolecularMassRatio+Samples.OutletHumidityRatio) ...
        ./ Data_Functions.Properties.saturationPressure(Samples.ColdTemperature_C);
    OffNominalMinimum = [min(Samples.ColdTemperature_C); min(ColdRH_percent); ...
        min(LCGSupply_C); min(Physiology.LCGOutletTemperature_C); min(WaterSupply_C); ...
        min(A.WaterReturn_C); S.MinimumRootTemperature_C; W.Temperature_C; Hardware.Design.RootFloor_C; ...
        min(A.WaterFlow_kg_h); min(A.BypassWaterFlow_kg_h); 100*min(A.BypassFraction)];
    OffNominalMaximum = [max(Samples.ColdTemperature_C); max(ColdRH_percent); ...
        max(LCGSupply_C); max(Physiology.LCGOutletTemperature_C); max(WaterSupply_C); ...
        max(A.WaterReturn_C); S.MaximumRootTemperature_C; W.Temperature_C; Hardware.Design.RootFloor_C; ...
        max(A.WaterFlow_kg_h); max(A.BypassWaterFlow_kg_h); 100*max(A.BypassFraction)];
    % Fin-root temperature is not a prediction of bulk coolant temperature.
    Hardware.Reports.PLSSAirAndWater = table(Parameter,Unit, ...
        OffNominalAverage,OffNominalMinimum,OffNominalMaximum);
    % Append actual off-nominal design histories; nominal hardware is not sized.
    % Endpoint samples enter extrema; zero endpoint duration excludes them from averages.
    HardwareValues = [Samples.Cooling_W,Samples.Reheat_W,Samples.Removal_kg_s*60000, ...
        Samples.ColdTemperature_C,ColdRH_percent,Samples.SupplyTemperature_C, ...
        Samples.OutletHumidityRatio,Samples.DryOxygenFlow_kg_s, ...
        Samples.RootTemperature_C,A.WaterInlet_C,A.WaterReturn_C,A.MixedReturn_C, ...
        A.WaterFlow_kg_h,A.BypassWaterFlow_kg_h,100*A.BypassFraction,A.RequiredUA_W_K];
    HardwareNames = ["Condenser cooling duty";"Air warmer heating duty"; ...
        "Condenser water removal rate";"Air between condenser and warmer temperature"; ...
        "Air between condenser and warmer RH";"Reheated supply air temperature"; ...
        "Condenser outlet humidity ratio";"Hardware dry oxygen flow";"Condenser fin-root temperature"; ...
        "Reheater water inlet temperature";"Reheater branch water return temperature"; ...
        "Reheater mixed water return temperature";"Reheater branch water flow"; ...
        "Reheater bypass water flow";"Reheater bypass fraction";"Reheater required conductance"];
    HardwareUnits = ["W";"W";"g/min";"C";"%";"C";"kg/kg dry oxygen"; ...
        "kg/s";"C";"C";"C";"C";"kg/h";"kg/h";"%";"W/K"];
    HardwareSummary = Data_Functions.Reporting.summarizeThermalSeries(HardwareNames, ...
        HardwareUnits,"Off-nominal sizing run (FOS moisture load)", ...
        HardwareValues,SampleDuration_min,"OffNominal");
    PhaseSummary = Data_Functions.Reporting.summarizeThermalSeries( ...
        ["Regional phase-change heat";"Regional liquid sensible heat"; ...
        "Regional phase-equilibrium heat sink requirement";"Regional retained liquid"], ...
        ["W";"W";"W";"g"],"Off-nominal sizing run (FOS moisture load)", ...
        [History.PhaseChangeHeat_W,History.LiquidSensibleHeat_W, ...
        History.RequiredPhaseHeatSink_W,sum(History.RegionLiquidEnd_g,2)], ...
        IntervalDuration_min,"OffNominal");
    ComponentTable = Hardware.Components.Summary;
    PackageValues = reshape([ComponentTable.ComponentVolume_L,ComponentTable.DryMass_kg, ...
        ComponentTable.StoredWater_kg]',1,[]);
    PackageNames = reshape((string(ComponentTable.Component)+" "+ ...
        ["package volume","dry mass","stored water capacity"])',[],1);
    PackageSummary = Data_Functions.Reporting.summarizeThermalSeries(PackageNames, ...
        repmat(["L";"kg";"kg"],height(ComponentTable),1),"Selected fixed component design", ...
        PackageValues,1,"OffNominal");
    Hardware.Reports.ThermalSystemSizing = [Hardware.Reports.ThermalSystemSizing; ...
        HardwareSummary;PhaseSummary;PackageSummary];
    Hardware.Reports.SensitivityAnalysis = Hardware.Sensitivity;

end

Data.Hardware = Hardware;
save(DataFile,'Data','-v7');

%% Report and plot only after calculations and data saving finish
Data_Functions.Reporting.printEVAReports(Hardware.Reports);
if Inputs.PlotResults
    if Hardware.Feasible

        EVA_Design = Hardware.Design; EVA_Profile = Hardware.Profile;
        EVA_Sizing = Hardware.Inputs.Search; BodyMicroclimate = EVA.Inputs.Environment;
if isempty(EVA_Sizing.InitialSuitRH_percent)
    EVA_Sizing.InitialSuitRH_percent = BodyMicroclimate.RelativeHumidity_percent;
end
if isempty(AirWarmer.WaterInlet_C)
    AirWarmer.WaterInlet_C = BodyMicroclimate.LCG.InletTemperature_C;
end
        State = Data_Functions.Reporting.summarizeEVAScenario(EVA.OffNominal.Physiology, EVA.Inputs);
        Moisture_Profile = EVA.OffNominal.Physiology;
        ZoneTemperatures_C = State.ZoneTemperatures_C; ZoneRH_percent = State.ZoneRH_percent;
        Moisture_Duration_min = Moisture_Profile.EndTime_min-Moisture_Profile.StartTime_min;
        EVA_Duration_min = sum(Moisture_Duration_min);
        AverageCondenserInlet_C = State.AverageCondenserInlet_C;
%% Suit-Air Liquid Storage and Phase Rates
        History = EVA_Design.SelectedHistory{1};
        figure(10); clf;
        set(gcf, 'Name', '10. Suit-Air Condensate', 'NumberTitle', 'off');
        tiledlayout(2, 1);
        nexttile;
        plot(EVA_Design.Time_min, History.RegionLiquidEnd_g, 'LineWidth', 1.2);
        ylabel('Retained liquid (g)'); legend('Head/neck', 'Torso/arms', 'Legs', 'Location', 'best'); grid on;
        nexttile;
        plot(EVA_Design.Time_min, [sum(History.Condensed_kg, 2), sum(History.Reevaporated_kg, 2)] * 1000 ...
            ./ (EVA_Profile.EndTime_min - EVA_Profile.StartTime_min), 'LineWidth', 1.2);
        ylabel('Phase rate (g/min)'); legend('Condensation', 'Re-evaporation', 'Location', 'best'); grid on;
        xlabel('EVA time (min)');
        sgtitle('Regional Condensate Storage and Phase Rates');

        % Temperature and RH along the Airflow Path
        % Regional values are zone means; the last point is the final leg outlet.
        % Spacing is schematic, not a physical distance along the suit.
        NodeLabels = {'Neck supply', 'Head/neck mean', 'Torso/arms mean', 'Leg zone mean', 'Leg outlet'};
        GradientTemperature_C = [BodyMicroclimate.AirTemperature_C, ...
            sum(ZoneTemperatures_C .* Moisture_Duration_min, 1) / EVA_Duration_min, AverageCondenserInlet_C];
        GradientRH_percent = [BodyMicroclimate.RelativeHumidity_percent, ...
            sum(ZoneRH_percent .* Moisture_Duration_min, 1) / EVA_Duration_min, ...
            sum(Moisture_Profile.CondenserInletRH_percent .* Moisture_Duration_min) / EVA_Duration_min];
        figure(11); clf;
        set(gcf, 'Name', '11. Suit Airflow', 'NumberTitle', 'off');
        tiledlayout(2, 1);
        sgtitle('Temperature and RH along Airflow Path in suit', 'FontSize', 16, 'FontWeight', 'bold');
        nexttile;
        plot(1:5, GradientTemperature_C, '-o', 'LineWidth', 1.5);
        xticks(1:5);
        xticklabels(NodeLabels);
        xlim([1, 5]);
        ylabel('Air temperature (C)');
        xlabel('JOS-3 Nodes');
        title('Time-Weighted Average Temperature along the Airflow Path');
        grid on;
        nexttile;
        plot(1:5, GradientRH_percent, '-o', 'LineWidth', 1.5);
        xticks(1:5);
        xticklabels(NodeLabels);
        xlim([1, 5]);
        ylabel('Relative humidity (%)');
        xlabel('JOS-3 Nodes');
        title('Time-Weighted Average RH along the Airflow Path');
        grid on;

%% Condenser Size-Temperature Trade
    end
    Design = Hardware.Design; SizeWeight = Hardware.Inputs.Search.SizeWeight;
    R = Design.SearchResults;
    figure(12); clf;
    set(gcf, 'Name', '12. Condenser Size-Temperature Trade', 'NumberTitle', 'off');
    if Design.Feasible
        F = R(R.Feasible, :);
        plot(F.RootFloor_C, F.CoreVolume_L, '-o', 'LineWidth', 1.3, 'MarkerSize', 5);
        hold on;
        plot(Design.RootFloor_C, Design.SelectedSummary.CoreVolume_L, 'gp', ...
            'MarkerSize', 12, 'MarkerFaceColor', 'g');
        hold off;
        xlabel('Minimum permitted fin-root temperature (C)'); ylabel('Condenser core volume (L)');
        legend('Minimum feasible size', 'Selected design', 'Location', 'northeast');
        title(sprintf('Size-Temperature Trade: Size Weight %.2f', SizeWeight));
    else
        % Compact failure summary remains available if no frontier exists.
        Labels = ["Supply target"; "Cold-outlet fog"; "Flow correlation"; "Air warmer"; "Other"];
        Group = 5 * ones(height(R), 1);
        Group(contains(R.Reason, 'target', 'IgnoreCase', true)) = 1;
        Group(contains(R.Reason, 'Cold', 'IgnoreCase', true) ...
            & contains(R.Reason, 'supersaturat', 'IgnoreCase', true)) = 2;
        Group(contains(R.Reason, 'laminar', 'IgnoreCase', true) ...
            | contains(R.Reason, 'correlation', 'IgnoreCase', true)) = 3;
        Group(contains(R.Reason, 'warmer', 'IgnoreCase', true) ...
            & ~contains(R.Reason, 'target missed', 'IgnoreCase', true)) = 4;
        barh(accumarray(Group, 1, [numel(Labels), 1]));
        yticks(1:numel(Labels)); yticklabels(Labels);
        xlabel('Rejected candidates'); title('No Feasible Design: Rejection Summary');
    end
    grid on;

    if Hardware.Feasible

%% RH Sizing - Graphs
        % Gas.Flow_CFM is the corresponding actual condenser-inlet flow at mean T/RH.

        % Full-EVA supply deviations: relative RH and absolute-temperature (kelvin) error.
        figure(13); clf;
        set(gcf, 'Name', '13. Supply Target Compliance', 'NumberTitle', 'off');
        tiledlayout(2, 1);
        History = EVA_Design.SelectedHistory{1};
        RHRelativeError_percent = 100 * History.RHError_percent / EVA_Sizing.SupplyRH_percent;
        TemperatureRelativeError_percent = 100 * History.TemperatureError_C ...
            ./ (EVA_Profile.SupplyTemperature_C + 273.15);
        RHRelativeTolerance_percent = repmat(100 * EVA_Sizing.RHTolerance_percent ...
            / EVA_Sizing.SupplyRH_percent, height(EVA_Profile), 1);
        TemperatureRelativeTolerance_percent = 100 * EVA_Sizing.TemperatureTolerance_C ...
            ./ (EVA_Profile.SupplyTemperature_C + 273.15);
        nexttile;
        plot(EVA_Design.Time_min, [RHRelativeError_percent, TemperatureRelativeError_percent], 'LineWidth', 1.3);
        hold on;
        plot(EVA_Design.Time_min, [RHRelativeTolerance_percent, TemperatureRelativeTolerance_percent], '--', 'LineWidth', 1);
        hold off;
        ylabel('Error relative to target (%)');
        legend('RH error', 'Temperature error (K basis)', 'RH tolerance', ...
            'Temperature tolerance (K basis)', 'Location', 'northeast'); grid on;
        nexttile;
        plot(EVA_Design.Time_min, [History.MaximumRH_percent, History.UncorrectedMaximumRH_percent], 'LineWidth', 1.3);
        legend('Equilibrium RH', 'Before phase adjustment', 'Location', 'northeast');
        ylabel('Maximum regional/suit RH (%)'); xlabel('EVA time (min)'); grid on;
        sgtitle('Supply Target Compliance and Regional RH Diagnostics');

%% Air Warmer - Graphs
        % Selected hardware basis: interval-average conditions.
        WarmerHistory = EVA_Design.SelectedHistory{1};
        figure(14); clf;
        set(gcf, 'Name', '14. Air Warmer EVA Performance', 'NumberTitle', 'off');
        tiledlayout(4, 1, 'TileSpacing', 'compact');
        nexttile;
        plot(EVA_Design.Time_min, WarmerHistory.Reheat_W, 'LineWidth', 1.3);
        ylabel('Heating (W thermal)');
        title('Air Warmer Heating Requirement');
        legend('Interval average', 'Location', 'best');
        grid on;
        nexttile;
        plot(EVA_Design.Time_min, [WarmerHistory.CondenserOutlet_C, ...
            WarmerHistory.ReheatedTemperature_C], 'LineWidth', 1.3);
        yline(BodyMicroclimate.AirTemperature_C, ':', 'Supply target', 'HandleVisibility', 'off');
        ylabel('Temperature (C)');
        title('Temperature Before and After Warming');
        ylim([min(WarmerHistory.CondenserOutlet_C) - 1, max(WarmerHistory.ReheatedTemperature_C) + 1]);
        legend('Warmer inlet', 'Warmer outlet', 'Location', 'best');
        grid on;
        nexttile;
        plot(EVA_Design.Time_min, [WarmerHistory.CondenserOutletRH_percent, ...
            WarmerHistory.ReheatedRH_percent], 'LineWidth', 1.3);
        yline(BodyMicroclimate.RelativeHumidity_percent, ':', 'Supply target', 'HandleVisibility', 'off');
        ylabel('Relative humidity (%)');
        title('RH Before and After Warming');
        WarmerRH = [WarmerHistory.CondenserOutletRH_percent; WarmerHistory.ReheatedRH_percent; ...
            BodyMicroclimate.RelativeHumidity_percent];
        ylim([max(0, min(WarmerRH) - 5), max(WarmerRH) + 5]);
        legend('Inlet interval average', 'Outlet interval average', 'Location', 'best');
        grid on;
        hold off;
        nexttile;
        WaterHistory = EVA_Design.AirWarmer;
        plot(WarmerHistory.Instantaneous.Time_min, ...
            [WaterHistory.WaterFlow_kg_h,WaterHistory.BypassWaterFlow_kg_h], 'LineWidth', 1.3);
        ylabel('Water flow (kg/h)');
        title('Bypass Flow Control: Fixed 18.3 C Water Supply'); grid on;
        legend('Reheater branch', 'Bypass', 'Location', 'best');
        xlabel('EVA time (min)');
        sgtitle('Air Warmer: Selected Outlet-Control Design');
    end

end

