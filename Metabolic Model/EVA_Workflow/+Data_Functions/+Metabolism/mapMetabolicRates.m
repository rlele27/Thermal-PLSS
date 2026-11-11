function Mapped_Rates_kJ_hr = mapMetabolicRates(Activity_Names, MetMan, AboveNominalFraction)
% MAPMETABOLICRATES Look up each nominal activity's rate in EVA_Data.mat Source.MetMan.
% Inputs: Activity_Names, MetMan.
% Outputs: Mapped_Rates_kJ_hr.
% Units: SI; degC and explicit _min/_hr/_g field suffixes where used.
% Side effects: None; returns results through its output arguments.
% Repeated activities are allowed only when their metabolic rates agree.
% Above Nominal uses the main-script fraction of the resistance exercise rate.
% Other MetMan outputs vary over time and require separate mapping rules.

validateattributes(AboveNominalFraction,{'numeric'},{'scalar','real','finite','>=',0,'<=',1});
Source_Activities = lower(strtrim(string(MetMan.Activity)));
Activity_Labels = strtrim(string(Activity_Names));
Requested_Activities = lower(Activity_Labels);

Mapped_Rates_kJ_hr = zeros(size(Requested_Activities));
AboveNominal_Rows = Requested_Activities == "above nominal";
if any(AboveNominal_Rows)
    Resistance_Rate_kJ_hr = Data_Functions.Metabolism.mapMetabolicRates("Exercise - Resistance", MetMan, AboveNominalFraction);
    Mapped_Rates_kJ_hr(AboveNominal_Rows) = AboveNominalFraction * Resistance_Rate_kJ_hr;
end

for Activity_Name = reshape(unique(Requested_Activities(~AboveNominal_Rows)), 1, [])
    Requested_Rows = Requested_Activities == Activity_Name;
    Source_Rows = Source_Activities == Activity_Name;
    if ~any(Source_Rows)
        Activity_Label = Activity_Labels(find(Requested_Rows, 1));
        error('MetabolicProfile:UnmappedActivity', ...
            ['Activity "%s" in Raw_Nominal.csv was not found in ' ...
             'EVA_Data.mat Source.MetMan. Update the activity mapping or add a ' ...
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
             'EVA_Data.mat Source.MetMan. Use an unambiguous activity mapping.'], ...
            char(Activity_Name));
    end
    Mapped_Rates_kJ_hr(Requested_Rows) = Source_Rates_kJ_hr(1);
end
end
