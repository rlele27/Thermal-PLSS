%% Compatibility Launcher
% All component calculations and assumptions are now in the main script.
% This entry point runs the complete metabolic, RH and component sizing model.
run(fullfile(fileparts(mfilename('fullpath')), 'Nominal_Metabolic_Profile.m'));
