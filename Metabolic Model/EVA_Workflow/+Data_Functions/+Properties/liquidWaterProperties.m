function Water = liquidWaterProperties(Temperature_C)
% LIQUIDWATERPROPERTIES IAPWS SR6-08(2011), liquid density and heat capacity.
% Inputs: Temperature_C.
% Outputs: Water.
% Units: SI; degC and explicit _min/_hr/_g field suffixes where used.
% Side effects: None; returns results through its output arguments.
% https://iapws.org/technical-guidance/release/LiquidWater.download
% Use the 0.1 MPa liquid correlations as a low-pressure approximation for rho/cp.
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

end
