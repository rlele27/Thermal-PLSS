clear;
clc;
close all;
%% Info
% Ventilation
    % Air temperature and bulk RH inputs define the controlled SUPPLY.
    % ASSUMPTION: head/neck -> torso/arms -> legs; same flow through three zones.
    % Return temperature/RH feed back into convection, respiration and evaporation.
    % Condensate stays in each air node and re-evaporates at local gas temperature.
    % Phase change includes latent heat; no suit-wall temperature or drainage model.
% Condenser Geometry
    % Althausen et al., AIAA 2006-1337, printed p. 4: use listed dimensions.
    % POCO HTC datasheet: 70 W/m/K in plane; a different porous graphite grade.
    % https://poco.entegris.com/content/dam/poco/resources/reference-materials/data-sheets/datasheet-htc-graphite-10231.pdf
    % ASSUMPTION: both top and bottom fin roots are cooled to SurfaceTemperature_C.
    % The half-height fin has an insulated symmetry plane; wetted fins can warm.
    % Straight parallel channels; gas properties use inlet conditions.
    % Fully developed laminar transfer gives a baseline without entry enhancement.
    % Cooling hardware must maintain both root temperatures; no fixed overall U is used.
% Porous Material References
    % Hasan et al., NASA/TM-2006-214130, printed pp. 4-5.
    % https://ntrs.nasa.gov/api/citations/20060021945/downloads/20060021945.pdf
    % Use reported bubble points as differential limits; verify with the selected wetted parts.
% Separator and Drain
    % Primed, water-wet ceramic separator is assumed; no oxygen-compatibility qualification is implied.
% RH Inventory at Fixed Airflow
    % Equal free-volume allocation to neck, torso and legs; fixed JOS-3 temperatures/sources.
    % Humidity changes do not rerun sweating, evaporation, air heating or wall condensation.
% Summary of Suit Outlet Values
    % Use an equivalent average return state that conserves the average water flow.
    % RH is calculated at the average temperature, rather than averaged directly.
% Representative Overall Air Conditions
    % Body surface area is a proxy for regional exposure, not measured air volume.
    % Average zone temperature and humidity ratio over area and EVA time.

%% Constants - Metabolic Scaling
FOS = 1.1;
G_Earth = 1;
G_Mars = 0.38;
v_walking = 1; % Walking speed (m/s).
M_dot_base = 100; % Sedentary metabolic rate (W).

%% Metabolic Model - Inputs
% Astronaut
Body.Height_m = 1.75;
Body.Weight_kg = 82;
Body.Fat_percent = 15;
Body.Age_years = 30;
Body.Sex = "male";
Body.CardiacIndex_L_min_m2 = 2.59;

% Suit Conditions
BodyMicroclimate.AirTemperature_C = 18;
BodyMicroclimate.RelativeHumidity_percent = 50; % Assumed bulk air RH.
BodyMicroclimate.Pressure_kPa = 31.7159; 
BodyMicroclimate.RadiantTemperature_C = BodyMicroclimate.AirTemperature_C; 
BodyMicroclimate.AirSpeed_m_s = 0.1; % Assumed local skin air speed (m/s).
BodyMicroclimate.Clothing_clo = 0.2; % Assumed light-garment insulation, not measured LCG data.
BodyMicroclimate.VaporPermeationEfficiency = 0.45; % Assumed garment permeability; affects evaporative resistance.
BodyMicroclimate.Posture = "standing";

% LCG
BodyMicroclimate.LCG.Enabled = true;
BodyMicroclimate.LCG.InletTemperature_C = 18.3;
BodyMicroclimate.LCG.ActivityCoolingFraction = 1; % Assumed fraction of activity heat removed.
BodyMicroclimate.LCG.BaselineMetabolism_W = M_dot_base;

% Ventilation
Ventilation.Flow_CFM = 6; 
BodyMicroclimate.Ventilation = Ventilation;

% Body and Moisture Simulation
BodyMicroclimate.TrackRetainedSweat = true; % Later evaporation retained; runoff excluded.
JOS3_Step_s = 30;
JOS3_Precondition_min = 60; % Excluded from EVA duration.

%% RH Sizing - Inputs
% Condenser Geometry and Material
Condenser.SurfaceTemperature_C = 1; % ASSUMED operating point, not a literature requirement.
Condenser.ChannelGap_m = 0.08 * 0.0254;
Condenser.FinThickness_m = 0.07 * 0.0254;
Condenser.ChannelHeight_m = 0.7 * 0.0254;
Condenser.ChannelLength_m = 1.72 * 0.0254;
Condenser.FinConductivity_W_mK = 70; % ASSUMED porous-graphite proxy, not measured PG-45.
Condenser.FinNodes = 12; % Conduction intervals over half the fin height.

% Porous Material
Separator.AveragePoreSize_m = 6.7e-5 * 0.0254; % Reported average; NOT a maximum diameter.
Separator.HydraulicConductivity_m_s = 7.56e-7 / 100; % Reported cm/s converted to m/s.
Separator.ReferenceBubblePressure_Pa = 14.7 * 6894.757; % Approximate reported ceramic entry pressure.
Substrate.AveragePoreSize_m = 0.0023 * 0.0254; % PG-45 graphite average
Substrate.ReferenceBubblePressure_Pa = 0.6 * 6894.757; % Measured PG-45 entry pressure, Fig. 7.
MaterialReferenceTemperature_C = 20; % ASSUMED: paper does not specify test-water temperature.

% Separator and Drain
Separator.Thickness_m = 0.001; % ASSUMED equivalent flat-layer thickness; tube wall not specified.
Separator.PermeabilityRetention = 0.50; % ASSUMED fouling allowance; not measured aging data.
Separator.SuctionPressure_Pa = 8000; % ASSUMED low-pressure design; paper tests used 3.5-7 psi at ambient pressure.
Separator.BubblePressureFOS = 2; % ASSUMED engineering margin on the reported bubble point.
Separator.MinimumLiquidPressure_kPa = 10; % ASSUMED degassing margin; vapor pressure is also checked.
Drain.PressureAllowance_Pa = 500; % ASSUMED routing/gravity allowance; no routing geometry is modeled.
Water_Load_FOS = 1.0; % Additional RH margin; metabolic FOS is already included.

% RH Inventory at Fixed Airflow
EVA_Sizing.FreeGasVolume_L = 1.5 * 28.316846592; % NASA EMU range: 1.5-2.0 ft3; editable analogue.
EVA_Sizing.MaximumSuitRH_percent = 100; % Saturation ceiling only; the former 65% comfort limit is disabled.
EVA_Sizing.InitialSuitRH_percent = 50; % ASSUMED starting RH; no active humidification.
EVA_Sizing.Verbose = false;
EVA_Sizing.CapacityFraction = 0.99; % Finite-area approximation to the air carrying limit.
EVA_Sizing.MaximumStep_s = 1; % Explicit gas-inventory integration; reduced further for stability.

%% Hardware Sizing - Inputs
% Package and Material
PackingFactor = 0.65; % ASSUMED component envelopes / internal package volume.
CoolingMargin = 1.20; % ASSUMED allowance for rounding, heat leaks and control.
GraphiteDensity_kg_m3 = 1500; % ASSUMED PG-45 bulk density; confirm selected material.
AluminiumDensity_kg_m3 = 2700; % NASA 6061 material reference; see sources file.
PorousBaseThickness_m = 0.001; % ASSUMED top/bottom porous bases; no separate casing.
HeaderLength_m = 0.010; % ASSUMED allowance at each end, not extra transfer length.

% Cold Heat Exchanger and Refrigeration
% R134a-type vapor-compression analogue, not an oxygen-side refrigerant selection.
EvaporatorApproach_K = 3; % ASSUMED refrigerant below the 1 C wetted surface.
ColdPlateHeatFlux_W_m2 = 5000; % ASSUMED derated footprint flux, not a boiling correlation.
ColdPlateThickness_m = 0.004; % ASSUMED machined/bonded cold plate.
ColdPlateMetalFraction = 0.60; % ASSUMED remaining metal after refrigerant channels.
% Hot Heat Exchanger - Water Leaving the LCG
Loop.LCGOutletTemperature_C = 25; % ASSUMED placeholder; NOT LCG inlet temperature.
Loop.Flow_L_min = 1.8; % Reference LCG flow: NASA 20080029248; change for your loop.
Loop.MaximumRise_K = 2; % ASSUMED permitted RH-induced water temperature rise.
Loop.CondensingApproach_K = 5; % ASSUMED hot refrigerant above heated loop water.
Loop.HeaderPressureDrop_Pa = 2000; % ASSUMED hot-HX header/routing allowance.
% Approximate water properties near 25 C, distinct from 1 C collected condensate.
Loop.Density_kg_m3 = 997;
Loop.Cp_J_kgK = 4180;
Loop.Viscosity_Pa_s = 0.00089;
Loop.Conductivity_W_mK = 0.60;
HotHX.Gap_m = 0.001; % ASSUMED parallel water channels.
HotHX.ChannelWidth_m = 0.010;
HotHX.Wall_m = 0.001;
HotHX.FinThickness_m = 0.0005;
HotHX.TargetVelocity_m_s = 0.3; % ASSUMED channel-count design target.
HotHX.RefrigerantFilm_W_m2K = 2000; % ASSUMED condensing-side coefficient; sensitivity needed.
HotHX.MetalConductivity_W_mK = 167; % Aluminium 6061 reference.
% Keep refrigeration inside its published map, rather than extrapolating COP.
RefrigerantCondensing_C = max((100 - 32) / 1.8, ...
    Loop.LCGOutletTemperature_C + Loop.MaximumRise_K + Loop.CondensingApproach_K);
Loop.Flow_m3_s = Loop.Flow_L_min / 60000;
Loop.HeatCapacity_W_K = Loop.Flow_m3_s * Loop.Density_kg_m3 * Loop.Cp_J_kgK;
CompressorMass_kg = 0.590; % Aspen A-series 1.4 cc reference, Jan. 2026.
CompressorEnvelope_m = [0.060, 0.060, 0.080]; % ASSUMED box incl. ports, not drawing dimensions.
% Pump Requirements and Storage
% No pump hardware, mass, envelope or electrical allowance is selected.
% Duty fraction assumes buffered liquid and pumping at the required rated flow.
PumpFlowMargin = 2; % ASSUMED required capability / mean collected liquid flow.
DrainLoss_Pa = 2000; % ASSUMED downstream liquid line/valve loss.
StorageFillFraction = 0.90; % ASSUMED useful liquid volume / internal tank volume.
ExternalPressure_kPa = 0.6; % ASSUMED Mars ambient; set suit pressure for internal installation.
TankMinimumWall_m = 0.0005; % ASSUMED manufacturing/handling minimum.
TankAllowableStress_Pa = 50e6; % ASSUMED derated aluminium allowable, not a code rating.
TankJointEfficiency = 0.8; % ASSUMED.
TankFittingsMass_kg = 0.05; % ASSUMED ports, bladder and supports.
BlowerEfficiency = 0.30; % ASSUMED electrical-to-gas efficiency.
GasPressureDropFactor = 3; % ASSUMED headers/entry allowance over straight-channel friction.

%% Metabolic Model - Data Import
Data_Folder = fileparts(mfilename('fullpath'));
addpath(fullfile(Data_Folder, 'JOS3'));

