function Temperature_C = jos3NeutralTemperature(MetabolicRate_met)
% Reproduce the upstream PMV-neutral initialization (unclothed, 50% RH).
% This intentionally follows its iteration and stopping tolerances.
Temperature_C = 28;
for Iteration = 1:100
    PMV = neutralPMV(Temperature_C, MetabolicRate_met);
    if abs(PMV) < 0.001
        break;
    end
    Temperature_C = Temperature_C - PMV / 3;
end
end

function PMV = neutralPMV(Temperature_C, MetabolicRate_met)
MetabolicRate_W_m2 = MetabolicRate_met * 58.15;
VaporPressure_kPa = exp(16.6536 - 4030.183 / (Temperature_C + 235)) * 0.5;
Convection_W_m2_K = 12.1 * sqrt(0.1);
ClothingTemperature_C = (34 + Temperature_C) / 2;
for Iteration = 1:100
    TargetTemperature_C = 35.7 - 0.028 * MetabolicRate_W_m2;
    ClothingTemperature_C = (TargetTemperature_C + ClothingTemperature_C) / 2;
    if abs(TargetTemperature_C - ClothingTemperature_C) < 0.0001
        break;
    end
end
Radiation_W_m2 = 3.96e-8 * ((ClothingTemperature_C + 273)^4 - (Temperature_C + 273)^4);
Convection_W_m2 = Convection_W_m2_K * (ClothingTemperature_C - Temperature_C);
Diffusion_W_m2 = 3.05 * (5.73 - 0.007 * MetabolicRate_W_m2 - VaporPressure_kPa);
Sweat_W_m2 = max(0, 0.42 * (MetabolicRate_W_m2 - 58.15));
Respiration_W_m2 = 0.0173 * MetabolicRate_W_m2 * (5.87 - VaporPressure_kPa) ...
    + 0.0014 * MetabolicRate_W_m2 * (34 - Temperature_C);
HeatLoad_W_m2 = MetabolicRate_W_m2 - Radiation_W_m2 - Convection_W_m2 ...
    - Diffusion_W_m2 - Sweat_W_m2 - Respiration_W_m2;
PMV = (0.303 * exp(-0.036 * MetabolicRate_W_m2) + 0.028) * HeatLoad_W_m2;
end
