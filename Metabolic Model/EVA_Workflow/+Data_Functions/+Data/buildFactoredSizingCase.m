function Design = buildFactoredSizingCase(EVA,CaseName)
% BUILDFACTOREDSIZINGCASE Apply design margins to completed output loads only.
% Inputs: EVA - completed physical cases; CaseName - Nominal or OffNominal.
% Outputs: Design - factored metabolic/physiology loads and sizing profile.
% Units: W, g/min, g; state variables/time retain their physical units/values.
% Side effects: None. Physical results are never modified or rerun.
FOS = EVA.Inputs.MetabolicFOS;
validateattributes(FOS,{'numeric'},{'scalar','real','finite','>=',1});
Physical = EVA.(CaseName);
Design.FOS = FOS;
Design.Metabolic = Physical.Metabolic;
LoadColumns = {'MetabolicRate_W','ExternalWork_W','HeatGeneration_W'};
Design.Metabolic{:,LoadColumns} = Physical.Metabolic{:,LoadColumns}*FOS;
Names = string(Physical.Physiology.Properties.VariableNames);
% Export load quantities, not fictitious multiplied temperatures/RH or flows.
LoadNames = Names((endsWith(Names,"_W") | endsWith(Names,"_g_min") ...
    | endsWith(Names,"_g")) & ~contains(Names,"Residual"));
Design.PhysiologyLoads = Physical.Physiology(:,["StartTime_min","EndTime_min",LoadNames]);
Design.PhysiologyLoads{:,LoadNames} = Physical.Physiology{:,LoadNames}*FOS;
% sizeEVARH already scales regional sources from Design/PhysicalMoisture.
% Keep humidity reconstruction fields intact; target-deficit diagnostics receive FOS.
Design.SizingProfile = Physical.SizingProfile;
Design.SizingProfile.RemainingCoolingShortfall_W = Physical.SizingProfile.RemainingCoolingShortfall_W*FOS;
Design.SizingProfile.DesignMoisture_g_min = Physical.SizingProfile.DesignMoisture_g_min*FOS;
% Only receiving-path loads receive FOS; storage, closure and gas states stay physical.
Transfer = Data_Functions.Data.buildThermalInterface(EVA,CaseName);
Design.ThermalPathwayLoads = Transfer.BodyPathways(:, ...
    {'StartTime_min','EndTime_min','LCGHeatPickup_W','HeatToSuitInterior_W', ...
    'HeatToVentilationSensible_W','HeatToVentilationLatent_W'});
Design.ThermalPathwayLoads{:,3:end} = Design.ThermalPathwayLoads{:,3:end}*FOS;
end