opts = spreadsheetImportOptions('NumVariables', 5);
opts.Sheet = 'Sheet1';
opts.DataRange = 'A4:E36';
opts.VariableNames = {'StartTime_hr', 'EndTime_hr', 'Duration_hr', 'Activity', 'MetabolicRate_kJ_hr'};
opts.VariableTypes = {'double', 'double', 'double', 'string', 'double'};
opts.SelectedVariableNames = {'StartTime_hr', 'EndTime_hr', 'Activity', 'MetabolicRate_kJ_hr'};
MetMan = readtable(fullfile(Data_Folder, 'Metabolic.xlsx'), opts);

filename = fullfile(Data_Folder, 'Raw_Nominal.csv');
opts = detectImportOptions(filename, 'ReadVariableNames', true);
opts.VariableNames = {'Time_min', 'MetabolicRate_Btu_hr', 'Activity'};
opts = setvartype(opts, 'Activity', 'string');
Nominal = readtable(filename, opts);

%% Metabolic Model - Calculations
% Data Manipulation
Nominal_Time_hours = Nominal.Time_min / 60;
Nominal_Duration_hr = diff(Nominal_Time_hours);
Nominal_MetabolicRate_W = Nominal.MetabolicRate_Btu_hr / 3.412141633;
Mapped_MetabolicRate_W = mapMetabolicRates(Nominal.Activity, MetMan) / 3.6;

% Martian Metabolic Rate Conversion
M_dot_activity_earth = Mapped_MetabolicRate_W - M_dot_base;
C_w_E = 3.531 - 3.374 * v_walking + 1.535 * v_walking^2 + 0.557 * G_Earth;
C_w_M = 3.531 - 3.374 * v_walking + 1.535 * v_walking^2 + 0.557 * G_Mars;
K_g = C_w_M / C_w_E;
M_dot_mars = (M_dot_base + K_g * M_dot_activity_earth) * FOS;

% Astronaut Source and Ideal PLSS Sink
Moisture_Profile = runJOS3Profile(Nominal.Time_min, Mapped_MetabolicRate_W, ...
    Body, BodyMicroclimate, JOS3_Step_s, JOS3_Precondition_min);
Moisture_Rate_g_min = Moisture_Profile.VaporToPLSS_g_min; % Net vapor reaching the PLSS after phase change.
SizingMoisture_Rate_g_min = Moisture_Rate_g_min * FOS;
Moisture_Duration_min = Moisture_Profile.EndTime_min - Moisture_Profile.StartTime_min;
EVA_Duration_min = sum(Moisture_Duration_min);

% Time-Weighted Averages and Peaks
Mars_Duration_hr = sum(Nominal_Duration_hr);
Mars_AverageRate_W = sum(M_dot_mars(1:end-1) .* Nominal_Duration_hr) / Mars_Duration_hr;
Active_Intervals = find(Nominal_Duration_hr > 0);
Mars_PeakRate_W = max(M_dot_mars(Active_Intervals));
AverageMoisture_g_min = sum(SizingMoisture_Rate_g_min .* Moisture_Duration_min) / EVA_Duration_min;
PeakMoisture_g_min = max(SizingMoisture_Rate_g_min);
AverageSourceMoisture_g_min = sum(Moisture_Profile.VaporToSuit_g_min .* Moisture_Duration_min) / EVA_Duration_min * FOS;
PeakSourceMoisture_g_min = max(Moisture_Profile.VaporToSuit_g_min) * FOS;

% Condenser Inlet Temperature
CondenserInlet_C = Moisture_Profile.CondenserInletTemperature_C; % Physical return conditions use unscaled heat and moisture.
AverageCondenserInlet_C = sum(CondenserInlet_C .* Moisture_Duration_min) / EVA_Duration_min;
PeakCondenserInlet_C = max(CondenserInlet_C);

% Summary of Suit Outlet Values
SupplyVaporPressure_Pa = exp(16.6536 - 4030.183 / (BodyMicroclimate.AirTemperature_C + 235)) ...
    * BodyMicroclimate.RelativeHumidity_percent / 100 * 1000;
DryOxygenFlow_kg_s = (BodyMicroclimate.Pressure_kPa * 1000 - SupplyVaporPressure_Pa) ...
    * Ventilation.Flow_CFM * 0.028316846592 / 60 / (259.84 * (BodyMicroclimate.AirTemperature_C + 273.15));
SupplyHumidityRatio = (0.01801528 / 0.0319988) * SupplyVaporPressure_Pa ...
    / (BodyMicroclimate.Pressure_kPa * 1000 - SupplyVaporPressure_Pa);
ReturnHumidityRatio = SupplyHumidityRatio + AverageMoisture_g_min / FOS / 60000 / DryOxygenFlow_kg_s;
ReturnVaporPressure_Pa = BodyMicroclimate.Pressure_kPa * 1000 * ReturnHumidityRatio ...
    / (0.01801528 / 0.0319988 + ReturnHumidityRatio);
% Buck saturation equation matches the RH sizing functions below.
ReturnSaturationPressure_Pa = 611.21 * exp((18.678 - AverageCondenserInlet_C / 234.5) ...
    * AverageCondenserInlet_C / (257.14 + AverageCondenserInlet_C));
RH_Sizing_InletRH_percent = 100 * ReturnVaporPressure_Pa / ReturnSaturationPressure_Pa;
RH_Sizing_Flow_CFM = DryOxygenFlow_kg_s * 259.84 * (AverageCondenserInlet_C + 273.15) ...
    / (BodyMicroclimate.Pressure_kPa * 1000 - ReturnVaporPressure_Pa) * 60 / 0.028316846592;
% Representative Overall Air Conditions
ZoneTemperatures_C = [Moisture_Profile.NeckAirTemperature_C, ...
    Moisture_Profile.TorsoAirTemperature_C, Moisture_Profile.LegAirTemperature_C];
ZoneRH_percent = [Moisture_Profile.NeckAirRH_percent, ...
    Moisture_Profile.TorsoAirRH_percent, Moisture_Profile.LegAirRH_percent];
Coefficients = jos3Coefficients();
SegmentArea_m2 = Coefficients.StandardArea_m2;
ZoneArea_m2 = [sum(SegmentArea_m2(1:2)); sum(SegmentArea_m2(3:11)); sum(SegmentArea_m2(12:17))];
ZoneWeights = ZoneArea_m2 / sum(ZoneArea_m2);
OverallAirTemperature_C = sum((ZoneTemperatures_C * ZoneWeights) .* Moisture_Duration_min) / EVA_Duration_min;
ZoneVaporPressure_kPa = exp(16.6536 - 4030.183 ./ (ZoneTemperatures_C + 235)) .* ZoneRH_percent / 100;
ZoneHumidityRatio = (0.01801528 / 0.0319988) * ZoneVaporPressure_kPa ...
    ./ (BodyMicroclimate.Pressure_kPa - ZoneVaporPressure_kPa);
OverallHumidityRatio = sum((ZoneHumidityRatio * ZoneWeights) .* Moisture_Duration_min) / EVA_Duration_min;
OverallVaporPressure_Pa = BodyMicroclimate.Pressure_kPa * 1000 * OverallHumidityRatio ...
    / (0.01801528 / 0.0319988 + OverallHumidityRatio);
OverallSaturationPressure_Pa = 611.21 * exp((18.678 - OverallAirTemperature_C / 234.5) ...
    * OverallAirTemperature_C / (257.14 + OverallAirTemperature_C));
OverallRH_percent = 100 * OverallVaporPressure_Pa / OverallSaturationPressure_Pa;
% Express the conserved dry-oxygen flow at the representative overall state.
OverallFlow_CFM = DryOxygenFlow_kg_s * 259.84 * (OverallAirTemperature_C + 273.15) ...
    / (BodyMicroclimate.Pressure_kPa * 1000 - OverallVaporPressure_Pa) * 60 / 0.028316846592;

%% Metabolic Model - Summary Tables
% Overall and Suit Outlet
% Overall quantities describe the EVA; outlet values describe the final leg return.
% Overall air values use body-area/time weighting; outlet values use the final return.
Quantity = ["Average moisture (g/min)"; "Peak moisture (g/min)"; ...
    "Average air temperature (C)"; "Equivalent average RH (%)"; ...
    "Actual airflow (CFM)"; "Pressure (kPa)"];
Overall = [AverageSourceMoisture_g_min; PeakSourceMoisture_g_min; OverallAirTemperature_C; ...
    OverallRH_percent; OverallFlow_CFM; BodyMicroclimate.Pressure_kPa];
SuitOutlet = [AverageMoisture_g_min; PeakMoisture_g_min; AverageCondenserInlet_C; ...
    RH_Sizing_InletRH_percent; RH_Sizing_Flow_CFM; BodyMicroclimate.Pressure_kPa];
% Moisture rows describe astronaut generation/net PLSS removal, not supply vapor.
SuitInlet = [0; 0; BodyMicroclimate.AirTemperature_C; ...
    BodyMicroclimate.RelativeHumidity_percent; Ventilation.Flow_CFM; BodyMicroclimate.Pressure_kPa];
Summary = table(Quantity, Overall, SuitInlet, SuitOutlet);

% EVA Summary
Quantity = ["EVA duration (hr)"; "Average metabolic rate (W)"; ...
    "Peak metabolic rate (W)"; "Final retained condensate (g)"];
Value = [Mars_Duration_hr; Mars_AverageRate_W; Mars_PeakRate_W; Moisture_Profile.CondensateEnd_g(end)];
EVA_Summary = table(Quantity, Value);

% PLSS Humidity Loads
Component = ["Respiratory"; "Evaporated fresh sweat"; "Skin diffusion"; ...
    "Evaporated retained sweat"; "Total vapor"];
ComponentRates_g_min = [Moisture_Profile.Respiratory_g_min, Moisture_Profile.SweatEvaporated_g_min, ...
    Moisture_Profile.SkinDiffusion_g_min, Moisture_Profile.RetainedEvaporation_g_min, ...
    Moisture_Profile.VaporToSuit_g_min] * FOS;
Total_g = sum(ComponentRates_g_min .* Moisture_Duration_min, 1)';
Average_g_min = Total_g / EVA_Duration_min;
Peak_g_min = max(ComponentRates_g_min, [], 1)';
Moisture_Summary = table(Component, Average_g_min, Peak_g_min, Total_g);

% Display Metabolic Results
disp('Overall, suit inlet and outlet summary (overall air: body-area and time weighted):');
disp(Summary);

disp('EVA summary:');
disp(EVA_Summary);

disp('Astronaut vapor sources:');
disp(Moisture_Summary);

%% Metabolic Model - EVA Air-State Profile
% Full EVA Air-State Profile
    % Preserve interval-average loads and coincident air states; no Mars adjustment.
    % Reconstruct regional outlet states from the JOS-3 inlet/outlet arithmetic means.
ProfilePressure_Pa = repmat(BodyMicroclimate.Pressure_kPa * 1000, height(Moisture_Profile), 1);
ProfileSupplyW = repmat(SupplyHumidityRatio, height(Moisture_Profile), 1);
ProfileSupplyT_C = repmat(BodyMicroclimate.AirTemperature_C, height(Moisture_Profile), 1);
ProfileMeanPressure_Pa = exp(16.6536 - 4030.183 ./ (ZoneTemperatures_C + 235)) ...
    .* ZoneRH_percent / 100 * 1000;
