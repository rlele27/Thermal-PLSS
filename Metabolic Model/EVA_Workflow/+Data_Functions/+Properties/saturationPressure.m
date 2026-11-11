function Pressure_Pa = saturationPressure(Temperature_C)
% SATURATIONPRESSURE Buck saturation pressure over liquid water; this script uses T >= 0 C.
% Inputs: Temperature_C.
% Outputs: Pressure_Pa.
% Units: SI; degC and explicit _min/_hr/_g field suffixes where used.
% Side effects: None; returns results through its output arguments.
Pressure_Pa = 611.21 * exp((18.678 - Temperature_C / 234.5) .* Temperature_C ./ (257.14 + Temperature_C));
end
