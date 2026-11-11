function [Cp, Viscosity, Conductivity] = oxygenProperties(T_K)
% OXYGENPROPERTIES NIST Shomate Cp (100-700 K), Lemmon-Jacobsen dilute O2 transport (2004).
% Inputs: T_K.
% Outputs: Cp, Viscosity, Conductivity.
% Units: SI; degC and explicit _min/_hr/_g field suffixes where used.
% Side effects: None; returns results through its output arguments.
% https://webbook.nist.gov/cgi/cbook.cgi?ID=C7782447&Mask=1
% https://trc.nist.gov/refprop/FAQ/NAO.PDF, Eqs. 2 and 5, Tables I, II, IV.
t = T_K / 1000;
Cp = (31.32234 - 20.23531 * t + 57.86644 * t.^2 - 36.50624 * t.^3 - 0.007374 ./ t.^2) / 0.0319988;
Log_Tstar = log(T_K / 118.5);
Collision_Integral = exp(0.431 - 0.4623 * Log_Tstar + 0.08406 * Log_Tstar.^2 + ...
    0.005341 * Log_Tstar.^3 - 0.00331 * Log_Tstar.^4);
Viscosity_microPa_s = 0.0266958 * sqrt(31.9988 * T_K) ./ (0.3428^2 * Collision_Integral);
Viscosity = Viscosity_microPa_s * 1e-6;
Conductivity = (1.036 * Viscosity_microPa_s + 6.283 * (154.581 ./ T_K).^(-0.9) ...
    - 4.262 * (154.581 ./ T_K).^(-0.6)) * 1e-3;
end