ProfileMeanW = (0.01801528 / 0.0319988) * ProfileMeanPressure_Pa ...
    ./ (ProfilePressure_Pa - ProfileMeanPressure_Pa);
ProfileOutletT_C = zeros(height(Moisture_Profile), 3);
ProfileOutletW = zeros(height(Moisture_Profile), 3);
for Zone = 1:3
    if Zone == 1
        NodeInletT_C = ProfileSupplyT_C;
        NodeInletW = ProfileSupplyW;
    else
        NodeInletT_C = ProfileOutletT_C(:, Zone - 1);
        NodeInletW = ProfileOutletW(:, Zone - 1);
    end
    ProfileOutletT_C(:, Zone) = 2 * ZoneTemperatures_C(:, Zone) - NodeInletT_C;
    ProfileOutletW(:, Zone) = 2 * ProfileMeanW(:, Zone) - NodeInletW;
end
assert(max(abs(ProfileOutletT_C(:, 3) - CondenserInlet_C)) < 1e-5, ...
    'RH:ProfileExport', 'Regional outlet reconstruction does not match JOS-3.');
EVA_Profile = table(Moisture_Profile.StartTime_min, Moisture_Profile.EndTime_min, ...
    SizingMoisture_Rate_g_min, Moisture_Rate_g_min, ProfilePressure_Pa / 1000, ...
    repmat(DryOxygenFlow_kg_s, height(Moisture_Profile), 1), ProfileSupplyT_C, ProfileSupplyW, ...
    'VariableNames', {'StartTime_min', 'EndTime_min', 'DesignMoisture_g_min', ...
    'PhysicalMoisture_g_min', 'Pressure_kPa', 'DryOxygenFlow_kg_s', ...
    'SupplyTemperature_C', 'SupplyHumidityRatio'});
EVA_Profile = [EVA_Profile, array2table(ZoneTemperatures_C, ...
    'VariableNames', {'NeckMean_C', 'TorsoMean_C', 'LegMean_C'}), ...
    array2table(ProfileMeanW, 'VariableNames', {'NeckMeanW', 'TorsoMeanW', 'LegMeanW'}), ...
    array2table(ProfileOutletT_C, 'VariableNames', {'NeckOutlet_C', 'TorsoOutlet_C', 'LegOutlet_C'}), ...
    array2table(ProfileOutletW, 'VariableNames', {'NeckOutletW', 'TorsoOutletW', 'LegOutletW'})];

%% Metabolic Model - Graphs
Moisture_Plot_Time_hr = [Moisture_Profile.StartTime_min; Moisture_Profile.EndTime_min(end)] / 60;
MetMan_Time_hours = [MetMan.StartTime_hr; MetMan.EndTime_hr(end)];
MetMan_MetabolicRate_W = [MetMan.MetabolicRate_kJ_hr; MetMan.MetabolicRate_kJ_hr(end)] / 3.6;
figure(1);
set(gcf, 'Name', '1. Metabolic Source Profiles', 'NumberTitle', 'off');
stairs(MetMan_Time_hours, MetMan_MetabolicRate_W);
hold on;
plot(Nominal_Time_hours, Nominal_MetabolicRate_W);
title('Source Metabolic Profiles');
legend('MetMan', 'Raw Nominal');
xlabel('Time (hours)');
ylabel('Metabolic Rate (W)');
grid on;

figure(2);
set(gcf, 'Name', '2. EVA Metabolism and Suit Outlet', 'NumberTitle', 'off');
tiledlayout(3, 1);
nexttile;
plot(Nominal_Time_hours, M_dot_mars);
title('Mapped Mars Metabolic Profile');
xlabel('Time (hours)');
ylabel('Metabolic Rate (W)');
grid on;

nexttile;
stairs(Moisture_Plot_Time_hr, [SizingMoisture_Rate_g_min; SizingMoisture_Rate_g_min(end)]);
title('Suit Outlet Moisture Rate');
xlabel('Time (hours)');
ylabel('Vapor rate (g/min)');
grid on;
nexttile;
stairs(Moisture_Plot_Time_hr, [CondenserInlet_C; CondenserInlet_C(end)]);
title('Suit Outlet Air Temperature');
xlabel('Time (hours)');
ylabel('Air temperature (C)');
grid on;

% Astronaut Vapor Sources
figure(3);
set(gcf, 'Name', '3. Astronaut Moisture Sources', 'NumberTitle', 'off');
stairs(Moisture_Plot_Time_hr, [ComponentRates_g_min; ComponentRates_g_min(end, :)]);
title('Astronaut Vapor Sources');
legend('Respiration', 'Fresh sweat evaporation', 'Skin diffusion', 'Retained sweat evaporation', 'Total astronaut vapor');
xlabel('Time (hours)');
ylabel('Vapor Rate (g/min)');
grid on;

% Regional Air Temperature
figure(4);
set(gcf, 'Name', '4. Suit Air Temperature History', 'NumberTitle', 'off');
stairs(Moisture_Plot_Time_hr, [ZoneTemperatures_C; ZoneTemperatures_C(end, :)]);
legend('Head/neck zone mean', 'Torso/arms zone mean', 'Leg zone mean', 'Location', 'best');
xlabel('Time (hours)');
ylabel('Air-region temperature (C)');
title('Suit Air Temperature by Region');
grid on;

% Temperature and RH along the Airflow Path
% Regional values are zone means; the last point is the final leg outlet.
% Spacing is schematic, not a physical distance along the suit.
NodeLabels = {'Neck supply', 'Head/neck mean', 'Torso/arms mean', 'Leg zone mean', 'Leg outlet'};
GradientTemperature_C = [BodyMicroclimate.AirTemperature_C, ...
    sum(ZoneTemperatures_C .* Moisture_Duration_min, 1) / EVA_Duration_min, AverageCondenserInlet_C];
GradientRH_percent = [BodyMicroclimate.RelativeHumidity_percent, ...
    sum(ZoneRH_percent .* Moisture_Duration_min, 1) / EVA_Duration_min, ...
    sum(Moisture_Profile.CondenserInletRH_percent .* Moisture_Duration_min) / EVA_Duration_min];
figure(5);
set(gcf, 'Name', '5. Average Suit Airflow Gradient', 'NumberTitle', 'off');
tiledlayout(2, 1);
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

%% RH Sizing - Calculations
% Metabolic Results Used by RH Sizing
    % Direct values replace the former spreadsheet transfer. No extra feedback is added.
Gas.SuitTemperature_C = AverageCondenserInlet_C;
Gas.SuitRH_percent = RH_Sizing_InletRH_percent;
Gas.Flow_CFM = RH_Sizing_Flow_CFM; % Actual condenser-inlet flow, not supply CFM.
Gas.Pressure_kPa = BodyMicroclimate.Pressure_kPa;

% Water Properties and Porous Pressure Limits
    % ASSUMPTION: liquid drains at the selected wetted-surface temperature.
    % IAPWS liquid-water density, viscosity and cp; IAPWS surface tension.
Water = liquidWaterProperties(Condenser.SurfaceTemperature_C);
ReferenceWater = liquidWaterProperties(MaterialReferenceTemperature_C);
Water.VaporCp_J_kgK = 1860; % Ideal-vapor cp approximation over this low-temperature range.
Water.VaporEnthalpyAtZero_J_kg = 2500900; % Psychrometric enthalpy reference, J/kg.
Water.VaporGasConstant_J_kgK = 461.51805;
% Convert reported hydraulic conductivity to intrinsic permeability, not cold-water K.
Separator.Permeability_m2 = Separator.HydraulicConductivity_m_s * ReferenceWater.Viscosity_Pa_s ...
    / (ReferenceWater.Density_kg_m3 * 9.80665);
% ASSUMPTION: wettability is unchanged; scale reported entry pressures with surface tension.
SurfaceTensionRatio = Water.SurfaceTension_N_m / ReferenceWater.SurfaceTension_N_m;
BubblePressure_Pa = Separator.ReferenceBubblePressure_Pa * SurfaceTensionRatio;
RetentionPressure_Pa = Substrate.ReferenceBubblePressure_Pa * SurfaceTensionRatio;

% Input Validation - RH Sizing
validateattributes(AverageMoisture_g_min, {'numeric'}, {'scalar', 'finite', 'positive'});
validateattributes(Water_Load_FOS, {'numeric'}, {'scalar', 'finite', '>=', 1});
validateattributes(Gas.SuitRH_percent, {'numeric'}, {'scalar', 'finite', '>', 0, '<=', 100});
validateattributes(Gas.SuitTemperature_C, {'numeric'}, {'scalar', 'finite', '>', 0});
validateattributes(Condenser.SurfaceTemperature_C, {'numeric'}, {'scalar', 'finite', '>', 0});
assert(Condenser.SurfaceTemperature_C < Gas.SuitTemperature_C, ...
    'RH:Temperature', 'Condenser surface must be colder than suit air.');
Positive = [EVA_Duration_min, Gas.Pressure_kPa, Gas.Flow_CFM, ...
    Condenser.ChannelGap_m, Condenser.ChannelHeight_m, Condenser.ChannelLength_m, Condenser.FinThickness_m, ...
    Condenser.FinConductivity_W_mK, EVA_Sizing.FreeGasVolume_L, ...
    Separator.Thickness_m, Separator.Permeability_m2, Separator.SuctionPressure_Pa, ...
    Separator.ReferenceBubblePressure_Pa, Separator.MinimumLiquidPressure_kPa, ...
    Substrate.ReferenceBubblePressure_Pa, Water.Density_kg_m3, Water.Viscosity_Pa_s];
assert(all(isfinite(Positive) & Positive > 0), 'RH:Inputs', 'Inputs must be positive and finite.');
assert(Separator.PermeabilityRetention > 0 && Separator.PermeabilityRetention <= 1 && ...
    Separator.BubblePressureFOS >= 1 && ...
    isfinite(Drain.PressureAllowance_Pa) && ...
    Drain.PressureAllowance_Pa >= 0, 'RH:DrainInputs', 'Check drainage assumptions.');

% Source Load and Oxygen Properties
Water.DesignRate_kg_s = AverageMoisture_g_min * Water_Load_FOS / 60000;
RequiredRemoval_g_min = Water.DesignRate_kg_s * 60000;
Gas = condenserGasProperties(Gas, Water, Condenser);

% Average-Load Condenser Area
Selected = condenserArea(Condenser.SurfaceTemperature_C, Gas, Water, Condenser);

% Continuous Liquid Extraction Area
SeparatorPressure_Pa = Separator.SuctionPressure_Pa - RetentionPressure_Pa - Drain.PressureAllowance_Pa;
DrainFeasible = SeparatorPressure_Pa > 0 && ...
    BubblePressure_Pa / Separator.SuctionPressure_Pa >= Separator.BubblePressureFOS && ...
    Gas.Pressure_kPa - Separator.SuctionPressure_Pa / 1000 >= Separator.MinimumLiquidPressure_kPa && ...
    Gas.Pressure_kPa * 1000 - Separator.SuctionPressure_Pa > saturationPressure(Water.Temperature_C);
