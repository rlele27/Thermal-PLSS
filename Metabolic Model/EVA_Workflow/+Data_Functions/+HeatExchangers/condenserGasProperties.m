function Gas = condenserGasProperties(Gas, Water, Condenser)
% CONDENSERGASPROPERTIES Recalculate gas properties consistently for both sizing and sensitivity cases.
% Inputs: Gas, Water, Condenser.
% Outputs: Gas.
% Units: SI; degC and explicit _min/_hr/_g field suffixes where used.
% Side effects: None; returns results through its output arguments.
Gas.Flow_L_min = Gas.Flow_CFM * 28.316846592;
Gas.Flow_m3_s = Gas.Flow_L_min / 60000;
Gas.Pressure_Pa = Gas.Pressure_kPa * 1000;
Gas.Temperature_K = Gas.SuitTemperature_C + 273.15;
Gas.Constant_J_kgK = 8.314462618 / 0.0319988;
Gas.MolecularMassRatio = Gas.Constant_J_kgK / Water.VaporGasConstant_J_kgK;
Gas.InletVaporPressure_Pa = Gas.SuitRH_percent / 100 * Data_Functions.Properties.saturationPressure(Gas.SuitTemperature_C);
assert(Gas.InletVaporPressure_Pa < Gas.Pressure_Pa, 'RH:Pressure', 'Vapor pressure must be below gas pressure.');
Gas.InletHumidityRatio = Gas.MolecularMassRatio * Gas.InletVaporPressure_Pa ...
    / (Gas.Pressure_Pa - Gas.InletVaporPressure_Pa);
Gas.DryDensity_kg_m3 = (Gas.Pressure_Pa - Gas.InletVaporPressure_Pa) / (Gas.Constant_J_kgK * Gas.Temperature_K);
Gas.DryFlow_kg_s = Gas.DryDensity_kg_m3 * Gas.Flow_m3_s;
Gas.Density_kg_m3 = Gas.DryDensity_kg_m3 + Gas.InletVaporPressure_Pa ...
    / (Water.VaporGasConstant_J_kgK * Gas.Temperature_K);
[Gas.Cp_J_kgK, Gas.Viscosity_Pa_s, Gas.Conductivity_W_mK] = Data_Functions.Properties.oxygenProperties(Gas.Temperature_K);
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
Fin = Data_Functions.HeatExchangers.wetFinPerformance(Gas, Water, Condenser);
Gas.FinEfficiency = Fin.Efficiency;
Gas.DryFinEfficiency = Fin.DryEfficiency;
Gas.SurfaceHeatEfficiency = Fin.SurfaceHeatEfficiency;
Gas.SurfaceMassEfficiency = Fin.SurfaceMassEfficiency;
Gas.FinMeanTemperature_C = Fin.MeanTemperature_C;
Gas.FinTipTemperature_C = Fin.TipTemperature_C;
% Constant inlet properties; viscosity/conductivity use dilute O2.

end
