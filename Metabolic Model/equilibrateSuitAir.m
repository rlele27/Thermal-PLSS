function [Vapor_kg, Liquid_kg, Phase_kg, Heat_J] = equilibrateSuitAir(Vapor_kg, Liquid_kg, SaturatedVapor_kg, LatentHeat_J_kg)
% Isothermal equilibrium of vapor and locally retained liquid, elementwise.
% Positive Phase/Heat means condensation/heat rejected to maintain prescribed T.
% Negative phase means evaporation, limited by available liquid. No drainage.
Total_kg = Vapor_kg + Liquid_kg;
assert(all(isfinite(Total_kg), 'all') && all(Total_kg >= -1e-12, 'all'), ...
    'RH:AvailableWater', 'Regional sources/sinks exceed available vapor and liquid.');
Total_kg = max(Total_kg, 0); % Roundoff only; never clip away supersaturated water.
NewVapor_kg = min(Total_kg, SaturatedVapor_kg);
Phase_kg = Vapor_kg - NewVapor_kg;
Vapor_kg = NewVapor_kg;
Liquid_kg = Total_kg - Vapor_kg;
Heat_J = Phase_kg .* LatentHeat_J_kg;
end
