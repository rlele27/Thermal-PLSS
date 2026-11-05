function Design = reweightEVADesign(Design, SizeWeight)
% Re-score the existing feasible frontier; no physical simulation is repeated.
validateattributes(SizeWeight, {'numeric'}, {'scalar', 'real', 'finite', '>=', 0, '<=', 1});
Design.SizeWeight = SizeWeight;
if ~Design.Feasible, return; end
R = Design.SearchResults;
R.Objective(:) = Inf;
R.Objective(R.Feasible) = SizeWeight * R.SizeCost(R.Feasible) ...
    + (1 - SizeWeight) * R.ColdCost(R.Feasible);
Rank = R(R.Feasible, {'Objective', 'Channels', 'RootFloor_C'});
Rank = sortrows(Rank, {'Objective', 'Channels', 'RootFloor_C'}, {'ascend', 'ascend', 'descend'});
Best = find(R.Feasible & R.Channels == Rank.Channels(1) & R.RootFloor_C == Rank.RootFloor_C(1), 1);
Index = find(cellfun(@(O) O.SearchRow == Best, Design.FeasibleOptions), 1);
O = Design.FeasibleOptions{Index};
H = O.History;
Design.SearchResults = R;
Design.AirWarmer = O.Warmer;
Design.SelectedHistory = {H};
Design.RootFloor_C = O.RootFloor_C;
Design.Objective = R.Objective(Best);
Design.NextSmallerChecked = O.Channels > Design.ChannelBounds(1);
Design.SelectedSummary = O.Summary;
Design.SelectedSummary.Objective = Design.Objective;
Design.SelectedSummary.SizeWeight = SizeWeight;
Design.SelectedSummary.AtChannelBound = any(O.Channels == Design.ChannelBounds);
Design.SelectedSummary.AtTemperatureBound = any(O.RootFloor_C == Design.RootTemperatureBounds_C);
Design.TimeHistory = [Design.TimeHistoryBase, ...
    table(H.Cooling_W, H.Reheat_W, H.ReheatedTemperature_C, H.ReheatedRH_percent, ...
    H.RHError_percent, H.TemperatureError_C, H.RootTemperature_C, ...
    sum(H.RegionLiquidEnd_g, 2), H.RegionLiquidEnd_g(:, 1), H.RegionLiquidEnd_g(:, 2), ...
    H.RegionLiquidEnd_g(:, 3), sum(H.Condensed_kg, 2) * 1000, ...
    sum(H.Reevaporated_kg, 2) * 1000, H.RequiredPhaseHeatSink_W, H.UncorrectedMaximumRH_percent, ...
    'VariableNames', {'Cooling_W', 'Reheat_W', 'SupplyTemperature_C', 'SupplyRH_percent', ...
    'MaximumRHError_percent', 'MaximumTemperatureError_C', 'RootTemperature_C', ...
    'StoredRegionalLiquid_g', 'HeadNeckLiquid_g', 'TorsoArmsLiquid_g', 'LegsLiquid_g', ...
    'RegionalCondensation_g', 'RegionalReevaporation_g', ...
    'RequiredRegionalPhaseHeatSink_W', 'PreEquilibriumMaximumRH_percent'})];
Design.BufferMassResidual_kg = H.MassResidual_kg;
Design.PhaseEnergyResidual_J = H.PhaseEnergyResidual_J;
end