%% RH Sizing - Sensitivity Analysis
% Change one input at a time by +/-10%; recalculate properties and transfer.
SensitivityInputs = ["Moisture load (g/min)", "Inlet temperature (C)", "Inlet RH (%)"];
SensitivityBase = [RequiredRemoval_g_min, Gas.SuitTemperature_C, Gas.SuitRH_percent];
Input = [repelem(SensitivityInputs(:), 2); "Surface temperature (C)"; "Surface temperature (C)"];
Change_percent = repmat([-10; 10], 3, 1);
Change = [repmat(["-10%"; "+10%"], 3, 1); "2 C surface"; "5 C surface"];
InputValue = zeros(8, 1);
Area_m2 = Inf(8, 1);
Cooling_W = NaN(8, 1);
Feasible = false(8, 1);
for Row = 1:8
    InputIndex = ceil(Row / 2);
    if Row <= 6
        InputValue(Row) = SensitivityBase(InputIndex) * (1 + Change_percent(Row) / 100);
    else
        SurfaceCases_C = [2, 5];
        InputValue(Row) = SurfaceCases_C(Row - 6);
    end
    TrialCondenser = Condenser;
    TrialGas = Gas;
    TrialWater = Water;
    switch InputIndex
        case 1
            TrialWater.DesignRate_kg_s = InputValue(Row) / 60000;
        case 2
            TrialGas.SuitTemperature_C = InputValue(Row);
        case 3
            TrialGas.SuitRH_percent = InputValue(Row);
        case 4
            TrialCondenser.SurfaceTemperature_C = InputValue(Row);
            Properties = liquidWaterProperties(InputValue(Row));
            TrialWater.Cp_J_kgK = Properties.Cp_J_kgK;
            TrialWater.Density_kg_m3 = Properties.Density_kg_m3;
            TrialWater.Viscosity_Pa_s = Properties.Viscosity_Pa_s;
    
    end
    % Keep invalid perturbed conditions visible as infeasible rows.
    if TrialGas.SuitRH_percent <= 100 && TrialGas.SuitTemperature_C > TrialCondenser.SurfaceTemperature_C ...
            && TrialGas.SuitRH_percent / 100 * saturationPressure(TrialGas.SuitTemperature_C) < TrialGas.Pressure_Pa
        TrialGas = condenserGasProperties(TrialGas, TrialWater, TrialCondenser);
        Trial = condenserArea(TrialCondenser.SurfaceTemperature_C, TrialGas, TrialWater, TrialCondenser);
        Area_m2(Row) = Trial.RequiredArea_m2;
        Cooling_W(Row) = Trial.CoolingDuty_W;
        Feasible(Row) = Trial.Feasible;
    end
end
AreaChange_percent = NaN(8, 1);
CoolingChange_percent = NaN(8, 1);
if Selected.Feasible
    AreaChange_percent = 100 * (Area_m2 / Selected.RequiredArea_m2 - 1);
    CoolingChange_percent = 100 * (Cooling_W / Selected.CoolingDuty_W - 1);
end
Sensitivity_Summary = table(Input, Change, InputValue, Area_m2, AreaChange_percent, ...
    Cooling_W, CoolingChange_percent, Feasible);

%% RH Sizing - Full EVA Comparison
% A separate function keeps the time-history sizing out of the plotting sections.
EVA_Sizing.LoadFOS = Water_Load_FOS;
EVA_Sizing.Duration_min = EVA_Duration_min;
GasPropertiesFunction = @condenserGasProperties;
AreaSizingFunction = @condenserArea;
EVA_Design = sizeEVARH(EVA_Profile, Gas, Water, Condenser, Separator, ...
    SeparatorPressure_Pa, EVA_Sizing, GasPropertiesFunction, AreaSizingFunction);
%% RH Sizing - Results
fprintf('\nFixed suit ventilation: %.3g actual CFM at the supply conditions.\n', Ventilation.Flow_CFM);
fprintf('RH excursions are reported without rejecting selected condensers; above 100%% indicates unmodelled condensation.\n');

disp('Selected condenser sizing and full-EVA performance:');
SelectedSummary = EVA_Design.SelectedSummary;
fprintf('%-32s %18s %18s\n', 'Quantity', 'Average-load size', '99% capacity size');
fprintf('%-32s %18s %18s\n', 'Core dimensions (L x W x H, mm)', ...
    sprintf('%.1f x %.1f x %.1f', SelectedSummary.CoreLength_mm(1), SelectedSummary.CoreWidth_mm(1), SelectedSummary.CoreHeight_mm(1)), ...
    sprintf('%.1f x %.1f x %.1f', SelectedSummary.CoreLength_mm(2), SelectedSummary.CoreWidth_mm(2), SelectedSummary.CoreHeight_mm(2)));
SelectedLabels = ["Transfer area (m2)"; "Core volume (L)"; "Average cooling (W)"; ...
    "Peak cooling (W)"; "Average removal (g/min)"; "Peak removal (g/min)"; ...
    "Max saturated capacity (g/min)"; "Collected water (g)"; "Maximum suit RH (%)"; ...
    "Average condenser exit temp (C)"; "Peak condenser exit temp (C)"; ...
    "Average condenser exit RH (%)"; "Peak condenser exit RH (%)"];
