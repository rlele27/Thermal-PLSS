function Result = summarizeEVAScenario(Profile, Inputs)
% SUMMARIZEEVASCENARIO Duration-weight one scenario's air and moisture outputs.
% Inputs: Profile, Inputs.
% Outputs: Result.
% Units: SI; degC and explicit _min/_hr/_g field suffixes where used.
% Side effects: None; returns results through its output arguments.
Moisture_Profile = Profile;
BodyMicroclimate = Inputs.Environment; Ventilation = BodyMicroclimate.Ventilation;
Moisture_Rate_g_min = Moisture_Profile.VaporToPLSS_g_min;
Moisture_Duration_min = Moisture_Profile.EndTime_min - Moisture_Profile.StartTime_min;
EVA_Duration_min = sum(Moisture_Duration_min);

AverageMoisture_g_min = sum(Moisture_Rate_g_min .* Moisture_Duration_min) / EVA_Duration_min;
PeakMoisture_g_min = max(Moisture_Rate_g_min);
AverageSourceMoisture_g_min = sum(Moisture_Profile.VaporToSuit_g_min .* Moisture_Duration_min) / EVA_Duration_min;
PeakSourceMoisture_g_min = max(Moisture_Profile.VaporToSuit_g_min);

% Condenser Inlet Temperature
CondenserInlet_C = Moisture_Profile.CondenserInletTemperature_C; % Physical return conditions use unscaled heat and moisture.
AverageCondenserInlet_C = sum(CondenserInlet_C .* Moisture_Duration_min) / EVA_Duration_min;

% Summary of Suit Outlet Values
SupplyVaporPressure_Pa = exp(16.6536 - 4030.183 / (BodyMicroclimate.AirTemperature_C + 235)) ...
    * BodyMicroclimate.RelativeHumidity_percent / 100 * 1000;
DryOxygenFlow_kg_s = (BodyMicroclimate.Pressure_kPa * 1000 - SupplyVaporPressure_Pa) ...
    * Ventilation.Flow_CFM * 0.028316846592 / 60 / (259.84 * (BodyMicroclimate.AirTemperature_C + 273.15));
SupplyHumidityRatio = (0.01801528 / 0.0319988) * SupplyVaporPressure_Pa ...
    / (BodyMicroclimate.Pressure_kPa * 1000 - SupplyVaporPressure_Pa);
ReturnHumidityRatio = SupplyHumidityRatio + AverageMoisture_g_min / 60000 / DryOxygenFlow_kg_s;
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
Coefficients = Data_Functions.Physiology.jos3Coefficients();
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

% PLSS Humidity Loads
Component = ["Respiratory"; "Evaporated fresh sweat"; "Skin diffusion"; ...
    "Evaporated retained sweat"; "Total vapor"];
ComponentRates_g_min = [Moisture_Profile.Respiratory_g_min, Moisture_Profile.SweatEvaporated_g_min, ...
    Moisture_Profile.SkinDiffusion_g_min, Moisture_Profile.RetainedEvaporation_g_min, ...
    Moisture_Profile.VaporToSuit_g_min];
Total_g = sum(ComponentRates_g_min .* Moisture_Duration_min, 1)';
Average_g_min = Total_g / EVA_Duration_min;
Peak_g_min = max(ComponentRates_g_min, [], 1)';
Moisture_Summary = table(Component, Average_g_min, Peak_g_min, Total_g);


Result = struct('AirSummary', Summary, 'MoistureSummary', Moisture_Summary, ...
    'Duration_min', EVA_Duration_min, 'AverageCondenserInlet_C', AverageCondenserInlet_C, ...
    'InletRH_percent', RH_Sizing_InletRH_percent, 'InletFlow_CFM', RH_Sizing_Flow_CFM, ...
    'AverageMoisture_g_min', AverageMoisture_g_min, 'PeakMoisture_g_min', PeakMoisture_g_min, ...
    'DryOxygenFlow_kg_s', DryOxygenFlow_kg_s, 'SupplyHumidityRatio', SupplyHumidityRatio, ...
    'ZoneTemperatures_C', ZoneTemperatures_C, 'ZoneRH_percent', ZoneRH_percent);
end
