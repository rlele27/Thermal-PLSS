function printEVAReports(Reports)
% PRINTEVAREPORTS Display ordered result tables without reading or writing files.
% Inputs: Reports.
% Outputs: None.
% Units: SI; degC and explicit _min/_hr/_g field suffixes where used.
% Side effects: Writes report tables to the command window.
% Keep the command window to the requested summary tables. Detailed body/LCG
% diagnostics remain available in Data.Simulation without extra console output.
Order = {'MetabolicRates','LCG','Air','Moisture','Condensate', ...
    'ComponentSizing','ComponentPerformance','PLSSAirAndWater','ThermalSystemSizing','SensitivityAnalysis','Feasibility'};
Names = Order(isfield(Reports, Order));
for Index = 1:numel(Names)
    Value = Reports.(Names{Index});
    assert(istable(Value), 'EVA:ReportType', 'Report %s must be a table.', Names{Index});
    Title = regexprep(Names{Index}, '([a-z])([A-Z])', '$1 $2');
    fprintf('\n%s\n%s\n%s\n', repmat('=',1,80), Title, repmat('=',1,80));
    disp(Value);
end
end