SelectedValues = [SelectedSummary.InstalledArea_m2'; SelectedSummary.CoreVolume_L'; ...
    SelectedSummary.AverageCooling_W'; SelectedSummary.PeakCooling_W'; ...
    SelectedSummary.AverageRemoval_g_min'; SelectedSummary.PeakRemoval_g_min'; ...
    SelectedSummary.MaximumSaturatedCapacity_g_min'; SelectedSummary.CollectedWater_g'; ...
    SelectedSummary.MaximumSuitRH_percent'; SelectedSummary.AverageCondenserOutlet_C'; ...
    SelectedSummary.PeakCondenserOutlet_C'; SelectedSummary.AverageCondenserOutletRH_percent'; ...
    SelectedSummary.PeakCondenserOutletRH_percent'];
for Row = 1:numel(SelectedLabels)
    fprintf('%-32s %18.3f %18.3f\n', SelectedLabels(Row), SelectedValues(Row, 1), SelectedValues(Row, 2));
end
fprintf('Condenser exit conditions are before external reheating; averages are time weighted.\n');
fprintf('Above 100%% RH indicates unmodelled condensation/fog; removal and cooling may be overstated.\n\n');
disp('Sensitivity at the average inlet state (fixed airflow; not a full-EVA rerun):');
disp(Sensitivity_Summary);
fprintf('Areas are rounded up to whole channels. Core length %.2f mm; height %.2f mm.\n', ...
    Condenser.ChannelLength_m * 1000, Condenser.ChannelHeight_m * 1000);
fprintf('Temperatures and astronaut sources remain prescribed; condenser feedback to JOS-3 is not rerun.\n');

%% Hardware Sizing - Input Requirements and Snapshot
% Save a design snapshot; component calculations below use Component_Inputs directly.
% Use the 99%-capacity case for all downstream component requirements.
ComponentDesign = EVA_Design.SelectedSummary(2, :);
ComponentDesignValid = ComponentDesign.MaximumSuitRH_percent <= 100 && DrainFeasible;
ComponentSeparatorArea_m2 = ComponentDesign.PeakRemoval_g_min / 60000 ...
    / Water.Density_kg_m3 * Water.Viscosity_Pa_s * Separator.Thickness_m ...
    / (Separator.Permeability_m2 * Separator.PermeabilityRetention * SeparatorPressure_Pa);
Parameter = ["WaterRate_g_min"; "EVA_Duration_min"; "SurfaceTemperature_C"; ...
    "CoolingDuty_W"; "CondenserArea_m2"; "ChannelCount"; "ChannelGap_m"; ...
    "FinThickness_m"; "ChannelHeight_m"; "ChannelLength_m"; "SeparatorArea_m2"; ...
    "SeparatorThickness_m"; "SuctionPressure_Pa"; "GasPressure_kPa"; ...
    "ActualFlow_m3_s"; "ChannelPressureDrop_Pa"; "WaterDensity_kg_m3"];
Label = ["Peak collected water rate, 99% capacity case"; "Storage duration"; "Cooled fin-root temperature"; ...
    "Peak cooling duty, 99% capacity case"; "Installed wetted condenser area"; ...
    "Rounded installed channel count"; "Clear gas gap"; "Graphite fin thickness"; ...
    "Clear gas channel height"; "Gas channel length"; "Required liquid separator area"; ...
    "Equivalent separator thickness"; "Liquid suction below suit pressure"; ...
    "Absolute gas pressure"; "Actual gas volume flow"; "Straight-channel friction only"; ...
    "Liquid density at operating temperature"];
Value = [ComponentDesign.PeakRemoval_g_min; EVA_Duration_min; Condenser.SurfaceTemperature_C; ...
    ComponentDesign.PeakCooling_W; ComponentDesign.InstalledArea_m2; ComponentDesign.Channels; ...
    Condenser.ChannelGap_m; Condenser.FinThickness_m; Condenser.ChannelHeight_m; ...
    Condenser.ChannelLength_m; ComponentSeparatorArea_m2; Separator.Thickness_m; ...
    Separator.SuctionPressure_Pa; Gas.Pressure_kPa; EVA_Design.PeakFlow_m3_s; ...
    EVA_Design.SelectedPressureDrop_Pa(2); Water.Density_kg_m3];
Unit = ["g/min"; "min"; "deg C"; "W thermal"; "m2"; "count"; "m"; "m"; "m"; "m"; ...
    "m2"; "m"; "Pa"; "kPa absolute"; "m3/s actual"; "Pa"; "kg/m3"];
Parameter = [Parameter; "AverageCoolingDuty_W"; "TotalCollectedWater_kg"; "AverageMoisture_g_min"];
Label = [Label; "Time-weighted EVA cooling duty"; "Integrated EVA collected water"; "Time-weighted EVA moisture"];
Value = [Value; ComponentDesign.AverageCooling_W; ComponentDesign.CollectedWater_g / 1000; ...
    ComponentDesign.AverageRemoval_g_min];
Unit = [Unit; "W thermal"; "kg"; "g/min"];
Component_Inputs = table(Parameter, Label, Value, Unit);
Component_Input_File = fullfile(fileparts(mfilename('fullpath')), 'RH_Component_Inputs.xlsx');
% Preserve other workbook sheets; clear only the obsolete sweep results.
if isfile(Component_Input_File) && any(strcmp(sheetnames(Component_Input_File), 'Airflow Search'))
    writecell({'Status', 'Airflow sweep removed; the model now uses the fixed supply airflow.'}, ...
        Component_Input_File, 'Sheet', 'Airflow Search', 'WriteMode', 'overwritesheet');
end
writecell({'99 percent capacity design valid', ComponentDesignValid; ...
    'Reason', char(ComponentDesign.Note); ...
    'Selected RH ceiling design valid', EVA_Design.BufferedFeasible}, ...
    Component_Input_File, 'Sheet', 'Design Status', 'WriteMode', 'overwritesheet');
writetable(EVA_Design.TimeHistory, Component_Input_File, 'Sheet', 'EVA Requirements', ...
    'WriteMode', 'overwritesheet', 'AutoFitWidth', true);
writetable(EVA_Design.SelectedSummary, Component_Input_File, 'Sheet', 'EVA Comparison', ...
    'WriteMode', 'overwritesheet', 'AutoFitWidth', true);
writetable(Component_Inputs, Component_Input_File, 'Sheet', 'Component Inputs', ...
    'WriteMode', 'overwritesheet', 'AutoFitWidth', true);
writecell({'Source', 'Nominal_Metabolic_Profile.m: 99 percent capacity condenser case'; ...
    'Updated UTC', char(datetime('now', 'TimeZone', 'UTC')); ...
    'Refresh', 'Rerun Nominal_Metabolic_Profile.m; component sizing is included.'}, ...
    Component_Input_File, 'Sheet', 'Component Inputs', 'Range', 'A24', 'AutoFitWidth', false);

%% Hardware Sizing - Calculations
% Use the in-memory 99%-capacity requirements; no workbook read is needed.
ComponentModelValid = ComponentDesignValid;
assert(all(isfinite(Component_Inputs.Value) & Component_Inputs.Value > 0), ...
    'RH:ComponentInputs', 'Component requirements must be positive and finite.');
for Row = 1:height(Component_Inputs)
    RH.(Component_Inputs.Parameter(Row)) = Component_Inputs.Value(Row);
end
assert(RH.ChannelCount == round(RH.ChannelCount), 'RH:Channels', 'Channel count must be an integer.');

% Assumption Checks
assert(PackingFactor > 0 && PackingFactor <= 1 && StorageFillFraction > 0 ...
    && StorageFillFraction < 1 && CoolingMargin >= 1 && TankJointEfficiency > 0 ...
    && TankJointEfficiency <= 1 && BlowerEfficiency > 0 && BlowerEfficiency <= 1, ...
    'RH:Assumptions', 'Check packing, fill, efficiency and margin inputs.');
assert(ColdPlateMetalFraction > 0 ...
    && ColdPlateMetalFraction <= 1 && ExternalPressure_kPa < RH.GasPressure_kPa, ...
    'RH:Geometry', 'Check cold plate and external pressure.');
assert(Loop.Flow_L_min > 0 && Loop.MaximumRise_K > 0 && Loop.CondensingApproach_K > 0 ...
    && Loop.HeaderPressureDrop_Pa >= 0, ...
    'RH:LoopInputs', 'Check shared water-loop inputs.');

% Integrated Porous Condenser and Separator Dimensions
CoreWidth_m = RH.ChannelCount * RH.ChannelGap_m ...
    + (RH.ChannelCount + 1) * RH.FinThickness_m;
CoreHeight_m = RH.ChannelHeight_m + 2 * PorousBaseThickness_m;
CoreLength_m = RH.ChannelLength_m;
FinVolume_m3 = (RH.ChannelCount + 1) * RH.FinThickness_m ...
    * RH.ChannelHeight_m * CoreLength_m;
BaseVolume_m3 = 2 * CoreWidth_m * CoreLength_m * PorousBaseThickness_m;
CondenserEnvelope_m = [CoreLength_m, CoreWidth_m, CoreHeight_m];
CondenserMass_kg = (FinVolume_m3 + BaseVolume_m3) * GraphiteDensity_kg_m3;
% ASSUMPTION: separation is integrated within this substrate envelope/mass.
% Hydraulic separator area remains a requirement, not an additional ceramic stack.
% Detailed embedded separator construction and gas/liquid manifolds are not sized.

% Heat Exchanger and Refrigeration Capability
DesignCooling_W = RH.CoolingDuty_W * CoolingMargin;
AverageDesignCooling_W = RH.AverageCoolingDuty_W * CoolingMargin;
ColdPlateArea_m2 = max(DesignCooling_W / ColdPlateHeatFlux_W_m2, CoreWidth_m * CoreLength_m);
ColdPlateEnvelope_m = [sqrt(ColdPlateArea_m2), sqrt(ColdPlateArea_m2), ColdPlateThickness_m];
ColdPlateMass_kg = prod(ColdPlateEnvelope_m) * ColdPlateMetalFraction * AluminiumDensity_kg_m3;
Evaporator_C = RH.SurfaceTemperature_C - EvaporatorApproach_K;
[UnitCapacity_W, UnitPower_W] = compressorMap(Evaporator_C, RefrigerantCondensing_C);
CompressorCount = ceil(DesignCooling_W / UnitCapacity_W);
CompressorDutyFraction = AverageDesignCooling_W / (CompressorCount * UnitCapacity_W);
CompressorAverage_W = CompressorCount * UnitPower_W * CompressorDutyFraction;
CompressorOn_W = CompressorCount * UnitPower_W;
% Map includes compressor electrical input; accessory hardware is excluded.
RefrigerationCOP = UnitCapacity_W / UnitPower_W;

% Pump Capability and Liquid Storage
LiquidFlow_m3_s = RH.WaterRate_g_min / 60000 / RH.WaterDensity_kg_m3;
RequiredPumpFlow_ml_min = LiquidFlow_m3_s * 60e6 * PumpFlowMargin;
PumpInlet_kPa = RH.GasPressure_kPa - RH.SuctionPressure_Pa / 1000;
% Tank is assumed pressure-balanced to suit pressure, with a liquid bladder.
RequiredPumpPressure_Pa = RH.SuctionPressure_Pa + DrainLoss_Pa;
PumpHydraulic_W = RequiredPumpPressure_Pa * RequiredPumpFlow_ml_min / 60e6;
AverageLiquidFlow_ml_min = RH.AverageMoisture_g_min / RH.WaterDensity_kg_m3 * 1000;
PumpDutyFraction = AverageLiquidFlow_ml_min / RequiredPumpFlow_ml_min;
% Equivalent on-time assumes storage between cycles; cycling/control is not designed.
PumpOnTime_min = PumpDutyFraction * RH.EVA_Duration_min;
assert(PumpInlet_kPa > 0, 'RH:PumpInlet', 'Pump inlet absolute pressure must be positive.');
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

% Transfer RH Heat to the Shared Water Loop
AddedBlower_W = RH.ActualFlow_m3_s * RH.ChannelPressureDrop_Pa ...
    * GasPressureDropFactor / BlowerEfficiency;
% Refrigerant condenser transfers evaporator heat plus compressor work.
HotHX.Duty_W = AverageDesignCooling_W + CompressorAverage_W;
% Size the exchanger for full reference compressor on-state capacity, not mean duty.
HotHX.DesignDuty_W = CompressorCount * UnitCapacity_W + CompressorOn_W;
HotHX.DesignWaterOutlet_C = Loop.LCGOutletTemperature_C + HotHX.DesignDuty_W / Loop.HeatCapacity_W_K;
HotApproach_K = RefrigerantCondensing_C - Loop.LCGOutletTemperature_C;
ColdApproach_K = RefrigerantCondensing_C - HotHX.DesignWaterOutlet_C;
assert(ColdApproach_K > 0, 'RH:WaterTemperature', 'Water is too warm for the selected condensing temperature.');
LMTD_K = (HotApproach_K - ColdApproach_K) / log(HotApproach_K / ColdApproach_K);
% Fully developed water-channel h; two broad faces transfer heat.
HotHX.ChannelCount = ceil(Loop.Flow_m3_s ...
    / (HotHX.TargetVelocity_m_s * HotHX.Gap_m * HotHX.ChannelWidth_m));
HotHX.HydraulicDiameter_m = 2 * HotHX.Gap_m * HotHX.ChannelWidth_m ...
    / (HotHX.Gap_m + HotHX.ChannelWidth_m);
a = HotHX.Gap_m / HotHX.ChannelWidth_m;
Nu = 7.541 * (1 - 2.610*a + 4.970*a^2 - 5.119*a^3 + 2.702*a^4 - 0.548*a^5);
HotHX.WaterFilm_W_m2K = Nu * Loop.Conductivity_W_mK / HotHX.HydraulicDiameter_m;
% Calculated resistance sum, not a fixed overall coefficient.
HotHX.Overall_W_m2K = 1 / (1 / HotHX.WaterFilm_W_m2K ...
    + HotHX.Wall_m / HotHX.MetalConductivity_W_mK + 1 / HotHX.RefrigerantFilm_W_m2K);
HotHX.Area_m2 = HotHX.DesignDuty_W / (HotHX.Overall_W_m2K * LMTD_K);
HotHX.Length_m = HotHX.Area_m2 / (2 * HotHX.ChannelCount * HotHX.ChannelWidth_m);
HotHX.Width_m = HotHX.ChannelCount * HotHX.ChannelWidth_m ...
    + (HotHX.ChannelCount + 1) * HotHX.FinThickness_m;
HotHX.Height_m = HotHX.Gap_m + 2 * HotHX.Wall_m;
% Two extra 1 mm outer plates allow refrigerant passages beside the water plate.
HotHXEnvelope_m = [HotHX.Length_m + 2 * HeaderLength_m, HotHX.Width_m, HotHX.Height_m + 0.002];
HotHXVoid_m3 = HotHX.ChannelCount * HotHX.Gap_m * HotHX.ChannelWidth_m * HotHX.Length_m;
HotHXMass_kg = (prod(HotHXEnvelope_m) - HotHXVoid_m3) * AluminiumDensity_kg_m3;
WaterVelocity_m_s = Loop.Flow_m3_s / (HotHX.ChannelCount * HotHX.Gap_m * HotHX.ChannelWidth_m);
HotHX.Reynolds = Loop.Density_kg_m3 * WaterVelocity_m_s * HotHX.HydraulicDiameter_m / Loop.Viscosity_Pa_s;
assert(HotHX.Reynolds < 2300, 'RH:WaterFlow', 'Water channels exceed the laminar correlation.');
Poiseuille = 96 * (1 - 1.3553*a + 1.9467*a^2 - 1.7012*a^3 + 0.9564*a^4 - 0.2537*a^5);
HotHX.PressureDrop_Pa = Poiseuille / HotHX.Reynolds * HotHX.Length_m ...
    / HotHX.HydraulicDiameter_m * Loop.Density_kg_m3 * WaterVelocity_m_s^2 / 2 ...
    + Loop.HeaderPressureDrop_Pa;
% Conservative allocation: all RH auxiliary electrical losses ultimately enter water.
ExternalRadiatorAddedLoad_W = HotHX.Duty_W + AddedBlower_W;
ExternalRadiatorAddedOnState_W = HotHX.DesignDuty_W + AddedBlower_W;
OnStateWaterToExternalCooling_C = Loop.LCGOutletTemperature_C ...
    + ExternalRadiatorAddedOnState_W / Loop.HeatCapacity_W_K;
assert(RefrigerantCondensing_C - OnStateWaterToExternalCooling_C >= Loop.CondensingApproach_K, ...
    'RH:LoopApproach', 'Insufficient hot-side temperature approach at on-state heat load.');
% MaximumRise_K selects an initial condensing-temperature allowance, not a measured water limit.
% This is only RH's added radiator load; existing LCG heat is not counted again.

%% Hardware Sizing - Results
Component = ["Porous condenser / integrated separator"; "Cold heat exchanger"; ...
    "Refrigeration compressors"; "Liquid storage tank"; "Refrigerant-to-water heat exchanger"];
Dimensions_m = [CondenserEnvelope_m; ColdPlateEnvelope_m; ...
    CompressorEnvelope_m .* [CompressorCount, 1, 1]; TankEnvelope_m; HotHXEnvelope_m];
Length_mm = Dimensions_m(:, 1) * 1000;
Width_mm = Dimensions_m(:, 2) * 1000;
Height_mm = Dimensions_m(:, 3) * 1000;
EnvelopeVolume_L = prod(Dimensions_m, 2) * 1000;
DryMass_kg = [CondenserMass_kg; ColdPlateMass_kg; ...
    CompressorCount * CompressorMass_kg; TankMass_kg; HotHXMass_kg];
StoredWater_kg = [0; 0; 0; WaterStored_kg; 0];
AverageElectrical_W = [0; 0; CompressorAverage_W; 0; 0];
OnStateElectrical_W = [0; 0; CompressorOn_W; 0; 0];
Component_Summary = table(Component, Length_mm, Width_mm, Height_mm, EnvelopeVolume_L, ...
    DryMass_kg, StoredWater_kg, AverageElectrical_W, OnStateElectrical_W);
InternalPackageVolume_L = sum(EnvelopeVolume_L) / PackingFactor;
System_Summary = table(PackingFactor, InternalPackageVolume_L, ...
    sum(DryMass_kg), sum(DryMass_kg) + WaterStored_kg, sum(AverageElectrical_W) + AddedBlower_W, ...
    sum(OnStateElectrical_W) + AddedBlower_W, (sum(AverageElectrical_W) + AddedBlower_W) * RH.EVA_Duration_min / 60, ...
    'VariableNames', {'PackingFactor', 'InternalPackage_L', ...
    'DryMass_kg', 'EndEVAMass_kg', 'AverageElectrical_W', 'OnStateElectrical_W', 'EVA_Energy_Wh'});
Capability_Summary = table(DesignCooling_W, ColdPlateArea_m2, RefrigerationCOP, ...
    RequiredPumpFlow_ml_min, RequiredPumpPressure_Pa / 1000, PumpInlet_kPa, ...
    PumpHydraulic_W, TankInternalVolume_m3 * 1000, ExternalRadiatorAddedLoad_W, ...
    'VariableNames', {'DesignCooling_W', 'ColdPlateArea_m2', 'COP', 'PumpFlow_ml_min', ...
    'PumpPressureRise_kPa', 'PumpInletAbsolute_kPa', 'PumpHydraulic_W', ...
    'TankCapacity_L', 'AddedExternalRadiatorLoad_W'});
if ~ComponentModelValid
    fprintf('Provisional 99%%-capacity hardware estimate: %s\n', string(ComponentDesign.Note));
end
disp(Component_Summary);
displaySummary('Package mass, volume and electrical demand', ...
    ["Packing factor"; "Internal package volume"; "Dry mass"; "End-EVA mass, including collected water"; ...
    "Average electrical power"; "Compressor on-state electrical power"; "EVA electrical energy"], ...
    table2array(System_Summary), ["-"; "L"; "kg"; "kg"; "W electrical"; "W electrical"; "Wh"]);
displaySummary('Equipment requirements and equivalent duty cycles', ...
    ["Liquid pump rated flow"; "Liquid pump pressure rise"; "Liquid pump inlet pressure"; ...
    "Liquid pump hydraulic power when on"; "Liquid pump equivalent duty cycle"; "Liquid pump total on-time"; ...
    "Cold heat exchanger design duty"; "Cold heat exchanger area"; "Cold exchanger equivalent load fraction"; ...
    "Compressor count"; "Cooling capacity per compressor"; "Electrical power per compressor"; ...
    "Compressor equivalent duty cycle"; "Compressor total on-time"; ...
    "Refrigerant evaporating temperature"; "Refrigerant condensing temperature"; ...
    "Hot heat exchanger design duty"; "Hot heat exchanger area"; ...
    "Hot exchanger equivalent load fraction"; "Required hot-side water flow"; ...
    "Hot-side water pressure drop"; "Integrated separator hydraulic area"; "Refrigeration COP"; "Water tank capacity"], ...
    [RequiredPumpFlow_ml_min; RequiredPumpPressure_Pa / 1000; PumpInlet_kPa; ...
    PumpHydraulic_W; PumpDutyFraction * 100; PumpOnTime_min; ...
    DesignCooling_W; ColdPlateArea_m2; AverageDesignCooling_W / DesignCooling_W * 100; CompressorCount; UnitCapacity_W; UnitPower_W; ...
    CompressorDutyFraction * 100; CompressorDutyFraction * RH.EVA_Duration_min; ...
    Evaporator_C; RefrigerantCondensing_C; HotHX.DesignDuty_W; HotHX.Area_m2; ...
    HotHX.Duty_W / HotHX.DesignDuty_W * 100; Loop.Flow_L_min; ...
    HotHX.PressureDrop_Pa / 1000; RH.SeparatorArea_m2; RefrigerationCOP; TankInternalVolume_m3 * 1000], ...
    ["mL/min"; "kPa"; "kPa absolute"; "W hydraulic"; "%"; "min"; ...
    "W thermal"; "m2"; "%"; "count"; "W thermal"; "W electrical"; "%"; "min"; ...
    "C"; "C"; "W thermal"; "m2"; "%"; "L/min"; "kPa"; "m2"; "-"; "L"]);
fprintf('Components use the 99%%-capacity condenser: its peak duty sizes refrigeration; storage and average power use its EVA totals.\n');
fprintf('Totals exclude casing, separate separator hardware, pumps, valves, tubing and controls. Blower increment remains included.\n');
fprintf('Duty cycles are equivalent load fractions, assuming buffered liquid and ideal compressor cycling.\n');
fprintf('Integrated separation is a packaging assumption; embedded construction needs verification.\n');

%% RH Sizing - Graphs
% Gas.Flow_CFM is the corresponding actual condenser-inlet flow at mean T/RH.
plotRHFigures(Gas, Water, Condenser, Ventilation.Flow_CFM, ComponentDesign);

% Maximum Suit RH for Both Selected Condensers
figure(8);
set(gcf, 'Name', '8. Condenser EVA Humidity Performance', 'NumberTitle', 'off');
clf;
hold on;
for Selection = 1:2
    History = EVA_Design.SelectedHistory{Selection};
    if ~isempty(History)
        % Plot each interval's maximum, matching the summary peak calculation.
        plot(EVA_Design.Time_min, History.MaximumRH_percent, 'LineWidth', 1.5, ...
            'DisplayName', EVA_Design.SelectedSummary.Case(Selection));
    end
end
xlim([EVA_Profile.StartTime_min(1), EVA_Profile.EndTime_min(end)]);
xlabel('EVA time (min)'); ylabel('Interval maximum suit RH (%)');
title({'Condenser EVA Humidity Performance', 'RH above 100% indicates unmodelled condensation'});
legend('show', 'Location', 'best');
grid on;
hold off;

%% Local Functions
function Mapped_Rates_kJ_hr = mapMetabolicRates(Activity_Names, MetMan)
% Look up each nominal activity's rate in Metabolic.xlsx.
% Repeated activities are allowed only when their metabolic rates agree.
% Above Nominal is defined as 80% of the source resistance exercise rate.
% Other MetMan outputs vary over time and require separate mapping rules.

Source_Activities = lower(strtrim(string(MetMan.Activity)));
Activity_Labels = strtrim(string(Activity_Names));
Requested_Activities = lower(Activity_Labels);

Mapped_Rates_kJ_hr = zeros(size(Requested_Activities));
AboveNominal_Rows = Requested_Activities == "above nominal";
if any(AboveNominal_Rows)
    Resistance_Rate_kJ_hr = mapMetabolicRates("Exercise - Resistance", MetMan);
    Mapped_Rates_kJ_hr(AboveNominal_Rows) = 0.8 * Resistance_Rate_kJ_hr;
end

for Activity_Name = reshape(unique(Requested_Activities(~AboveNominal_Rows)), 1, [])
    Requested_Rows = Requested_Activities == Activity_Name;
    Source_Rows = Source_Activities == Activity_Name;
    if ~any(Source_Rows)
        Activity_Label = Activity_Labels(find(Requested_Rows, 1));
        error('MetabolicProfile:UnmappedActivity', ...
            ['Activity "%s" in Raw_Nominal.csv was not found in ' ...
             'Metabolic.xlsx. Update the activity mapping or add a ' ...
             'corresponding source activity.'], char(Activity_Label));
    end

    Source_Rates_kJ_hr = MetMan.MetabolicRate_kJ_hr(Source_Rows);
    if any(~isfinite(Source_Rates_kJ_hr) | Source_Rates_kJ_hr < 0)
        error('MetabolicProfile:InvalidRate', ...
            'Activity "%s" has a missing or invalid metabolic rate.', ...
            char(Activity_Name));
    end
    if numel(unique(Source_Rates_kJ_hr)) ~= 1
        error('MetabolicProfile:ConflictingRates', ...
            ['Activity "%s" has multiple metabolic rates in ' ...
             'Metabolic.xlsx. Use an unambiguous activity mapping.'], ...
            char(Activity_Name));
    end
    Mapped_Rates_kJ_hr(Requested_Rows) = Source_Rates_kJ_hr(1);
end
end

function Water = liquidWaterProperties(Temperature_C)
% IAPWS SR6-08(2011), Eqs. 2 and 7, Tables 1-2; R1-76(2014) surface tension.
% https://iapws.org/technical-guidance/release/LiquidWater.download
% https://iapws.org/technical-guidance/release/Surf-H2O.download
% Use the 0.1 MPa liquid correlations as a low-pressure approximation for rho/cp.
% IAPWS permits the viscosity equation from saturation pressure to 0.3 MPa.
validateattributes(Temperature_C, {'numeric'}, {'scalar', 'finite', '>=', 0, '<=', 100});
T_K = Temperature_C + 273.15;
R = 461.51805;
Alpha = 10 / (593 - T_K);
Beta = 10 / (T_K - 232);
% Specific volume, m^3/kg: Eq. 2.
a = [6.74458446e3, -2.22521604e5, 1.00231247e8, -1.63552118e9, 8.32299658e9];
n = [4, 5, 7, 8, 9];
b = [5.78545292e-3, -1.53195665e-2, 3.11337859e-2, -4.23546241e-2, 3.38713507e-2, -1.19946761e-2];
SpecificVolume_m3_kg = R * 10 / 1e5 * (1.93763157e-2 + sum(a .* Alpha.^n) + sum(b .* Beta.^(1:6)));
% Isobaric cp from the Gibbs-energy derivatives in Table 2.
a = [-1.661470539e5, 2.708781640e6, -1.557191544e8];
n = [4, 5, 7];
b = [-8.237426256e-1, 1.908956353, -2.017597384, 8.546361348e-1];
m = [2, 3, 4, 5];
Water.Cp_J_kgK = -R * (-8.983025854 + T_K / 10 * ...
    (sum(n .* (n + 1) .* a .* Alpha.^(n + 2)) + sum(m .* (m + 1) .* b .* Beta.^(m + 2))));
Water.Temperature_C = Temperature_C;
Water.Density_kg_m3 = 1 / SpecificVolume_m3_kg;
Water.Viscosity_Pa_s = 1e-6 * sum([280.68, 511.45, 61.131, 0.45903] ...
    .* (T_K / 300).^[-1.9, -7.7, -19.6, -40]);
Tau = 1 - T_K / 647.096;
Water.SurfaceTension_N_m = 0.2358 * Tau^1.256 * (1 - 0.625 * Tau);
end

function Gas = condenserGasProperties(Gas, Water, Condenser)
% Recalculate gas properties consistently for both sizing and sensitivity cases.
Gas.Flow_L_min = Gas.Flow_CFM * 28.316846592;
Gas.Flow_m3_s = Gas.Flow_L_min / 60000;
Gas.Pressure_Pa = Gas.Pressure_kPa * 1000;
Gas.Temperature_K = Gas.SuitTemperature_C + 273.15;
Gas.Constant_J_kgK = 8.314462618 / 0.0319988;
Gas.MolecularMassRatio = Gas.Constant_J_kgK / Water.VaporGasConstant_J_kgK;
Gas.InletVaporPressure_Pa = Gas.SuitRH_percent / 100 * saturationPressure(Gas.SuitTemperature_C);
assert(Gas.InletVaporPressure_Pa < Gas.Pressure_Pa, 'RH:Pressure', 'Vapor pressure must be below gas pressure.');
Gas.InletHumidityRatio = Gas.MolecularMassRatio * Gas.InletVaporPressure_Pa ...
    / (Gas.Pressure_Pa - Gas.InletVaporPressure_Pa);
Gas.DryDensity_kg_m3 = (Gas.Pressure_Pa - Gas.InletVaporPressure_Pa) / (Gas.Constant_J_kgK * Gas.Temperature_K);
Gas.DryFlow_kg_s = Gas.DryDensity_kg_m3 * Gas.Flow_m3_s;
Gas.Density_kg_m3 = Gas.DryDensity_kg_m3 + Gas.InletVaporPressure_Pa ...
    / (Water.VaporGasConstant_J_kgK * Gas.Temperature_K);
[Gas.Cp_J_kgK, Gas.Viscosity_Pa_s, Gas.Conductivity_W_mK] = oxygenProperties(Gas.Temperature_K);
% Fuller et al. oxygen-water binary diffusivity (Seader et al., Eq. 3-36, Table 3.1).
% https://catalogimages.wiley.com/images/db/pdf/0471464805.ch3.pdf
ReducedMolarMass_g_mol = 2 / (1 / 31.9988 + 1 / 18.01528);
Gas.VaporDiffusivity_m2_s = 1e-4 * 0.00143 * Gas.Temperature_K^1.75 ...
    / ((Gas.Pressure_kPa / 101.325) * sqrt(ReducedMolarMass_g_mol) * (16.3^(1/3) + 13.1^(1/3))^2);
Gas.Schmidt = Gas.Viscosity_Pa_s / (Gas.Density_kg_m3 * Gas.VaporDiffusivity_m2_s);
% Uniform-wall-temperature rectangular-duct correlation (Shah/London).
% See Maya HTT VVC6, constant-temperature case, for the Nu polynomial.
% https://help.mayahtt.com/tmg/topics/validation/VVC6_forced_convection_in_rectangular_duct.html
Gas.AspectRatio = min(Condenser.ChannelGap_m, Condenser.ChannelHeight_m) ...
    / max(Condenser.ChannelGap_m, Condenser.ChannelHeight_m);
Gas.HydraulicDiameter_m = 2 * Condenser.ChannelGap_m * Condenser.ChannelHeight_m ...
    / (Condenser.ChannelGap_m + Condenser.ChannelHeight_m);
a = Gas.AspectRatio;
Gas.Nusselt = 7.541 * (1 - 2.610*a + 4.970*a^2 - 5.119*a^3 + 2.702*a^4 - 0.548*a^5);
% Same laminar transport equation and constant wall concentration: Sh = Nu.
% This is a dilute-vapor approximation, without Stefan-flow corrections.
Gas.HeatTransfer_W_m2K = Gas.Nusselt * Gas.Conductivity_W_mK / Gas.HydraulicDiameter_m;
Gas.MassTransfer_m_s = Gas.Nusselt * Gas.VaporDiffusivity_m2_s / Gas.HydraulicDiameter_m;
Gas.MixtureCp_J_kgK = (Gas.Cp_J_kgK + Gas.InletHumidityRatio * Water.VaporCp_J_kgK) ...
    / (1 + Gas.InletHumidityRatio);
Gas.Prandtl = Gas.MixtureCp_J_kgK * Gas.Viscosity_Pa_s / Gas.Conductivity_W_mK;
% Fin conduction includes sensible and condensation latent heat.
Fin = wetFinPerformance(Gas, Water, Condenser);
Gas.FinEfficiency = Fin.Efficiency;
Gas.DryFinEfficiency = Fin.DryEfficiency;
Gas.SurfaceHeatEfficiency = Fin.SurfaceHeatEfficiency;
Gas.SurfaceMassEfficiency = Fin.SurfaceMassEfficiency;
Gas.FinMeanTemperature_C = Fin.MeanTemperature_C;
Gas.FinTipTemperature_C = Fin.TipTemperature_C;
% Constant inlet properties; viscosity/conductivity use dilute O2.

end

function Result = condenserArea(Surface_C, Gas, W, C)
% Root-cooled wet fins: effective heat/mass-transfer areas set outlet states.
% Sensible heat transfer sets outlet temperature; enthalpy gives cooling duty.
% Constant gas volume/properties and dilute-vapor transfer are approximations.
pSurface = saturationPressure(Surface_C);
wSurface = Gas.MolecularMassRatio * pSurface / (Gas.Pressure_Pa - pSurface);
MaximumRate = max(0, Gas.DryFlow_kg_s * (Gas.InletHumidityRatio - wSurface));
Result = struct('MaximumRemoval_g_min', MaximumRate * 60000, 'Feasible', false, ...
    'Status', "Required removal exceeds the surface-equilibrium limit at this airflow.", ...
    'RequiredArea_m2', Inf, 'InstalledArea_m2', Inf, 'ChannelCount', NaN, ...
    'Reynolds', NaN, 'ChannelPressureDrop_Pa', NaN, 'CoreWidth_m', NaN, ...
    'EntryLengthRatio', NaN, 'OutletTemperature_C', NaN, 'OutletRH_percent', NaN, ...
    'ReheatedRH_percent', NaN, 'CoolingDuty_W', NaN, 'ExternalReheat_W', NaN);
if W.DesignRate_kg_s >= MaximumRate || MaximumRate <= 0
    return;
end
Area_m2 = -Gas.Flow_m3_s / (Gas.MassTransfer_m_s * Gas.SurfaceMassEfficiency) * log1p(-W.DesignRate_kg_s / MaximumRate);
wOutlet = Gas.InletHumidityRatio - W.DesignRate_kg_s / Gas.DryFlow_kg_s;
% Mean humidity accounts for the changing sensible heat capacity of the vapor.
HeatCapacity_W_K = Gas.DryFlow_kg_s * (Gas.Cp_J_kgK ...
    + (Gas.InletHumidityRatio + wOutlet) / 2 * W.VaporCp_J_kgK);
Outlet_C = Surface_C + (Gas.SuitTemperature_C - Surface_C) ...
    * exp(-Gas.HeatTransfer_W_m2K * Gas.SurfaceHeatEfficiency * Area_m2 / HeatCapacity_W_K);
pOutlet = Gas.Pressure_Pa * wOutlet / (Gas.MolecularMassRatio + wOutlet);
OutletRH = 100 * pOutlet / saturationPressure(Outlet_C);
% Retain the wall-transfer requirement for reporting, but flag bulk fog as invalid.
BulkFog = OutletRH > 100 + 1e-6;
ChannelArea_m2 = 2 * (C.ChannelGap_m + C.ChannelHeight_m) * C.ChannelLength_m;
Channels = max(1, ceil(Area_m2 / ChannelArea_m2));
Velocity_m_s = Gas.Flow_m3_s / (Channels * C.ChannelGap_m * C.ChannelHeight_m);
Re = Gas.Density_kg_m3 * Velocity_m_s * Gas.HydraulicDiameter_m / Gas.Viscosity_Pa_s;
if Re >= 2300
    Result.Status = "Channel flow is outside the laminar correlation; revise geometry.";
    return;
end
a = Gas.AspectRatio;
Poiseuille = 96 * (1 - 1.3553*a + 1.9467*a^2 - 1.7012*a^3 + 0.9564*a^4 - 0.2537*a^5);
FrictionDrop_Pa = Poiseuille / Re * C.ChannelLength_m / Gas.HydraulicDiameter_m ...
    * Gas.Density_kg_m3 * Velocity_m_s^2 / 2;
hIn = Gas.Cp_J_kgK * Gas.SuitTemperature_C + Gas.InletHumidityRatio ...
    * (W.VaporEnthalpyAtZero_J_kg + W.VaporCp_J_kgK * Gas.SuitTemperature_C);
hOut = Gas.Cp_J_kgK * Outlet_C + wOutlet * (W.VaporEnthalpyAtZero_J_kg + W.VaporCp_J_kgK * Outlet_C);
Result.Feasible = ~BulkFog;
Result.Status = "Finite area meets the load with cooled fin roots and calculated wet-fin efficiency.";
if BulkFog
    Result.Status = "Wall-transfer sizing only: bulk fog predicted; mist capture/transport needs validation.";
end
Result.RequiredArea_m2 = Area_m2;
Result.ChannelCount = Channels;
Result.InstalledArea_m2 = Channels * ChannelArea_m2;
Result.Reynolds = Re;
Result.ChannelPressureDrop_Pa = FrictionDrop_Pa;
% Single straight stack envelope; excludes casing, headers and separator inserts.
Result.CoreWidth_m = Channels * C.ChannelGap_m + (Channels + 1) * C.FinThickness_m;
Result.EntryLengthRatio = 0.05 * Re * max([1, Gas.Prandtl, Gas.Schmidt]) ...
    * Gas.HydraulicDiameter_m / C.ChannelLength_m;
Result.OutletTemperature_C = Outlet_C;
Result.OutletRH_percent = OutletRH;
Result.ReheatedRH_percent = 100 * pOutlet / saturationPressure(Gas.SuitTemperature_C);
Result.CoolingDuty_W = Gas.DryFlow_kg_s * (hIn - hOut) - W.DesignRate_kg_s * W.Cp_J_kgK * Surface_C;
Result.ExternalReheat_W = Gas.DryFlow_kg_s * (Gas.Cp_J_kgK + wOutlet * W.VaporCp_J_kgK) ...
    * (Gas.SuitTemperature_C - Outlet_C);
% Duty/outlet correspond to continuous required area; rounded installation has margin.
end

function [Cp, Viscosity, Conductivity] = oxygenProperties(T_K)
% NIST Shomate Cp (100-700 K), Lemmon-Jacobsen dilute O2 transport (2004).
% https://webbook.nist.gov/cgi/cbook.cgi?ID=C7782447&Mask=1
% https://trc.nist.gov/refprop/FAQ/NAO.PDF, Eqs. 2 and 5, Tables I, II, IV.
t = T_K / 1000;
Cp = (31.32234 - 20.23531 * t + 57.86644 * t^2 - 36.50624 * t^3 - 0.007374 / t^2) / 0.0319988;
Log_Tstar = log(T_K / 118.5);
Collision_Integral = exp(0.431 - 0.4623 * Log_Tstar + 0.08406 * Log_Tstar^2 + ...
    0.005341 * Log_Tstar^3 - 0.00331 * Log_Tstar^4);
Viscosity_microPa_s = 0.0266958 * sqrt(31.9988 * T_K) / (0.3428^2 * Collision_Integral);
Viscosity = Viscosity_microPa_s * 1e-6;
Conductivity = (1.036 * Viscosity_microPa_s + 6.283 * (154.581 / T_K)^(-0.9) ...
    - 4.262 * (154.581 / T_K)^(-0.6)) * 1e-3;
end

function Pressure_Pa = saturationPressure(Temperature_C)
% Buck saturation pressure over liquid water; this script uses T >= 0 C.
Pressure_Pa = 611.21 * exp((18.678 - Temperature_C / 234.5) .* Temperature_C ./ (257.14 + Temperature_C));
end

function Fin = wetFinPerformance(Gas, W, C)
% One-dimensional graphite conduction, including local condensation latent heat.
% Two cooled roots: solve half the height, with zero gradient at the midplane.
% Insulated-tip dry benchmark: eta = tanh(mL)/(mL), Nellis/Klein fin theory.
N = C.FinNodes;
L = C.ChannelHeight_m / 2;
dx = L / N;
Conduction = C.FinConductivity_W_mK * C.FinThickness_m / dx^2;
h = Gas.HeatTransfer_W_m2K;
LatentHeat = W.VaporEnthalpyAtZero_J_kg + (W.VaporCp_J_kgK - W.Cp_J_kgK) * C.SurfaceTemperature_C;
LatentFilm = LatentHeat * Gas.DryDensity_kg_m3 * Gas.MassTransfer_m_s;
Root = C.SurfaceTemperature_C;
Temperature = repmat(Root, 1, N);
for Iteration = 1:30
    p = saturationPressure(Temperature);
    ws = Gas.MolecularMassRatio * p ./ (Gas.Pressure_Pa - p);
    dp = (saturationPressure(Temperature + 0.001) - saturationPressure(Temperature - 0.001)) / 0.002;
    dws = Gas.MolecularMassRatio * Gas.Pressure_Pa * dp ./ (Gas.Pressure_Pa - p).^2;
    Wet = Gas.InletHumidityRatio > ws;
    dws = dws .* Wet;
    VaporDifference = max(0, Gas.InletHumidityRatio - ws);
    Diagonal = 2 * Conduction + 2 * h + 2 * LatentFilm * dws;
    Right = 2 * h * Gas.SuitTemperature_C + 2 * LatentFilm * (VaporDifference + dws .* Temperature);
    Right(1) = Right(1) + Conduction * Root;
    % Tridiagonal Newton solve; reflected last node enforces zero tip gradient.
    Upper = repmat(-Conduction, 1, N - 1);
    Lower = repmat(-Conduction, 1, N - 1);
    Lower(end) = -2 * Conduction;
    for Node = 2:N
        Multiplier = Lower(Node - 1) / Diagonal(Node - 1);
        Diagonal(Node) = Diagonal(Node) - Multiplier * Upper(Node - 1);
        Right(Node) = Right(Node) - Multiplier * Right(Node - 1);
    end
    NewTemperature = Right ./ Diagonal;
    for Node = N-1:-1:1
        NewTemperature(Node) = (Right(Node) - Upper(Node) * NewTemperature(Node + 1)) / Diagonal(Node);
    end
    Change = max(abs(NewTemperature - Temperature));
    Temperature = NewTemperature;
    if Change < 1e-7
        break;
    end
end
assert(Change < 1e-5, 'RH:FinConvergence', 'Wet fin temperature did not converge.');
Temperature = [Root, Temperature];
p = saturationPressure(Temperature);
ws = Gas.MolecularMassRatio * p ./ (Gas.Pressure_Pa - p);
pRoot = saturationPressure(Root);
wRoot = Gas.MolecularMassRatio * pRoot / (Gas.Pressure_Pa - pRoot);
MeanTemperature = trapz(Temperature) / N;
MeanVaporDifference = trapz(max(0, Gas.InletHumidityRatio - ws)) / N;
HeatRatio = (Gas.SuitTemperature_C - MeanTemperature) / (Gas.SuitTemperature_C - Root);
MassRatio = 1;
if Gas.InletHumidityRatio > wRoot
    MassRatio = MeanVaporDifference / (Gas.InletHumidityRatio - wRoot);
end
IdealFlux = h * (Gas.SuitTemperature_C - Root) + LatentFilm * max(0, Gas.InletHumidityRatio - wRoot);
ActualFlux = h * (Gas.SuitTemperature_C - MeanTemperature) + LatentFilm * MeanVaporDifference;
Fin.Efficiency = ActualFlux / IdealFlux;
mL = sqrt(2 * h / (C.FinConductivity_W_mK * C.FinThickness_m)) * L;
Fin.DryEfficiency = tanh(mL) / mL;
FinFraction = C.ChannelHeight_m / (C.ChannelHeight_m + C.ChannelGap_m);
Fin.SurfaceHeatEfficiency = 1 - FinFraction * (1 - HeatRatio);
Fin.SurfaceMassEfficiency = 1 - FinFraction * (1 - MassRatio);
Fin.MeanTemperature_C = MeanTemperature;
Fin.TipTemperature_C = Temperature(end);
% Efficiencies evaluated at inlet conditions give no downstream recovery credit.
end

function plotRHFigures(Gas, Water, Condenser, SupplyFlow_CFM, CapacityDesign)
% Fixed mean inlet T/RH plots at the selected supply airflow.
Selected = condenserArea(Condenser.SurfaceTemperature_C, Gas, Water, Condenser);
% Above-Freezing Capacity
Surface_C = linspace(0, Gas.SuitTemperature_C, 100);
MaximumRemoval_g_min = zeros(size(Surface_C));
for Index = 1:numel(Surface_C)
    Trial = condenserArea(Surface_C(Index), Gas, Water, Condenser);
    MaximumRemoval_g_min(Index) = Trial.MaximumRemoval_g_min;
end
figure(6);
set(gcf, 'Name', '6. Condenser Moisture Carrying Capacity', 'NumberTitle', 'off');
plot(Surface_C, MaximumRemoval_g_min);
hold on;
yline(Water.DesignRate_kg_s * 60000, '--', 'Required removal');
xline(Condenser.SurfaceTemperature_C, ':', 'Selected surface');
xlabel('Condenser surface temperature (C)');
ylabel('Infinite-area removal limit (g/min)');
title({"Above-Freezing Capacity at Fixed Airflow", ...
    sprintf('Supply %.3g CFM; condenser inlet %.3f actual CFM', SupplyFlow_CFM, Gas.Flow_CFM)});
grid on;

% Condenser Area versus Removal Rate
% Place the installed 99%-capacity EVA design at its mean-inlet removal rate.
CapacityArea_m2 = CapacityDesign.InstalledArea_m2;
CapacityRemoval_g_min = Selected.MaximumRemoval_g_min * (1 - exp( ...
    -Gas.MassTransfer_m_s * Gas.SurfaceMassEfficiency * CapacityArea_m2 / Gas.Flow_m3_s));
RemovalRate_g_min = unique([linspace(0.01 * Selected.MaximumRemoval_g_min, ...
    max(0.99 * Selected.MaximumRemoval_g_min, CapacityRemoval_g_min), 160), ...
    Water.DesignRate_kg_s * 60000, CapacityRemoval_g_min]);
RequiredArea_m2 = Inf(size(RemovalRate_g_min));
for Index = 1:numel(RemovalRate_g_min)
    TrialWater = Water;
    TrialWater.DesignRate_kg_s = RemovalRate_g_min(Index) / 60000;
    Trial = condenserArea(Condenser.SurfaceTemperature_C, Gas, TrialWater, Condenser);
    RequiredArea_m2(Index) = Trial.RequiredArea_m2;
end
figure(7);
set(gcf, 'Name', '7. Condenser Area Requirement', 'NumberTitle', 'off');
plot(RemovalRate_g_min, RequiredArea_m2, 'LineWidth', 1.5, 'DisplayName', 'Mean-inlet area requirement');
hold on;
RequiredRemoval_g_min = Water.DesignRate_kg_s * 60000;
xline(RequiredRemoval_g_min, ':', 'Average removal load', 'HandleVisibility', 'off');
if Selected.Feasible
    yline(Selected.RequiredArea_m2, ':', 'Area at average load', 'HandleVisibility', 'off');
    plot(RequiredRemoval_g_min, Selected.RequiredArea_m2, 'p', 'MarkerSize', 13, ...
        'MarkerFaceColor', 'y', 'MarkerEdgeColor', 'k', 'DisplayName', 'Average-load design');
end
yline(CapacityArea_m2, '--', '99% capacity installed area', 'HandleVisibility', 'off');
plot(CapacityRemoval_g_min, CapacityArea_m2, 'd', 'MarkerSize', 10, ...
    'MarkerFaceColor', 'c', 'MarkerEdgeColor', 'k', ...
    'DisplayName', '99% EVA capacity design at mean inlet');
legend('show', 'Location', 'best');
xlabel('Water removal rate (g/min)');
ylabel('Required condenser transfer area (m^2)');
title({sprintf('Condenser Area at Fixed %.3g Supply ACFM', SupplyFlow_CFM), ...
    sprintf('Inlet %.3f actual CFM, %.2f C, %.2f%% RH; roots %.1f C', ...
    Gas.Flow_CFM, Gas.SuitTemperature_C, Gas.SuitRH_percent, Condenser.SurfaceTemperature_C)});
grid on;
end

% Component Sizing Functions
function [Capacity_W, Power_W] = compressorMap(Evaporator_C, Condensing_C)
% Aspen 14-24-000X R134a map, 4000 rpm, capacity p. 2 and input power p. 4.
% 10 F superheat, 8 F subcooling; no extrapolation outside tabulated temperatures.
% https://www.aspencompressor.com/_files/ugd/87858f_5c6d7c7912304575bd2d4ac588718b5b.pdf
Evaporator_F = Evaporator_C * 1.8 + 32;
Condensing_F = Condensing_C * 1.8 + 32;
EvaporatorGrid_F = 10:10:70;
CondensingGrid_F = [100, 120, 140];
CapacityMap_W = [62, 106, 150, 210, 271, 350, 430; ...
    56, 95, 134, 186, 239, 309, 379; 32, 69, 106, 156, 207, 274, 340];
PowerMap_W = [85, 71, 67, 62, 60, 58, 57; ...
    83, 84, 84, 84, 84, 85, 85; 79, 97, 105, 110, 112, 115, 116];
assert(Evaporator_F >= 10 && Evaporator_F <= 70 && Condensing_F >= 100 ...
    && Condensing_F <= 140, 'RH:CompressorMap', 'Temperatures outside reference compressor map.');
Capacity_W = interp2(EvaporatorGrid_F, CondensingGrid_F, CapacityMap_W, Evaporator_F, Condensing_F);
Power_W = interp2(EvaporatorGrid_F, CondensingGrid_F, PowerMap_W, Evaporator_F, Condensing_F);
end

function displaySummary(Title, Label, Value, Unit)
% Compact vertical output; numeric workspace summary tables remain available.
fprintf('\n%s\n', Title);
fprintf('%-48s %12s  %s\n', 'Parameter', 'Value', 'Unit');
fprintf('%s\n', repmat('-', 1, 78));
for Row = 1:numel(Label)
    fprintf('%-48s %12.5g  %s\n', Label(Row), Value(Row), Unit(Row));
end
fprintf('\n');
end
